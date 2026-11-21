#!/usr/bin/env bash
#
# rebuild.sh — preflight the tree, build this machine's NixOS generation, then
# activate it. Spec 32, tasks 2.0-4.0: tree/host resolution, orientation banner,
# guards, the alejandra format step, a `nom`-monitored build with a real log,
# serialised activation, verification and notification.
#
# Local rebuilds are limited to the x86_64-linux desktops (bee-pc, bee-gpd);
# every other host is built and deployed by CI (workflow_dispatch) or deploy-rs.
set -euo pipefail

ALLOWED_HOSTS="bee-pc bee-gpd"
EXPECTED_PLATFORM="x86_64-linux"

usage() {
  cat <<'EOF'
Usage: rebuild.sh [options]

Build this machine's NixOS configuration from the current tree (the git
toplevel, or this script's directory when it is not inside a git work tree).

Options:
  --dry-run       Build only; do not activate the new generation.
  --boot          Install the new generation for the next boot instead of
                  switching to it now.
  --force         Build even when the tree looks unchanged, and skip the
                  untracked-Nix-file guard.
  --host <name>   Build for <name> instead of this machine's hostname.
  -h, --help      Print this help and exit.

Local rebuilds are limited to: bee-pc bee-gpd  (x86_64-linux only).
Every other host is built and deployed elsewhere, either by CI
(workflow_dispatch) or by:
  nix run .#deploy -- .#<host> --skip-checks -- -L

State and build logs live in the "nixos-rebuild" directory, for example
  ${XDG_STATE_HOME:-$HOME/.local/state}/nixos-rebuild

Exit codes: 0 success or nothing to do, 1 build/activation/verification
failure, 2 usage error or refused input, 130 interrupted.
EOF
}

# ── 1. arguments ────────────────────────────────────────────────────────────

DRY_RUN=false
BOOT=false
FORCE=false
HELP=false
HOST=""
HOST_FROM_FLAG=false

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      HELP=true
      ;;
    --dry-run)
      DRY_RUN=true
      ;;
    --boot)
      BOOT=true
      ;;
    --force)
      FORCE=true
      ;;
    --host)
      if [ "$#" -lt 2 ]; then
        printf 'error: --host requires a value\n' >&2
        usage >&2
        exit 2
      fi
      HOST="$2"
      HOST_FROM_FLAG=true
      shift
      ;;
    *)
      printf 'error: unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

# --help is answered from the arguments alone: no git, no nix, no cwd probing.
if $HELP; then
  usage
  exit 0
fi

if $DRY_RUN && $BOOT; then
  printf 'error: --dry-run and --boot cannot be combined\n' >&2
  usage >&2
  exit 2
fi

# ── 2. resolve the tree ─────────────────────────────────────────────────────

CALLER_PWD="$PWD"
if git_toplevel="$(git rev-parse --show-toplevel 2>/dev/null)" &&
  [ -n "$git_toplevel" ] && [ -f "$git_toplevel/flake.nix" ]; then
  TREE="$(cd "$git_toplevel" && pwd)"
  TREE_REASON="git toplevel of $CALLER_PWD"
else
  TREE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  TREE_REASON="script directory (not inside a git work tree)"
fi
cd "$TREE"

# ── 3. resolve and validate the host ────────────────────────────────────────

if $HOST_FROM_FLAG; then
  HOST_SOURCE="--host"
else
  HOST="$(hostname -s)"
  HOST_SOURCE="hostname"
fi

# a. Is it a nixosConfiguration at all? The attribute set is what is queried, not
#    the host's own options: some configurations predate nixpkgs.hostPlatform,
#    so evaluating them would fail for a reason that is not "no such host".
if ! exists="$(nix eval ".#nixosConfigurations" --apply "names: builtins.elem \"$HOST\" (builtins.attrNames names)" 2>/dev/null)"; then
  printf "error: host '%s' is not a nixosConfiguration in %s\n" "$HOST" "$TREE" >&2
  exit 2
fi
if [ "$exists" != "true" ]; then
  printf "error: host '%s' is not a nixosConfiguration in %s\n" "$HOST" "$TREE" >&2
  exit 2
fi

