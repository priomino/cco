#!/bin/bash
# sweep.sh (v2) - runs inside a throwaway engine-image container (docker run -i ... bash -s).
# The caller sets MODEL=/models/<file> and optionally PROMPT_TOKENS, THREADS_LIST, FA_LIST.
BIN="$HOME/.unsloth/llama.cpp/build/bin"
export LD_LIBRARY_PATH="$BIN:$LD_LIBRARY_PATH"
SRV="$BIN/llama-server"
THREADS_LIST="${THREADS_LIST:-4 6 8 12}"
FA_LIST="${FA_LIST:-off on}"
PT="${PROMPT_TOKENS:-600}"
PORT=8099

echo "--- cpu ---"; nproc
grep -m1 'model name' /proc/cpuinfo
lscpu 2>/dev/null | grep -E 'Thread|Core|Socket|L2|L3' | cut -c1-120
echo "cpu flags of interest: $(grep -m1 '^flags' /proc/cpuinfo | tr ' ' '\n' | grep -E '^(avx|avx2|avx_vnni|avx512f|avx512_vnni|fma|f16c|amx_tile|amx_int8)$' | sort -u | tr '\n' ' ')"
echo "cgroup cpu.max: $(cat /sys/fs/cgroup/cpu.max 2>/dev/null)"
free -m | head -2
[ -x "$SRV" ] || { echo "NO_LLAMA_SERVER"; exit 0; }

PARA="The quick brown fox jumps over the lazy dog while the engineers measure how many tokens per second a small language model can process on a laptop processor with shared memory. "
N=$(( PT / 35 ))
{
  printf '{"prompt":"Run %s. ' "$(date +%s%N)"
  i=0; while [ "$i" -lt "$N" ]; do printf '%s' "$PARA"; i=$((i+1)); done
  printf 'Summarize the text above in one sentence.","n_predict":32,"temperature":0,"cache_prompt":false}'
} > /tmp/p.json

FIRST=1
for FA in $FA_LIST; do
  for T in $THREADS_LIST; do
    echo "--- threads=$T flash-attn=$FA ---"
    "$SRV" -m "$MODEL" -c 4096 -t "$T" -tb "$T" --flash-attn "$FA" --parallel 1 --host 127.0.0.1 --port $PORT > /tmp/srv.log 2>&1 &
    PID=$!
    ok=0; i=0
    while [ "$i" -lt 150 ]; do
      if curl -s --max-time 2 "http://127.0.0.1:$PORT/health" | grep -q '"ok"'; then ok=1; break; fi
      kill -0 $PID 2>/dev/null || break
      sleep 1; i=$((i+1))
    done
    if [ "$ok" -ne 1 ]; then
      echo "SERVER_FAILED threads=$T fa=$FA"; tail -8 /tmp/srv.log | cut -c1-200
      kill $PID 2>/dev/null; wait $PID 2>/dev/null; continue
    fi
    if [ "$FIRST" -eq 1 ]; then
      echo "--- backend / CPU features reported by llama-server ---"
      grep -iE 'load_backend|system_info|backend' /tmp/srv.log | cut -c1-220 | head -10
      FIRST=0
    fi
    R=$(curl -s --max-time 900 -H 'content-type: application/json' -d @/tmp/p.json "http://127.0.0.1:$PORT/completion")
    PN=$(echo "$R" | grep -o '"prompt_n":[0-9]*' | head -1 | cut -d: -f2)
    PP=$(echo "$R" | grep -o '"prompt_per_second":[0-9.]*' | head -1 | cut -d: -f2)
    GP=$(echo "$R" | grep -o '"predicted_per_second":[0-9.]*' | head -1 | cut -d: -f2)
    echo "RESULT threads=$T fa=$FA prompt_tokens=${PN:-?} prefill_tok_s=${PP:-?} gen_tok_s=${GP:-?}"
    kill $PID 2>/dev/null; wait $PID 2>/dev/null
  done
done
echo SWEEP_DONE