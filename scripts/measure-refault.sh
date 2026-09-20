#!/usr/bin/env bash
set -euo pipefail

CONTAINER="${CONTAINER:-qwen-177b}"
MODEL_DIR="${MODEL_DIR:-/home/bee/models/qwen-177b-atomic}"
DEPTH="${DEPTH:-24576}"
DROP="${DROP:-0}"
N_PREDICT="${N_PREDICT:-128}"
SERVER_URL="${SERVER_URL:-http://127.0.0.1:8080}"
MODEL="${MODEL:-qwen3.8-flash-next}"
OUTDIR="${OUTDIR:-$HOME/refault-results}"
LABEL="${LABEL:-run}"
CURL_TIMEOUT="${CURL_TIMEOUT:-3600}"

usage() {
  cat <<'EOF'
measure-refault.sh - quantify page-cache residency and SSD refault cost (Spec 04)

Runs one fixed deep-context completion (temperature 0, ignore_eos) and records the
delta in the llama-server process major faults, the NVMe sectors read for the model
device, and vmtouch page-cache residency around the run. Run once with DROP=0 (warm)
and once with DROP=1 (cold, drops page caches first) to isolate refault cost.

Environment overrides:
  CONTAINER   docker container name        (default qwen-177b)
  MODEL_DIR   model directory              (default /home/bee/models/qwen-177b-atomic)
  DEPTH       context depth in tokens      (default 24576)
  DROP        1 = drop page caches first   (default 0)
  N_PREDICT   decode tokens               (default 128)
  SERVER_URL, MODEL, OUTDIR, LABEL, CURL_TIMEOUT

Usage: scripts/measure-refault.sh [--help]

Writes: $OUTDIR/$LABEL.csv
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

for tool in curl jq awk; do
  command -v "$tool" >/dev/null 2>&1 || { echo "missing required tool: $tool" >&2; exit 127; }
done
command -v nix >/dev/null 2>&1 || { echo "missing nix (needed for vmtouch)" >&2; exit 127; }

pid() { docker inspect "$CONTAINER" --format '{{.State.Pid}}'; }

majflt() {
  local p
  p="$(pid)"
  awk -v p="$p" '$1==p {print $12}' "/proc/$p/stat"
}

model_dev() { readlink -f "$(findmnt -no SOURCE --target "$MODEL_DIR")"; }

read_sectors() { cat "/sys/class/block/$(basename "$(model_dev)")/stat" | awk '{print $3}'; }

residency() {
  nix shell nixpkgs#vmtouch -c vmtouch -v "$MODEL_DIR" 2>/dev/null \
    | awk '/Resident Pages/{print $4" "$5}'
}

make_prompt() {
  local depth="$1" chars half unit out
  chars=$(( depth * 4 ))
  half=$(( chars / 2 ))
  unit="The archive log records routine maintenance activity for the cluster. "
  out=""
  while (( ${#out} < half )); do out+="$unit"; done
  out+=" IMPORTANT PASSCODE: ZQ7-PLUM-4412. "
  while (( ${#out} < chars )); do out+="$unit"; done
  printf '%s\n\nQuestion: reply with the single word READY.\n' "${out:0:chars}"
}

mkdir -p "$OUTDIR"
csv="$OUTDIR/$LABEL.csv"

pf="$(mktemp)"
bf="$(mktemp)"
make_prompt "$DEPTH" > "$pf"
jq -nc --rawfile p "$pf" --arg m "$MODEL" --argjson n "$N_PREDICT" \
  '{prompt:$p, model:$m, n_predict:$n, temperature:0, cache_prompt:false, stream:false, ignore_eos:true}' > "$bf"

mf0="$(majflt)"
rs0="$(read_sectors)"
res0="$(residency)"

if [[ "$DROP" == "1" ]]; then
  sync
  sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches'
fi

resdrop="$(residency)"

resp="$(curl -s --max-time "$CURL_TIMEOUT" "$SERVER_URL/completion" \
  -H 'Content-Type: application/json' --data-binary @"$bf")"

mf1="$(majflt)"
rs1="$(read_sectors)"
res1="$(residency)"

pp="$(jq -r '.timings.prompt_per_second // "n/a"' <<<"$resp")"
tg="$(jq -r '.timings.predicted_per_second // "n/a"' <<<"$resp")"
pn="$(jq -r '.timings.prompt_n // "n/a"' <<<"$resp")"
dmf=$(( mf1 - mf0 ))
drs=$(( rs1 - rs0 ))
read_mib=$(( drs / 2048 ))

printf 'label,depth,drop,majflt_delta,read_sectors_delta,read_mib,pp_tps,tg_tps,prompt_n,resident_before,resident_after_drop,resident_after\n' > "$csv"
printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,"%s","%s","%s"\n' \
  "$LABEL" "$DEPTH" "$DROP" "$dmf" "$drs" "$read_mib" "$pp" "$tg" "$pn" "$res0" "$resdrop" "$res1" >> "$csv"

rm -f "$pf" "$bf"
echo "label=$LABEL depth=$DEPTH drop=$DROP majflt_delta=$dmf read_mib=$read_mib pp=$pp tg=$tg" >&2
cat "$csv"
