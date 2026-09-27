#!/usr/bin/env bash
# =============================================================================
# llama-preset-base — Qwen preset installer for llama.cpp
#
# What it does:
#   1. Checks that llama.cpp CLI (llama-server) is present in PATH.
#      If it is NOT found, this script does NOT build anything: it prints the
#      link to the upstream repository and recommends following the official
#      build instructions for your hardware (CUDA, Vulkan, ROCm, SYCL, Metal...).
#   2. Creates a launcher at ~/.local/bin/llama-qwen
#      (launches llama-server in router mode with the Qwen model preset).
#   3. Creates the model preset at ~/.config/llama.cpp/models.ini
#      (INI configuration for the router mode).
#
# Quick install (self-contained, templates are embedded):
#   curl -fsSL https://raw.githubusercontent.com/<USER>/llama-preset-base/main/install.sh | bash
#
# With options:
#   curl -fsSL <url>/install.sh | bash -s -- --port 9200 --api-key "mykey"
#
# The script is non-interactive — safe for curl | bash.
# =============================================================================

set -euo pipefail

# ------------------------------ defaults ------------------------------------
readonly SCRIPT_NAME="llama-preset-base"
readonly LLAMA_CPP_REPO_URL="https://github.com/ggml-org/llama.cpp"
readonly LLAMA_CPP_BUILD_DOC_URL="https://github.com/ggml-org/llama.cpp/blob/master/docs/build.md"

PORT=9199
API_KEY=""                       # empty => will generate a random key
FORCE=0                          # 1 = overwrite existing files without backup
SKIP_FILES=0                     # 1 = skip creating launcher and preset
SKIP_LLCPP=0                     # 1 = skip the llama.cpp presence check
LLAMA_QWEN_DEST="${HOME}/.local/bin/llama-qwen"
MODELS_INI_DEST="${HOME}/.config/llama.cpp/models.ini"
LLAMA_SERVER_BIN=""

# --------------------------------- utilities --------------------------------
if [[ -t 1 ]]; then
  C_GRN=$'\033[32m'; C_YLW=$'\033[33m'; C_RED=$'\033[31m'; C_RST=$'\033[0m'
else
  C_GRN=""; C_YLW=""; C_RED=""; C_RST=""
fi
info() { printf '%s[*]%s %s\n' "$C_GRN" "$C_RST" "$*"; }
warn() { printf '%s[!]%s %s\n' "$C_YLW" "$C_RST" "$*" >&2; }
err()  { printf '%s[x]%s %s\n' "$C_RED" "$C_RST" "$*" >&2; }
die()  { err "$*"; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  cat <<'USAGE'
llama-preset-base — Qwen preset installer for llama.cpp

Quick install:
  curl -fsSL https://raw.githubusercontent.com/<USER>/llama-preset-base/main/install.sh | bash

With options:
  curl -fsSL <url>/install.sh | bash -s -- [options]

Options:
  -p, --port PORT        server port (default: 9199)
      --api-key KEY      API key for the server (default: randomly generated, "sk-..." format)
  -f, --force            overwrite existing files without backup
      --skip-files       skip creating launcher and preset
      --skip-llama-cpp   skip checking for llama.cpp in PATH
      --launcher PATH    where to write the launcher (default: ~/.local/bin/llama-qwen)
      --preset PATH      where to write the preset (default: ~/.config/llama.cpp/models.ini)
  -h, --help             this help message

Note: this installer does NOT build llama.cpp. If llama-server is missing,
install it yourself following https://github.com/ggml-org/llama.cpp
USAGE
}

