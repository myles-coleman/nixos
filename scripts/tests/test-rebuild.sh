#!/usr/bin/env bash
#
# Tests for the rebuild.sh contract (spec 32, Units 2, 3 and 4).
#
# Assertions 1-20 pin the preflight contract (FR-1 to FR-14): the CLI surface,
# tree/host resolution, the banner and the pre-build guards.
# Assertions 21-33 pin the build contract: the alejandra format step, the
# `nom`-monitored build, log capture, the exit status taken from `nix` rather
# than `nom`, out-link cleanup and the interrupt trap.
# Assertions 34-46 pin the activation contract (FR-24 to FR-31): the
# non-interactive sudo guard, the activation lock, `switch`/`boot` invocation,
# log append, the `/run/current-system` equality check, the generation and
# failed-unit report, the reboot note and notification tolerance.
#
# rebuild.sh is replaced wholesale by spec 32. These tests pin that contract
# with a stub PATH and throwaway git fixtures: no Nix, no network, no real
# activation.
#
# `git` is real, not stubbed (spec 32, Amendment 2): the fixtures are the only
# way to exercise the queries the script actually makes (`rev-parse`,
# `branch --show-current`, `status --porcelain`, `ls-files`, `diff`). The other
# commands in FR-36 (`nix`, `nom`, `nix-instantiate`, `nixos-rebuild`,
# `alejandra`, `notify-send`, `systemctl`, `hostname`, `sudo`, `flock`,
# `readlink`) are stubs under
# $TMP/bin. Coreutils stay real.
#
# Usage: scripts/tests/test-rebuild.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SCRIPT="$ROOT/rebuild.sh"

TOTAL=51

TMP="$(mktemp -d)"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

STUBBIN="$TMP/bin"
CAPTURE="$TMP/capture"
mkdir -p "$STUBBIN" "$CAPTURE" "$TMP/home" "$TMP/state"

# Capture the real tools before the stub directory takes over PATH.
REAL_GIT="$(command -v git)"
REAL_READLINK="$(command -v readlink)"
export PATH="$STUBBIN:$PATH"

# ── assertion harness ────────────────────────────────────────────────────────

fail() {
  printf 'FAIL %s/%s - %s\n' "$1" "$TOTAL" "$2" >&2
  exit 1
}

pass() {
  printf 'PASS %s/%s - %s\n' "$1" "$TOTAL" "$2"
}

assert_eq() {
  local want="$1" got="$2" n="$3" label="$4"
  if [ "$want" != "$got" ]; then
    fail "$n" "$label (expected '$want', got '$got')"
  fi
}

assert_contains() {
  local file="$1" needle="$2" n="$3" label="$4"
  if ! grep -qF -- "$needle" "$file"; then
    fail "$n" "$label (no '$needle' in $(basename "$file"))"
  fi
}

assert_not_contains() {
  local file="$1" needle="$2" n="$3" label="$4"
  if grep -qF -- "$needle" "$file"; then
    fail "$n" "$label (unexpected '$needle' in $(basename "$file"))"
  fi
}

assert_no_call() {
  local name="$1" n="$2" label="$3"
  if [ -s "$CAPTURE/$name" ]; then
    fail "$n" "$label ($name was invoked: $(tr '\n' ';' <"$CAPTURE/$name"))"
  fi
}

assert_line_present() {
  local file="$1" prefix="$2" n="$3" label="$4"
  if ! awk -v p="$prefix" 'index($0, p) == 1 { found = 1 } END { exit !found }' "$file"; then
    fail "$n" "$label (no banner line starting '$prefix')"
  fi
}

assert_line_has() {
  local file="$1" prefix="$2" needle="$3" n="$4" label="$5"
  if ! awk -v p="$prefix" -v s="$needle" \
    'index($0, p) == 1 && index($0, s) > 0 { found = 1 } END { exit !found }' "$file"; then
    fail "$n" "$label (no line starting '$prefix' containing '$needle')"
  fi
}

expect_status() {
  local want="$1" n="$2" label="$3"
  if [ "$STATUS" -ne "$want" ]; then
    fail "$n" "$label (exit $STATUS, expected $want; stderr: $(tr '\n' ' ' <"$TMP/err" | cut -c1-400))"
  fi
}

banner_line() {
  awk -v p="  $1:" 'index($0, p) == 1 { print; exit }' "$TMP/out"
}

nix_build_count() {
  if [ -f "$CAPTURE/nix" ]; then
    grep -cE '^build( |$)' "$CAPTURE/nix" || true
  else
    printf '0\n'
  fi
}

nix_toplevel_eval_count() {
  if [ -f "$CAPTURE/nix" ]; then
    grep -cE '^eval .*system\.build\.toplevel' "$CAPTURE/nix" || true
  else
    printf '0\n'
  fi
}

# ── stubs ────────────────────────────────────────────────────────────────────

write_stub() {
  local name="$1"
  cat >"$STUBBIN/$name"
  chmod +x "$STUBBIN/$name"
}

write_stub hostname <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$CAPTURE/hostname"
printf '%s\n' "\${STUB_HOSTNAME:-bee-gpd}"
EOF

write_stub nix <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$CAPTURE/nix"

# A host name the tree does not know: every evaluation of it fails.
if [ -n "\${STUB_UNKNOWN_HOST:-}" ]; then
  for arg in "\$@"; do
    case "\$arg" in
      *"\$STUB_UNKNOWN_HOST"*) exit 1 ;;
    esac
  done
fi

