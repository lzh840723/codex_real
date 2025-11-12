# AI Interaction Enhancement Framework

This is a shell-based framework designed to solve the problem of limited context tokens in the Codex model. It uses a larger-context model, Gemini, as a "copilot" for Codex, intelligently managing the communication and task allocation between the two. The framework provides the necessary observability and context management tools to orchestrate this complex interaction, effectively extending Codex's capabilities.

### Key Features

*   **Panel Mirroring (`RAW=1`):** Logs the raw terminal output of AI interactions to the `state/.raw/` directory for a complete audit trail.
*   **Event Tracing (`TRACE=1`):** Creates structured JSONL logs in `state/.trace/`, detailing the execution flow, including routing decisions, context size, and results.
*   **Context Snapshots (`TRACE=2`):** Saves the exact context sent to the model into `state/.raw/`, which is invaluable for debugging prompts.
*   **HCML (Compact Communication):** Utilizes a compact format (`hcml.maps.json`, `hcml.rules.txt`) for efficient communication with the model. Features like hash-based caching for rules and aliases significantly reduce token usage in consecutive runs.
*   **Adaptive Slicing:** Intelligently extracts relevant code snippets based on `NEED_LIST` requests from the model, providing more precise context.

### Quick Start

1.  **Set Environment Variables (Recommended):**
    ```bash
    export RAW=1 TRACE=2 PANEL=1
    ```

2.  **Run a Command:**
    ```bash
    # Execute a planning command
    make plan
    ```

3.  **Review the Output:**
    ```bash
    # See a summary of the last run
    make explain

    # List the raw logs and context snapshots
    ls -lt state/.raw/
    ```

---

# AI 交互增强框架 (简体中文)

这是一个基于 Shell 的框架，其核心目标是解决 Codex 模型上下文 Token 不足的问题。它创新地引入了具备更大上下文窗口的 Gemini 模型作为 Codex 的“副驾”，并智能地管理两个模型之间的通信与任务分配。本框架提供了实现这种复杂交互所必需的可观察性和上下文管理工具，从而有效地扩展了 Codex 的能力。

### 主要功能

*   **面板镜像 (`RAW=1`):** 将 AI 交互的原始终端输出完整记录到 `state/.raw/` 目录，用于全面审计。
*   **事件追踪 (`TRACE=1`):** 在 `state/.trace/` 目录中创建结构化的 JSONL 日志，详细说明执行流程，包括路由决策、上下文大小和结果。
*   **上下文快照 (`TRACE=2`):** 将发送给模型的精确上下文保存到 `state/.raw/` 中，这对于调试提示非常有价值。
*   **HCML (紧凑通信):** 使用紧凑格式 (`hcml.maps.json`, `hcml.rules.txt`) 与模型进行高效通信。其基于哈希的规则和别名缓存等功能，能显著减少连续运行中的 Token 使用量。
*   **自适应切片:** 根据模型的 `NEED_LIST` 请求，智能地提取相关代码片段，提供更精确的上下文。

### 快速入门

1.  **设置环境变量 (推荐):**
    ```bash
    export RAW=1 TRACE=2 PANEL=1
    ```

2.  **运行一个命令:**
    ```bash
    # 执行一个计划命令
    make plan
    ```

3.  **查看结果:**
    ```bash
    # 查看上一次运行的摘要
    make explain

    # 列出原始日志和上下文快照
    ls -lt state/.raw/
    ```

---

# AI対話拡張フレームワーク (日本語)

このシェルベースのフレームワークは、Codexモデルのコンテキストトークン不足という問題を解決するために設計されました。より大きなコンテキストウィンドウを持つGeminiモデルをCodexの「コパイロット」として活用し、両モデル間の通信とタスク割り当てをインテリジェントに管理します。このフレームワークは、このような複雑な連携を実現するために不可欠な可観測性（オブザーバビリティ）とコンテキスト管理ツールを提供し、Codexの能力を効果的に拡張します。

### 主な機能

*   **パネルミラーリング (`RAW=1`):** AI対話の生のターミナル出力を `state/.raw/` ディレクトリに記録し、完全な監査証跡を提供します。
*   **イベントトレース (`TRACE=1`):** `state/.trace/` ディレクトリに構造化されたJSONLログを作成し、ルーティング決定、コンテキストサイズ、結果などの実行フローを詳述します。
*   **コンテキストスナップショット (`TRACE=2`):** モデルに送信された正確なコンテキストを `state/.raw/` に保存します。これはプロンプトのデバッグに非常に価値があります。
*   **HCML (コンパクト通信):** コンパクトなフォーマット（`hcml.maps.json`, `hcml.rules.txt`）を利用して、モデルと効率的に通信します。ルールやエイリアスに対するハッシュベースのキャッシングのような機能により、連続実行時のトークン使用量を大幅に削減します。
*   **適応型スライシング:** モデルからの `NEED_LIST` リクエストに基づき、関連するコードスニペットをインテリジェントに抽出し、より正確なコンテキストを提供します。

### クイックスタート

1.  **環境変数を設定する (推奨):**
    ```bash
    export RAW=1 TRACE=2 PANEL=1
    ```

2.  **コマンドを実行する:**
    ```bash
    # 計画コマンドを実行する
    make plan
    ```

3.  **結果を確認する:**
    ```bash
    # 直前の実行概要を確認する
    make explain

    # 生ログとコンテキストスナップショットを一覧表示する
    ls -lt state/.raw/
    ```