# b. What does it build for? Queried through the derivation set so it answers
#    for every host, including those on the legacy nixpkgs.system.
if ! platform="$(nix eval --raw ".#nixosConfigurations.$HOST.pkgs.stdenv.hostPlatform.system" 2>/dev/null)"; then
  printf "error: refusing host '%s': could not evaluate its platform\n" "$HOST" >&2
  exit 2
fi

# c. Only native-buildable hosts may be rebuilt here.
if [ "$platform" != "$EXPECTED_PLATFORM" ]; then
  printf "error: refusing host '%s': evaluates to %s, expected %s\n" \
    "$HOST" "$platform" "$EXPECTED_PLATFORM" >&2
  exit 2
fi

# d. Only the local desktops are in the allowlist.
case "$HOST" in
  bee-pc|bee-gpd) ;;
  *)
    printf "error: refusing host '%s': local rebuilds are limited to: %s\n" \
      "$HOST" "$ALLOWED_HOSTS" >&2
    printf '       use CI (workflow_dispatch) or: nix run .#deploy -- .#<host> --skip-checks -- -L\n' >&2
    exit 2
    ;;
esac

# ── 4. orientation banner ───────────────────────────────────────────────────
#
# Every field is best effort: a field that cannot be determined prints
# "unknown" and never aborts the run. A non-git tree still prints all lines.

banner() {
  printf '  %-10s %s\n' "$1:" "$2"
}

banner tree "$TREE ($TREE_REASON)"
banner host "$HOST ($HOST_SOURCE)"

branch="$(git branch --show-current 2>/dev/null || true)"
[ -n "$branch" ] || branch="detached"
banner branch "$branch"

commit="$(git rev-parse --short HEAD 2>/dev/null || true)"
[ -n "$commit" ] || commit="unknown"
banner commit "$commit"

if changes_raw="$(git status --porcelain 2>/dev/null)"; then
  changes_count="$(printf '%s\n' "$changes_raw" | grep -c . || true)"
  banner changes "$changes_count dirty files"
else
  banner changes unknown
fi

git_dir="$(git rev-parse --git-dir 2>/dev/null || true)"
if [ -n "$git_dir" ] && [ -f "$git_dir/commondir" ]; then
  banner worktree "linked worktree"
elif [ -n "$git_dir" ]; then
  banner worktree "main checkout"
else
  banner worktree unknown
fi

