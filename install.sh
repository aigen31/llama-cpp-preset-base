#!/usr/bin/env bash
# =============================================================================
# llama-preset-base — Qwen preset installer for llama.cpp
#
# What it does:
#   1. Checks for the presence of llama.cpp CLI (llama-cli / llama-server).
#      If not found — clones and builds llama.cpp from
#      https://github.com/ggml-org/llama.cpp and installs binaries to PATH.
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
readonly LLAMA_CPP_REPO="https://github.com/ggml-org/llama.cpp.git"
readonly SCRIPT_NAME="llama-preset-base"

PORT=9199
API_KEY=""                       # empty => will generate a random key
FORCE=0                          # 1 = overwrite existing files without backup
SKIP_FILES=0                     # 1 = skip creating launcher and preset
SKIP_LLCPP=0                     # 1 = skip llama.cpp check/installation
AUTO_DEPS=1                      # 1 = auto-install build dependencies
CUDA_MODE="auto"                 # auto | on | off
BUILD_DIR="${HOME}/.cache/llama-preset-base/llama.cpp"
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
      --api-key KEY      API key for the server (default: randomly generated)
  -f, --force            overwrite existing files without backup
      --skip-files       skip creating launcher and preset
      --skip-llama-cpp   skip checking/building llama.cpp
      --no-auto-deps     don't auto-install build dependencies
      --cuda             force CUDA backend during build (default: auto-detect)
      --no-cuda          force CPU-only build
      --build-dir DIR    where to clone llama.cpp (default: ~/.cache/llama-preset-base/llama.cpp)
      --launcher PATH    where to write the launcher (default: ~/.local/bin/llama-qwen)
      --preset PATH      where to write the preset (default: ~/.config/llama.cpp/models.ini)
  -h, --help             this help message
USAGE
}

parse_args() {
  while (( $# )); do
    case "$1" in
      -f|--force)          FORCE=1 ;;
      --skip-files)        SKIP_FILES=1 ;;
      --skip-llama-cpp)    SKIP_LLCPP=1 ;;
      --no-auto-deps)      AUTO_DEPS=0 ;;
      --cuda)              CUDA_MODE="on" ;;
      --no-cuda)           CUDA_MODE="off" ;;
      --api-key)           (( $# >= 2 )) || die "--api-key requires a value"; API_KEY="$2"; shift ;;
      -p|--port)           (( $# >= 2 )) || die "--port requires a value"; PORT="$2"; shift ;;
      --build-dir)         (( $# >= 2 )) || die "--build-dir requires a value"; BUILD_DIR="$2"; shift ;;
      --launcher)          (( $# >= 2 )) || die "--launcher requires a value"; LLAMA_QWEN_DEST="$2"; shift ;;
      --preset)            (( $# >= 2 )) || die "--preset requires a value"; MODELS_INI_DEST="$2"; shift ;;
      -h|--help)           usage; exit 0 ;;
      *)                   die "unknown option: $1 (see --help)" ;;
    esac
    shift
  done
  [[ "$PORT" =~ ^[0-9]+$ ]] && (( PORT > 0 && PORT < 65536 )) || die "invalid port: $PORT"
}

# ------------------------------ build dependencies ---------------------------
detect_pkg_mgr() {
  if   have apt-get; then echo apt
  elif have dnf;     then echo dnf
  elif have pacman;  then echo pacman
  elif have zypper;  then echo zypper
  elif have apk;     then echo apk
  else echo ""
  fi
}

ensure_build_deps() {
  local cc="" c
  for c in g++ clang++ c++ cc; do
    if have "$c"; then cc="$c"; break; fi
  done

  if have git && have cmake && [[ -n "$cc" ]]; then
    info "build dependencies are already present (compiler: $cc)"
    return 0
  fi

  local missing=()
  if ! have git;   then missing+=("git"); fi
  if ! have cmake; then missing+=("cmake"); fi
  if [[ -z "$cc" ]]; then missing+=("g++/clang++"); fi

  warn "missing build dependencies: ${missing[*]}"
  if (( ! AUTO_DEPS )); then
    die "install them manually and re-run:
  apt:    sudo apt install build-essential cmake git
  dnf:    sudo dnf install gcc-c++ glibc-devel make cmake git
  pacman: sudo pacman -S base-devel cmake git
  zypper: sudo zypper install gcc-c++ cmake make git
  apk:    sudo apk add build-base cmake git"
  fi

  local mgr
  mgr="$(detect_pkg_mgr)"
  [[ -n "$mgr" ]] || die "no supported package manager (apt/dnf/pacman/zypper/apk) found"

  info "installing build dependencies via $mgr: ${missing[*]}"
  local sudo=""
  if [[ ${EUID} -ne 0 ]]; then
    if have sudo; then sudo="sudo"
    else die "root privileges or sudo required to install dependencies"; fi
  fi
  case "$mgr" in
    apt)    $sudo apt-get update -y && $sudo apt-get install -y build-essential cmake git ;;
    dnf)    $sudo dnf install -y gcc-c++ glibc-devel make cmake git ;;
    pacman) $sudo pacman -Sy --noconfirm base-devel cmake git ;;
    zypper) $sudo zypper --non-interactive install gcc-c++ cmake make git ;;
    apk)    $sudo apk add --no-cache build-base cmake git ;;
  esac

  # re-check
  if ! have git || ! have cmake; then
    die "dependency installation failed — please install manually (git, cmake, C++ compiler)"
  fi
}

