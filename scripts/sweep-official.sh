#!/usr/bin/env bash
set -euo pipefail

IMAGE="${IMAGE:-ghcr.io/ggml-org/llama.cpp@sha256:b54c5c6adb542a396885b4b07a5159e9ab0c649e007cc9f7f088799043cc9e4f}"
MODEL_PATH="${MODEL_PATH:-/models/qwen-177b-atomic/Qwen3.8-Flash-Next-AD-3.84bpw-IQ4_XS-M64-00001-of-00028.gguf}"
ALIAS="${ALIAS:-qwen3.8-flash-next}"
CONFIGS="${CONFIGS:-28:6 24:6}"
DEPTHS="${DEPTHS:-1024 24576}"
REPS="${REPS:-3}"
N_PREDICT="${N_PREDICT:-128}"
OUTDIR="${OUTDIR:-$HOME/sweep-results}"
PROD_UNIT="${PROD_UNIT:-docker-qwen-177b}"
TEMP_NAME="${TEMP_NAME:-bench-qwen}"
HARNESS="${HARNESS:-$HOME/bench-llama-decode.sh}"
PORT="${PORT:-8080}"

usage() {
  cat <<'EOF'
sweep-official.sh - run the official llama.cpp config sweep on bee-gpu-server (Spec 04)

For each "-ncmoe:threads" pair in CONFIGS it stops the production unit, starts an
equivalent bench container via direct `docker run`, waits for /health, runs
bench-llama-decode.sh, and removes the bench container. Production is restored on
exit or error via a trap.

Environment overrides:
  CONFIGS   space-separated ncmoe:threads pairs (default "28:6 24:6")
  DEPTHS    harness depths (default "1024 24576"; use "1024 24576 49152" to confirm)
  REPS      harness reps (default 3)
  OUTDIR    result directory (default ~/sweep-results)
  IMAGE, MODEL_PATH, ALIAS, PROD_UNIT, TEMP_NAME, HARNESS, PORT

Usage: scripts/sweep-official.sh
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

restore() {
  docker rm -f "$TEMP_NAME" >/dev/null 2>&1 || true
  sudo systemctl start "$PROD_UNIT" >/dev/null 2>&1 || true
}

wait_health() {
  local i
  for i in $(seq 1 150); do
    if [[ "$(curl -s --max-time 5 "http://127.0.0.1:$PORT/health" 2>/dev/null || true)" == *ok* ]]; then
      return 0
    fi
    sleep 5
  done
  return 1
}

mkdir -p "$OUTDIR"
trap restore EXIT

for cfg in $CONFIGS; do
  ncmoe="${cfg%%:*}"
  threads="${cfg##*:}"
  label="ncmoe${ncmoe}-t${threads}"
  echo "=== $label start $(date -u +%H:%M:%SZ) ==="

  sudo systemctl stop "$PROD_UNIT" >/dev/null 2>&1 || true
  sleep 5
  docker rm -f "$TEMP_NAME" >/dev/null 2>&1 || true
  sleep 5

  docker run -d --name "$TEMP_NAME" \
    --device=/dev/dri/renderD128:/dev/dri/renderD128 \
    --device=/dev/kfd:/dev/kfd \
    --group-add=video --group-add=render \
    --ipc=host --cap-add=SYS_PTRACE --security-opt=seccomp=unconfined \
    --ulimit=memlock=-1 \
    -p "$PORT:8080" -v /home/bee/models:/models \
    "$IMAGE" \
    --host 0.0.0.0 --port 8080 \
    -m "$MODEL_PATH" --jinja --alias "$ALIAS" \
    -ngl 99 -ncmoe "$ncmoe" -fit off -fa on \
    -c 100000 -ctk q4_0 -ctv q4_0 \
    -b 1024 -ub 512 -t "$threads" -np 1 \
    --temp 1 --top-k 20 --min-p 0 --top-p 0.95 --metrics >/dev/null

  if ! wait_health; then
    {
      echo "label,status,note"
      echo "$label,FAIL,did not become healthy within timeout (possible VRAM/OOM)"
    } > "$OUTDIR/$label.csv"
    echo "FAIL $label" | tee -a "$OUTDIR/errors.log"
    docker logs --tail 20 "$TEMP_NAME" > "$OUTDIR/$label.log" 2>&1 || true
    docker rm -f "$TEMP_NAME" >/dev/null 2>&1 || true
    continue
  fi

  env LABEL="$label" OUTDIR="$OUTDIR" DROP_CACHES=1 DEPTHS="$DEPTHS" REPS="$REPS" \
      N_PREDICT="$N_PREDICT" SERVER_URL="http://127.0.0.1:$PORT" MODEL="$ALIAS" \
      bash -c 'nix shell nixpkgs#jq -c bash "$0"' "$HARNESS" || echo "harness failed: $label" | tee -a "$OUTDIR/errors.log"

  docker rm -f "$TEMP_NAME" >/dev/null 2>&1 || true
  echo "=== $label done $(date -u +%H:%M:%SZ) ==="
done

restore
trap - EXIT
echo "sweep complete $(date -u +%H:%M:%SZ)"
