# Troubleshooting (symptom -> cause -> fix)

## Join-Path / Start-Transcript error "argument is null or empty" when running a script
- **Symptom:** `Join-Path : Cannot bind argument to parameter 'Path' because it is an empty string`, then `Stop-Transcript : The host is not currently transcribing`.
- **Cause:** the script was pasted into the console. `$PSScriptRoot` is empty unless a script runs from a file.
- **Fix:** save it as a `.ps1` file and run `powershell -ExecutionPolicy Bypass -File .\name.ps1`. Scripts in this repo fall back to the current directory when `$PSScriptRoot` is empty.

## `docker info --format` fails with "template parsing error ... unexpected \\ in command"
- **Cause:** a `{{"\n"}}` escape inside a PowerShell string does not survive quoting.
- **Fix:** use `docker info --format '{{json .}}'` and parse with `ConvertFrom-Json`, or ask for a few simple fields.

## "failed to connect to the docker API at npipe:////./pipe/docker_engine"
- **Cause:** Rancher Desktop was not running (its WSL distros were `Stopped`).
- **Fix:** start Rancher Desktop with the dockerd (moby) engine and wait until it is running.

## docker CLI hangs with no output (observed once, not reproduced)
- **Symptom:** a script stuck at its first `docker info` call even though Rancher Desktop was running.
- **Suspected cause (not confirmed):** a transient stall in Rancher's Windows-side docker proxy; `docker.log` showed `docker-proxy` errors ("bad file descriptor", "transport endpoint is not connected") shortly before.
- **Fix:** quit Rancher Desktop from the tray, run `wsl --shutdown`, start Rancher Desktop, wait about two minutes. Repo scripts wrap every external call in a timeout so they report instead of hanging.
## Scaffold or copy script fails with "Missing source script"
- **Symptom:** `SCAFFOLD FAILED: Missing source script: ...\audit2.ps1`.
- **Cause:** the earlier scripts were pasted into the console and never saved as files, so there was nothing to copy.
- **Fix:** save scripts as `.ps1` files before running them. For this repo, `scripts/windows/audit.ps1` and `scripts/windows/probe-igpu.ps1` are the saved copies.

## Engine image build fails: "linux extracted binary preflight failed ... missing=libgomp.so.1"
- **Symptom:** Unsloth's installer downloads the prebuilt llama.cpp CPU bundle, then prints `llama-server: missing=libgomp.so.1`, `selected backend could not be installed` and `studio setup failed (exit code 1)`.
- **Cause:** the minimal `ubuntu:24.04` image lacks the OpenMP runtime the prebuilt binaries need. With the backend set explicitly to `cpu` the installer does not fall back to a source build.
- **Fix:** install `libgomp1` in the Dockerfile (`apt-get install -y --no-install-recommends curl ca-certificates libgomp1`).

## build-engine.ps1 prints "BUILD FAILED ... exit code" with an empty code although the build succeeded
- **Symptom:** the docker log ends with `naming to ... done`, but the script reports failure and the exit code field is blank.
- **Cause:** in Windows PowerShell 5.1, `Start-Process -PassThru` leaves `ExitCode` empty unless the process handle is read before the process exits.
- **Fix:** the script reads `$p.Handle` right after starting the process and, as a fallback, judges success from the build log. If you see this in another script, do the same.

## Hugging Face API answers "Invalid username or password" for a model repo
- **Symptom:** `{"error":"Invalid username or password."}` when listing `https://huggingface.co/api/models/<repo>/tree/main`.
- **Cause:** the repo does not exist or is private; anonymous requests for those get a 401 instead of a 404.
- **Fix:** check the repo name in a browser, or use another repo (`CCO_MODEL_REPO`).

## `/v1/models` returns an empty list right after the engine starts
- **Symptom:** the smoke test got `{"object":"list","data":[]}` and fell back to the model name `default`; the first generation request took longer than the following ones.
- **Cause:** the web server (and `/api/health`) answer within seconds, but the model loads about 14 s later.
- **Fix:** wait for the log line `Loaded GGUF model via llama-server` before testing; `engine-bench.ps1` does this.