# ----------------------------------- build llama.cpp -------------------------
build_llama_cpp() {
  info "llama.cpp not found — building from source: $LLAMA_CPP_REPO"
  ensure_build_deps

  mkdir -p "$(dirname "$BUILD_DIR")"
  if [[ -d "$BUILD_DIR/.git" ]]; then
    info "updating existing clone: $BUILD_DIR"
    git -C "$BUILD_DIR" fetch --depth 1 origin
    git -C "$BUILD_DIR" reset --hard origin/HEAD
  else
    rm -rf "$BUILD_DIR"
    git clone --depth 1 "$LLAMA_CPP_REPO" "$BUILD_DIR"
  fi

  # --- detect CUDA backend ---
  local mode="$CUDA_MODE"
  if [[ "$mode" == "auto" ]]; then
    if have nvidia-smi || have nvcc || [[ -e /dev/nvidia0 ]]; then
      mode="on"
    else
      mode="off"
    fi
  fi

  local cfg=(-DCMAKE_BUILD_TYPE=Release)
  if [[ "$mode" == "on" ]]; then
    if have nvcc || [[ -d /usr/local/cuda ]]; then
      cfg+=(-DGGML_CUDA=ON)
      info "CUDA backend: enabled"
    else
      warn "CUDA requested but no CUDA toolkit (nvcc) found — building without CUDA"
    fi
  fi

  info "configuring (cmake)..."
  cmake -S "$BUILD_DIR" -B "$BUILD_DIR/build" "${cfg[@]}"

  local jobs
  jobs="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"
  info "compiling (jobs=$jobs, this may take a few minutes)..."
  cmake --build "$BUILD_DIR/build" --config Release -j "$jobs"

  local bin src
  for bin in llama-cli llama-server; do
    src="$BUILD_DIR/build/bin/$bin"
    if [[ ! -x "$src" ]]; then
      die "expected binary not found after build: $src"
    fi
  done

  # --- install binaries ---
  local dest_dir
  if [[ ${EUID} -eq 0 && -d /usr/local/bin ]]; then
    dest_dir="/usr/local/bin"
  elif [[ -w /usr/local/bin ]]; then
    dest_dir="/usr/local/bin"
  else
    dest_dir="${HOME}/.local/bin"
    mkdir -p "$dest_dir"
  fi

  for bin in llama-cli llama-server; do
    install -m 0755 "$BUILD_DIR/build/bin/$bin" "$dest_dir/$bin"
    info "installed: $dest_dir/$bin"
  done

  case ":$PATH:" in
    *":$dest_dir:"*) ;;
    *) warn "$dest_dir is not in PATH. Add it to ~/.bashrc:
  export PATH=\"$dest_dir:\$PATH\"" ;;
  esac
}

ensure_llama_cpp() {
  local need_build=0
  if have llama-server; then
    if llama-server --version >/dev/null 2>&1; then
      LLAMA_SERVER_BIN="$(command -v llama-server)"
      info "llama.cpp found: $LLAMA_SERVER_BIN"
      llama-server --version | head -1 | sed 's/^/     /'
      if ! have llama-cli; then
        warn "llama-cli not found in PATH (optional; preset only needs llama-server)"
      fi
    else
      warn "llama-server found but doesn't run — rebuilding"
      need_build=1
    fi
  elif have llama-cli; then
    warn "llama-cli found, but llama-server is missing — building llama.cpp"
    need_build=1
  else
    info "llama-cli / llama-server not found in PATH"
    need_build=1
  fi

  if (( need_build )); then
    build_llama_cpp
    have llama-server || die "llama-server still not found in PATH (check your PATH)"
    LLAMA_SERVER_BIN="$(command -v llama-server)"
  fi
}

# ---------------------------------- API key ----------------------------------
generate_api_key() {
  if have openssl; then
    openssl rand -base64 16 | tr -d '\n'
  else
    od -An -v -tx1 -N16 /dev/urandom | tr -d ' \n'
  fi
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
  cat > "$MODELS_INI_DEST" <<'MODELS_EOF'
[*]
ctx-size = 16384
parallel = 1
mlock = 1
flash-attn = on
n-gpu-layers = -1

[unsloth/Qwen3.8-27B-MTP-GGUF-64K]
hf-repo = unsloth/Qwen3.8-27B-GGUF
hf-file = Qwen3.8-27B-UD-Q4_K_XL.gguf
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
hf-repo = unsloth/Qwen3.8-27B-GGUF
hf-file = Qwen3.8-27B-UD-Q4_K_XL.gguf
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
hf-repo = unsloth/Qwen3.8-27B-GGUF
hf-file = Qwen3.8-27B-UD-Q4_K_XL.gguf
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
hf-repo = unsloth/Qwen3.8-27B-GGUF
hf-file = Qwen3.8-27B-UD-Q4_K_XL.gguf
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
hf-repo = unsloth/Qwen3.6-35B-A3B-MTP-GGUF
hf-file = Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf
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
hf-repo = unsloth/Qwen3.6-35B-A3B-MTP-GGUF
hf-file = Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf
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
    info "generated a random API key"
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

  # 1) llama.cpp
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
