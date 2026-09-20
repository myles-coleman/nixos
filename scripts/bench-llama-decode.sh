#!/usr/bin/env bash
set -euo pipefail

SERVER_URL="${SERVER_URL:-http://127.0.0.1:8080}"
MODEL="${MODEL:-qwen3.8-flash-next}"
DEPTHS="${DEPTHS:-1024 24576 49152}"
REPS="${REPS:-3}"
N_PREDICT="${N_PREDICT:-128}"
OUTDIR="${OUTDIR:-bench-results}"
LABEL="${LABEL:-official}"
DROP_CACHES="${DROP_CACHES:-0}"
BASELINE_PP="${BASELINE_PP:-}"
VRAM_SYSFS="${VRAM_SYSFS:-/sys/class/drm/card1/device/mem_info_vram_used}"
CURL_TIMEOUT="${CURL_TIMEOUT:-3600}"
HEALTH_TRIES="${HEALTH_TRIES:-180}"

usage() {
  cat <<'EOF'
bench-llama-decode.sh - fixed-prompt llama.cpp decode/prefill benchmark (Spec 04)

Measures single-stream decode (tg) and prefill (pp) throughput from the running
llama.cpp server's /completion timings, at several context depths. The first rep
per depth is a discarded warmup; the rest are reported as a median.

Environment overrides:
  SERVER_URL    llama.cpp base URL                (default http://127.0.0.1:8080)
  MODEL         served model alias                (default qwen3.8-flash-next)
  DEPTHS        context depths in tokens          (default "1024 24576 49152")
  REPS          reps per depth incl. warmup       (default 3)
  N_PREDICT     decode tokens per run             (default 128)
  OUTDIR        result directory                  (default ./bench-results)
  LABEL         configuration label for results   (default official)
  DROP_CACHES   1 = drop page caches per depth    (default 0)
  BASELINE_PP   baseline prefill t/s; flags a >10% regression when set
  VRAM_SYSFS    amdgpu vram_used path
  CURL_TIMEOUT  per-request timeout seconds       (default 3600)
  HEALTH_TRIES  readiness polls before giving up  (default 180)

Usage: scripts/bench-llama-decode.sh [--help]

Writes:
  $OUTDIR/$LABEL.csv  raw measured rows
  $OUTDIR/$LABEL.md   reviewer summary with medians and guardrails
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

for tool in curl jq awk sort; do
  command -v "$tool" >/dev/null 2>&1 || { echo "missing required tool: $tool" >&2; exit 127; }
done

make_prompt() {
  local depth="$1" chars unit out
  chars=$(( depth * 4 ))
  unit="The quick brown fox jumps over the lazy dog near the riverbank. "
  out=""
  while (( ${#out} < chars )); do
    out+="$unit"
  done
  printf '%s\n\nQuestion: reply with the single word READY.\n' "${out:0:chars}"
}

vram_used_mib() {
  if [[ -r "$VRAM_SYSFS" ]]; then
    awk '{printf "%.0f", $1/1048576}' "$VRAM_SYSFS"
  else
    echo "n/a"
  fi
}

ram_line() {
  free -m | awk '/^Mem:/{printf "ram_used_mb=%s ram_avail_mb=%s", $3, $7} /^Swap:/{printf " swap_used_mb=%s", $3}'
}

oom_count() {
  dmesg 2>/dev/null | grep -ciE 'killed process|out of memory' 2>/dev/null || true
}

drop_caches() {
  sync
  sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches'
}

median() {
  sort -n | awk '{a[NR]=$1} END{if(NR==0){print "n/a"} else if(NR%2){print a[(NR+1)/2]} else {print (a[NR/2]+a[NR/2+1])/2}}'
}

wait_healthy() {
  local tries=0
  until [[ "$(curl -s --max-time 5 "$SERVER_URL/health" 2>/dev/null || true)" == *ok* ]]; do
    tries=$((tries+1))
    if (( tries > HEALTH_TRIES )); then
      echo "server at $SERVER_URL did not become healthy" >&2
      exit 1
    fi
    sleep 5
  done
}

run_once() {
  local prompt="$1" pf bf out
  pf="$(mktemp)"
  bf="$(mktemp)"
  printf '%s' "$prompt" > "$pf"
  jq -nc --rawfile p "$pf" --arg m "$MODEL" --argjson n "$N_PREDICT" \
    '{prompt:$p, model:$m, n_predict:$n, temperature:0, cache_prompt:false, stream:false}' > "$bf"
  out="$(curl -s --max-time "$CURL_TIMEOUT" "$SERVER_URL/completion" \
    -H 'Content-Type: application/json' --data-binary @"$bf")"
  rm -f "$pf" "$bf"
  printf '%s' "$out"
}

wait_healthy
mkdir -p "$OUTDIR"
csv="$OUTDIR/$LABEL.csv"
printf 'label,depth,rep,pp_tps,tg_tps,prompt_n,predicted_n\n' > "$csv"

for depth in $DEPTHS; do
  if [[ "$DROP_CACHES" == "1" ]]; then
    drop_caches
  fi
  prompt="$(make_prompt "$depth")"
  for (( rep=1; rep<=REPS; rep++ )); do
    resp="$(run_once "$prompt")"
    pp="$(jq -r '.timings.prompt_per_second // empty' <<<"$resp")"
    tg="$(jq -r '.timings.predicted_per_second // empty' <<<"$resp")"
    pn="$(jq -r '.timings.prompt_n // empty' <<<"$resp")"
    dn="$(jq -r '.timings.predicted_n // empty' <<<"$resp")"
    if [[ -z "$pp" || -z "$tg" ]]; then
      echo "failed to parse timings from response: $resp" >&2
      exit 1
    fi
    if (( rep == 1 )); then
      kind=warmup
    else
      kind=measured
      printf '%s,%s,%s,%s,%s,%s,%s\n' "$LABEL" "$depth" "$rep" "$pp" "$tg" "$pn" "$dn" >> "$csv"
    fi
    echo "depth=$depth rep=$rep($kind) pp=$pp tg=$tg $(ram_line) vram_mib=$(vram_used_mib)" >&2
  done
done

report="$OUTDIR/$LABEL.md"
{
  echo "# Benchmark - $LABEL"
  echo
  echo "- Generated (UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "- Server: $SERVER_URL"
  echo "- Model: $MODEL"
  echo "- Reps per depth: $REPS (first discarded as warmup)"
  echo "- Decode tokens per run: $N_PREDICT"
  echo
  echo "## Median throughput"
  echo
  echo "| depth | pp t/s (median) | tg t/s (median) | measured reps |"
  echo "| --- | --- | --- | --- |"
  local_pp_first=""
  for depth in $DEPTHS; do
    ppmed="$(awk -F, -v d="$depth" -v l="$LABEL" '$1==l && $2==d {print $4}' "$csv" | median)"
    tgmed="$(awk -F, -v d="$depth" -v l="$LABEL" '$1==l && $2==d {print $5}' "$csv" | median)"
    n="$(awk -F, -v d="$depth" -v l="$LABEL" '$1==l && $2==d' "$csv" | wc -l)"
    if [[ -z "$local_pp_first" ]]; then local_pp_first="$ppmed"; fi
    printf '| %s | %s | %s | %s |\n' "$depth" "$ppmed" "$tgmed" "$n"
  done
  echo
  echo "## Guardrails"
  echo
  if [[ -n "$BASELINE_PP" && "$BASELINE_PP" != "0" ]]; then
    delta="$(awk -v a="$local_pp_first" -v b="$BASELINE_PP" 'BEGIN{if(b==0){print "n/a"} else {printf "%.1f", (a-b)/b*100}}')"
    echo "- Prefill at shallowest depth: ${local_pp_first} t/s versus baseline ${BASELINE_PP} t/s (${delta}%)."
    if awk -v a="$local_pp_first" -v b="$BASELINE_PP" 'BEGIN{exit !(a < b*0.9)}'; then
      echo "- RESULT: prefill regression exceeds the 10% guardrail."
    else
      echo "- RESULT: prefill is within the 10% guardrail."
    fi
  else
    echo "- Prefill guardrail: not evaluated (set BASELINE_PP to enable)."
  fi
  echo "- OOM or killed-process dmesg hits observed: $(oom_count)"
  echo "- Swap state at end: $(ram_line)"
} > "$report"

echo "wrote $csv and $report" >&2