## docker.exe or the compose plugin crash with "fatal error: runtime: cannot allocate memory"
- **Symptom:** during the model load, `docker inspect`, `docker logs` or `docker compose` print Go runtime stack traces ("out of memory allocating heap arena map"); a later `docker compose down` says `unknown flag: --project-directory`; the engine container is left running.
- **Cause:** Windows could not give a new process memory. Observed: 32.0 GiB committed of a 37.9 GiB commit limit (31.4 GiB RAM plus a fixed 6.5 GiB page file), with the WSL VM at 8-9 GiB and a browser open; the model load makes the VM grow quickly. The engine container itself was fine.
- **Fix:** the benchmark script retries such calls and falls back to `docker rm -f` for our container and network. To gain headroom: close heavy applications, make the page file system-managed (System Properties > Advanced > Performance > Settings > Advanced > Virtual memory), or cap the WSL VM with `.wslconfig` (`memory=` under `[wsl2]`, followed by `wsl --shutdown`, which also restarts the other containers).
- **Check:** `Get-CimInstance Win32_OperatingSystem` shows `FreeVirtualMemory` (free commit); below roughly 6 GiB while loading is risky.

## Sweep script prints NO_LLAMA_BENCH
- **Symptom:** the CPU sweep runs in about a second and prints `NO_LLAMA_BENCH`.
- **Cause:** Unsloth's prebuilt llama.cpp bundle only ships `llama-server`, `llama-quantize` and a diffusion server as executables; the other tools exist only as `libllama-*-impl.so` libraries.
- **Fix:** benchmark with `llama-server` itself (start it per configuration and read the `timings` of a `/completion` response); this is what `cpu-sweep.ps1` v2 does.

## Generation speed collapses to under 1 token/s with 12 threads
- **Symptom:** `llama-server` started with `-t 12` generates 0.7 tokens/s while 4-8 threads give 5-6 tokens/s; prompt processing is barely affected.
- **Cause:** the VM exposes 12 vCPUs of a hybrid CPU (2 performance + 8 efficiency cores) and the host has other work to do; with every thread busy, each token waits for the slowest one.
- **Fix:** use 8 threads or fewer.

## vulkaninfo in the container lists only llvmpipe (no Intel GPU)
- **Symptom:** `vulkaninfo --summary` shows one device, `llvmpipe` (`PHYSICAL_DEVICE_TYPE_CPU`); `/usr/share/vulkan/icd.d/` has no `dzn_icd*.json`.
- **Cause:** Ubuntu 24.04's `mesa-vulkan-drivers` (25.2.8) is built without the `dzn` driver, and the Intel Vulkan drivers need a DRM render node (`/dev/dri`) that WSL2 does not provide (inference).
- **Fix:** none within Ubuntu's packages. Options: a distribution or build whose Mesa includes `dzn`, or an Intel SYCL / Level Zero build of llama.cpp (see architecture D19). Until then use the `cpu` profile.

## Python in a container fails with "ModuleNotFoundError: No module named 'json'"
- **Symptom:** a script run with `python3` inside an Ubuntu 24.04 image dies on its first `import json`.
- **Cause:** the `python3-minimal` package contains only the interpreter, not the standard library.
- **Fix:** install `python3` (or `python3-stdlib`-providing packages) instead of `python3-minimal`.

## `claude -p` inside a script fed through `bash -s` swallows the rest of the script
- **Symptom:** a test script piped into `docker run -i ... bash -s` stops after the first `claude -p` call; the remaining commands never run.
- **Cause:** `claude -p` reads its standard input as extra prompt text, so it consumes the rest of the script that `bash -s` is reading from stdin.
- **Fix:** give such commands their own input: `claude -p "..." < /dev/null`.

## Claude Code prints "[claude-code:unrecognized_model]" on stderr
- **Symptom:** `claude -p` prints `[claude-code:unrecognized_model] {"model":"<local name>",...}` and still succeeds (exit code 0).
- **Cause:** Claude Code does not know the local model name, so it assumes a 200K context window and default capabilities. The message is informational.
- **Fix:** none needed; set `CLAUDE_CODE_MAX_CONTEXT_TOKENS` to the engine's real context window (32768) so auto-compaction triggers at the right place.

## "invalid mount config for type bind: bind source path does not exist: //c/..."
- **Symptom:** `docker run --mount type=bind,source=//c/projects/x,...` fails.
- **Cause:** the engine inside Rancher Desktop does not understand the `//c/` or `/c/` notations.
- **Fix:** use the plain Windows path (`C:\projects\x`) with `--mount type=bind,source=...`, or the WSL form `/mnt/c/projects/x`.

## Red "NativeCommandError" text around harmless output of a native command
- **Symptom:** a script prints `powershell.exe : <message>` followed by `CategoryInfo : NotSpecified ... NativeCommandError` although the command succeeded (exit code 0).
- **Cause:** in Windows PowerShell 5.1, merging a native command's error stream with `2>&1` turns every line written to stderr into an error record, even informational ones (here Claude Code's `[claude-code:unrecognized_model]` notice).
- **Fix:** do not merge stderr (`2>&1`) when the lines are not needed; stderr then goes to the console as plain text.

