#!/usr/bin/env bash
set -euo pipefail
umask 077

# k3s-backup.sh - take a restorable, encrypted snapshot of the k3s datastore.
#
# Spec 28, Unit 2. K3s only supports rolling back to a minor you hold a backup
# taken on, so every upgrade hop starts with this script. The artifact contains
# the SQLite datastore and `server/token` - a control-plane credential - so it is
# encrypted with age, written 0600, kept outside git, and never produced in CI.
#
# Usage:
#   scripts/k3s-backup.sh --minor 1.34 --recipient age1...     # take a backup
#   scripts/k3s-backup.sh --verify <artifact>                   # prove it restores
#   scripts/k3s-backup.sh --self-test                           # no cluster needed
#
# Environment overrides:
#   K3S_SERVER_HOST  control-plane host          (default 10.0.0.140)
#   K3S_SSH_USER     ssh user on that host       (default pi)
#   OUT_DIR          artifact directory          (default $HOME/k3s-backups)
#   AGE_RECIPIENT    age recipient to encrypt to (required; or --recipient)
#   AGE_IDENTITY     age identity for --verify   (default $HOME/.config/age/keys.txt)
#   MANIFEST_OUT     also write the manifest here (optional; or --manifest-out)

K3S_SERVER_HOST="${K3S_SERVER_HOST:-10.0.0.140}"
K3S_SSH_USER="${K3S_SSH_USER:-pi}"
OUT_DIR="${OUT_DIR:-$HOME/k3s-backups}"
AGE_RECIPIENT="${AGE_RECIPIENT:-}"
AGE_IDENTITY="${AGE_IDENTITY:-$HOME/.config/age/keys.txt}"
MANIFEST_OUT="${MANIFEST_OUT:-}"
MINOR="${MINOR:-}"

DB_PATH="/var/lib/rancher/k3s/server/db/state.db"
SNAPSHOT_PATH="/var/lib/rancher/k3s/server/db/state.db.snapshot"
TOKEN_PATH="/var/lib/rancher/k3s/server/token"

# Command prefix used to run sqlite3 on the control plane. Defaults to the
# package the `k3s-server` aspect installs. Override it while node0 still runs a
# generation without sqlite3, for example:
#   K3S_REMOTE_SQLITE="sudo -n nix --extra-experimental-features 'nix-command flakes' shell nixpkgs#sqlite --command sqlite3"
K3S_REMOTE_SQLITE="${K3S_REMOTE_SQLITE:-sudo -n sqlite3}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'EOF'
k3s-backup.sh - encrypted, restorable snapshots of the k3s datastore

Usage:
  scripts/k3s-backup.sh --minor <X.Y> --recipient <age-recipient> [options]
  scripts/k3s-backup.sh --verify <artifact>
  scripts/k3s-backup.sh --self-test
  scripts/k3s-backup.sh --help

Options:
  --minor X.Y          Minor the datastore is being taken on. Goes in the file
                       name and the manifest; it is the label rollback relies on.
  --recipient AGE      age recipient public key to encrypt to.
  --out-dir DIR        Destination directory (default $HOME/k3s-backups).
  --manifest-out FILE  Also write the manifest to FILE for the vault.
  --identity FILE      age identity for --verify (default $HOME/.config/age/keys.txt).

What it does:
  1. Takes an online SQLite backup of server/db/state.db on the control plane.
  2. Runs PRAGMA integrity_check on that snapshot and aborts if it is not ok.
  3. Streams the snapshot plus server/token through age into
     <out-dir>/<minor>-<token-gen>-<date>.tar.age, mode 0600.
  4. Removes the temporary snapshot on the control plane, success or failure.
  5. Prints a manifest (path, sha256, minor, token-generation hash, recipient).

Safety:
  Refuses to run when CI is set, when the destination is inside a git work tree,
  or when the destination is group- or world-accessible. The token is never
  printed: only a hash prefix and its byte length.

Environment overrides:
  K3S_SERVER_HOST (default 10.0.0.140)   K3S_SSH_USER (default pi)
  OUT_DIR (default $HOME/k3s-backups)    AGE_RECIPIENT
  AGE_IDENTITY (default $HOME/.config/age/keys.txt)   MANIFEST_OUT
  K3S_REMOTE_SQLITE (default "sudo -n sqlite3") — override only while the node
  does not yet ship sqlite3; see --help output of the script for the nix shell form.