# "build" is dispatched before the evaluation answers below: the build argv
# itself contains system.build.toplevel, so an eval loop placed first would
# answer the build with a store path and make this branch unreachable.
if [ "\${1:-}" = "build" ]; then
  out=""
  prev=""
  for arg in "\$@"; do
    if [ "\$prev" = "--out-link" ]; then out="\$arg"; fi
    prev="\$arg"
  done
  # nix writes the out-link as a symlink to the built store path.
  if [ -n "\$out" ]; then
    ln -sfn "\${STUB_TOPLEVEL:-/nix/store/00000000000000000000000000000001-system}" "\$out"
  fi
  printf '%s\n' '@nix {"action":"msg","level":0,"msg":"stub"}' >&2
  sleep "\${STUB_BUILD_SLEEP:-0}"
  exit "\${STUB_BUILD_STATUS:-0}"
fi

for arg in "\$@"; do
  case "\$arg" in
    *builtins.attrNames*)
      printf 'true\n'
      exit 0
      ;;
  esac
done

for arg in "\$@"; do
  case "\$arg" in
    *hostPlatform.system*)
      printf '%s\n' "\${STUB_PLATFORM:-x86_64-linux}"
      exit 0
      ;;
  esac
done

for arg in "\$@"; do
  case "\$arg" in
    *system.build.toplevel*)
      printf '%s\n' "\${STUB_TOPLEVEL:-/nix/store/00000000000000000000000000000001-system}"
      exit 0
      ;;
  esac
done

exit 0
EOF

write_stub nom <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$CAPTURE/nom"
cat >/dev/null
exit "\${STUB_NOM_STATUS:-0}"
EOF

write_stub alejandra <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$CAPTURE/alejandra"
status="\${STUB_ALEJANDRA_STATUS:-0}"
if [ "\${1:-}" = "--check" ] && [ "\$status" -ne 0 ]; then
  printf '%s\n' '- ./broken.nix: unexpected TOKEN_ASSIGN at 1..2' >&2
fi
exit "\$status"
EOF

write_stub nix-instantiate <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$CAPTURE/nix-instantiate"
printf '%s\n' 'broken.nix:1:1: error: syntax error' >&2
exit "\${STUB_NIX_INSTANTIATE_STATUS:-1}"
EOF

write_stub nixos-rebuild <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$CAPTURE/nixos-rebuild"
if [ "\${1:-}" = "list-generations" ]; then
  printf '   1   current  2026-11-19\n'
  printf '   0  2026-11-01\n'
  exit "\${STUB_LIST_GEN_STATUS:-0}"
fi
# Mark the activation on stderr: the script must append activation output to
# the build log, so this line and the build's @nix line must both survive.
printf '%s\n' 'stub-activation-marker' >&2
exit "\${STUB_ACT_STATUS:-0}"
EOF

write_stub sudo <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$CAPTURE/sudo"
exit "\${STUB_SUDO_STATUS:-0}"
EOF

write_stub flock <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$CAPTURE/flock"
if [ "\${STUB_FLOCK_SLEEP:-0}" -gt 0 ]; then sleep "\$STUB_FLOCK_SLEEP"; fi
exit "\${STUB_FLOCK_STATUS:-0}"
EOF

write_stub systemctl <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$CAPTURE/systemctl"
count="\${STUB_FAILED_UNITS:-0}"
i=0
while [ "\$i" -lt "\$count" ]; do
  printf '%s\n' '● stub.service loaded failed failed Stub'
  i=\$((i + 1))
done
exit 0
EOF

write_stub notify-send <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$CAPTURE/notify-send"
exit "\${STUB_NOTIFY_STATUS:-0}"
EOF

write_stub readlink <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$CAPTURE/readlink"
path=""
for arg in "\$@"; do
  case "\$arg" in
    -*) ;;
    *) path="\$arg" ;;
  esac
done
case "\$path" in
  /run/current-system)
    printf '%s\n' "\${STUB_CURRENT_SYSTEM:-/nix/store/00000000000000000000000000000001-system}"
    ;;
  /run/booted-system)
    printf '%s\n' "\${STUB_BOOTED_SYSTEM:-/nix/store/00000000000000000000000000000001-system}"
    ;;
  *)
    exec "$REAL_READLINK" "\$@"
    ;;
esac
EOF

# ── fixtures (real git) ──────────────────────────────────────────────────────

gitq() {
  "$REAL_GIT" -c user.email=t@example.invalid -c user.name=t "$@"
}

make_repo() {
  local dir="$1" branch="${2:-main}"
  mkdir -p "$dir"
  "$REAL_GIT" -C "$dir" init -q
  "$REAL_GIT" -C "$dir" symbolic-ref HEAD "refs/heads/$branch"
  cat >"$dir/flake.nix" <<'NIX'
{
  # nixosConfigurations.bee-gpd and nixosConfigurations.bee-pc
  nixosConfigurations = {
    bee-gpd = { };
    bee-pc = { };
  };
}
NIX
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$dir/rebuild.sh"
  mkdir -p "$dir/modules"
  printf '%s\n' '{ }' >"$dir/modules/test.nix"
  gitq -C "$dir" add -A
  gitq -C "$dir" commit -q -m init
}

# ── runner ───────────────────────────────────────────────────────────────────

STATUS=0