parse_args() {
  while (( $# )); do
    case "$1" in
      -f|--force)          FORCE=1 ;;
      --skip-files)        SKIP_FILES=1 ;;
      --skip-llama-cpp)    SKIP_LLCPP=1 ;;
      --api-key)           (( $# >= 2 )) || die "--api-key requires a value"; API_KEY="$2"; shift ;;
      -p|--port)           (( $# >= 2 )) || die "--port requires a value"; PORT="$2"; shift ;;
      --launcher)          (( $# >= 2 )) || die "--launcher requires a value"; LLAMA_QWEN_DEST="$2"; shift ;;
      --preset)            (( $# >= 2 )) || die "--preset requires a value"; MODELS_INI_DEST="$2"; shift ;;
      -h|--help)           usage; exit 0 ;;
      *)                   die "unknown option: $1 (see --help)" ;;
    esac
    shift
  done
  [[ "$PORT" =~ ^[0-9]+$ ]] && (( PORT > 0 && PORT < 65536 )) || die "invalid port: $PORT"
}

# ------------------------------ llama.cpp check ------------------------------
print_llama_cpp_hint() {
  warn "llama.cpp (llama-server) was not found in PATH."
  cat >&2 <<HINT

  This installer does NOT compile or install llama.cpp for you.
  Install it manually — the official sources of truth are:

    repository : ${LLAMA_CPP_REPO_URL}
    build docs : ${LLAMA_CPP_BUILD_DOC_URL}

  Follow the build instructions from the repository and pick the backend that
  matches YOUR hardware, for example:

    NVIDIA GPU (CUDA)    : cmake -B build -DGGML_CUDA=ON
    AMD GPU (ROCm/HIP)   : cmake -B build -DGGML_HIP=ON
    Any GPU (Vulkan)     : cmake -B build -DGGML_VULKAN=ON
    Intel GPU (SYCL)     : cmake -B build -DGGML_SYCL=ON
    Apple Silicon (Metal): cmake -B build -DGGML_METAL=ON   # enabled by default on macOS
    CPU only             : cmake -B build

  Then build and install the binaries:

    cmake --build build --config Release -j "\$(nproc)"
    # put build/bin/llama-server (and llama-cli) in your PATH, e.g.:
    install -m 0755 build/bin/llama-server ~/.local/bin/

  After llama.cpp is in PATH, just run: llama-qwen

HINT
}

ensure_llama_cpp() {
  if have llama-server; then
    if llama-server --version >/dev/null 2>&1; then
      LLAMA_SERVER_BIN="$(command -v llama-server)"
      info "llama.cpp found: $LLAMA_SERVER_BIN"
      llama-server --version | head -1 | sed 's/^/     /'
      if ! have llama-cli; then
        warn "llama-cli not found in PATH (optional; the preset only needs llama-server)"
      fi
      return 0
    fi
    warn "llama-server found at $(command -v llama-server) but it failed to run"
  fi

  LLAMA_SERVER_BIN=""
  print_llama_cpp_hint
}

# ---------------------------------- API key ----------------------------------
generate_api_key() {
  # Common practice for LLM API keys: a short provider prefix ("sk-")
  # followed by ~48 random alphanumeric characters (OpenAI/OpenRouter style).
  local raw
  if have openssl; then
    raw="$(openssl rand -base64 48 | tr -d '\n=' | tr '/+' 'AZ')"
  else
    raw="$(od -An -v -tx1 -N48 /dev/urandom | tr -d ' \n')"
  fi
  raw="${raw//[^A-Za-z0-9]/}"
  printf 'sk-%s\n' "${raw:0:48}"
}

# ---------------------------------- backups ----------------------------------
backup_if_exists() { # $1 = file path
  local dest="$1" ts
  if [[ -e "$dest" ]] && (( FORCE == 0 )); then
    ts="$(date +%Y%m%d-%H%M%S)"
    cp -a "$dest" "${dest}.bak.${ts}"
    info "existing $dest backed up to ${dest}.bak.${ts}"
  fi
}

# ----------------------------------- templates -------------------------------
write_launcher() {
  local tmp content
  tmp="$(mktemp)"
  cat > "$tmp" <<'LAUNCHER_EOF'
#!/usr/bin/env bash
# llama-qwen — llama-server (router) with Qwen model preset
# Generated by: llama-preset-base

PORT=__PORT__
API_KEY="__API_KEY__"
MODELS_PRESET="${HOME}/.config/llama.cpp/models.ini"

echo ""
echo "============================================="
echo "[*] Starting LLaMA server on port ${PORT}..."
echo "============================================="
echo ""

llama-server --models-max 1 --host 0.0.0.0 --port "${PORT}" \
  --api-key "${API_KEY}" \
  --models-preset "${MODELS_PRESET}"

echo ""
echo "============================================="
echo "[*] Done."
read -rp "Press Enter to exit"
LAUNCHER_EOF
  content="$(cat "$tmp")"
  content="${content//__PORT__/${PORT}}"
  content="${content//__API_KEY__/${API_KEY}}"
  printf '%s\n' "$content" > "$LLAMA_QWEN_DEST"
  rm -f "$tmp"
  chmod +x "$LLAMA_QWEN_DEST"
}

write_models_ini() {
  # `hf` is the preset alias of `--hf-repo` / `-hf` and takes a full Hugging
  # Face reference "<user>/<model>[:QUANT]" (quant is case-insensitive).
  # See: https://github.com/ggml-org/llama.cpp/blob/master/docs/preset.md
  cat > "$MODELS_INI_DEST" <<'MODELS_EOF'
[*]
ctx-size = 16384
parallel = 1
mlock = 1
flash-attn = on
n-gpu-layers = -1

[unsloth/Qwen3.8-27B-MTP-GGUF-64K]
hf = unsloth/Qwen3.8-27B-GGUF:Q4_K_XL
ctx-size = 65536
spec-type = draft-mtp
spec-draft-n-max = 4
temperature = 1.0
top-p = 0.95
top-k = 20
min-p = 0.0
presence-penalty = 0.0
repeat-penalty = 1.0

[unsloth/Qwen3.8-27B-MTP-GGUF-64K-noreasoning]
hf = unsloth/Qwen3.8-27B-GGUF:Q4_K_XL
ctx-size = 65536
spec-type = draft-mtp
spec-draft-n-max = 4
reasoning = off
temperature = 0.7
top-p = 0.8
top-k = 20
min-p = 0.0
presence-penalty = 1.5
repeat-penalty = 1.0

[unsloth/Qwen3.8-27B-MTP-GGUF-32K]
hf = unsloth/Qwen3.8-27B-GGUF:Q4_K_XL
ctx-size = 32768
spec-type = draft-mtp
spec-draft-n-max = 4
temperature = 1.0
top-p = 0.95
top-k = 20
min-p = 0.0
presence-penalty = 0.0
repeat-penalty = 1.0

[unsloth/Qwen3.8-27B-MTP-GGUF-32K-noreasoning]
hf = unsloth/Qwen3.8-27B-GGUF:Q4_K_XL
ctx-size = 32768
spec-type = draft-mtp
spec-draft-n-max = 4
reasoning = off
temperature = 0.7
top-p = 0.8
top-k = 20
min-p = 0.0
presence-penalty = 1.5
repeat-penalty = 1.0

[unsloth/Qwen3.6-35B-A3B-MTP-GGUF-64K]
hf = unsloth/Qwen3.6-35B-A3B-MTP-GGUF:Q4_K_XL
ctx-size = 65536
spec-type = draft-mtp
spec-draft-n-max = 2
temperature = 1.0
top-p = 0.95
top-k = 20
min-p = 0.0
presence-penalty = 1.5
repeat-penalty = 1.0

[unsloth/Qwen3.6-35B-A3B-MTP-GGUF-32K]
hf = unsloth/Qwen3.6-35B-A3B-MTP-GGUF:Q4_K_XL
ctx-size = 32768
spec-type = draft-mtp
spec-draft-n-max = 2
temperature = 1.0
top-p = 0.95
top-k = 20
min-p = 0.0
presence-penalty = 1.5
repeat-penalty = 1.0
MODELS_EOF
}

# ------------------------------ preset installation --------------------------
install_preset_files() {
  if [[ -z "$API_KEY" ]]; then
    API_KEY="$(generate_api_key)"
    info "generated a random API key (sk-... format)"
  fi

  mkdir -p "$(dirname "$LLAMA_QWEN_DEST")" "$(dirname "$MODELS_INI_DEST")"

  backup_if_exists "$LLAMA_QWEN_DEST"
  write_launcher
  info "launcher created: $LLAMA_QWEN_DEST"

  backup_if_exists "$MODELS_INI_DEST"
  write_models_ini
  info "model preset created: $MODELS_INI_DEST"
}

# ----------------------------------- summary ---------------------------------
print_summary() {
  local models_list
  models_list="$(grep -oE '^\[(.+)\]$' "$MODELS_INI_DEST" 2>/dev/null | grep -v '^\[\*\]$' | sed 's/^\[//; s/\]$//' | paste -sd ', ' - || true)"

  echo ""
  echo "============================================="
  echo " $SCRIPT_NAME installed"
  echo "============================================="
  echo "  launcher   : $LLAMA_QWEN_DEST"
  echo "  preset     : $MODELS_INI_DEST"
  if [[ -n "$LLAMA_SERVER_BIN" ]]; then
    echo "  server     : $LLAMA_SERVER_BIN"
  else
    echo "  server     : NOT INSTALLED (see instructions above)"
  fi
  echo "  port       : $PORT"
  echo "  api-key    : $API_KEY"
  echo ""
  echo "Start the server:"
  echo "  llama-qwen"
  echo ""
  echo "Test the API (in another terminal, after the model is loaded):"
  echo "  curl -s http://localhost:${PORT}/v1/chat/completions \\"
  echo "    -H \"Authorization: Bearer ${API_KEY}\" \\"
  echo "    -H 'Content-Type: application/json' \\"
  echo "    -d '{\"model\":\"${models_list%%,*}\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}'"
  echo ""
  echo "List models:  curl -s -H \"Authorization: Bearer ${API_KEY}\" http://localhost:${PORT}/v1/models"
  echo ""
  echo "Note: on the first request to a GGUF model it will be auto-downloaded"
  echo "      from Hugging Face (check disk space; size depends on the model, see preset: ${MODELS_INI_DEST})."
  if [[ -z "$LLAMA_SERVER_BIN" ]]; then
    echo ""
    echo "llama-server is missing. Build llama.cpp for your hardware following:"
    echo "  ${LLAMA_CPP_REPO_URL}"
    echo "  ${LLAMA_CPP_BUILD_DOC_URL}"
  fi
  echo "============================================="
}

# ----------------------------------- main ------------------------------------
main() {
  parse_args "$@"

  echo ""
  echo "============================================="
  echo " $SCRIPT_NAME — Qwen preset installer"
  echo "============================================="
  echo ""

  # 1) llama.cpp presence check (no automatic build)
  if (( SKIP_LLCPP )); then
    info "llama.cpp check skipped (--skip-llama-cpp)"
  else
    ensure_llama_cpp
  fi

  # 2) preset files
  if (( SKIP_FILES )); then
    info "file creation skipped (--skip-files)"
  else
    install_preset_files
  fi

  print_summary
}

main "$@"
