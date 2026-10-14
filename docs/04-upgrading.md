# Upgrading

The engine (Unsloth) and Claude Code track the latest releases by default (architecture D10). Every build leaves a snapshot tag named after the version it contains (`cco-engine:<version>-cpu`, `cco-claude:<version>`); the floating tags `cco-engine:cpu` and `cco-claude:cli` are what compose and the scripts use.

Run all commands from a normal PowerShell window in the repository.

## Check the setup
`powershell -ExecutionPolicy Bypass -File scripts\windows\validate-config.ps1` (add `-Deep` to re-verify the model checksum; needs the internet).

## Upgrade the engine or Claude Code (recommended)
`powershell -ExecutionPolicy Bypass -File scripts\windows\upgrade.ps1 -Component engine` (or `claude`)

It validates the configuration, records the current version, rebuilds without cache, and stops if nothing newer exists. Otherwise it runs the gate (engine: tool-calling conformance test and the file-creation test; Claude Code: the end-to-end entry test and the file-creation test) and points the floating tag back at the previous version if the gate fails. Successful upgrades are logged in `docs/01-build-log/upgrades.md`. Expect 5 to 15 minutes.

## Choose a version yourself
Set `CCO_UNSLOTH_VERSION` (engine) or `CCO_CLAUDE_VERSION` (Claude Code) in `config/.env` to an exact version, then run `scripts\windows\build-engine.ps1` or `scripts\windows\build-claude.ps1`. Set the value back to `latest` to track releases again. Optional hardening for the engine: `build-engine.ps1 -ShowInstallerSha` and set `CCO_UNSLOTH_INSTALLER_SHA256` so builds fail if the installer changes.

## Roll back
`powershell -ExecutionPolicy Bypass -File scripts\windows\rollback.ps1 -Component claude -List` shows the kept versions; `... -Version <version>` switches to one of them (nothing is rebuilt). Stop the engine first (`down.ps1`) when rolling back the engine.

## Swap the model
1. Edit `CCO_MODEL_REPO` and `CCO_MODEL_FILE` in `config/.env` (leave `CCO_MODEL_SHA256` empty to use the checksum published by Hugging Face).
2. Run `scripts\windows\download-model.ps1` (needs the internet, verifies the checksum).
3. Run `scripts\windows\conformance.ps1` and `scripts\windows\test-file-creation.ps1 -Modes bare`.
To go back, restore the two values; the old model file stays in the `cco_models` volume until you delete it. Other quantisations or models change speed, memory use and tool-calling quality: measure before relying on them.

## Disk space
Old snapshot images stay until removed (about 2 GB per engine version). List them with `docker images cco-engine` and remove one with `docker image rm cco-engine:<version>-cpu`. Never run `docker system prune` on an engine that hosts other projects.