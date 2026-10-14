#!/bin/bash
# session.sh - runs inside the Claude Code image (docker run -i ... bash -s) on the compose network.
# The caller prepends exports for ANTHROPIC_AUTH_TOKEN and the other settings.
export PATH="$HOME/.local/bin:$PATH"
cd /workspace || exit 1
printf '{"name":"demo","version":"1.2.3"}\n' > package.json
printf 'foo is here. foo again.\n' > notes.txt
printf '# Demo project\n' > README.md
echo "claude: $(claude --version 2>&1 | head -1)"
echo "engine reachable: $(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$ANTHROPIC_BASE_URL/api/health" || echo no)"
echo "internet reachable (must be no): $(curl -s -o /dev/null -w '%{http_code}' --max-time 5 https://example.com 2>/dev/null || echo no)"
PROMPT="Read package.json and tell me the version number. Then in notes.txt replace every word foo with bar. Finally show me the content of notes.txt."
echo "--- running claude -p in bare mode ---"
START=$(date +%s)
claude -p "$PROMPT" --output-format json --permission-mode acceptEdits --max-turns 8 --allowedTools "Read" "Edit" "Bash" < /dev/null > /tmp/out.json 2> /tmp/err.txt
RC=$?
echo "claude exit code: $RC   seconds: $(( $(date +%s) - START ))"
echo "--- stderr (first 1500 chars) ---"; head -c 1500 /tmp/err.txt; echo
echo "--- result json (first 2500 chars) ---"; head -c 2500 /tmp/out.json; echo
echo "--- files after the session ---"
echo "notes.txt: $(cat notes.txt)"
if grep -q bar notes.txt && ! grep -q foo notes.txt; then echo "EDIT_OK=yes"; else echo "EDIT_OK=no"; fi
if grep -q '1\.2\.3' /tmp/out.json; then echo "VERSION_REPORTED=yes"; else echo "VERSION_REPORTED=no"; fi
echo SESSION_DONE