EOF
}

die() {
  echo "k3s-backup: $*" >&2
  exit 1
}

note() {
  echo "k3s-backup: $*" >&2
}

need_tool() {
  command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"
}

ssh_node() {
  ssh -o BatchMode=yes -o ConnectTimeout=10 \
    "${K3S_SSH_USER}@${K3S_SERVER_HOST}" "$@"
}

# --- guards -----------------------------------------------------------------
# Each guard is a function so --self-test can exercise the real code path in a
# subshell without recursing into the script.

guard_not_ci() {
  if [ -n "${CI:-}" ]; then
    die "refusing to run in CI (CI is set): backups contain server/token and must be produced under operator control"
  fi
}

guard_out_dir() {
  local dir="$1" mode
  if [ -e "$dir" ]; then
    [ -d "$dir" ] || die "OUT_DIR exists but is not a directory: $dir"
    mode="$(stat -c %a "$dir")"
    case "$mode" in
      *00) ;;
      *)
        die "refusing to write into a group/world-accessible directory ($dir mode $mode); chmod 700 it first"
        ;;
    esac
  else
    mkdir -p "$dir"
    chmod 700 "$dir"
  fi
  if command -v git >/dev/null 2>&1 &&
    git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    die "refusing to write into a git work tree ($dir): a token-bearing artifact must never be committable"
  fi
}

# --- backup -----------------------------------------------------------------

remote_snapshot_cleanup() {
  ssh_node "sudo -n rm -f '${SNAPSHOT_PATH}'" >/dev/null 2>&1 || true
}

do_backup() {
  local taken token_gen artifact size sha commit integrity

  [ -n "$MINOR" ] || die "--minor <X.Y> is required (or MINOR=...); it labels the artifact for rollback"
  [[ "$MINOR" =~ ^[0-9]+\.[0-9]+$ ]] || die "--minor must look like 1.34, got: $MINOR"
  [ -n "$AGE_RECIPIENT" ] || die "--recipient <age-recipient> is required (or AGE_RECIPIENT=...)"

  need_tool ssh
  need_tool age
  need_tool sha256sum
  need_tool tar

  guard_not_ci
  guard_out_dir "$OUT_DIR"

  taken="$(date -u +%Y%m%dT%H%M%SZ)"

  note "snapshotting ${DB_PATH} on ${K3S_SSH_USER}@${K3S_SERVER_HOST}"
  ssh_node "${K3S_REMOTE_SQLITE} '${DB_PATH}' \".backup '${SNAPSHOT_PATH}'\"" ||
    die "sqlite3 .backup failed on the control plane (is sqlite3 installed? see k3s-server aspect)"

  # From here on the control plane holds a second copy of the datastore; always
  # remove it, whatever happens below.
  trap remote_snapshot_cleanup EXIT

  integrity="$(ssh_node "${K3S_REMOTE_SQLITE} '${SNAPSHOT_PATH}' 'PRAGMA integrity_check;'")" ||
    die "could not run PRAGMA integrity_check on the snapshot"
  [ "$integrity" = "ok" ] || die "snapshot failed PRAGMA integrity_check: ${integrity}"

  token_gen="$(ssh_node "sudo -n sha256sum '${TOKEN_PATH}'" | cut -c1-12)" ||
    die "could not hash ${TOKEN_PATH} on the control plane"
  [ -n "$token_gen" ] || die "empty token generation hash"

  artifact="${OUT_DIR}/${MINOR}-${token_gen}-${taken}.tar.age"
  note "streaming snapshot + token through age into ${artifact}"
  ssh_node "sudo -n tar -C /var/lib/rancher/k3s -cf - server/db/state.db.snapshot server/token" |
    age --recipient "$AGE_RECIPIENT" --output "$artifact" ||
    die "streaming or encryption failed"

  chmod 600 "$artifact"

  size="$(stat -c %s "$artifact")"
  sha="$(sha256sum "$artifact" | cut -d' ' -f1)"
  [ "$size" -gt 0 ] || die "artifact is empty: $artifact"

  commit="unknown"
  if command -v git >/dev/null 2>&1 &&
    git -C "$REPO_ROOT" rev-parse --short HEAD >/dev/null 2>&1; then
    commit="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
  fi

  manifest="$(
    cat <<EOF
k3s datastore backup
taken_utc: ${taken}
minor: ${MINOR}
artifact: ${artifact}
size_bytes: ${size}
sha256: ${sha}
token_generation: ${token_gen}
age_recipient: ${AGE_RECIPIENT}
integrity_check: ok
repo_commit: ${commit}
source: ${K3S_SSH_USER}@${K3S_SERVER_HOST}
EOF
  )"

  if [ -n "$MANIFEST_OUT" ]; then
    printf '%s\n' "$manifest" >"$MANIFEST_OUT"
  fi
  printf '%s\n' "$manifest"

  note "done. This artifact is the rollback point for ${MINOR}; keep it until the hop's soak is over."
}

