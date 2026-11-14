#!/usr/bin/env bash
set -euo pipefail

# coverage-report.sh - wrapper for the Python coverage harness.
#
# Run from a lab-attached namespace, for example:
#   lab-exec.sh coverage-report.sh --base-url http://10.99.0.2:3000

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "${here}/coverage-report.py" "$@"
