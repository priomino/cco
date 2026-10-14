#!/bin/bash
# cco-claude-entry - reads the engine API key that claude.ps1 copied into the container, then starts Claude Code.
export PATH="$HOME/.local/bin:$PATH"
if [ -r /tmp/cco-engine-key ]; then
  ANTHROPIC_AUTH_TOKEN="$(tr -d '\r\n' < /tmp/cco-engine-key)"
  export ANTHROPIC_AUTH_TOKEN
  rm -f /tmp/cco-engine-key 2>/dev/null
fi
exec claude "$@"