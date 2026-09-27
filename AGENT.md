# AGENT.md — AI Agent Instructions

## Repository purpose

`llama-preset-base` is an installer for a local LLM server with a Qwen model preset.
The sole executable artifact is **`install.sh`**, which the user downloads via `curl`
from GitHub and runs (`curl -fsSL <url>/install.sh | bash`).
Other files (`README.md`, `AGENT.md`) are documentation only.

## Key invariant: install.sh must be self-contained

**All generated output is embedded inside `install.sh`**:
- launcher template — in the `LAUNCHER_EOF` heredoc (`write_launcher` function),
- preset template — in the `MODELS_EOF` heredoc (`write_models_ini` function).

There must be no external templates, assets, or sub-requests at install time:
the installation must work with a single `curl | bash` command on a clean machine.
The script performs **no network requests at all** and never compiles anything.

If behavior/configuration changes, modify the **templates inside `install.sh`** directly,
not separate files.

## Template modification rules

1. **Quoted heredocs** (`<<'LAUNCHER_EOF'`, `<<'MODELS_EOF'`) — content is not interpreted by bash.
   Everything that must appear verbatim in the final file (including `$HOME`, `${PORT}`, etc.)
   is written exactly as-is.
2. Substitutions in the launcher are done **only** via placeholders
   `__PORT__` and `__API_KEY__` using bash string substitution
   (`content="${content//__PORT__/${PORT}}"`) — do NOT use `sed`
   (the API key may contain sed-special characters). If you add a new substitution,
   add a new placeholder `__XXX__` and a corresponding replacement line.
3. `models.ini` — valid INI for the router mode of `llama-server`
   (format docs: [llama.cpp Model presets](https://github.com/ggml-org/llama.cpp/blob/master/docs/preset.md)):
   `[*]` section = global args; `[model_name]` sections = individual models;
   the `hf` key = the preset alias of `-hf` / `--hf-repo` and takes a full Hugging Face
   reference `"<user>/<model>[:QUANT]"` (e.g. `unsloth/Qwen3.8-27B-GGUF:Q4_K_XL`,
   quant is case-insensitive and defaults to `Q4_K_M`); the section name = model name in
   API calls. Do not break the format when editing, and do not reintroduce the split
   `hf-repo` + `hf-file` pair.
4. Server command in launcher: `llama-server --models-max 1 --host 0.0.0.0
   --port --api-key --models-preset`. If changing flags, cross-reference with the latest
   `llama-server` documentation (flag names change occasionally).

## Rules for install.sh

1. **Non-interactive**: no `read`/prompts in `install.sh` — it runs via pipe (`bash -s -- args`). The only interactive `read` is allowed in the *generated* launcher (`llama-qwen`) — this is a deliberate design choice (server runs until Enter).
2. **`set -euo pipefail`** is mandatory. Avoid `set -e` traps:
   - standalone `cmd && other` lines (use `if cmd; then ...; fi` instead);
   - arithmetic `(( expr ))` returning 0 outside an `if`;
   - `"${arr[@]}"` for empty arrays on old bash (acceptable here, Linux bash ≥ 5).
3. **Idempotency**: re-running the script must not break anything.
   Existing files are backed up to `*.bak.<timestamp>` (unless `--force`).
   Do not overcomplicate; don't add new flags without reason.
4. **llama.cpp check only — never build**: llama.cpp is considered installed if a working
   `llama-server` exists in `PATH` (`llama-server --version` returns 0). If it is missing,
   the script must **not** clone, configure, compile or install anything: it prints the
   upstream repository/build-doc links and recommends building for the user's hardware
   (CUDA / ROCm / Vulkan / SYCL / Metal / CPU), then still creates the launcher and preset.
   Rationale: backend choice is hardware-specific and must stay with the user.
5. **No build tooling**: do not shell out to `git`/`cmake`/package managers, do not
   auto-install dependencies, and do not write outside `$HOME` and the two output files.
6. **Security by default**: API key is generated randomly in the common LLM-API-key shape
   `sk-` + 48 alphanumeric characters (`openssl rand`, fallback `od`), never hardcoded.
7. **No external network calls**: the embedded templates plus `$HOME` writes are the whole
   install. Keep it that way (see "Key invariant").

## Pre-commit checklist

1. `bash -n install.sh` — syntax validation.
2. `shellcheck install.sh` (if available) — zero new findings.
3. **Sandboxed test (llama.cpp present in the system)**:
   ```bash
   HOME=/tmp/lpb-test bash install.sh --port 19199
   bash -n /tmp/lpb-test/.local/bin/llama-qwen   # syntax of generated launcher
   ```
   Verify: `llama-qwen` is created (executable, contains port and key),
   `models.ini` uses `hf = <repo>:Q4_K_XL`, key matches `^sk-[A-Za-z0-9]{48}$`,
   summary output includes key, port, curl example.
4. **Sandboxed test (llama.cpp missing)**: hide `llama-server` from `PATH` (e.g. via a
   shadow bin directory of symlinks without llama-server/llama-cli) and run the script.
   Verify: it prints the repository link and per-hardware backend hints, does NOT invoke
   git/cmake, exits 0, and still writes launcher + preset.
5. **Idempotency**: second run in same `HOME` → files backed up.
6. `grep -n 'USER' install.sh README.md` — README should retain `<USER>` placeholder; `install.sh` should have no hardcoded user repo links.
7. After tests, remove sandboxes: `rm -rf /tmp/lpb-test*`.

## Do not

- Extract templates into separate repo files (breaks `curl | bash`).
- Add interactive prompts to `install.sh`.
- Add automatic compilation/installation of llama.cpp back into `install.sh`.
- Hardcode API keys or specific user paths (except safe `$HOME` defaults).
- Use `sudo` or `rm -rf` outside `$HOME` and `mktemp` scratch files.
- Change `print_summary` output format without good reason — that's what the user sees (key, port, start commands).
- Recommend a specific llama.cpp version or backend as mandatory: point at upstream and let the user pick the backend for their hardware.