## Claude Code prints new files instead of saving them
- **Symptom:** asked to create a file, Claude Code shows the content in its answer but no file appears.
- **Likely cause:** in bare mode (`CLAUDE_CODE_SIMPLE=1`) the only tools are Bash, Read and Edit; there is no Write tool, `--tools` cannot add one, and the minimal system prompt does not tell the model how to save files, so a small model just prints the content.
- **Fix:** an appended instruction (bare mode: create files with Bash heredocs, change them with Edit) or `lean` mode, which adds the Write tool; see architecture D27 and the file-creation test (step 22).

## Scripts stop at the first line a child process writes to stderr (PowerShell ISE)
- **Symptom:** a script run from PowerShell ISE shows a red `NativeCommandError` banner around harmless output (for example Claude Code's `[claude-code:unrecognized_model]` notice) and then ends without its result line.
- **Cause:** ISE has no real console: it turns native programs' stderr lines into error records and can cut the run short. The interactive Claude Code interface cannot run in ISE at all.
- **Fix:** run all scripts of this project from a normal PowerShell window (`$Host.Name` prints `ConsoleHost`) or Windows Terminal. In print mode `claude.ps1` also runs `docker start` through `cmd.exe` with `2>&1`.

## PowerShell: "Variable reference is not valid. ':' was not followed by a valid variable name character"
- **Symptom:** a script fails to parse at a string such as `"Mode $mode: ..."`.
- **Cause:** `$name:` is read as a scope or drive prefix (like `$env:PATH`).
- **Fix:** write `${name}:`. Lint all scripts with `[System.Management.Automation.Language.Parser]::ParseFile(...)` before running them.

## Claude Code answers with a chat message instead of calling a tool (mostly `lean` mode)
- **Symptom:** asked to create or edit a file, the model replies with text (an explanation, or the file content) and no tool call, only some of the time.
- **Likely causes:** sampling randomness at the default temperature, and the long agent-style system prompt of the `lean` and `full` modes (see architecture D29).
- **Mitigations:** use `bare` mode (`claude.ps1 -Mode bare`); lower the engine temperature (`CCO_ENGINE_TEMPERATURE=0.2` in `config/.env`, then restart the engine); measure with `test-tool-reliability.ps1`.

## "Network cco_net Resource is still in use" when stopping
- **Symptom:** `down.ps1` or `compose down` removes the engine container but prints `Network cco_net Resource is still in use`.
- **Cause:** a Claude Code container (`cco-claude-<hex>`) was left behind, for example by an interrupted interactive session; even a stopped container keeps its network attachment.
- **Fix:** `Stop-CcoEngine` (used by `down.ps1`, `claude.ps1` and the tests) now removes leftover `cco-claude-*` containers first. Manually: `docker ps -aq --filter name=cco-claude- | ForEach-Object { docker rm -f $_ }` and `docker network rm cco_net`.

## Inspecting what Claude Code actually did in a session
- Claude Code stores each session as a transcript (JSONL) in its config directory, which is the Docker volume `cco_claude_home` (mounted at `/home/cco/.claude-cfg`).
- `scripts\windows\show-last-session.ps1 [-Sessions 1] [-MaxLines 80]` prints a compact summary: per message the role, text snippets, tool calls (tool name and key input) and tool results. Review the output before sharing it; it contains the first 240 characters of messages and tool inputs.
## A script called with an array of arguments ignores the switches
- **Symptom:** `& .\script.ps1 @('-Upgrade')` runs the script without `-Upgrade` (here: `upgrade.ps1` rebuilt from cache and reported "nothing changed").
- **Cause:** splatting an array passes each item as a plain positional string, never as a named parameter.
- **Fix:** splat a hashtable instead: `& .\script.ps1 @{ Upgrade = $true }` (named values: `@{ Repeat = 2 }`, lists: `@{ Modes = @('bare') }`).

## Free Windows commit looks very low right after the engine stopped
- **Symptom:** `validate-config.ps1` or a script reports 0.8-0.9 GiB of free Windows commit shortly after `down.ps1`.
- **Cause:** the WSL VM that hosts the containers keeps its memory for a while after the engine stops; Windows gets it back slowly. Observed: the next engine start still worked every time.
- **Fix:** wait a minute before the next start if the docker client ever crashes again (see the "cannot allocate memory" entry). WSL also has an `autoMemoryReclaim` setting in `.wslconfig` (verify the exact name and values in Microsoft's WSL documentation); changing it restarts WSL and every container in it.