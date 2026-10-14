# Claude Code Offline

Run Anthropic's **Claude Code** command-line tool fully offline against a **local model** (Qwen2.5-7B-Instruct, served by the **Unsloth** engine), with everything in Docker, on Windows 11.

**Status: v1.0.0. CPU only, Windows 11 only.** It works end to end, including with the host network switched off, but it is slow and limited. Please read "What to expect" first.

## What to expect

Measured on an Intel Core i7-1265U laptop (31 GB RAM, integrated graphics not used), CPU only:

- Engine start: about 25 to 35 seconds.
- The first message of a session (engine freshly started): about **1 minute** in `bare` mode (about 1,000 prompt tokens), about **2.5 minutes** in `lean` mode, about **15 minutes** in `full` mode (about 17,000 tokens).
- Later messages reuse the engine's prompt cache: only new tokens are processed, so a short follow-up takes seconds.
- Generation speed: about 5 tokens per second; prompt processing about 18 to 21 tokens per second.
- A small task (read a file, edit another, report back) takes about 1.5 minutes end to end.
- A 7-billion-parameter model is far less capable than the hosted Claude models. Use it for small, well-specified edits and questions, not for large autonomous work. Tool calling was tested (structure and correctness) and works for the supported tools, but a small model can still make mistakes.

## How it works

    Windows 11
     +-- Docker engine (Rancher Desktop, dockerd)
          +-- engine container: Unsloth + llama.cpp, model from the volume cco_models
          |     on the internal network cco_net: no route to the internet, no published ports
          +-- Claude Code container (official native build), started on demand by claude.ps1
                your project folder is mounted at /workspace; it talks to the engine at http://engine:8888

Claude Code is the official, unmodified program, configured only through its supported settings. The engine speaks the Anthropic Messages API directly (no translation layer was needed).

## Requirements

- Windows 11 (64-bit) with WSL 2.
- **Rancher Desktop** with the container engine set to **dockerd (moby)**. This is what the project was built and tested on. Docker Desktop with the WSL 2 backend should work but has not been tested.
- 16 GB of RAM or more (the engine needs about 7 GiB, and the Docker VM about 15 GiB of address space; 32 GB is more comfortable), and about 15 GiB of free disk space.
- Internet access for the installation only (about 6 GiB of downloads).
- A normal PowerShell window or Windows Terminal. **PowerShell ISE is not supported.**

## Quick start

1. Download or clone this repository.
2. Open a normal PowerShell window in the repository folder and run:

        powershell -ExecutionPolicy Bypass -File scripts\windows\install.ps1

   It builds the two images, downloads and verifies the model, validates the configuration and runs two tests. On the reference machine it took **18.7 minutes** (engine image 4 min, Claude Code image 2 min, model download 9 min, tests 4 min). That is longer than the 10 minutes I aimed for: almost all of it is download and build time.
3. Go to a project folder and start Claude Code:

        cd C:\path\to\your\project
        powershell -ExecutionPolicy Bypass -File C:\path\to\claude-code-offline\scripts\windows\claude.ps1

   `claude.ps1` starts the engine if needed, opens Claude Code on the current folder, and stops the engine when you leave Claude Code.

## Daily use

See [docs/02-usage.md](docs/02-usage.md). The essentials:

- `claude.ps1 [-Project <folder>] [-Mode bare|lean|full] [-Prompt "<text>"] [-KeepEngine]`
- `up.ps1` and `down.ps1` start and stop the engine by hand.
- `validate-config.ps1` checks the setup; `upgrade.ps1` and `rollback.ps1` manage versions; `uninstall.ps1` removes everything the project created.

## Modes

| Mode | Tools | First message (cold engine) | Notes |
|---|---|---|---|
| `bare` (default) | Bash, Read, Edit | about 1 minute | New files are written through Bash. |
| `lean` | Bash, Read, Edit, Write | about 2.5 minutes | A real Write tool. |
| `full` | about 20 tools | about 15 minutes | Not practical on CPU; for faster hardware. |

Set the default with `CCO_CLAUDE_MODE` in `config\.env`, or per run with `-Mode`.

## Offline and privacy

- The engine and Claude Code run on an internal Docker network with no route to the internet, and nothing is published to the host. This was verified, and a full session was also run with the host's network switched off.
- Claude Code's telemetry, auto-updates, error reporting and other non-essential traffic are switched off in `docker/claude/claude.env`. The engine's update checks, statistics and public-IP checks are switched off in `docker/compose.yaml`. The internet is only needed for installing, building, upgrading and downloading the model.
- The engine runs with server-side tools (web search, code execution) disabled.

## Safety

- The Claude Code container can **read and write everything in the folder you give it**, and its Bash tool runs commands inside the container (as a non-root user, without internet access). Keep your project under version control and review what it changes.
- The engine's API key lives inside the engine container and is passed to the Claude Code container through a temporary file that is deleted at once; it never appears in command lines or logs the scripts print. The generated engine password is stored in `config\.env`, which is git-ignored. Never commit it.

## Configuration, upgrades, troubleshooting

- [docs/03-configuration.md](docs/03-configuration.md): every setting.
- [docs/04-upgrading.md](docs/04-upgrading.md): upgrades with gate tests, rollback, model swap.
- [docs/05-troubleshooting.md](docs/05-troubleshooting.md): problems that were actually met while building this, with causes and fixes.
- [docs/06-known-limitations.md](docs/06-known-limitations.md): the honest list, including performance numbers.
- [docs/00-architecture.md](docs/00-architecture.md): every design decision with the alternatives rejected; [docs/01-build-log/](docs/01-build-log/) records how it was built, step by step; [docs/07-roadmap.md](docs/07-roadmap.md) lists what comes next (macOS through Docker Model Runner, iGPU, and two parked questions).

## Not affiliated

This is an independent project. It is not affiliated with, endorsed by or supported by Anthropic or Unsloth. "Claude" and "Claude Code" are Anthropic's trademarks. See [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

## License

This project is released under the MIT License (see `LICENSE`). The software it installs keeps its own licences (see `THIRD-PARTY-NOTICES.md`).