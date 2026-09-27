# llama-preset-base

**English** · [Русский](#русский) · [中文](#中文)

---

<a id="english"></a>

## English

Installer for a local LLM server with a Qwen model preset.

It sets up three things:

- **llama.cpp check** — verifies that `llama-cli` / `llama-server` is available in `PATH`. **The script does not compile or install llama.cpp.** If the server is missing, it prints the link to the upstream repository and recommends building it yourself for your hardware (CUDA, Vulkan, ROCm, SYCL, Metal, CPU…). See [Prerequisite: llama.cpp](#prerequisite-llamacpp).
- **`~/.local/bin/llama-qwen`** — launcher: starts `llama-server` in router mode with the preset, port, and API key.
- **`~/.config/llama.cpp/models.ini`** — model preset (INI) for llama-server's router mode: Qwen3.8-27B / Qwen3.6-35B-A3B with MTP speculative decoding, 32K/64K contexts, and reasoning/noreasoning variants.

### Installation

The installer is self-contained (file templates are embedded inside), so you only need one command:

```bash
curl -fsSL https://raw.githubusercontent.com/<USER>/llama-preset-base/main/install.sh | bash
```

With options (pass arguments after `--`):

```bash
curl -fsSL https://raw.githubusercontent.com/<USER>/llama-preset-base/main/install.sh \
  | bash -s -- --port 9200 --api-key "sk-my-secret-key"
```

### Options

| Flag | Description |
|---|---|
| `-p, --port PORT` | server port (default: `9199`) |
| `--api-key KEY` | API key for the server (default: randomly generated, `sk-…` format) |
| `-f, --force` | overwrite existing files without backup |
| `--skip-files` | skip creating launcher and preset |
| `--skip-llama-cpp` | skip checking for llama.cpp in `PATH` |
| `--launcher PATH` | where to write the launcher (default: `~/.local/bin/llama-qwen`) |
| `--preset PATH` | where to write the preset (default: `~/.config/llama.cpp/models.ini`) |
| `-h, --help` | help message |

The script is non-interactive — safe for `curl | bash`. On re-installation, existing files are first copied to `*.bak.<timestamp>` (use `--force` to overwrite silently). The API key follows the common LLM-API-key shape: the prefix `sk-` followed by 48 random alphanumeric characters.

### Prerequisite: llama.cpp

`llama-server` must be in `PATH`. This installer **never builds llama.cpp automatically** — the choice of backend depends on your hardware and is left to you.

1. Open the upstream repository: <https://github.com/ggml-org/llama.cpp>
2. Follow the official build instructions: <https://github.com/ggml-org/llama.cpp/blob/master/docs/build.md>
3. Choose the backend matching your hardware:

   | Hardware | CMake flag |
   |---|---|
   | NVIDIA GPU (CUDA) | `-DGGML_CUDA=ON` |
   | AMD GPU (ROCm/HIP) | `-DGGML_HIP=ON` |
   | Any GPU (Vulkan) | `-DGGML_VULKAN=ON` |
   | Intel GPU (SYCL) | `-DGGML_SYCL=ON` |
   | Apple Silicon (Metal) | `-DGGML_METAL=ON` (enabled by default on macOS) |
   | CPU only | *(no flag)* |

   Example (CUDA):

   ```bash
   git clone https://github.com/ggml-org/llama.cpp
   cd llama.cpp
   cmake -B build -DGGML_CUDA=ON
   cmake --build build --config Release -j "$(nproc)"
   install -m 0755 build/bin/llama-server ~/.local/bin/
   ```

4. Re-run this installer (or just run `llama-qwen`) once `llama-server` is in `PATH`.

If the server is not found, the installer still creates the launcher and preset and reminds you where to get llama.cpp.

### Usage

#### 1. Start the server

```bash
llama-qwen
```

This launches `llama-server` in router mode:

```
llama-server --models-max 1 --host 0.0.0.0 --port 9199 \
  --api-key "<key>" --models-preset ~/.config/llama.cpp/models.ini
```

On the first request to a GGUF model, **it is automatically downloaded from Hugging Face** (several dozen GBs for Q4 27B/35B models — make sure you have enough disk space).

#### 2. API requests

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

#### Available presets (default)

| Model name in API | Model | Context | Features |
|---|---|---|---|
| `unsloth/Qwen3.8-27B-MTP-GGUF-64K` | Qwen3.8-27B UD Q4_K_XL | 64K | MTP spec-decoding, reasoning |
| `unsloth/Qwen3.8-27B-MTP-GGUF-64K-noreasoning` | same | 64K | no reasoning, T=0.7 |
| `unsloth/Qwen3.8-27B-MTP-GGUF-32K` | same | 32K | MTP spec-decoding |
| `unsloth/Qwen3.8-27B-MTP-GGUF-32K-noreasoning` | same | 32K | no reasoning, T=0.7 |
| `unsloth/Qwen3.6-35B-A3B-MTP-GGUF-64K` | Qwen3.6-35B-A3B UD Q4_K_XL | 64K | MoE, MTP spec-decoding |
| `unsloth/Qwen3.6-35B-A3B-MTP-GGUF-32K` | same | 32K | MoE, MTP spec-decoding |

Global settings (`[*]`): `ctx-size=16384` (minimum for router), `parallel=1`, `mlock=1`, `flash-attn=on`, `n-gpu-layers=-1` (entire graph on GPU).

### Customization

**Change models/parameters** — edit `~/.config/llama.cpp/models.ini`.
Each `[model_name]` section is an independent model; keys correspond to `llama-server` arguments (without `--`). Models are fetched with the single `hf` key, which takes a full Hugging Face reference `"<user>/<model>[:QUANT]"` — for example `hf = unsloth/Qwen3.8-27B-GGUF:Q4_K_XL`. The quant tag is case-insensitive and defaults to `Q4_K_M`. Format documentation: [llama.cpp INI presets](https://github.com/ggml-org/llama.cpp/blob/master/docs/preset.md). Restart `llama-qwen` after changes.

**Change port/API key** — edit `~/.local/bin/llama-qwen` directly, or reinstall with:
`… | bash -s -- --port … --api-key …`

### Uninstall

```bash
rm -f  ~/.local/bin/llama-qwen
rm -rf ~/.config/llama.cpp
# if you installed llama.cpp yourself and want to remove it:
rm -f  ~/.local/bin/llama-cli ~/.local/bin/llama-server
```

### Troubleshooting

| Symptom | Solution |
|---|---|
| `llama-server: command not found` when running `llama-qwen` | Install llama.cpp (see [Prerequisite](#prerequisite-llamacpp)); make sure its binary directory is in `PATH`, e.g. `export PATH="$HOME/.local/bin:$PATH"` in `~/.bashrc` |
| `Address already in use` | Port is occupied: `ss -tlnp \| grep 9199`; change port in `llama-qwen` |
| Slow first launch | Initial GGUF download from Hugging Face; monitor with `df -h` |
| Out of VRAM | Reduce `ctx-size` in `models.ini` or offload fewer layers; verify that your llama.cpp build includes the right GPU backend |
| Wrong GPU backend | Rebuild llama.cpp with the flag for your hardware (CUDA/Vulkan/ROCm/…) |
| Installer overwrote files | Old versions are preserved alongside as `*.bak.<timestamp>` |

---

<a id="русский"></a>

## Русский

Установщик локального LLM-сервера с пресетом моделей Qwen.

Он настраивает три вещи:

- **Проверка llama.cpp** — проверяет наличие `llama-cli` / `llama-server` в `PATH`. **Скрипт не компилирует и не устанавливает llama.cpp.** Если сервер не найден, он выводит ссылку на официальный репозиторий и рекомендует собрать llama.cpp самостоятельно под ваше оборудование (CUDA, Vulkan, ROCm, SYCL, Metal, CPU…). См. [Требование: llama.cpp](#требование-llamacpp).
- **`~/.local/bin/llama-qwen`** — лаунчер: запускает `llama-server` в режиме router с пресетом, портом и API-ключом.
- **`~/.config/llama.cpp/models.ini`** — пресет моделей (INI) для режима router: Qwen3.8-27B / Qwen3.6-35B-A3B со спекулятивным декодированием MTP, контекстами 32K/64K и вариантами с/без reasoning.

### Установка

Установщик самодостаточен (шаблоны файлов встроены внутрь), поэтому нужна одна команда:

```bash
curl -fsSL https://raw.githubusercontent.com/<USER>/llama-preset-base/main/install.sh | bash
```

С параметрами (аргументы передаются после `--`):

```bash
curl -fsSL https://raw.githubusercontent.com/<USER>/llama-preset-base/main/install.sh \
  | bash -s -- --port 9200 --api-key "sk-my-secret-key"
```

### Параметры

| Флаг | Описание |
|---|---|
| `-p, --port PORT` | порт сервера (по умолчанию: `9199`) |
| `--api-key KEY` | API-ключ сервера (по умолчанию: генерируется случайно в формате `sk-…`) |
| `-f, --force` | перезаписать существующие файлы без резервной копии |
| `--skip-files` | не создавать лаунчер и пресет |
| `--skip-llama-cpp` | не проверять наличие llama.cpp в `PATH` |
| `--launcher PATH` | куда записать лаунчер (по умолчанию: `~/.local/bin/llama-qwen`) |
| `--preset PATH` | куда записать пресет (по умолчанию: `~/.config/llama.cpp/models.ini`) |
| `-h, --help` | справка |

Скрипт неинтерактивен — безопасен для `curl | bash`. При повторной установке существующие файлы сначала копируются в `*.bak.<timestamp>` (используйте `--force`, чтобы перезаписать молча). API-ключ соответствует общепринятому формату ключей LLM API: префикс `sk-` и 48 случайных алфавитно-цифровых символов.

### Требование: llama.cpp

`llama-server` должен находиться в `PATH`. Этот установщик **никогда не собирает llama.cpp автоматически** — выбор бэкенда зависит от вашего оборудования и остаётся за вами.

1. Откройте официальный репозиторий: <https://github.com/ggml-org/llama.cpp>
2. Следуйте официальной инструкции по сборке: <https://github.com/ggml-org/llama.cpp/blob/master/docs/build.md>
3. Выберите бэкенд под ваше оборудование:

   | Оборудование | Флаг CMake |
   |---|---|
   | NVIDIA GPU (CUDA) | `-DGGML_CUDA=ON` |
   | AMD GPU (ROCm/HIP) | `-DGGML_HIP=ON` |
   | Любой GPU (Vulkan) | `-DGGML_VULKAN=ON` |
   | Intel GPU (SYCL) | `-DGGML_SYCL=ON` |
   | Apple Silicon (Metal) | `-DGGML_METAL=ON` (включён по умолчанию в macOS) |
   | Только CPU | *(без флага)* |

   Пример (CUDA):

   ```bash
   git clone https://github.com/ggml-org/llama.cpp
   cd llama.cpp
   cmake -B build -DGGML_CUDA=ON
   cmake --build build --config Release -j "$(nproc)"
   install -m 0755 build/bin/llama-server ~/.local/bin/
   ```

4. Запустите этот установщик снова (или просто `llama-qwen`), когда `llama-server` появится в `PATH`.

Если сервер не найден, установщик всё равно создаёт лаунчер и пресет и напоминает, где взять llama.cpp.

### Использование

#### 1. Запуск сервера

```bash
llama-qwen
```

Запускается `llama-server` в режиме router:

```
llama-server --models-max 1 --host 0.0.0.0 --port 9199 \
  --api-key "<key>" --models-preset ~/.config/llama.cpp/models.ini
```

При первом запросе к GGUF-модели **она автоматически скачивается с Hugging Face** (несколько десятков ГБ для моделей Q4 27B/35B — убедитесь, что на диске достаточно места).

#### 2. Запросы к API

Имя модели в вызовах API = имя секции в `models.ini`. Список моделей:

```bash
curl -s -H "Authorization: Bearer <API_KEY>" http://localhost:9199/v1/models
```

Пример запроса, совместимого с OpenAI:

```bash
curl -s http://localhost:9199/v1/chat/completions \
  -H "Authorization: Bearer <API_KEY>" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "unsloth/Qwen3.8-27B-MTP-GGUF-64K",
    "messages": [{"role": "user", "content": "Привет!"}]
  }'
```

API-ключ — тот, что вывел установщик (или заданный через `--api-key`). Совместимо с клиентами OpenAI: укажите базовый URL `http://localhost:9199/v1`.

#### Доступные пресеты (по умолчанию)

| Имя модели в API | Модель | Контекст | Особенности |
|---|---|---|---|
| `unsloth/Qwen3.8-27B-MTP-GGUF-64K` | Qwen3.8-27B UD Q4_K_XL | 64K | MTP spec-decoding, reasoning |
| `unsloth/Qwen3.8-27B-MTP-GGUF-64K-noreasoning` | та же | 64K | без reasoning, T=0.7 |
| `unsloth/Qwen3.8-27B-MTP-GGUF-32K` | та же | 32K | MTP spec-decoding |
| `unsloth/Qwen3.8-27B-MTP-GGUF-32K-noreasoning` | та же | 32K | без reasoning, T=0.7 |
| `unsloth/Qwen3.6-35B-A3B-MTP-GGUF-64K` | Qwen3.6-35B-A3B UD Q4_K_XL | 64K | MoE, MTP spec-decoding |
| `unsloth/Qwen3.6-35B-A3B-MTP-GGUF-32K` | та же | 32K | MoE, MTP spec-decoding |

Глобальные настройки (`[*]`): `ctx-size=16384` (минимум для router), `parallel=1`, `mlock=1`, `flash-attn=on`, `n-gpu-layers=-1` (весь граф на GPU).

### Кастомизация

**Смена моделей/параметров** — отредактируйте `~/.config/llama.cpp/models.ini`.
Каждая секция `[model_name]` — независимая модель; ключи соответствуют аргументам `llama-server` (без `--`). Модели загружаются одним ключом `hf`, который принимает полную ссылку Hugging Face `"<user>/<model>[:QUANT]"` — например `hf = unsloth/Qwen3.8-27B-GGUF:Q4_K_XL`. Тег квантизации нечувствителен к регистру и по умолчанию равен `Q4_K_M`. Документация формата: [INI-пресеты llama.cpp](https://github.com/ggml-org/llama.cpp/blob/master/docs/preset.md). После изменений перезапустите `llama-qwen`.

**Смена порта/API-ключа** — отредактируйте `~/.local/bin/llama-qwen` напрямую или переустановите:
`… | bash -s -- --port … --api-key …`

### Удаление

```bash
rm -f  ~/.local/bin/llama-qwen
rm -rf ~/.config/llama.cpp
# если вы сами устанавливали llama.cpp и хотите его удалить:
rm -f  ~/.local/bin/llama-cli ~/.local/bin/llama-server
```

### Диагностика

| Симптом | Решение |
|---|---|
| `llama-server: command not found` при запуске `llama-qwen` | Установите llama.cpp (см. [Требование](#требование-llamacpp)); добавьте каталог бинарников в `PATH`, например `export PATH="$HOME/.local/bin:$PATH"` в `~/.bashrc` |
| `Address already in use` | Порт занят: `ss -tlnp \| grep 9199`; измените порт в `llama-qwen` |
| Долгий первый запуск | Первичная загрузка GGUF с Hugging Face; следите через `df -h` |
| Не хватает VRAM | Уменьшите `ctx-size` в `models.ini` или выгружайте меньше слоёв; проверьте, что сборка llama.cpp включает нужный GPU-бэкенд |
| Неверный GPU-бэкенд | Пересоберите llama.cpp с флагом под ваше оборудование (CUDA/Vulkan/ROCm/…) |
| Установщик перезаписал файлы | Старые версии сохранены рядом как `*.bak.<timestamp>` |

---

<a id="中文"></a>

## 中文

本地 LLM 服务器安装器，内置 Qwen 模型预设。

它会完成三件事：

- **llama.cpp 检查** —— 检查 `PATH` 中是否存在 `llama-cli` / `llama-server`。**脚本不会编译或安装 llama.cpp。** 如果未找到服务器，它会输出官方仓库链接，并建议你根据自己的硬件（CUDA、Vulkan、ROCm、SYCL、Metal、CPU……）自行编译。参见[前置条件：llama.cpp](#前置条件llamacpp)。
- **`~/.local/bin/llama-qwen`** —— 启动器：以 router 模式启动 `llama-server`，带上预设、端口和 API 密钥。
- **`~/.config/llama.cpp/models.ini`** —— 模型预设（INI），用于 llama-server 的 router 模式：Qwen3.8-27B / Qwen3.6-35B-A3B，支持 MTP 投机解码、32K/64K 上下文，以及带/不带 reasoning 的变体。

### 安装

安装器是自包含的（文件模板内嵌其中），只需一条命令：

```bash
curl -fsSL https://raw.githubusercontent.com/<USER>/llama-preset-base/main/install.sh | bash
```

带参数（参数写在 `--` 之后）：

```bash
curl -fsSL https://raw.githubusercontent.com/<USER>/llama-preset-base/main/install.sh \
  | bash -s -- --port 9200 --api-key "sk-my-secret-key"
```

### 选项

| 参数 | 说明 |
|---|---|
| `-p, --port PORT` | 服务器端口（默认：`9199`） |
| `--api-key KEY` | 服务器 API 密钥（默认：随机生成，格式为 `sk-…`） |
| `-f, --force` | 直接覆盖已有文件，不备份 |
| `--skip-files` | 跳过创建启动器和预设 |
| `--skip-llama-cpp` | 跳过对 `PATH` 中 llama.cpp 的检查 |
| `--launcher PATH` | 启动器写入路径（默认：`~/.local/bin/llama-qwen`） |
| `--preset PATH` | 预设写入路径（默认：`~/.config/llama.cpp/models.ini`） |
| `-h, --help` | 帮助信息 |

脚本是非交互式的 —— 可安全用于 `curl | bash`。重新安装时，已有文件会先备份为 `*.bak.<timestamp>`（使用 `--force` 可静默覆盖）。API 密钥采用 LLM API 的通用格式：前缀 `sk-` 加 48 个随机字母数字字符。

### 前置条件：llama.cpp

`llama-server` 必须位于 `PATH` 中。本安装器**绝不会自动编译 llama.cpp** —— 后端的选择取决于你的硬件，由你决定。

1. 打开官方仓库：<https://github.com/ggml-org/llama.cpp>
2. 按官方构建说明操作：<https://github.com/ggml-org/llama.cpp/blob/master/docs/build.md>
3. 选择与你的硬件匹配的后端：

   | 硬件 | CMake 参数 |
   |---|---|
   | NVIDIA GPU (CUDA) | `-DGGML_CUDA=ON` |
   | AMD GPU (ROCm/HIP) | `-DGGML_HIP=ON` |
   | 任意 GPU (Vulkan) | `-DGGML_VULKAN=ON` |
   | Intel GPU (SYCL) | `-DGGML_SYCL=ON` |
   | Apple Silicon (Metal) | `-DGGML_METAL=ON`（macOS 默认启用） |
   | 仅 CPU | *（无需参数）* |

   示例（CUDA）：

   ```bash
   git clone https://github.com/ggml-org/llama.cpp
   cd llama.cpp
   cmake -B build -DGGML_CUDA=ON
   cmake --build build --config Release -j "$(nproc)"
   install -m 0755 build/bin/llama-server ~/.local/bin/
   ```

4. 当 `llama-server` 进入 `PATH` 后，重新运行本安装器（或直接运行 `llama-qwen`）。

如果未找到服务器，安装器仍会创建启动器和预设，并提示你到哪里获取 llama.cpp。

### 使用

#### 1. 启动服务器

```bash
llama-qwen
```

它以 router 模式启动 `llama-server`：

```
llama-server --models-max 1 --host 0.0.0.0 --port 9199 \
  --api-key "<key>" --models-preset ~/.config/llama.cpp/models.ini
```

首次请求某个 GGUF 模型时，**它会自动从 Hugging Face 下载**（Q4 的 27B/35B 模型有几十 GB —— 请确保磁盘空间充足）。

#### 2. API 请求

API 调用中的模型名称 = `models.ini` 中的节名。列出可用模型：

```bash
curl -s -H "Authorization: Bearer <API_KEY>" http://localhost:9199/v1/models
```

OpenAI 兼容请求示例：

```bash
curl -s http://localhost:9199/v1/chat/completions \
  -H "Authorization: Bearer <API_KEY>" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "unsloth/Qwen3.8-27B-MTP-GGUF-64K",
    "messages": [{"role": "user", "content": "你好！"}]
  }'
```

API 密钥是安装器输出的那个（或通过 `--api-key` 指定）。兼容 OpenAI 客户端 —— 只需把 base URL 设为 `http://localhost:9199/v1`。

#### 可用预设（默认）

| API 中的模型名 | 模型 | 上下文 | 特性 |
|---|---|---|---|
| `unsloth/Qwen3.8-27B-MTP-GGUF-64K` | Qwen3.8-27B UD Q4_K_XL | 64K | MTP 投机解码、reasoning |
| `unsloth/Qwen3.8-27B-MTP-GGUF-64K-noreasoning` | 同上 | 64K | 无 reasoning，T=0.7 |
| `unsloth/Qwen3.8-27B-MTP-GGUF-32K` | 同上 | 32K | MTP 投机解码 |
| `unsloth/Qwen3.8-27B-MTP-GGUF-32K-noreasoning` | 同上 | 32K | 无 reasoning，T=0.7 |
| `unsloth/Qwen3.6-35B-A3B-MTP-GGUF-64K` | Qwen3.6-35B-A3B UD Q4_K_XL | 64K | MoE、MTP 投机解码 |
| `unsloth/Qwen3.6-35B-A3B-MTP-GGUF-32K` | 同上 | 32K | MoE、MTP 投机解码 |

全局设置（`[*]`）：`ctx-size=16384`（router 的最小值）、`parallel=1`、`mlock=1`、`flash-attn=on`、`n-gpu-layers=-1`（整个计算图放在 GPU 上）。

### 自定义

**修改模型/参数** —— 编辑 `~/.config/llama.cpp/models.ini`。
每个 `[model_name]` 节都是独立模型；键名对应 `llama-server` 的参数（去掉 `--`）。模型通过单个 `hf` 键获取，其值为完整的 Hugging Face 引用 `"<user>/<model>[:QUANT]"` —— 例如 `hf = unsloth/Qwen3.8-27B-GGUF:Q4_K_XL`。量化标签不区分大小写，默认是 `Q4_K_M`。格式文档：[llama.cpp INI 预设](https://github.com/ggml-org/llama.cpp/blob/master/docs/preset.md)。修改后重启 `llama-qwen`。

**修改端口/API 密钥** —— 直接编辑 `~/.local/bin/llama-qwen`，或用以下方式重装：
`… | bash -s -- --port … --api-key …`

### 卸载

```bash
rm -f  ~/.local/bin/llama-qwen
rm -rf ~/.config/llama.cpp
# 如果你自己安装了 llama.cpp 并想移除：
rm -f  ~/.local/bin/llama-cli ~/.local/bin/llama-server
```

### 故障排查

| 现象 | 解决办法 |
|---|---|
| 运行 `llama-qwen` 时提示 `llama-server: command not found` | 安装 llama.cpp（见[前置条件](#前置条件llamacpp)）；把二进制目录加入 `PATH`，例如在 `~/.bashrc` 中 `export PATH="$HOME/.local/bin:$PATH"` |
| `Address already in use` | 端口被占用：`ss -tlnp \| grep 9199`；修改 `llama-qwen` 中的端口 |
| 首次启动很慢 | 首次从 Hugging Face 下载 GGUF；用 `df -h` 观察磁盘 |
| 显存不足 | 减小 `models.ini` 中的 `ctx-size`，或减少卸载层数；确认你的 llama.cpp 构建启用了正确的 GPU 后端 |
| GPU 后端不对 | 用匹配你硬件的参数重新编译 llama.cpp（CUDA/Vulkan/ROCm/…） |
| 安装器覆盖了文件 | 旧版本已保留为 `*.bak.<timestamp>` |
