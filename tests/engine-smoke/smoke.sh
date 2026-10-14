#!/bin/bash
# smoke.sh - runs INSIDE the engine container (docker exec -i <container> bash -s).
# The caller prepends a line KEY='<api key>' (and optionally BASE=...).
B="${BASE:-http://127.0.0.1:8888}"
echo "--- GET /v1/models ---"
curl -sS --max-time 30 -H "Authorization: Bearer $KEY" "$B/v1/models" | cut -c1-600; echo
ID=$(curl -s --max-time 30 -H "Authorization: Bearer $KEY" "$B/v1/models" | sed -n 's/.*"id" *: *"\([^"]*\)".*/\1/p' | head -1)
[ -z "$ID" ] && ID=default
echo "MODEL_ID=$ID"
printf '{"model":"%s","max_tokens":48,"messages":[{"role":"user","content":"Reply with exactly five words about the sea."}]}' "$ID" > /tmp/req1.json
echo "--- POST /v1/messages (Anthropic format, non-streaming) ---"
R=$(curl -s --max-time 600 -o /tmp/resp1.json -w '%{http_code} %{time_total}' -H "Authorization: Bearer $KEY" -H 'content-type: application/json' -H 'anthropic-version: 2023-06-01' -d @/tmp/req1.json "$B/v1/messages")
echo "MESSAGES_RESULT=$R"; cut -c1-900 /tmp/resp1.json; echo
echo "--- POST /v1/chat/completions (OpenAI format, non-streaming) ---"
R=$(curl -s --max-time 600 -o /tmp/resp2.json -w '%{http_code} %{time_total}' -H "Authorization: Bearer $KEY" -H 'content-type: application/json' -d @/tmp/req1.json "$B/v1/chat/completions")
echo "CHAT_RESULT=$R"; cut -c1-900 /tmp/resp2.json; echo
echo SMOKE_DONE