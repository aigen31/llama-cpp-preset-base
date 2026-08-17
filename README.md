# llama-preset-base

One-script installer for a local LLM server with the Qwen model preset:

- **llama.cpp** — checks if `llama-cli` / `llama-server` is in `PATH`. If missing, it clones [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp), builds it (with auto-detected CUDA), and installs binaries.
- **`~/.local/bin/llama-qwen`** — launcher: starts `llama-server` in router mode with the preset, port, and API key.
- **`~/.config/llama.cpp/models.ini`** — model preset (INI) for llama-server's router mode: Qwen3.8-27B / Qwen3.6-35B-A3B with MTP speculative decoding, 32K/64K contexts, and reasoning/noreasoning variants.

## Installation

The installer is self-contained (file templates are embedded inside), so you only need one command:

```bash
curl -fsSL https://raw.githubusercontent.com/<USER>/llama-preset-base/main/install.sh | bash
```

With options (pass arguments after `--`):

```bash
curl -fsSL https://raw.githubusercontent.com/<USER>/llama-preset-base/main/install.sh \
  | bash -s -- --port 9200 --api-key "my-secret-key"
```

### Options

| Flag | Description |
|---|---|
| `-p, --port PORT` | server port (default: `9199`) |
| `--api-key KEY` | API key for the server (default: randomly generated) |
| `-f, --force` | overwrite existing files without backup |
| `--skip-files` | skip creating launcher and preset |
| `--skip-llama-cpp` | skip checking/building llama.cpp |
| `--no-auto-deps` | don't auto-install build dependencies (apt/dnf/pacman/zypper/apk) |
| `--cuda` / `--no-cuda` | force CUDA backend on/off during build (default: auto-detect) |
| `--build-dir DIR` | where to clone llama.cpp (default: `~/.cache/llama-preset-base/llama.cpp`) |
| `--launcher PATH` | where to write the launcher (default: `~/.local/bin/llama-qwen`) |
| `--preset PATH` | where to write the preset (default: `~/.config/llama.cpp/models.ini`) |
| `-h, --help` | help message |

The script is non-interactive — safe for `curl | bash`. On re-installation, existing files are first copied to `*.bak.<timestamp>` (use `--force` to overwrite silently).

### What happens during llama.cpp build

1. Checks dependencies: `git`, `cmake`, C++ compiler (`g++`/`clang++`). Installs missing ones via your system package manager (requires `sudo`).
2. `git clone --depth 1 https://github.com/ggml-org/llama.cpp`
   (if a clone already exists in `--build-dir`, it is updated instead of recreated).
3. `cmake -DCMAKE_BUILD_TYPE=Release` (+ `-DGGML_CUDA=ON` if an NVIDIA GPU and CUDA toolkit are detected) followed by compilation.
4. Copies `llama-cli` and `llama-server` to `/usr/local/bin` (or `~/.local/bin` if you don't have root privileges). Warns if the directory is not in `PATH`.

> If llama.cpp is already installed (detected via `llama-server`), the build step is skipped.

## Usage

### 1. Start the server

```bash
llama-qwen
```

This launches `llama-server` in router mode:

```
llama-server --models-max 1 --host 0.0.0.0 --port 9199 \
  --api-key "<key>" --models-preset ~/.config/llama.cpp/models.ini
```

On the first request to a GGUF model, **it is automatically downloaded from Hugging Face** (several dozen GBs for Q4_K_XL 27B/35B models — make sure you have enough disk space).

### 2. API requests

The model name in API calls = the section name in `models.ini`. List available models:

```bash
curl -s -H "Authorization: Bearer <API_KEY>" http://localhost:9199/v1/models
```

Example OpenAI-compatible request:

```bash
curl -s http://localhost:9199/v1/chat/completions \
  -H "Authorization: Bearer <API_KEY>" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "unsloth/Qwen3.8-27B-MTP-GGUF-64K",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

The API key is the one printed by the installer (or set via `--api-key`). Compatible with OpenAI clients — just set the base URL to `http://localhost:9199/v1`.

### Available presets (default)

| Model name in API | Model | Context | Features |
|---|---|---|---|
| `unsloth/Qwen3.8-27B-MTP-GGUF-64K` | Qwen3.8-27B UD Q4_K_XL | 64K | MTP spec-decoding, reasoning |
| `unsloth/Qwen3.8-27B-MTP-GGUF-64K-noreasoning` | same | 64K | no reasoning, T=0.7 |
| `unsloth/Qwen3.8-27B-MTP-GGUF-32K` | same | 32K | MTP spec-decoding |
| `unsloth/Qwen3.8-27B-MTP-GGUF-32K-noreasoning` | same | 32K | no reasoning, T=0.7 |
| `unsloth/Qwen3.6-35B-A3B-MTP-GGUF-64K` | Qwen3.6-35B-A3B UD Q4_K_XL | 64K | MoE, MTP spec-decoding |
| `unsloth/Qwen3.6-35B-A3B-MTP-GGUF-32K` | same | 32K | MoE, MTP spec-decoding |

Global settings (`[*]`): `ctx-size=16384` (minimum for router), `parallel=1`, `mlock=1`, `flash-attn=on`, `n-gpu-layers=-1` (entire graph on GPU).

## Customization

**Change models/parameters** — edit `~/.config/llama.cpp/models.ini`.
Each `[model_name]` section is an independent model; keys correspond to `llama-server` arguments (without `--`), plus `hf-repo`/`hf-file` for Hugging Face GGUF downloads. See the format documentation: [tools/server/README.md → Model presets](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md). Restart `llama-qwen` after changes.

**Change port/API key** — edit `~/.local/bin/llama-qwen` directly, or reinstall with:
`... | bash -s -- --port ... --api-key ...`

## Uninstall

```bash
rm -f  ~/.local/bin/llama-qwen
rm -rf ~/.config/llama.cpp
rm -rf ~/.cache/llama-preset-base     # llama.cpp clone (if built by the script)
# optionally:
rm -f  ~/.local/bin/llama-cli ~/.local/bin/llama-server
```

## Troubleshooting

| Symptom | Solution |
|---|---|
| `llama-server: command not found` when running `llama-qwen` | The binary directory is not in `PATH`; add `export PATH="$HOME/.local/bin:$PATH"` to `~/.bashrc` |
| `Address already in use` | Port is occupied: `ss -tlnp \| grep 9199`; change port in `llama-qwen` |
| Slow first launch | Initial GGUF download from Hugging Face; monitor with `df -h` |
| Out of VRAM | Reduce `ctx-size` in `models.ini` or disable some layers; if building with CUDA, verify `llama-server --version` loads correctly |
| Build fails on CUDA | Retry with `--no-cuda` (CPU build), or update your CUDA toolkit |
| Installer overwrote files | Old versions are preserved alongside as `*.bak.<timestamp>` |
