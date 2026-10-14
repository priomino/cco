#!/bin/bash
# bench.sh - runs INSIDE the engine container (docker exec -i <container> bash -s).
# The caller prepends: KEY='<api key>' and SIZES='2000 8000 16000'
B="${BASE:-http://127.0.0.1:8888}"
PARA="The quick brown fox jumps over the lazy dog while the engineers measure how many tokens per second a small language model can process on a laptop processor with shared memory. "
# PARA is roughly 35 tokens; the real count is read from the usage fields of each response.

mk() {  # $1 target tokens, $2 output file, $3 max_tokens
  local n=$(( $1 / 35 )) i=0
  {
    printf '{"model":"default","max_tokens":%s,"messages":[{"role":"user","content":"Run %s. ' "$3" "$(date +%s%N)"
    while [ "$i" -lt "$n" ]; do printf '%s' "$PARA"; i=$((i+1)); done
    printf 'Now answer in one short sentence: what is this text about?"}]}'
  } > "$2"
}
post() {  # $1 request file, $2 label
  local r t
  r=$(curl -s --max-time 900 -o /tmp/bresp.json -w '%{http_code} %{time_total}' -H "Authorization: Bearer $KEY" -H 'content-type: application/json' -H 'anthropic-version: 2023-06-01' -d @"$1" "$B/v1/messages")
  echo "$2 RESULT=$r"
  echo "  usage: $(grep -o '"usage":{[^}]*}' /tmp/bresp.json | head -1)"
  echo "  text:  $(grep -o '"text":"[^"]*"' /tmp/bresp.json | head -1 | cut -c1-160)"
  t=${r#* }; t=${t%.*}
  return $(( t > 400 ? 1 : 0 ))
}

echo "--- warm-up (tiny request) ---"
printf '{"model":"default","max_tokens":8,"messages":[{"role":"user","content":"Say OK."}]}' > /tmp/w.json
post /tmp/w.json "WARMUP"

for S in $SIZES; do
  echo "--- prompt of about $S tokens (unique prefix, no cache hit expected) ---"
  mk "$S" /tmp/b_last.json 48
  if ! post /tmp/b_last.json "SIZE=$S"; then echo "STOPPING: this size took more than 400 s; larger sizes skipped"; break; fi
done

if [ -s /tmp/b_last.json ]; then
  echo "--- second turn: same prefix, different final question (cache should cover the prefix) ---"
  sed 's/Now answer in one short sentence: what is this text about?/Now list three words that appear in the text./' /tmp/b_last.json > /tmp/b_var.json
  post /tmp/b_var.json "SECOND_TURN"
fi

echo "--- generation speed: 160-token story, short prompt ---"
printf '{"model":"default","max_tokens":160,"messages":[{"role":"user","content":"Write a story of about 150 words about a lighthouse keeper."}]}' > /tmp/g.json
post /tmp/g.json "DECODE"

echo "--- llama-server timing lines (last 30) ---"
grep -hE 'prompt eval time|[^t] eval time|total time' /home/cco/.unsloth/studio/logs/llama-server/*.log 2>/dev/null | cut -c1-200 | tail -30
echo BENCH_DONE