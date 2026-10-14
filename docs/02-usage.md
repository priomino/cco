# Usage

Run every command from a normal PowerShell window (not ISE). Paths below are relative to the repository; `claude.ps1` can be run from any folder by giving its full path.

## Start Claude Code on a project

    cd C:\path\to\your\project
    powershell -ExecutionPolicy Bypass -File C:\path\to\claude-code-offline\scripts\windows\claude.ps1

- The engine is started if it is not running (about 30 seconds) and the current folder is mounted at `/workspace`.
- The first message of a session needs prompt processing (about 1 minute in `bare` mode); later messages are much faster.
- When you leave Claude Code (`/exit` or Ctrl+C) the engine is stopped, unless another Claude Code session is still running. `-KeepEngine` leaves it running (about 7 GiB of memory) so the next start is quick.
- If a console window is closed abruptly, run `down.ps1` to clean up.

## Options of claude.ps1

| Option | Meaning |
|---|---|
| `-Project <folder>` | Folder to work on (default: the current folder). Local drives only; whole drives are refused. |
| `-Mode bare\|lean\|full` | Tool set and prompt size, see the README. Default from `CCO_CLAUDE_MODE`, otherwise `bare`. |
| `-Prompt "<text>"` | Non-interactive: runs one request, prints the answer, exits. Edits are accepted automatically in this mode. |
| `-KeepEngine` | Keep the engine running afterwards. |

Anything else after the options is passed to Claude Code in interactive mode.

## Working with the model

- Give small, concrete tasks, and name files. In `bare` mode say what to create or change; the model saves files with the Bash and Edit tools.
- Claude Code asks for permission before running commands or changing files in interactive mode; read what it proposes.
- The context window is 32,768 tokens. Long conversations or big files fill it; start a new session when answers degrade.
- Everything stays on your machine; nothing is sent anywhere.

## Start and stop the engine by hand

    powershell -ExecutionPolicy Bypass -File scripts\windows\up.ps1
    powershell -ExecutionPolicy Bypass -File scripts\windows\down.ps1

`up.ps1` waits until the model is loaded and the container reports healthy.

## Check, test, upgrade, remove

| Task | Command (in `scripts\windows`) |
|---|---|
| Check the setup | `validate-config.ps1` (add `-Deep` to re-verify the model checksum) |
| Tool-calling conformance test | `conformance.ps1` |
| File-creation test | `test-file-creation.ps1` |
| End-to-end test | `test-claude-entry.ps1` |
| Offline test (network switched off) | `verify-offline.ps1` |
| Upgrade the engine or Claude Code | `upgrade.ps1 -Component engine` or `claude` |
| Roll back | `rollback.ps1 -Component engine\|claude -List`, then `-Version <v>` |
| Remove everything the project created | `uninstall.ps1` (with `-RemoveModel` and `-RemoveConfig` for a full removal) |
| Look at what Claude Code did | `show-last-session.ps1` |

Details and expected output: [04-upgrading.md](04-upgrading.md) and [05-troubleshooting.md](05-troubleshooting.md).