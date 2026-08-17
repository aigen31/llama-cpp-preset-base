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
the installation must work with a single `curl | bash` command on a clean machine
(the only external network resource being `git clone` of llama.cpp).

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
   (format docs: [llama.cpp Model presets](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md)):
   `[*]` section = global args; `[model_name]` sections = individual models;
   `hf-repo` + `hf-file` point to a Hugging Face GGUF; the section name = model name in API calls. Do not break the format when editing.
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
   Existing git clone in `--build-dir` is updated, not recreated. Do not overcomplicate; don't add new flags without reason.
4. **llama.cpp check**: considered installed if a working `llama-server` exists in `PATH` (`llama-server --version` returns 0). Only `llama-cli` present → still rebuild (preset requires the server). Neither found → build from https://github.com/ggml-org/llama.cpp.
5. **Build flow**: shallow clone → `cmake -S -B build -DCMAKE_BUILD_TYPE=Release` (+ `-DGGML_CUDA=ON` on auto-detected GPU: `nvidia-smi`/`nvcc`/`/dev/nvidia0`) → `cmake --build build -j$(nproc)` → `install -m 0755 build/bin/{llama-cli,llama-server}` to `/usr/local/bin` (if writable) or `~/.local/bin`.
   When modifying: preserve the order "deps check → clone → cmake → build → install → PATH verify".
6. **Security by default**: API key is generated randomly (`openssl rand -base64 16`, fallback `od`), never hardcoded. The script writes only to `$HOME` and (with privileges) `/usr/local/bin`.
7. **Package managers**: support apt/dnf/pacman/zypper/apk. When adding a new one, add a branch in `detect_pkg_mgr` and `ensure_build_deps`.

## Pre-commit checklist

1. `bash -n install.sh` — syntax validation.
2. `shellcheck install.sh` (if available) — zero new findings.
3. **Sandboxed test (no build path, llama.cpp exists in the system)**:
   ```bash
   HOME=/tmp/lpb-test bash install.sh --port 19199
   bash -n /tmp/lpb-test/.local/bin/llama-qwen   # syntax of generated launcher
   ```
   Verify: `llama-qwen` is created (executable, contains port and key),
   `models.ini` is correct, summary output includes key, port, and curl example.
4. **Sandboxed test with build path** (only if build logic changed):
   ```bash
   env -i HOME=/tmp/lpb-test2 PATH="/tmp/lpb-test2/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/cuda/bin" \
     bash install.sh
   /tmp/lpb-test2/.local/bin/llama-server --version
   ```
   (`PATH` intentionally excludes `/usr/local/bin` to hide the system-installed llama.cpp
   and exercise the build path; test is long ~5–15 min with CUDA.)
5. **Idempotency**: second run in same `HOME` → files backed up, build skipped.
6. `grep -n 'USER' install.sh README.md` — README should retain `<USER>` placeholder; `install.sh` should have no hardcoded user repo links.
7. After tests, remove sandboxes: `rm -rf /tmp/lpb-test*`.

## Do not

- Extract templates into separate repo files (breaks `curl | bash`).
- Add interactive prompts to `install.sh`.
- Hardcode API keys or specific user paths (except safe `$HOME` defaults).
- Use `sudo rm -rf` in user directories; only use `rm -rf` for `$BUILD_DIR` and `mktemp` scratch files.
- Change `print_summary` output format without good reason — that's what the user sees (key, port, start commands).
- Manually pin llama.cpp versions/branches: always build from `master` via `git fetch --depth 1` + `reset --hard origin/HEAD`.