# First "rev" of the nixpkgs node in a flake.lock stream.
lock_nixpkgs_rev() {
  awk '
    /"nixpkgs"[ \t]*:[ \t]*\{/ { inblock = 1 }
    inblock && /"rev"[ \t]*:/ {
      line = $0
      sub(/^[^"]*"rev"[ \t]*:[ \t]*"/, "", line)
      sub(/".*$/, "", line)
      print line
      exit
    }
  '
}

lock_line="unknown"
worktree_rev=""
main_rev=""
[ -f "$TREE/flake.lock" ] && worktree_rev="$(lock_nixpkgs_rev <"$TREE/flake.lock" 2>/dev/null || true)"
if main_lock="$(git show main:flake.lock 2>/dev/null)"; then
  main_rev="$(printf '%s\n' "$main_lock" | lock_nixpkgs_rev || true)"
fi
if [ -n "$worktree_rev" ] && [ -n "$main_rev" ]; then
  if [ "$worktree_rev" = "$main_rev" ]; then
    lock_line="same as main"
  else
    lock_line="differs from main (nixpkgs $(printf '%s' "$main_rev" | cut -c1-7) -> $(printf '%s' "$worktree_rev" | cut -c1-7))"
  fi
fi
banner flake.lock "$lock_line"

script_line="unknown"
if self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; then
  self="$self_dir/$(basename "${BASH_SOURCE[0]}")"
  if [ -f "$TREE/rebuild.sh" ] && [ -f "$self" ]; then
    if cmp -s "$TREE/rebuild.sh" "$self"; then
      script_line="matches the running script"
    else
      script_line="differs from the running script"
    fi
  fi
fi
banner script "$script_line"

# ── 5. guards ───────────────────────────────────────────────────────────────

# Untracked Nix files are invisible to the flake, so a build would silently
# ignore them. A failing git call skips this guard rather than blocking.
if ! $FORCE; then
  if untracked="$(git ls-files --others --exclude-standard -- '*.nix' 2>/dev/null)"; then
    if [ -n "$untracked" ]; then
      printf 'error: refusing to build: untracked Nix files are not visible to flakes:\n' >&2
      printf '%s\n' "$untracked" | sed 's/^/  /' >&2
      printf '       track them, or pass --force to build anyway\n' >&2
      exit 2
    fi
  fi
fi

# Nothing to do only when the tree is clean (a failing git call counts as not
# clean) and the evaluated toplevel is already the running system.
tree_clean=false
if status_raw="$(git status --porcelain 2>/dev/null)"; then
  if [ -z "$status_raw" ]; then
    tree_clean=true
  fi
fi

if ! $FORCE && $tree_clean; then
  current_system="$(readlink -f /run/current-system 2>/dev/null || true)"
  if toplevel="$(nix eval --raw ".#nixosConfigurations.$HOST.config.system.build.toplevel" 2>/dev/null)"; then
    if [ -n "$current_system" ] && [ "$toplevel" = "$current_system" ]; then
      printf 'nothing to do: %s already matches /run/current-system\n' "$TREE"
      exit 0
    fi
  fi
fi

# ── 6. format, then build ───────────────────────────────────────────────────

# An interrupt can arrive at any point below, including during the format step,
# so the trap is installed before either. `out_link` is only set once the build
# section is reached; `log` likewise.
on_interrupt() {
  [ -n "${out_link:-}" ] && rm -f "$out_link"
  printf '\ninterrupted: log at %s\n' "${log:-<no log>}" >&2
  exit 130
}
trap on_interrupt INT TERM

# Only tracked files: this can never walk into .worktrees/ or format scratch
# files. The listing is probed first: outside a git work tree `git ls-files`
# fails, and the flake cannot see anything there, so the step is skipped
# instead of being reported as a formatting failure. Both failures are consumed
# by `if !`/`elif !` so `set -e` cannot abort before the diagnostic below.
if ! git ls-files -z -- '*.nix' >/dev/null 2>&1; then
  printf 'note: not a git work tree; skipping the tracked-file format step\n' >&2
elif ! git ls-files -z -- '*.nix' | xargs -0 -r alejandra >/dev/null 2>&1; then
  flagged="$(alejandra --check $(git ls-files -- '*.nix') 2>&1 | sed -n 's/^- \(\.\/\)\?\(.*\.nix\):.*/\2/p')" || true
  if [ -n "$flagged" ]; then
    nix-instantiate --parse $flagged || true
  fi
  printf 'formatting failed\n' >&2
  exit 1
fi

# What the build will actually see, with no context lines to keep it readable.
git diff HEAD -U0 -- '*.nix' 'flake.lock' || true

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/nixos-rebuild"
mkdir -p "$state_dir"
tree_name="$(basename "$TREE" | sed 's/[^A-Za-z0-9._-]/_/g')"
log="$state_dir/$tree_name-$(date +%Y%m%dT%H%M%S).log"
ln -sfn "$log" "$state_dir/last.log"
out_link="$state_dir/result"
rm -f "$out_link"

if ! command -v nom >/dev/null 2>&1; then
  printf 'error: nix-output-monitor (nom) is not installed; it comes from the dev-tools aspect\n' >&2
  exit 1
fi

# The build status is taken from `nix` via PIPESTATUS[0] and never from `nom` or
# `pipefail`: nom's exit status in filter mode is a heuristic about the stream it
# happened to parse, not a statement about the build (spec 32, FR-19). `tee`
# writes the log even when the build fails or is interrupted.
set +e
nix build ".#nixosConfigurations.$HOST.config.system.build.toplevel" \
  --log-format internal-json -v --out-link "$out_link" 2>&1 | tee "$log" | nom --json
build_status=${PIPESTATUS[0]}
set -e

if [ "$build_status" -ne 0 ]; then
  printf 'error: build failed (log: %s)\n' "$log" >&2
  exit 1
fi

built_path="$(readlink -f "$out_link")"
rm -f "$out_link"
printf 'built:  %s\n' "$built_path"
printf 'log:    %s\n' "$log"
printf 'replay: nom --json < %s\n' "$log"

if $DRY_RUN; then
  exit 0
fi

# ── 7. notification helper ──────────────────────────────────────────────────
#
# Desktop notification, used for the outcome below. It is optional and its exit
# status is never allowed to speak for the rebuild: no notify-send, no session
# bus, or a failing call are all silent no-ops.
notify() {
  command -v notify-send >/dev/null 2>&1 || return 0
  [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] || return 0
  notify-send "$1" "$2" || true
}

# ── 8. serialise activation ─────────────────────────────────────────────────
#
# Two rebuilds activating at once would race on the same generation and on the
# system profile, so the activation is serialised by an exclusive lock taken
# before sudo (the wait must not start after the password prompt). The lock file
# is left in place: it is a rendezvous point, not state to be cleaned up. The
# holding fd is inherited by the activation below, which keeps the lock held for
# as long as this process lives.

exec 9>"$state_dir/lock"
if ! flock -n 9; then
  printf 'waiting: another rebuild holds the activation lock\n' >&2
fi
# The blocking acquire runs in both cases: when the probe won, it re-enters the
# lock this process already holds on fd 9 and returns at once; when the probe
# lost, it waits for the holder to finish.
flock 9

# ── 9. sudo ─────────────────────────────────────────────────────────────────
#
# nixos-rebuild --sudo needs credentials for the whole activation. Prompting
# once here keeps `nixos-rebuild`'s own sudo non-interactive, and makes the
# no-tty case a pre-activation error instead of a half-run activation.

if [ -t 0 ]; then
  sudo -v || {
    printf 'error: sudo authentication failed\n' >&2
    exit 1
  }
else
  if ! sudo -n true 2>/dev/null; then
    printf 'error: sudo needs a password and stdin is not a terminal; run rebuild interactively\n' >&2
    exit 1
  fi
fi

# ── 10. activate ────────────────────────────────────────────────────────────

if $BOOT; then action=boot; else action=switch; fi

# Appended to the build log, so one file holds the whole run. The activation
# status comes from nixos-rebuild via PIPESTATUS[0], never from `tee` and never
# from nom: nom is not in this pipeline (it would parse nixos-rebuild's prose as
# if it were a build stream).
set +e
nixos-rebuild "$action" --flake ".#$HOST" --sudo 2>&1 | tee -a "$log"
activation_status=${PIPESTATUS[0]}
set -e

if [ "$activation_status" -ne 0 ]; then
  printf 'error: activation failed (log: %s)\n' "$log" >&2
  notify 'NixOS rebuild: activation failed' "$HOST: see $log"
  exit 1
fi

# ── 11. verify what was activated ───────────────────────────────────────────
#
# A switch must have moved /run/current-system onto the generation just built;
# anything else means the activation silently did nothing. --boot makes no such
# claim: it only installs the boot entry for the next boot.

if ! $BOOT; then
  current_system="$(readlink -f /run/current-system 2>/dev/null || true)"
  if [ "$current_system" != "$built_path" ]; then
    printf 'error: activation did not take effect: /run/current-system is %s, expected %s\n' \
      "${current_system:-<unreadable>}" "$built_path" >&2
    notify 'NixOS rebuild: activation did not take effect' \
      "$HOST: /run/current-system is ${current_system:-<unreadable>}"
    exit 1
  fi
fi

# The report is decoration: every failure below is tolerated, and none of it may
# turn a successful activation into a failure. A failed list-generations prints
# "unknown" rather than an empty line.

generation="unknown"
if generations="$(nixos-rebuild list-generations 2>/dev/null)"; then
  generation="$(printf '%s\n' "$generations" |
    awk '/current/ { print; exit }' |
    sed 's/^[[:space:]]*//' || true)"
  [ -n "$generation" ] || generation=unknown
fi
printf '  generation: %s\n' "$generation"

failed_units="$(systemctl --failed --no-legend 2>/dev/null | grep -c . || true)"
[ -n "$failed_units" ] || failed_units=0
printf '  units:     %s failed\n' "$failed_units"

# A switch does not change the running kernel; only a reboot does. The note is
# informational and never changes the exit code.
booted_system="$(readlink -f /run/booted-system 2>/dev/null || true)"
current_system="$(readlink -f /run/current-system 2>/dev/null || true)"
if [ "$booted_system" != "$current_system" ]; then
  printf 'note: reboot to run the new kernel (/run/booted-system differs from /run/current-system)\n' >&2
fi

# ── 12. notify the outcome ──────────────────────────────────────────────────

notify 'NixOS rebuild: activated' \
  "$HOST: generation $generation, $failed_units failed units"

printf 'activated: %s\n' "$built_path"