# --- verify -----------------------------------------------------------------

do_verify() {
  local artifact="$1" work sha integrity token_bytes token_sha

  [ -n "$artifact" ] || die "--verify needs an artifact path"
  [ -f "$artifact" ] || die "artifact not found: $artifact"
  [ -f "$AGE_IDENTITY" ] || die "age identity not found: $AGE_IDENTITY (set AGE_IDENTITY or --identity)"

  need_tool age
  need_tool sha256sum
  need_tool tar

  work="$(mktemp -d)"
  chmod 700 "$work"
  # shellcheck disable=SC2064  # expand now: $work is function-local and out of scope at exit
  trap "rm -rf '${work}'" EXIT

  sha="$(sha256sum "$artifact" | cut -d' ' -f1)"
  note "decrypting ${artifact}"

  age --decrypt --identity "$AGE_IDENTITY" --output "$work/payload.tar" "$artifact" ||
    die "decryption failed (wrong identity for this artifact?)"

  tar -tf "$work/payload.tar" >/dev/null || die "decrypted payload is not a tar archive"
  tar -xf "$work/payload.tar" -C "$work"

  [ -f "$work/server/db/state.db.snapshot" ] || die "artifact does not contain server/db/state.db.snapshot"
  [ -f "$work/server/token" ] || die "artifact does not contain server/token"

  need_tool sqlite3
  integrity="$(sqlite3 "$work/server/db/state.db.snapshot" 'PRAGMA integrity_check;')"
  [ "$integrity" = "ok" ] || die "restored database failed PRAGMA integrity_check: ${integrity}"

  token_bytes="$(wc -c <"$work/server/token")"
  token_sha="$(sha256sum "$work/server/token" | cut -c1-12)"

  cat <<EOF
verify: OK
artifact: ${artifact}
sha256: ${sha}
database_integrity: ok
token_member: present (${token_bytes} bytes, sha256 prefix ${token_sha})
EOF
}

# --- self test --------------------------------------------------------------