reset_capture() {
  mkdir -p "$CAPTURE"
  rm -f "$CAPTURE"/*
}

invoke() {
  local script="$1" cwd="$2"
  shift 2
  reset_capture
  set +e
  (
    cd "$cwd" &&
      env -u DBUS_SESSION_BUS_ADDRESS \
        XDG_STATE_HOME="$TMP/state" \
        HOME="$TMP/home" \
        bash "$script" "$@"
  ) >"$TMP/out" 2>"$TMP/err"
  STATUS=$?
  set -e
}

run_rebuild() {
  local cwd="$1"
  shift
  invoke "$SCRIPT" "$cwd" "$@"
}

# ── fixtures ─────────────────────────────────────────────────────────────────

REPO="$TMP/repo"
make_repo "$REPO"

WTREPO="$TMP/wt-repo"
make_repo "$WTREPO"
WT="$TMP/wt"
"$REAL_GIT" -C "$WTREPO" worktree add -q "$WT" -b wt-branch

SCRIPTDIR="$TMP/scriptdir"
OUTSIDE="$TMP/outside"
mkdir -p "$SCRIPTDIR" "$OUTSIDE"
cp "$SCRIPT" "$SCRIPTDIR/rebuild.sh"
cp "$REPO/flake.nix" "$SCRIPTDIR/flake.nix"

export STUB_HOSTNAME=bee-gpd

# 1. --help exits 0 and documents the flag surface, the allowlist and the log dir.
run_rebuild "$REPO" --help
expect_status 0 1 "--help exits 0"
for needle in --dry-run --boot --force --host --help bee-pc bee-gpd nixos-rebuild; do
  assert_contains "$TMP/out" "$needle" 1 "--help documents $needle"
done
pass 1 "--help exits 0 and documents every flag, both allowlisted hosts and the log directory"

# 2. An unknown flag is a usage error on stderr with exit 2.
run_rebuild "$REPO" --nonsense
expect_status 2 2 "an unknown flag exits 2"
assert_contains "$TMP/err" "unknown option" 2 "an unknown flag is named on stderr"
assert_contains "$TMP/err" "Usage:" 2 "an unknown flag prints usage on stderr"
pass 2 "an unknown flag exits 2 with 'unknown option' and usage on stderr"

# 3. --host with no value is a usage error.
run_rebuild "$REPO" --host
expect_status 2 3 "--host with no value exits 2"
assert_contains "$TMP/err" "requires a value" 3 "--host with no value says it requires a value"
pass 3 "--host with no value exits 2 and says the option requires a value"

# 4. --dry-run and --boot are contradictory.
run_rebuild "$REPO" --dry-run --boot
expect_status 2 4 "--dry-run --boot exits 2"
assert_contains "$TMP/err" "cannot be combined" 4 "--dry-run --boot says the flags cannot be combined"
pass 4 "--dry-run --boot exits 2 and says the flags cannot be combined"

# 5. With no --host the target host comes from the machine's hostname.
STUB_HOSTNAME=bee-pc
run_rebuild "$REPO" --dry-run --force
STUB_HOSTNAME=bee-gpd
expect_status 0 5 "the hostname-derived run completes"
assert_line_has "$TMP/out" "  host:" "bee-pc" 5 "the banner reports the hostname-derived host"
pass 5 "with no --host the banner reports the hostname (bee-pc)"

# 6. A host outside the local allowlist is refused, naming the CI path.
run_rebuild "$REPO" --host homelab
expect_status 2 6 "--host homelab exits 2"
assert_contains "$TMP/err" "limited to: bee-pc bee-gpd" 6 "the refusal names the allowlist"
if ! grep -qF -- "workflow_dispatch" "$TMP/err" && ! grep -qF -- "nix run .#deploy" "$TMP/err"; then
  fail 6 "the refusal does not name workflow_dispatch or nix run .#deploy"
fi
pass 6 "--host homelab exits 2 naming the allowlist and the CI/deploy path"

# 7. A host whose platform is not x86_64-linux is refused. `pikvm` is a real
#    aarch64 nixosConfiguration, so the refusal must name the platform.
export STUB_PLATFORM=aarch64-linux
run_rebuild "$REPO" --host pikvm
unset STUB_PLATFORM
expect_status 2 7 "--host pikvm on an aarch64 platform exits 2"
assert_contains "$TMP/err" "aarch64-linux" 7 "the refusal names the evaluated platform"
pass 7 "a non-x86_64-linux host exits 2 with the platform named"

# 8. A host that is not a nixosConfiguration in the tree is refused.
export STUB_UNKNOWN_HOST=nope
STUB_PLATFORM=""
run_rebuild "$REPO" --host nope
unset STUB_UNKNOWN_HOST
unset STUB_PLATFORM
expect_status 2 8 "--host nope exits 2"
assert_contains "$TMP/err" "is not a nixosConfiguration" 8 "the refusal says the host is not a nixosConfiguration"
pass 8 "an unknown nixosConfiguration exits 2 with an explicit message"

# 9. From a linked worktree the tree is that worktree, not the main checkout.
run_rebuild "$WT" --dry-run --force
expect_status 0 9 "the worktree run completes"
tree_line="$(banner_line tree)"
case "$tree_line" in
  *"$WT"*) ;;
  *) fail 9 "the tree banner line does not name the worktree '$WT' (got '$tree_line')" ;;
esac
case "$tree_line" in
  *"$WTREPO"*) fail 9 "the tree banner line names the main checkout instead of the worktree" ;;
esac
pass 9 "the tree banner line names the linked worktree and not the main checkout"

# 10. Outside any git repository the script falls back to its own directory.
invoke "$SCRIPTDIR/rebuild.sh" "$OUTSIDE" --dry-run --force
assert_line_has "$TMP/out" "  tree:" "$SCRIPTDIR" 10 "the tree banner line names the script directory"
assert_contains "$TMP/out" "script directory" 10 "the banner says why it chose the script directory"
pass 10 "outside git the banner reports the script directory and the reason"

# 11. The banner carries every orientation field.
run_rebuild "$REPO" --dry-run --force
for label in tree host branch commit changes worktree flake.lock script; do
  assert_line_present "$TMP/out" "  $label:" 11 "the banner has a '$label:' line"
done
pass 11 "the banner has tree, host, branch, commit, changes, worktree, flake.lock and script lines"

# 12. A detached HEAD is reported as detached.
DETACHED="$TMP/detached"
make_repo "$DETACHED"
"$REAL_GIT" -C "$DETACHED" checkout -q --detach
run_rebuild "$DETACHED" --dry-run --force
expect_status 0 12 "the detached-HEAD run completes"
assert_line_has "$TMP/out" "  branch:" "detached" 12 "the branch banner line reports detached"
pass 12 "on a detached HEAD the branch banner line reports detached"

# 13. A missing local main is decorative, not fatal.
NOMAIN="$TMP/nomain"
make_repo "$NOMAIN" trunk
run_rebuild "$NOMAIN" --force --dry-run
expect_status 0 13 "a missing local main does not abort the run"
assert_line_present "$TMP/out" "  flake.lock:" 13 "the flake.lock banner line is still printed"
pass 13 "with no local main the run exits 0 and still prints the flake.lock line"

# 14. An untracked Nix file is refused and listed.
GUARD="$TMP/guard"
make_repo "$GUARD"
: >"$GUARD/scratch.nix"
run_rebuild "$GUARD" --dry-run
expect_status 2 14 "an untracked .nix file exits 2"
assert_contains "$TMP/err" "scratch.nix" 14 "the refusal lists the untracked file"
assert_contains "$TMP/err" "--force" 14 "the refusal mentions --force"
pass 14 "an untracked .nix file exits 2, is listed, and --force is named"

# 15. --force bypasses the untracked-file guard and the build is attempted.
run_rebuild "$GUARD" --force --dry-run
expect_status 0 15 "--force with an untracked .nix file does not exit 2"
assert_eq 1 "$(nix_build_count)" 15 "--force still attempts exactly one build"
pass 15 "--force bypasses the untracked-file guard and builds once"

# 16. --force does not bypass host validation.
run_rebuild "$GUARD" --force --host homelab
expect_status 2 16 "--force --host homelab exits 2"
assert_contains "$TMP/err" "limited to: bee-pc bee-gpd" 16 "--force does not bypass the allowlist"
pass 16 "--force does not bypass host validation"

# 17. A clean tree already running the evaluated toplevel is a success with no build.
CLEAN="$TMP/clean"
make_repo "$CLEAN"
run_rebuild "$CLEAN"
expect_status 0 17 "the nothing-to-do path exits 0"
assert_contains "$TMP/out" "nothing to do" 17 "the nothing-to-do path says so"
assert_eq 0 "$(nix_build_count)" 17 "the nothing-to-do path never builds"
pass 17 "a clean tree equal to /run/current-system prints nothing to do, exits 0 and never builds"

# 18. A clean tree with a different toplevel builds exactly once.
DIFFERENT="$TMP/different"
make_repo "$DIFFERENT"
export STUB_TOPLEVEL=/nix/store/00000000000000000000000000000002-system
run_rebuild "$DIFFERENT" --dry-run
unset STUB_TOPLEVEL
expect_status 0 18 "a clean tree with a different toplevel builds and exits 0"
assert_eq 1 "$(nix_build_count)" 18 "a clean tree with a different toplevel builds exactly once"
pass 18 "a clean tree whose toplevel differs from /run/current-system builds once"

# 19. A dirty tree builds without the toplevel evaluation.
DIRTY="$TMP/dirty"
make_repo "$DIRTY"
printf '\n# dirty\n' >>"$DIRTY/modules/test.nix"
run_rebuild "$DIRTY" --dry-run
expect_status 0 19 "a dirty tree builds and exits 0"
assert_eq 1 "$(nix_build_count)" 19 "a dirty tree builds once"
assert_eq 0 "$(nix_toplevel_eval_count)" 19 "a dirty tree skips the toplevel evaluation"
pass 19 "a dirty tree builds without running the nothing-to-do evaluation"

# 20. rebuild.sh stays bash-3 compatible.
if grep -qE 'declare[[:space:]]+-A' "$SCRIPT"; then
  fail 20 "rebuild.sh uses 'declare -A' (not bash 3 compatible)"
fi
if grep -qw 'mapfile' "$SCRIPT"; then
  fail 20 "rebuild.sh uses 'mapfile' (not bash 3 compatible)"
fi
if grep -qE '\$\{[a-z][[:alnum:]_]*,,}' "$SCRIPT"; then
  fail 20 "rebuild.sh lowercases with \${var,,} (not bash 3 compatible)"
fi
pass 20 "rebuild.sh has no declare -A, mapfile or \${var,,}"

# ── build contract (spec 32, Unit 3) ────────────────────────────────────────
#
# Assertions 21-33. Everything above this line is the preflight contract.

# The argv of a `nix build` invocation, if the run made one.
nix_build_line() {
  if [ -f "$CAPTURE/nix" ]; then
    awk '/^build( |$)/ { print; exit }' "$CAPTURE/nix"
  fi
}

# Regular *.log files in the state directory created after <marker>.
logs_newer_than() {
  find "$STATE_DIR" -maxdepth 1 -type f -name '*.log' -newer "$1" 2>/dev/null || true
}

# Anything named `result` left in the state directory.
state_result_leftovers() {
  find "$STATE_DIR" -maxdepth 1 -name 'result' 2>/dev/null || true
}

STATE_DIR="$TMP/state/nixos-rebuild"

# 21. The format step covers exactly the tracked Nix files: never an untracked
#     file, never a bare `.`.
FMT="$TMP/fmt"
make_repo "$FMT"
printf '%s\n' '{ }' >"$FMT/extra.nix"
run_rebuild "$FMT" --force --dry-run
expect_status 0 21 "the untracked-file --force run completes"
if [ ! -s "$CAPTURE/alejandra" ]; then
  fail 21 "alejandra was never invoked"
fi
if ! grep -qF 'flake.nix' "$CAPTURE/alejandra"; then
  fail 21 "alejandra was not given flake.nix (got: $(tr '\n' ';' <"$CAPTURE/alejandra"))"
fi
if ! grep -qF 'modules/test.nix' "$CAPTURE/alejandra"; then
  fail 21 "alejandra was not given modules/test.nix"
fi
if grep -qF 'extra.nix' "$CAPTURE/alejandra"; then
  fail 21 "alejandra was given the untracked extra.nix"
fi
if grep -qE '^\.$' "$CAPTURE/alejandra"; then
  fail 21 "alejandra was given a bare '.'"
fi
pass 21 "alejandra formats the tracked Nix files, never extra.nix, never a bare ."

# 22. A failing alejandra aborts with exit 1 before the build.
FAILDIR="$TMP/failfmt"
make_repo "$FAILDIR"
STUB_ALEJANDRA_STATUS=1 run_rebuild "$FAILDIR" --force --dry-run
expect_status 1 22 "a failing alejandra exits 1"
assert_contains "$TMP/err" "formatting failed" 22 "the failure says formatting failed"
assert_eq 0 "$(nix_build_count)" 22 "a formatting failure never builds"
pass 22 "a failing alejandra exits 1 with 'formatting failed' and never builds"

# 23. The diagnostic names the file alejandra --check flagged, and that file is
#     re-parsed with nix-instantiate --parse.
assert_contains "$TMP/err" "broken.nix" 23 "stderr names the flagged file"
if [ ! -s "$CAPTURE/nix-instantiate" ]; then
  fail 23 "the flagged file was not re-parsed with nix-instantiate"
fi
if ! grep -qF 'broken.nix' "$CAPTURE/nix-instantiate"; then
  fail 23 "nix-instantiate was not given broken.nix"
fi
pass 23 "the formatting failure names broken.nix and re-parses it with nix-instantiate"

# 24. The pre-build diff uses the '*.nix' pathspec, so an uncommitted change to
#     the top-level flake.nix appears in the output.
DIFFFIX="$TMP/difffix"
make_repo "$DIFFFIX"
printf '\n# uncommitted-top-level-flake-change\n' >>"$DIFFFIX/flake.nix"
run_rebuild "$DIFFFIX" --force --dry-run
expect_status 0 24 "the dirty-flake run completes"
assert_contains "$TMP/out" "flake.nix" 24 "the diff output names flake.nix"
assert_contains "$TMP/out" "uncommitted-top-level-flake-change" 24 "the diff shows the uncommitted top-level change"
pass 24 "an uncommitted top-level flake.nix change appears in the diff output"

# 25. The build is the internal-json, verbose one, so nom can consume it.
BUILD="$TMP/build"
make_repo "$BUILD"
run_rebuild "$BUILD" --dry-run --force
expect_status 0 25 "the build run completes"
build_argv="$(nix_build_line)"
if [ -z "$build_argv" ]; then
  fail 25 "no nix build invocation was captured"
fi
case "$build_argv" in
  *"--log-format internal-json"*) ;;
  *) fail 25 "the build lacks '--log-format internal-json' (got: $build_argv)" ;;
esac
case "$build_argv" in
  *" -v"*) ;;
  *) fail 25 "the build lacks -v (got: $build_argv)" ;;
esac
pass 25 "the build passes --log-format internal-json and -v"

# 26. nom consumes that stream.
if [ ! -s "$CAPTURE/nom" ]; then
  fail 26 "nom was never invoked"
fi
if ! grep -qF -- '--json' "$CAPTURE/nom"; then
  fail 26 "nom was not given --json (got: $(tr '\n' ';' <"$CAPTURE/nom"))"
fi
pass 26 "nom is invoked with --json"

# 27. The build log is <state>/<tree>-<timestamp>.log and last.log points at it.
LOGFIX="$TMP/logfix"
make_repo "$LOGFIX"
LOGMARK="$TMP/logmark-27"
: >"$LOGMARK"
run_rebuild "$LOGFIX" --dry-run --force
expect_status 0 27 "the logged run completes"
new_logs="$(logs_newer_than "$LOGMARK")"
if [ -z "$new_logs" ]; then
  fail 27 "no *.log file was created under $STATE_DIR"
fi
assert_eq 1 "$(printf '%s\n' "$new_logs" | grep -c . || true)" 27 "the run writes exactly one log file"
log_file="$(printf '%s\n' "$new_logs" | awk 'NR == 1 { print }')"
if ! printf '%s\n' "$log_file" | grep -qE '^.+-[0-9][A-Za-z0-9:._-]*\.log$'; then
  fail 27 "the log file name '$(basename "$log_file")' is not <tree>-<timestamp>.log"
fi
if [ ! -L "$STATE_DIR/last.log" ]; then
  fail 27 "last.log is not a symlink"
fi
last_target="$("$REAL_READLINK" -f "$STATE_DIR/last.log" 2>/dev/null || true)"
assert_eq "$log_file" "$last_target" 27 "last.log resolves to the new log"
pass 27 "the run writes one <tree>-<timestamp>.log and last.log points at it"

# 28. The exit status comes from nix, not nom: nix failing while nom succeeds is
#     a failure, and the log is kept.
FAILBUILD="$TMP/failbuild"
make_repo "$FAILBUILD"
FAILMARK="$TMP/logmark-28"
: >"$FAILMARK"
STUB_BUILD_STATUS=1 STUB_NOM_STATUS=0 run_rebuild "$FAILBUILD" --dry-run --force
expect_status 1 28 "nix failing while nom succeeds exits 1"
if [ -z "$(logs_newer_than "$FAILMARK")" ]; then
  fail 28 "the failed run kept no log file"
fi
pass 28 "nix failing while nom succeeds exits 1 and the log survives"

# 29. ... and nix succeeding while nom fails is still a success.
OKNOM="$TMP/oknom"
make_repo "$OKNOM"
STUB_BUILD_STATUS=0 STUB_NOM_STATUS=1 run_rebuild "$OKNOM" --dry-run --force
expect_status 0 29 "nix succeeding while nom fails exits 0"
pass 29 "nix succeeding while nom fails exits 0"

# 30. A successful run reports built/log/replay and leaves no out-link behind.
SUCCESS="$TMP/success"
make_repo "$SUCCESS"
rm -f "$STATE_DIR/result"
run_rebuild "$SUCCESS" --dry-run --force
expect_status 0 30 "the successful run exits 0"
for needle in 'built:' 'log:' 'replay:'; do
  assert_contains "$TMP/out" "$needle" 30 "a successful run prints $needle"
done
if [ -L "$SUCCESS/result" ] || [ -e "$SUCCESS/result" ]; then
  fail 30 "the tree still has a result entry"
fi
if [ -n "$(state_result_leftovers)" ]; then
  fail 30 "the state directory still has a result entry"
fi
pass 30 "a successful run prints built/log/replay and leaves no result behind"

# 31. SIGINT during the build exits 130, names the log and removes the out-link.
INT="$TMP/interrupt"
make_repo "$INT"
rm -f "$STATE_DIR/result"
reset_capture
set +e
# Job control must be on for this launch: a background command started by a
# non-interactive shell inherits SIGINT as ignored, so the script could never
# install its trap and the kill below would do nothing.
set -m
(
  cd "$INT" || exit 99
  exec env -u DBUS_SESSION_BUS_ADDRESS \
    XDG_STATE_HOME="$TMP/state" \
    HOME="$TMP/home" \
    STUB_BUILD_SLEEP=3 \
    bash "$SCRIPT" --dry-run --force
) >"$TMP/int.out" 2>"$TMP/int.err" &
int_pid=$!
sleep 0.5
kill -INT "$int_pid" 2>/dev/null
wait "$int_pid"
int_status=$?
set +m
set -e
assert_eq 130 "$int_status" 31 "SIGINT during the build exits 130"
if [ -z "$(nix_build_line)" ]; then
  fail 31 "the interrupted run never reached the build"
fi
if ! grep -qF '.log' "$TMP/int.out" && ! grep -qF '.log' "$TMP/int.err"; then
  fail 31 "the interrupt does not name a log path"
fi
if [ -n "$(state_result_leftovers)" ]; then
  fail 31 "the interrupt left the out-link behind"
fi
pass 31 "SIGINT exits 130, names the log and removes the out-link"

# 32. --dry-run never activates through nixos-rebuild.
run_rebuild "$SUCCESS" --dry-run --force
expect_status 0 32 "the --dry-run run completes"
assert_no_call nixos-rebuild 32 "--dry-run never invokes nixos-rebuild"
pass 32 "--dry-run never invokes nixos-rebuild"

# 33. The build argv names this configuration, so nom's output is about it.
run_rebuild "$SUCCESS" --dry-run --force
expect_status 0 33 "the argv run completes"
build_argv="$(nix_build_line)"
if [ -z "$build_argv" ]; then
  fail 33 "no nix build invocation was captured"
fi
case "$build_argv" in
  *".#nixosConfigurations.bee-gpd.config.system.build.toplevel"*) ;;
  *) fail 33 "the build argv does not name the configuration (got: $build_argv)" ;;
esac
pass 33 "the build argv names .#nixosConfigurations.bee-gpd.config.system.build.toplevel"

# ── activation contract (spec 32, Unit 4) ───────────────────────────────────
#
# Assertions 34-46. Everything above this line is preflight and build.

# Like `invoke`, but with stdin on /dev/null so `[ -t 0 ]` is false and the
# script takes its non-interactive sudo path. Every assertion below uses this.
invoke_switch() {
  local cwd="$1"
  shift
  reset_capture
  set +e
  (
    cd "$cwd" &&
      env -u DBUS_SESSION_BUS_ADDRESS \
        XDG_STATE_HOME="$TMP/state" \
        HOME="$TMP/home" \
        bash "$SCRIPT" "$@" </dev/null
  ) >"$TMP/out" 2>"$TMP/err"
  STATUS=$?
  set -e
}

run_switch() {
  local cwd="$1"
  shift
  invoke_switch "$cwd" "$@"
}

# The most recently written build log, if any.
newest_log() {
  if ls -t "$STATE_DIR"/*.log >/dev/null 2>&1; then
    ls -t "$STATE_DIR"/*.log | awk 'NR == 1 { print }'
  fi
}

# The activation argv: everything except the list-generations probe.
activation_argv() {
  awk '!/^list-generations( |$)/ { print; exit }' "$CAPTURE/nixos-rebuild"
}

ACT="$TMP/act"
make_repo "$ACT"

# 34. Without a tty a failing `sudo -n true` aborts before activation and points
#     at interactive use.
STUB_SUDO_STATUS=1 run_switch "$ACT" --force
expect_status 1 34 "a failing non-interactive sudo exits 1"
assert_contains "$TMP/err" "needs a password" 34 "the failure says a password is needed"
assert_contains "$TMP/err" "not a terminal" 34 "the failure says stdin is not a terminal"
assert_no_call nixos-rebuild 34 "a failing non-interactive sudo never activates"
pass 34 "non-interactive sudo failure exits 1, names the terminal, and never invokes nixos-rebuild"

# 35. The same non-interactive path activates once sudo credentials exist.
STUB_SUDO_STATUS=0 run_switch "$ACT" --force
expect_status 0 35 "the non-interactive switch exits 0"
if [ ! -s "$CAPTURE/nixos-rebuild" ]; then
  fail 35 "nixos-rebuild was never invoked"
fi
pass 35 "a non-interactive switch runs nixos-rebuild and exits 0"

# 36. The activation invocation is `switch --flake .#<host> --sudo`.
STUB_SUDO_STATUS=0 run_switch "$ACT" --force
expect_status 0 36 "the switch run exits 0"
act_argv="$(activation_argv)"
if [ -z "$act_argv" ]; then
  fail 36 "no non-list-generations nixos-rebuild invocation was captured"
fi
if ! printf '%s\n' "$act_argv" | grep -qE '(^| )switch( |$)'; then
  fail 36 "the activation argv lacks 'switch' (got: $act_argv)"
fi
if ! printf '%s\n' "$act_argv" | grep -qF -- '--flake .#bee-gpd'; then
  fail 36 "the activation argv lacks '--flake .#bee-gpd' (got: $act_argv)"
fi
if ! printf '%s\n' "$act_argv" | grep -qF -- '--sudo'; then
  fail 36 "the activation argv lacks '--sudo' (got: $act_argv)"
fi
pass 36 "the activation invocation is 'switch --flake .#bee-gpd --sudo'"

# 37. --boot activates with `boot`, not `switch`, and still uses --sudo.
STUB_SUDO_STATUS=0 run_switch "$ACT" --boot --force
expect_status 0 37 "the --boot run exits 0"
act_argv="$(activation_argv)"
if [ -z "$act_argv" ]; then
  fail 37 "no activation invocation was captured"
fi
if ! printf '%s\n' "$act_argv" | grep -qE '(^| )boot( |$)'; then
  fail 37 "the --boot activation argv lacks 'boot' (got: $act_argv)"
fi
if printf '%s\n' "$act_argv" | grep -qE '(^| )switch( |$)'; then
  fail 37 "the --boot activation argv uses 'switch' (got: $act_argv)"
fi
if ! printf '%s\n' "$act_argv" | grep -qF -- '--sudo'; then
  fail 37 "the --boot activation argv lacks '--sudo' (got: $act_argv)"
fi
pass 37 "--boot activates with 'boot --flake .#bee-gpd --sudo', never 'switch'"

# 38. Activation output is appended to the same log: the activation marker and
#     the build's @nix line must both be present, so this is append, not
#     truncate.
STUB_SUDO_STATUS=0 run_switch "$ACT" --force
expect_status 0 38 "the logged switch exits 0"
log38="$(newest_log)"
if [ -z "$log38" ]; then
  fail 38 "no build log was written"
fi
assert_contains "$log38" "stub-activation-marker" 38 "the activation output is in the log"
assert_contains "$log38" "@nix" 38 "the build output survives activation (append, not truncate)"
pass 38 "activation output is appended to the build log, which still holds the build output"

# 39. nom never sees the activation stream: one nom invocation for the build.
STUB_SUDO_STATUS=0 run_switch "$ACT" --force
expect_status 0 39 "the nom-counted switch exits 0"
nom_lines="$(grep -c . "$CAPTURE/nom" 2>/dev/null || true)"
assert_eq 1 "$nom_lines" 39 "nom runs exactly once (build only), never for activation"
pass 39 "nom runs exactly once, for the build only"

# 40. Activation is serialised by a lock file under the state directory.
STUB_SUDO_STATUS=0 run_switch "$ACT" --force
expect_status 0 40 "the locked switch exits 0"
if [ ! -s "$CAPTURE/flock" ]; then
  fail 40 "flock was never invoked"
fi
if [ ! -e "$STATE_DIR/lock" ]; then
  fail 40 "no lock file at $STATE_DIR/lock"
fi
pass 40 "the activation takes a flock and leaves $STATE_DIR/lock behind"

# 41. The waiting message is only reachable when the non-blocking `flock -n`
#     attempt loses the race. The stub answers STUB_FLOCK_STATUS for every
#     invocation, so failing only the first attempt cannot be staged. Assert
#     instead that with the lock free the script does not claim to wait, and
#     that it probes with `flock -n` before the blocking call that follows.
STUB_FLOCK_STATUS=0 run_switch "$ACT" --force
expect_status 0 41 "the free-lock switch exits 0"
assert_not_contains "$TMP/err" "another rebuild holds the activation lock" 41 \
  "a free lock does not print the waiting line"
if [ ! -s "$CAPTURE/flock" ]; then
  fail 41 "flock was never invoked"
fi
first_flock="$(awk 'NR == 1 { print }' "$CAPTURE/flock")"
case "$first_flock" in
  *"-n"*) ;;
  *) fail 41 "the first flock call is not a non-blocking probe (got: $first_flock)" ;;
esac
if ! awk 'NR > 1 && $0 !~ /-n/ { found = 1 } END { exit !found }' "$CAPTURE/flock"; then
  fail 41 "no blocking flock followed the non-blocking probe"
fi
pass 41 "the lock is probed with flock -n before the blocking flock, and no waiting line is printed"

# 42. A switch whose /run/current-system is not the built path fails loudly.
STUB_SUDO_STATUS=0 \
  STUB_CURRENT_SYSTEM=/nix/store/00000000000000000000000000000099-system \
  run_switch "$ACT" --force
expect_status 1 42 "a switch that did not take effect exits 1"
assert_contains "$TMP/err" "activation did not take effect" 42 "the mismatch is named on stderr"
pass 42 "a /run/current-system mismatch exits 1 with 'activation did not take effect'"

# 43. --boot makes no equality claim about /run/current-system.
STUB_SUDO_STATUS=0 \
  STUB_CURRENT_SYSTEM=/nix/store/00000000000000000000000000000099-system \
  run_switch "$ACT" --boot --force
expect_status 0 43 "--boot with a different current-system exits 0"
assert_not_contains "$TMP/err" "activation did not take effect" 43 \
  "--boot makes no current-system equality claim"
pass 43 "--boot makes no current-system equality claim"

# 44. A failing list-generations does not abort; the generation line still prints.
STUB_SUDO_STATUS=0 STUB_LIST_GEN_STATUS=1 run_switch "$ACT" --force
expect_status 0 44 "a failing list-generations does not change the exit code"
assert_line_present "$TMP/out" "  generation:" 44 "the generation line still prints"
pass 44 "a failing list-generations is tolerated and the generation line still prints"

# 45. The report counts failed units, and a stale booted system prints the
#     reboot note.
STUB_SUDO_STATUS=0 \
  STUB_FAILED_UNITS=2 \
  STUB_BOOTED_SYSTEM=/nix/store/00000000000000000000000000000002-system \
  run_switch "$ACT" --force
expect_status 0 45 "the reporting switch exits 0"
assert_contains "$TMP/out" "2 failed" 45 "stdout reports two failed units"
assert_contains "$TMP/err" "reboot" 45 "a differing booted system prints the reboot note"
pass 45 "stdout reports '2 failed' and a differing booted system prints the reboot note"

# 46. A failing notify-send never turns a successful switch into a failure.
STUB_SUDO_STATUS=0 STUB_NOTIFY_STATUS=1 run_switch "$ACT" --force
expect_status 0 46 "a failing notify-send leaves the exit code at 0"
pass 46 "a failing notify-send leaves the exit code at 0"

# ── config changes the script relies on (spec 32, Unit 5) ───────────────────
#
# Assertions 47-51. The script is only safe to hand to a reader once the
# config it depends on is in place: nom on PATH, a bounded boot menu, the
# alias, a CI lane, and docs that no longer promise the removed flags.

# 47. nix-output-monitor is provided by dev-tools, and only there (FR-32).
DEVTOOLS="$ROOT/modules/aspects/dev-tools.nix"
COMMON="$ROOT/modules/aspects/common.nix"
assert_contains "$DEVTOOLS" "nix-output-monitor" 47 \
  "nix-output-monitor is missing from modules/aspects/dev-tools.nix"
assert_not_contains "$COMMON" "nix-output-monitor" 47 \
  "nix-output-monitor still appears in modules/aspects/common.nix"
pass 47 "nix-output-monitor is in dev-tools.nix and absent from common.nix"

# 48. bee-gpd keeps a single generation, with the ESP rationale spelled out
#     (FR-33 as superseded by Amendment 1).
BEEGPD="$ROOT/hosts/bee-gpd/default.nix"
assert_contains "$BEEGPD" "configurationLimit = 1;" 48 \
  "hosts/bee-gpd/default.nix lacks 'configurationLimit = 1;'"
assert_contains "$BEEGPD" "NixOS generation costs" 48 \
  "hosts/bee-gpd/default.nix lacks the ESP rationale line 'NixOS generation costs'"
pass 48 "bee-gpd pins configurationLimit = 1 and states the ESP generation cost"

# 49. The shell offers `sh` to other shells and the rebuild alias (FR-34).
HOMEZSH="$ROOT/modules/aspects/home-zsh.nix"
assert_contains "$HOMEZSH" 'sh = "bash"' 49 \
  'modules/aspects/home-zsh.nix lacks the sh = "bash" alias'
assert_contains "$HOMEZSH" 'rebuild = "sh ~/nixos/rebuild.sh"' 49 \
  'modules/aspects/home-zsh.nix lacks rebuild = "sh ~/nixos/rebuild.sh"'
pass 49 'home-zsh.nix exposes sh = "bash" and the rebuild alias'

# 50. CI runs this suite, so the contract cannot rot between local runs
#     (FR-37).
PRWORKFLOW="$ROOT/.github/workflows/pr.yaml"
assert_contains "$PRWORKFLOW" "scripts/tests/test-rebuild.sh" 50 \
  "the PR workflow never runs scripts/tests/test-rebuild.sh"
pass 50 "the PR workflow runs scripts/tests/test-rebuild.sh"

# 51. No tracked Markdown still tells a reader to rebuild a host with the flag
#     this script no longer has. `git grep` searches tracked files only, so
#     untracked worktrees and build outputs cannot fail the assertion, and
#     exit 1 means "no matches", which is the pass.
STALEREFS="$TMP/stalerefs-51"
: >"$STALEREFS"
set +e
"$REAL_GIT" -C "$ROOT" grep -nE -- \
  '--homelab|--pikvm|--protecli-vault|10\.0\.0\.150' -- '*.md' >"$STALEREFS" 2>&1
stale_status=$?
set -e
case "$stale_status" in
  0)
    fail 51 "a tracked *.md still mentions a removed flag or host address: $(awk 'NR == 1 { print }' "$STALEREFS")"
    ;;
  1) ;;
  *)
    fail 51 "git grep failed with exit $stale_status: $(awk 'NR == 1 { print }' "$STALEREFS")"
    ;;
esac
pass 51 "no tracked *.md mentions --homelab, --pikvm, --protecli-vault or 10.0.0.150"

printf '\nall %s assertions passed\n' "$TOTAL"
