#!/usr/bin/env bash
set -euo pipefail

# reset-target.sh - reset the disposable Juice Shop target and print its baseline.
#
# Must run as root on homelab. The target's root is tmpfs, so a restart is a
# reset; the script waits for the app, then prints the version, challenge count,
# solved count, and a digest over the full challenge projection.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
unit="${TARGET_UNIT:-microvm@redteam-target.service}"
base_url="${TARGET_URL:-http://10.99.0.2:3000}"

systemctl restart "$unit"

ready=false
for _ in $(seq 1 120); do
  if "${here}/lab-exec.sh" curl -fsS --max-time 2 "${base_url}/rest/admin/application-version" >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 1
done

if [ "$ready" != true ]; then
  echo "reset-target: target did not become healthy within 120s" >&2
  exit 1
fi

"${here}/lab-exec.sh" python3 "${here}/baseline-digest.py"