do_self_test() {
  local work db restored rows_before rows_after integrity pub key

  need_tool sqlite3
  need_tool age
  need_tool age-keygen
  need_tool tar
  need_tool sha256sum

  work="$(mktemp -d)"
  chmod 700 "$work"
  # shellcheck disable=SC2064  # expand now: $work is function-local and out of scope at exit
  trap "rm -rf '${work}'" EXIT

  # 1. a real WAL-mode database with enough rows to be non-trivial
  db="$work/state.db"
  sqlite3 "$db" <<'SQL'
PRAGMA journal_mode=WAL;
CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT);
WITH RECURSIVE c(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM c WHERE x < 500)
INSERT INTO t (v) SELECT hex(randomblob(16)) FROM c;
SQL
  rows_before="$(sqlite3 "$db" 'SELECT count(*) FROM t;')"

  # 2. the same snapshot call the real backup makes
  sqlite3 "$db" ".backup '$work/state.db.snapshot'"
  integrity="$(sqlite3 "$work/state.db.snapshot" 'PRAGMA integrity_check;')"
  [ "$integrity" = "ok" ] || die "self-test: snapshot integrity_check returned ${integrity}"
  echo "PASS self-test: snapshot integrity_check ok (${rows_before} rows)"

  # 3. encrypt the same payload shape and decrypt it again
  mkdir -p "$work/server/db"
  mv "$work/state.db.snapshot" "$work/server/db/state.db.snapshot"
  printf 'self-test-token\n' >"$work/server/token"

  key="$work/key.txt"
  age-keygen --output "$key" 2>/dev/null
  pub="$(grep -o 'age1[0-9a-z]*' "$key" | head -1)"
  [ -n "$pub" ] || die "self-test: could not derive a public key from age-keygen output"

  tar -C "$work" -cf - server |
    age --recipient "$pub" --output "$work/payload.tar.age"
  [ -s "$work/payload.tar.age" ] || die "self-test: encrypted payload is empty"
  echo "PASS self-test: payload encrypted to ${pub:0:12}..."

  age --decrypt --identity "$key" --output "$work/payload.tar" "$work/payload.tar.age"
  mkdir -p "$work/restored"
  tar -xf "$work/payload.tar" -C "$work/restored"

  restored="$work/restored/server/db/state.db.snapshot"
  integrity="$(sqlite3 "$restored" 'PRAGMA integrity_check;')"
  [ "$integrity" = "ok" ] || die "self-test: restored integrity_check returned ${integrity}"
  rows_after="$(sqlite3 "$restored" 'SELECT count(*) FROM t;')"
  [ "$rows_after" = "$rows_before" ] ||
    die "self-test: row count changed across the round trip (${rows_before} -> ${rows_after})"
  [ -f "$work/restored/server/token" ] || die "self-test: token member did not survive the round trip"
  echo "PASS self-test: decrypt + extract + integrity ok (${rows_after} rows, token present)"

  # 4. the three refusal guards must actually refuse
  if (CI=1 guard_not_ci) >/dev/null 2>&1; then
    die "self-test: CI guard did not fire"
  fi
  echo "PASS self-test: CI guard refuses"

  mkdir -p "$work/gitrepo"
  git -C "$work/gitrepo" init -q
  if (OUT_DIR="$work/gitrepo/backups" guard_out_dir "$work/gitrepo/backups") >/dev/null 2>&1; then
    die "self-test: git-work-tree guard did not fire"
  fi
  echo "PASS self-test: git-work-tree guard refuses"

  mkdir -p "$work/opendir"
  chmod 777 "$work/opendir"
  if (guard_out_dir "$work/opendir") >/dev/null 2>&1; then
    die "self-test: world-accessible guard did not fire"
  fi
  echo "PASS self-test: world-accessible guard refuses"

  echo "PASS self-test: all checks passed"
}

# --- argument parsing -------------------------------------------------------

main() {
  local action="backup"

  if [ $# -eq 0 ]; then
    usage
    exit 2
  fi

  while [ $# -gt 0 ]; do
    case "$1" in
      -h | --help)
        usage
        exit 0
        ;;
      --self-test)
        action="self-test"
        shift
        ;;
      --verify)
        action="verify"
        [ $# -ge 2 ] || {
          usage
          exit 2
        }
        VERIFY_ARTIFACT="$2"
        shift 2
        ;;
      --minor)
        [ $# -ge 2 ] || {
          usage
          exit 2
        }
        MINOR="$2"
        shift 2
        ;;
      --recipient)
        [ $# -ge 2 ] || {
          usage
          exit 2
        }
        AGE_RECIPIENT="$2"
        shift 2
        ;;
      --out-dir)
        [ $# -ge 2 ] || {
          usage
          exit 2
        }
        OUT_DIR="$2"
        shift 2
        ;;
      --manifest-out)
        [ $# -ge 2 ] || {
          usage
          exit 2
        }
        MANIFEST_OUT="$2"
        shift 2
        ;;
      --identity)
        [ $# -ge 2 ] || {
          usage
          exit 2
        }
        AGE_IDENTITY="$2"
        shift 2
        ;;
      *)
        echo "k3s-backup: unknown argument: $1" >&2
        usage >&2
        exit 2
        ;;
    esac
  done

  case "$action" in
    self-test) do_self_test ;;
    verify) do_verify "${VERIFY_ARTIFACT:-}" ;;
    backup) do_backup ;;
  esac
}

main "$@"
