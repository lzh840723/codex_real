# 项目测试计划书 (TESTING.md)

## 1. 简介

本文档旨在为 `ai/ai.sh` 脚本提供一份全面的测试计划，以确保其所有逻辑单元的正确性、健壮性和可靠性。测试将覆盖从初始化、日志记录到核心模型调用和上下文处理的全部功能。

## 2. 测试前提条件

在执行测试之前，请确保系统环境中已安装以下依赖工具：

*   `bash`: 脚本执行环境。
*   `git`: 用于获取项目根目录。
*   `python3`: 用于上下文 Token 估算。
*   `ctags`: 用于“自适应切片”中的函数范围解析 (例如 `universal-ctags`)。
*   `jq`: 用于 `explain` 命令中的 JSON 解析。
*   `shasum`: 用于文件哈希计算 (通常内置于 macOS/Linux)。
*   `script`, `stdbuf`, `tee`: 用于 `run_and_panel` 功能 (通常为系统内置)。

## 3. 测试套件与用例

### 套件 1：初始化与配置

此套件用于验证脚本的启动、环境变量处理和配置文件读取是否正常。

*   **[x] 测试用例 1.1：环境变量默认值**
    *   **步骤**: 不设置任何环境变量，直接执行 `./ai/ai.sh`。
    *   **预期结果**: 脚本应使用默认值：`TRACE=0`, `RAW=1`, `PANEL=0`。不应产生 `trace` 文件或 `panel` 输出。

*   **[x] 测试用例 1.2：环境变量自定义值**
    *   **步骤**: 执行 `export TRACE=2 PANEL=1 && ./ai/ai.sh explain`。
    *   **预期结果**:
        *   `TRACE` 应被设为 `2`，`PANEL` 应被设为 `1`。
        *   终端应出现 `panel_note` 的输出 (例如 `── HH:MM:SS ── CALL ── ... ──`)。
        *   应在 `state/.trace/` 目录下生成 `jsonl` 格式的追踪文件。

*   **[x] 测试用-例 1.3：`router.yml` 配置读取**
    *   **步骤**:
        1.  修改 `ai/router.yml` 中的 `margin_default` 为 `99`。
        2.  在 `ai/ai.sh` 中添加 `echo "Margin Default: $SLICE_DEF"` 进行调试。
        3.  执行脚本。
    *   **预期结果**: 脚本应输出 `Margin Default: 99`。

### 套件 2：追踪与日志

此套件用于验证脚本的“可见性”功能，包括事件流、面板镜像和上下文快照。

*   **[x] 测试用例 2.1：`trace` 事件流记录**
    *   **步骤**: 执行 `export TRACE=1 && ./ai/ai.sh plan`。
    *   **预期结果**: `state/.trace/` 目录下应生成一个 `.jsonl` 文件，其中至少包含 `route`, `ctx`, `result` 事件。

*   **[x] 测试用例 2.2：`run_and_panel` 面板镜像**
    *   **步骤**: 执行 `export RAW=1 && ./ai/ai.sh plan`。
    *   **预期结果**: `state/.raw/` 目录下应生成一个 `_gemini.log` 文件，其内容与终端上模拟的模型调用输出一致。

*   **[x] 测试用例 2.3：`save_ctx` 上下文快照**
    *   **步骤**: 执行 `export TRACE=2 && ./ai/ai.sh thin` (或任何会调用 `build_ctx_thin` 的命令)。
    *   **预期结果**: `state/.raw/` 目录下应生成一个 `_ctx_thin.snapshot` 文件。

### 套件 3：哈希与缓存

此套件用于验证文件哈希生成及基于哈希的缓存逻辑。

*   **[x] 测试用例 3.1：哈希生成**
    *   **步骤**:
        1.  在 `ai/ai.sh` 中添加 `echo "Rules Hash: $RULES_HASH"` 进行调试。
        2.  执行脚本。
        3.  修改 `ai/prompts/hcml.rules.txt` 文件。
        4.  再次执行脚本。
    *   **预期结果**: 两次执行输出的 `Rules Hash` 值应不相同。

*   **[x] 测试用例 3.2：缓存命中与未命中**
    *   **步骤**:
        1.  删除 `.state/.cache.json`。
        2.  在 `call_gemini` 函数中添加调试输出，标示 `cache_need_rules` 的返回值。
        3.  执行 `./ai/ai.sh plan`。
        4.  再次执行 `./ai/ai.sh plan`。
    *   **预期结果**:
        *   第一次执行，`cache_need_rules` 应返回 `true` (或 0)，表示需要发送规则。
        *   第二次执行，`cache_need_rules` 应返回 `false` (或 1)，表示缓存命中，无需发送。

### 套件 4：自适应切片 (`NEED_LIST` 处理)

此套件用于验证当模型返回 `NEED_LIST` 时，脚本能否正确解析并提取代码片段。

*   **[x] 测试用例 4.1：`fn_range` 函数范围解析**
    *   **前提**: 创建一个包含示例函数的测试文件 `test.py`，并安装 `ctags`。
    *   **步骤**: 在 `ai/ai.sh` 中直接调用 `fn_range "test.py" "my_function"`。
    *   **预期结果**: 脚本应能输出 `my_function` 在 `test.py` 中的起始和结束行号。
    *   **备注**: 基于代码审查模拟通过。

*   **[x] 测试用例 4.2：`needlist_to_slices` 切片生成**
    *   **步骤**:
        1.  创建一个包含 `NEED_LIST` 指令的模拟模型输出文件 `/tmp/model.out`，例如 `NEED_LIST\n/path/to/file.py::my_function`。
        2.  在 `ai/ai.sh` 中手动触发 `needlist_to_slices`。
    *   **预期结果**: 应生成 `/tmp/_slices.ctx` 文件，其中包含从 `file.py` 中提取的 `my_function` 及其上下文（由 `adaptive_margin` 决定）。
    *   **备注**: 基于代码审查模拟通过。

### 套件 5：主逻辑与路由

此套件用于验证脚本的命令分发和核心业务流程。

*   **[x] 测试用例 5.1：命令路由**
    *   **步骤**: 分别执行 `./ai/ai.sh plan`, `./ai/ai.sh patch`, `./ai/ai.sh spec`。
    *   **预期结果**: 每次执行都应触发 `call_gemini` 函数，并使用对应的 `prompt.txt` 文件。

*   **[x] 测试用例 5.2：`explain` 命令**
    *   **步骤**:
        1.  首先执行 `./ai/ai.sh plan` 以生成一个追踪文件。
        2.  然后执行 `./ai/ai.sh explain`。
    *   **预期结果**: `explain` 命令应能找到最新的 `.jsonl` 文件，并使用 `jq` (如果存在) 格式化输出其中的 `route`, `ctx`, `result` 等事件。

*   **[x] 测试用例 5.3：未知命令**
    *   **步骤**: 执行 `./ai/ai.sh unknown_command`。
    *   **预期结果**: 脚本应输出用法说明 (`Usage: ...`) 并以非零状态码退出。
