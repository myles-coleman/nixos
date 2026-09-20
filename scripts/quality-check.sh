#!/usr/bin/env bash
set -euo pipefail

SERVER_URL="${SERVER_URL:-http://127.0.0.1:8080}"
REFERENCE_URL="${REFERENCE_URL:-}"
MODEL="${MODEL:-qwen3.8-flash-next}"
OUTDIR="${OUTDIR:-bench-results}"
LABEL="${LABEL:-candidate}"
N_PREDICT="${N_PREDICT:-256}"
NEEDLE_DEPTH="${NEEDLE_DEPTH:-24576}"
NEEDLE="${NEEDLE:-ZQ7-PLUM-4412}"
CURL_TIMEOUT="${CURL_TIMEOUT:-3600}"

usage() {
  cat <<'EOF'
quality-check.sh - semantic sanity and greedy parity checks (Spec 04)

Runs a fixed set of prompts to catch two regression classes:
  1. semantic sanity  - answers stay coherent and correct for code, factual, and
     arithmetic prompts, and a long-context needle is retrieved.
  2. greedy parity    - temperature 0 output is byte-identical between a reference
     server and the server under test, when a reference URL is supplied.

Environment overrides:
  SERVER_URL      server under test          (default http://127.0.0.1:8080)
  REFERENCE_URL   baseline server for parity (default empty = parity skipped)
  MODEL           served model alias         (default qwen3.8-flash-next)
  OUTDIR          result directory           (default ./bench-results)
  LABEL           configuration label        (default candidate)
  N_PREDICT       max tokens per answer      (default 256)
  NEEDLE_DEPTH    needle context depth       (default 24576)
  NEEDLE          hidden passcode string     (default ZQ7-PLUM-4412)
  CURL_TIMEOUT    per-request timeout        (default 3600)

Usage: scripts/quality-check.sh [--help]

Writes: $OUTDIR/$LABEL-quality.md
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

for tool in curl jq; do
  command -v "$tool" >/dev/null 2>&1 || { echo "missing required tool: $tool" >&2; exit 127; }
done

complete() {
  local url="$1" prompt="$2" temp="$3" body
  body="$(jq -nc --arg p "$prompt" --arg m "$MODEL" --argjson n "$N_PREDICT" --argjson t "$temp" \
    '{prompt:$p, model:$m, n_predict:$n, temperature:$t, cache_prompt:false, stream:false}')"
  curl -s --max-time "$CURL_TIMEOUT" "$url/completion" -H 'Content-Type: application/json' -d "$body" \
    | jq -r '.content'
}

make_needle_prompt() {
  local depth="$1" chars half unit out
  chars=$(( depth * 4 ))
  half=$(( chars / 2 ))
  unit="The archive log records routine maintenance activity for the cluster. "
  out=""
  while (( ${#out} < half )); do out+="$unit"; done
  out+=" IMPORTANT PASSCODE: $NEEDLE. "
  while (( ${#out} < chars )); do out+="$unit"; done
  printf '%s\n\nQuestion: what is the passcode? Reply with only the passcode.\n' "${out:0:chars}"
}

prompt_code='Write a bash function named reverse_string that reverses its first argument. Return only the code.'
prompt_factual='What is the capital of Australia? Answer with one word.'
prompt_math='If a train travels 60 km in 45 minutes, what is its average speed in km/h? Answer with the number only.'

mkdir -p "$OUTDIR"
report="$OUTDIR/$LABEL-quality.md"
{
  echo "# Quality check - $LABEL"
  echo
  echo "- Generated (UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "- Server under test: $SERVER_URL"
  echo "- Reference server: ${REFERENCE_URL:-none}"
  echo
  echo "## Semantic sanity"
  echo
} > "$report"

for pair in "code:$prompt_code" "factual:$prompt_factual" "math:$prompt_math"; do
  name="${pair%%:*}"
  prompt="${pair#*:}"
  answer="$(complete "$SERVER_URL" "$prompt" 0)"
  {
    echo "### $name"
    echo
    echo "**Prompt:** $prompt"
    echo
    echo "**Answer:**"
    echo
    echo '~~~text'
    echo "$answer"
    echo '~~~'
    echo
  } >> "$report"
done

needle_prompt="$(make_needle_prompt "$NEEDLE_DEPTH")"
needle_answer="$(complete "$SERVER_URL" "$needle_prompt" 0)"
if [[ "$needle_answer" == *"$NEEDLE"* ]]; then
  needle_result="PASS"
else
  needle_result="FAIL"
fi
{
  echo "### needle retrieval (depth ~$NEEDLE_DEPTH tokens)"
  echo
  echo "- Expected passcode: \`$NEEDLE\`"
  echo "- Result: **$needle_result**"
  echo
  echo '~~~text'
  echo "$needle_answer"
  echo '~~~'
  echo
} >> "$report"

if [[ -n "$REFERENCE_URL" ]]; then
  {
    echo "## Greedy (temperature 0) parity vs reference"
    echo
    echo "| prompt | parity |"
    echo "| --- | --- |"
  } >> "$report"
  for pair in "code:$prompt_code" "factual:$prompt_factual" "math:$prompt_math"; do
    name="${pair%%:*}"
    prompt="${pair#*:}"
    a="$(complete "$REFERENCE_URL" "$prompt" 0)"
    b="$(complete "$SERVER_URL" "$prompt" 0)"
    if [[ "$a" == "$b" ]]; then
      verdict="identical"
    else
      verdict="DIFFERENT"
    fi
    echo "| $name | $verdict |" >> "$report"
  done
  echo >> "$report"
else
  {
    echo "## Greedy (temperature 0) parity vs reference"
    echo
    echo "Skipped: set REFERENCE_URL to compare against the frozen baseline."
    echo
  } >> "$report"
fi

echo "wrote $report" >&2
