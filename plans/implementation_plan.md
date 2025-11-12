# 《README.AI.md》功能实现计划书

## 1. 项目目标

完整实现 `README.AI.md` 设计文档中 v1.1 和 v1.2 版本描述的所有 AI 代理增强功能，以提升 AI 交互的透明度、可追溯性和效率。

## 2. 项目阶段与任务分解

### 第一阶段：v1.1 功能实现

此阶段的目标是实现文档中描述的基础功能，包括面板镜像、事件流和上下文快照。

*   **任务 1.1：搭建基础文件结构**
    *   [ ] 创建 `ai/` 目录及其子目录 `ai/prompts/`。
    *   [ ] 创建 `state/` 目录及其子目录 `state/.raw/` 和 `state/.trace/`。
    *   [ ] 创建核心脚本文件 `ai/ai.sh`。
    *   [ ] 创建 `Makefile` 用于定义快捷命令。
    *   [ ] 创建 Prompt 规则文件 `ai/prompts/hcml.rules.txt`。
    *   [ ] 创建 Prompt 内容文件 `ai/prompts/patch.prompt.txt` 和 `ai/prompts/spec.prompt.txt`。

*   **任务 1.2：实现 `ai.sh` 核心功能 (v1.1)**
    *   [ ] 在 `ai.sh` 中定义环境变量与开关 (`RAW`, `TRACE`, `PANEL`)。
    *   [ ] 实现“面板原样镜像”功能 (`run_and_panel` 函数)。
    *   [ ] 实现“上下文快照”功能 (`save_ctx` 函数)。
    *   [ ] 实现“TRACE 事件流”记录功能 (`trace` 和 `panel_note` 函数)。
    *   [ ] 修改模型调用逻辑 (`call_gemini`, `call_codex`) 以集成 `run_and_panel`。
    *   [ ] 实现 `explain` 子命令，用于回放最近一次执行的摘要。

*   **任务 1.3：更新 Prompt 和 Makefile**
    *   [ ] 在 `patch.prompt.txt` 文件末尾追加 `OBS` 块。
    *   [ ] 在 `spec.prompt.txt` 文件末尾追加 `Design_Notes` 块。
    *   [ ] 在 `Makefile` 中添加 `explain`、`plan`、`test`、`patch` 等目标。

### 第二阶段：v1.2 功能实现 (优化)

此阶段的目标是实现 v1.2 中提出的优化措施，以降低 Token 消耗和提高效率。

*   **任务 2.1：添加新的配置文件**
    *   [ ] 创建 `ai/router.yml` 并添加 `slice` (自适应切片) 和 `maps`/`rules` (版本) 相关配置。
    *   [ ] 创建 `ai/hcml.maps.json` 文件，用于定义 c/k/n 的枚举映射。

*   **任务 2.2：升级 `ai.sh` 脚本 (v1.2)**
    *   [ ] 添加 `yaml_get` 工具函数，用于读取 `router.yml` 配置。
    *   [ ] 实现哈希工具 (`file_sha`, `short8`) 和缓存逻辑 (`cache_*` 函数)，用于实现“哈希头”机制，避免重复发送规则。
    *   [ ] 实现“自适应切片边距”功能 (`adaptive_margin`, `fn_range`, `extract_slice`)，以优化 `NEED_LIST` 的处理。
    *   [ ] 更新 `build_hcml` 和 `call_gemini` 函数，以集成哈希头和条件性发送规则的逻辑。

*   **任务 2.3：更新 HCML 规则**
    *   [ ] 在 `hcml.rules.txt` 中追加关于数字编码和哈希头的说明。

### 第三阶段：集成、测试与验证

*   **任务 3.1：端到端测试**
    *   [ ] 编写一个或多个测试用例来模拟真实使用场景。
    *   [ ] 严格按照 `README.AI.md` 中提供的“一键启动”示例 (`export ... && make ...`) 进行测试。

*   **任务 3.2：功能验证**
    *   [ ] 验证 `state/.raw/` 目录中是否成功生成了面板镜像日志。
    *   [ ] 验证 `state/.trace/` 目录中是否成功生成了结构化的 `jsonl` 事件流。
    *   [ ] 设置 `TRACE=2`，验证是否生成了上下文快照 (`.snapshot` 文件)。
    *   [ ] 执行 `make explain`，验证是否能正确显示最近一次执行的摘要。
    *   [ ] 验证自适应切片和哈希头功能是否按预期工作，并观察 Token 使用量的变化。

## 3. 交付物

1.  一个包含 `ai` 目录、`state` 目录、`Makefile` 和相关配置文件的完整项目结构。
2.  功能完整的 `ai/ai.sh` 脚本。
3.  一份简单的使用说明或更新后的 `README.md`。
