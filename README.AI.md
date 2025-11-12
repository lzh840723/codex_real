# 设计1 · v1.1（追加“可见思考/面板镜像/脚本思考可见化”）

## 新增能力一览

* **RAW 面板镜像**：把 Codex/Gemini CLI 在终端显示的**原样输出**（队列、状态、报错、进度等）同时写入 `state/.raw/*.log`，与你截图中的面板一致。
* **OBS（理由简述）**：在各模型输出中**强制要求一个短“思考结论块”**（WHY/ASSUMPTIONS/RISKS/NEXT），便于审计而不泄露长链式推理。
* **TRACE 事件流**：结构化记录每轮**路由决策、上下文体积、NEED_LIST、结果摘要**等，便于复盘（保留 v1.0 的 explain）。
* **上下文快照**：可选保存**送入模型的上下文包**（裁剪后的 micro/thin/full 版本），方便逐字对照。

---

## 1) 文件/目录追加

```
/state/.raw/                     # 新：供应商面板原样日志输出目录
/ai/prompts/hcml.rules.txt       # 仍保留（v1.0 已有）
```

---

## 2) 环境变量与开关（默认即可）

* `RAW=1`：开启**面板原样镜像**到 `state/.raw/*.log`
* `TRACE=1`：开启**结构化事件流**（jsonl）
* `PANEL=1`：终端打印简洁小节标题（CALL/CTX/NEED_LIST/RESULT）
* `TRACE=2`：在 `TRACE=1` 基础上，**额外保存上下文快照**（`*_ctx_*.snapshot`）

示例：

```bash
export RAW=1 TRACE=1 PANEL=1
make patch
```

---

## 3) 修改 `/ai/prompts/patch.prompt.txt`（追加 OBS 块）

在文件末尾**追加**（不要覆盖原有内容）：

```
在 VERIFY 之后追加 OBS（≤10行，总≤600字）:
- WHY_BRIEF: 用 2–5 行说明修改的核心理由与关键权衡（避免逐步推理）
- ASSUMPTIONS: 1–3 条假设
- RISKS: 1–2 条潜在风险与缓解
- NEXT: 下一步最小行动
```

## 4) 修改 `/ai/prompts/spec.prompt.txt`（追加 Design_Notes）

在文件末尾**追加**：

```
在文档末尾附 Design_Notes（≤10行）:
- Key Decisions（3–5 条）
- Open Risks（1–2 条）
- Assumptions（1–3 条）
```

---

## 5) 升级 `/ai/ai.sh`（面板镜像 + 上下文快照 + 追踪）

在变量区**加入**以下片段（放在 `ROOT/AI_DIR/STATE_DIR` 定义之后）：

```bash
# === 面板原样镜像 / 上下文快照 / 追踪 ===
RAW_DIR="$STATE_DIR/.raw"; mkdir -p "$RAW_DIR"
TRACE_DIR="$STATE_DIR/.trace"; mkdir -p "$TRACE_DIR"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
TRACE="${TRACE:-0}"   # 0关闭 | 1事件流 | 2事件流+上下文快照
RAW="${RAW:-1}"       # 1启用原样镜像
PANEL="${PANEL:-0}"   # 1启用终端小节标题

trace_file="$TRACE_DIR/${STAMP}_${CMD:-run}.jsonl"
trace(){ [ "$TRACE" != "0" ] && echo "$*" >> "$trace_file"; }
panel_note(){ [ "$PANEL" = "1" ] && printf '\n── %s ── %s ── %s ──\n' "$(date +%H:%M:%S)" "$1" "$2" >&2; }

_has(){ command -v "$1" >/dev/null 2>&1; }
# 原样镜像供应商面板到 .raw/*.log
run_and_panel(){ # 用法: run_and_panel <tag> <cmd...>
  local tag="$1"; shift
  local logfile="$RAW_DIR/${STAMP}_${tag}.log"
  if [ "$RAW" = "1" ]; then
    if _has script; then
      script -q -f "$logfile" "$@" | tee /dev/tty
    elif _has stdbuf; then
      stdbuf -oL -eL "$@" 2>&1 | tee "$logfile"
    else
      "$@" 2>&1 | tee "$logfile"
    fi
  else
    "$@"
  fi
}
# 保存上下文快照（TRACE=2 时）
save_ctx(){ # save_ctx <mode> <file>
  [ "$TRACE" = "2" ] && cp "$2" "$RAW_DIR/${STAMP}_ctx_${1}.snapshot" || true
}
```

### 在“选档”后写一条路由事件（保留你原有 choose_mode）：

```bash
trace "{\"event\":\"route\",\"cmd\":\"$CMD\",\"mode\":\"$MODE\",\"mem\":\"${MEM_MODE:-hybrid}\",\"target\":\"$TARGET\",\"codex_hint\":\"${CODEX_REMAIN_HINT:-unknown}\"}"
panel_note "CALL" "cmd=$CMD mode=$MODE mem=${MEM_MODE:-hybrid}"
```

### 在构建上下文的函数末尾**保存快照并估算体积**

以 `build_ctx_thin` 为例（`micro/full` 同理照搬）：

```bash
build_ctx_thin(){
  {
    # ... 你原有的thin组包内容 ...
  } | tee /tmp/_ctx_thin.$$ | token_guard 1500
  # —— 追加：快照 + 体积估算 + 追踪 ——
  save_ctx thin /tmp/_ctx_thin.$$
  if [ "$TRACE" != "0" ]; then
    CTOK=$(python3 - <<'PY'
import sys; data=open("/tmp/_ctx_thin.$$","rb").read(); print(int(len(data)/4))
PY
)
    DF=$(collect_diff_names | wc -l | tr -d ' ')
    trace "{\"event\":\"ctx\",\"mode\":\"thin\",\"approx_tokens\":$CTOK,\"diff_files\":$DF}"
  fi
  rm -f /tmp/_ctx_thin.$$
}
```

### 替换模型调用为“面板镜像”的形式

把原来的直接调用改为：

```bash
# call_gemini():
case "$mode" in
  micro) build_ctx_micro > /tmp/ai_ctx.md ;;
  thin)  build_ctx_thin  > /tmp/ai_ctx.md ;;
  full)  build_ctx_full  > /tmp/ai_ctx.md ;;
esac
[ -f "$PROMPT_DIR/hcml.rules.txt" ] && cat "$PROMPT_DIR/hcml.rules.txt" >> /tmp/ai_ctx.md || true
panel_note "CTX" "gemini model=$G_MODEL file=/tmp/ai_ctx.md"
run_and_panel "gemini" gemini --model "$G_MODEL" --input-file /tmp/ai_ctx.md --system "$(cat "$prompt")" \
|| run_and_panel "gemini" gemini --model "$G_FALLBACK" --input-file /tmp/ai_ctx.md --system "$(cat "$prompt")"
```

```bash
# call_codex():
case "$mode" in
  micro) build_hcml | token_guard 400  > /tmp/ai_ctx.json ;;
  thin)  { build_hcml; echo; build_ctx_thin; } | token_guard 1500 > /tmp/ai_ctx.json ;;
  full)  { build_hcml; echo; build_ctx_full; } | token_guard 3000 > /tmp/ai_ctx.json ;;
esac
panel_note "CTX" "codex ctx=/tmp/ai_ctx.json"
run_and_panel "codex" codex --non-interactive --system "$(cat "$prompt")" --input-file /tmp/ai_ctx.json \
|| { echo "[warn] Codex限额/失败，回退到 Gemini" >&2; call_gemini "$prompt" "$mode"; }
```

### 结果与 NEED_LIST 的回显与追踪（若你已有解析，只补“记录/回显”）：

```bash
# 模型输出写入临时文件后，追加：
if [ -f /tmp/model.out ]; then
  if grep -q "^NEED_LIST" /tmp/model.out; then
    NL="$(grep -A20 '^NEED_LIST' /tmp/model.out | head -n 20 | tr -d '\n' | sed 's/"/\\"/g')"
    trace "{\"event\":\"need_list\",\"items\":\"$NL\"}"
    panel_note "NEED_LIST" "$(echo "$NL" | fold -s -w 120)"
  fi
  HAS_PATCH=$(grep -qc '^PATCH' /tmp/model.out && echo 1 || echo 0)
  trace "{\"event\":\"result\",\"has_patch\":$HAS_PATCH,\"status\":\"ok\"}"
  panel_note "RESULT" "has_patch=$HAS_PATCH"
fi
```

---

## 6) `Makefile` 追加 explain 目标（若未加）

```makefile
.PHONY: explain
explain: ; @./ai/ai.sh explain
```

在 `ai.sh` 的 `case` 末尾**保留/追加** explain 子命令（v1.0已有；这里复述）：

```bash
  explain)
    LAST=$(ls -t "$STATE_DIR/.trace"/*.jsonl 2>/dev/null | head -n1)
    [ -z "$LAST" ] && { echo "没有找到最近的 trace"; exit 0; }
    echo "最近一次执行摘要：$LAST"
    echo "---- ROUTE ----";  grep '"event":"route"'    "$LAST" | tail -n1 | jq .
    echo "---- CONTEXT ---"; grep '"event":"ctx"'      "$LAST" | tail -n1 | jq .
    echo "---- NEED_LIST -"; grep '"event":"need_list"' "$LAST" | tail -n1 | jq -r '.items' | fold -s -w 120
    echo "---- RESULT ----";  grep '"event":"result"'  "$LAST" | tail -n1 | jq .
    ;;
```

---

## 7) README.AI.md 需新增的“如何查看可见思考”

* **实时面板**（与你截图相同）：开启 `RAW=1`，终端所见即供应商面板；副本在 `state/.raw/*.log`。
* **上下文快照**：`TRACE=2` 时保存 `*_ctx_*.snapshot`，可对照“喂给模型的真实内容”。
* **事件流解释**：`TRACE=1` + `make patch` 后执行 `./ai/ai.sh explain` 查看**路由/上下文体积/NEED_LIST/结果**。
* **理由简述**：补丁输出的 `OBS` 块与 SPEC 的 `Design_Notes`，记录**本轮思考结论**（WHY/假设/风险/下一步）。

---

## 8) 一键启动（示例）

```bash
export RAW=1 TRACE=1 PANEL=1
make plan
make test
make patch
./ai/ai.sh explain
ls -lt state/.raw
```

---

### 你关心的点，明确回答

* **“我们的脚本的‘思考’看得到吗？”**
  能。通过三层：① 供应商面板原样镜像（你截图那种）；② 我们强制的 `OBS/Design_Notes`“思考结论”；③ `TRACE` 事件流（路由/上下文/NEED_LIST/结果）。
* **无会话模式会不会看不到？**
  不会。面板镜像与事件流全部在**本地脚本层**完成；与是否依赖“服务器会话记忆”无关。

# 追加设计

好的。我把你要的三处微优化直接并入「设计1」，形成设计1 · v1.2：
① 枚举压缩（c_map/k_map/n_map）；② 别名表持久化 + 规则/别名哈希头（仅变更时发送）；③ 自适应切片边距（按函数体大小与语言调整 ± 行数）。
下面给出可直接粘贴的新增/修改内容（尽量最小侵入，兼容你现有 v1.1）。

⸻

一、router.yml（追加配置）

把下段追加到 /ai/router.yml 末尾（或合并到相应键）：

slice:
  margin_default: 15
  margin_min: 8
  margin_max: 20
  fn_small_lines: 40      # 函数体 <40 行 → 用较小边距
  fn_large_lines: 200     # 函数体 >200 行 → 用较大边距
  lang_bumps:             # 语言额外加成（可选）
    ".java": 2
    ".ts": 1
    ".py": 0

maps:
  version: 1              # hcml.maps.json 的版本号（用于哈希头）
rules:
  version: 1              # hcml.rules.txt 的版本号（用于哈希头）


⸻

二、枚举表文件（新增）

新增文件：/ai/hcml.maps.json（后续你可按需扩充；数字越稳定，越省 Token）

{
  "c_map": {
    "0": "no_schema",
    "1": "perf_ok",
    "2": "rollback",
    "3": "multi_ok",
    "4": "backward_compat",
    "5": "no_db_write"
  },
  "k_map": {
    "0": "unit_green",
    "1": "it_green",
    "2": "no_changes_in_dao_db",
    "3": "lint_ok",
    "4": "ci_green"
  },
  "n_map": {
    "0": "patch_fn",
    "1": "add_tests",
    "2": "temp_debug_once",
    "3": "update_docs",
    "4": "run_cmds"
  }
}

交接里若写 c:[0,1,2]，在 hcml.rules.txt 里已声明“数字采用该映射”；模型只需按数字理解即可。

⸻

三、hcml.rules.txt（声明“数字可用”与哈希头）

在 /ai/prompts/hcml.rules.txt 追加如下说明（放文件末尾）：

# Encoding rules (compact):
# - c/k/n may use numeric codes per /ai/hcml.maps.json (c_map/k_map/n_map).
# - If a numeric array is given, interpret via the maps; if strings are given, use as-is.
# Header hints:
# - header:{rules_hash:<8>, maps_hash:<8>, aliases_hash:<8>} may appear.
#   If hashes unchanged, do not require resending full rules/aliases.


⸻

四、ai.sh：三处核心改动

直接把以下片段插入/替换到你的 /ai/ai.sh。如遇同名函数，以此为准（它们向后兼容 v1.1）。

1) 读取 router 配置的小工具（放在变量区后）

yaml_get() { # yaml_get key default
  local k="$1" d="${2:-}"; awk -v k="$k" -F': *' '$1==k{print $2; found=1} END{if(!found) print "'"$d"'"}' "$AI_DIR/router.yml" 2>/dev/null
}
SLICE_DEF="$(yaml_get 'margin_default' 15)"
SLICE_MIN="$(yaml_get 'margin_min' 8)"
SLICE_MAX="$(yaml_get 'margin_max' 20)"
FN_SMALL="$(yaml_get 'fn_small_lines' 40)"
FN_LARGE="$(yaml_get 'fn_large_lines' 200)"
JAVA_BUMP="$(awk -F': *' '/\.java/{print $2}' "$AI_DIR/router.yml" 2>/dev/null | tail -n1)"; [ -z "$JAVA_BUMP" ] && JAVA_BUMP=2
TS_BUMP="$(awk -F': *' '/\.ts/{print $2}' "$AI_DIR/router.yml" 2>/dev/null | tail -n1)";   [ -z "$TS_BUMP" ]   && TS_BUMP=1
PY_BUMP="$(awk -F': *' '/\.py/{print $2}' "$AI_DIR/router.yml" 2>/dev/null | tail -n1)";   [ -z "$PY_BUMP" ]   && PY_BUMP=0

2) 哈希工具 + 规则/别名“哈希头”（仅变更时发送）

放到你原来的 sha1() 附近：

short8(){ echo "$1" | cut -c1-8; }
file_sha(){ [ -f "$1" ] && shasum "$1" | awk '{print $1}' || echo "0"; }

RULES_PATH="$PROMPT_DIR/hcml.rules.txt"
MAPS_PATH="$AI_DIR/hcml.maps.json"
ALIASES_PATH="$STATE_DIR/aliases.json"

RULES_HASH="$(short8 "$(file_sha "$RULES_PATH")")"
MAPS_HASH="$(short8 "$(file_sha "$MAPS_PATH")")"
ALIASES_HASH="$(short8 "$(file_sha "$ALIASES_PATH")")"

# 缓存记录这些哈希，决定是否需要再次携带全文
cache_set_hashes(){
  local json="$(load_cache)"
  json=$(jq --arg r "$RULES_HASH" --arg m "$MAPS_HASH" --arg a "$ALIASES_HASH" \
         '.rules_hash=$r | .maps_hash=$m | .aliases_hash=$a' <<<"$json")
  save_cache "$json"
}
cache_need_rules(){
  local json="$(load_cache)"
  local r=$(jq -r '.rules_hash//""' <<<"$json"); [ "$r" = "$RULES_HASH" ] || return 0; return 1
}
cache_need_maps(){
  local json="$(load_cache)"
  local m=$(jq -r '.maps_hash//""' <<<"$json"); [ "$m" = "$MAPS_HASH" ] || return 0; return 1
}
cache_need_aliases(){
  local json="$(load_cache)"
  local a=$(jq -r '.aliases_hash//""' <<<"$json"); [ "$a" = "$ALIASES_HASH" ] || return 0; return 1
}

在每次调用前把“哈希头”写入上下文（示例：你在 build_hcml() 里加）：

emit_header(){
  echo "header:{rules_hash:$RULES_HASH, maps_hash:$MAPS_HASH, aliases_hash:$ALIASES_HASH}"
}

把 build_hcml() 替换为（或在现有基础上微调）：

build_hcml(){ # 紧凑交接，结合 micro/thin/full 的信息 + 哈希头
  make_aliases
  ALIASES_HASH="$(short8 "$(file_sha "$ALIASES_PATH")")"
  {
    emit_header
    echo "# HCML v0.3 — see /ai/prompts/hcml.rules.txt"
    echo "t: AUTO"
    echo "g: follow SPEC/PLAN, fix failures"
    # 别名：stateless 或哈希变更才附带全文，否则只发引用
    if [ "$MEM_MODE" = "stateless" ] || cache_need_aliases; then
      echo -n "a: "; cat "$ALIASES_PATH" 2>/dev/null || echo "{}"
    else
      echo "a_ref: $ALIASES_HASH"
    fi
    # 错误与下一步：此处仍用人类可读短语（可在 encode_* 里转为编号）
    echo "e: {head:\"$(collect_last_log | head -n 1)\", tail:\"$(collect_last_log | tail -n 1)\"}"
    echo "n: [0,1]"   # 默认用 n_map 的 0=patch_fn,1=add_tests
    echo "k: [0,2]"   # 0=unit_green, 2=no_changes_in_dao_db
    echo "u: [\"git stash -u || true\",\"git reset --hard HEAD~1\"]"
  }
  cache_set_hashes
}

在 call_gemini 构建上下文时：
仅在需要时附 hcml.rules.txt & hcml.maps.json，否则只带“哈希头”。在你现有的 call_gemini() 里，把附加规则的那行改为：

# 仅在 stateless 或规则/映射哈希变更时，附带全文规则/映射（减少重复发送）
if [ "$MEM_MODE" = "stateless" ] || cache_need_rules; then
  [ -f "$RULES_PATH" ] && cat "$RULES_PATH" >> /tmp/ai_ctx.md
fi
if [ "$MEM_MODE" = "stateless" ] || cache_need_maps; then
  [ -f "$MAPS_PATH" ] && { echo; echo "## MAPS"; cat "$MAPS_PATH"; } >> /tmp/ai_ctx.md
fi

3) 自适应切片边距（用于 NEED_LIST 解析/补片）

新增以下函数（放在 symbol_to_range() 附近）：

line_count(){ [ -f "$1" ] && wc -l < "$1" | tr -d ' ' || echo 0; }

fn_range(){ # fn_range <path> <symbol> -> start end  (用 ctags 解析)
  local path="$1" sym="$2"
  local start end
  start=$(ctags -x --languages=Java,Go,Python,TypeScript,JavaScript "$path" \
           | awk -v s="$sym" '$1==s {print $3}' | head -n1)
  # 粗略找函数结束：从 start 开始向下找一个空行/'}' 的近似止点（保守）
  if [ -n "$start" ]; then
    end=$(tail -n +$start "$path" | nl -ba -v $start | awk '/^\s*}$|^\s*def |^\s*class |^\s*\w+\s*\(.*\)\s*{/{print $1; exit}' | head -n1)
    [ -z "$end" ] && end=$(line_count "$path")
    echo "$start $end"
  fi
}

adaptive_margin(){ # adaptive_margin <path> <symbol_or_empty> <L> <R>
  local path="$1" sym="$2" L="$3" R="$4" ext="${1##*.}"
  local base="$SLICE_DEF" bump=0 span=0
  case "$ext" in
    java) bump=$JAVA_BUMP ;;
    ts)   bump=$TS_BUMP ;;
    py)   bump=$PY_BUMP ;;
  esac
  if [ -n "$sym" ]; then
    read -r s e <<<"$(fn_range "$path" "$sym")"
    [ -n "$s" ] && [ -n "$e" ] && span=$((e - s + 1))
  elif [ -n "$L" ] && [ -n "$R" ]; then
    span=$((R - L + 1))
  fi
  local m="$base"
  if [ "$span" -gt "$FN_LARGE" ]; then m=$((base + 5))
  elif [ "$span" -lt "$FN_SMALL" ]; then m=$((base - 5))
  fi
  m=$((m + bump))
  [ "$m" -lt "$SLICE_MIN" ] && m="$SLICE_MIN"
  [ "$m" -gt "$SLICE_MAX" ] && m="$SLICE_MAX"
  echo "$m"
}

extract_slice(){ # extract_slice <path> <L> <R> <sym>
  local path="$1" L="$2" R="$3" sym="$4"
  local n=$(adaptive_margin "$path" "$sym" "$L" "$R")
  if [ -n "$sym" ]; then
    read -r s e <<<"$(fn_range "$path" "$sym")"
    [ -z "$s" ] && return 0
    L=$((s - n)); [ "$L" -lt 1 ] && L=1
    R=$((e + n))
  else
    [ -z "$L" ] && L=1
    [ -z "$R" ] && R=$(line_count "$path")
    L=$((L - n)); [ "$L" -lt 1 ] && L=1
    R=$((R + n))
  fi
  echo "## SLICE:$path:$L-$R"
  sed -n "${L},${R}p" "$path"
}

# 解析 NEED_LIST 并生成精准切片文件
needlist_to_slices(){ # stdin: NEED_LIST 文本 -> /tmp/_slices.ctx
  : > /tmp/_slices.ctx
  while read -r line; do
    # 形如 path::symbol 或 path#Lx-Ly
    if [[ "$line" =~ ^(.+)::([A-Za-z0-9_]+)$ ]]; then
      p="${BASH_REMATCH[1]}"; s="${BASH_REMATCH[2]}"
      [ -f "$TARGET/$p" ] && extract_slice "$TARGET/$p" "" "" "$s" >> /tmp/_slices.ctx
    elif [[ "$line" =~ ^(.+)#L([0-9]+)-L([0-9]+)$ ]]; then
      p="${BASH_REMATCH[1]}"; L="${BASH_REMATCH[2]}"; R="${BASH_REMATCH[3]}"
      [ -f "$TARGET/$p" ] && extract_slice "$TARGET/$p" "$L" "$R" "" >> /tmp/_slices.ctx
    fi
  done
}

在你处理 NEED_LIST 的地方，把原来的 “TODO” 改为真正抽片并回补上下文（示例）：

# 假设 NEED 保存到 /tmp/NEED_LIST.txt
needlist_to_slices < /tmp/NEED_LIST.txt
# 将切片拼到上下文后再次调用模型（thin 档）
cat /tmp/_slices.ctx >> /tmp/ai_ctx.md

自适应边距会自动根据函数体大小与语言做 ± 行数调整，减少“切太短再补一轮”。

⸻

五、HCML 里使用数字编码（可选但建议）

当你构造 HCML/Dense-JSON 时（build_hcml() 里），将 c/k/n 改为纯数字数组，例如：

echo "c: [0,1,2,3]"   # no_schema, perf_ok, rollback, multi_ok
echo "k: [0,2]"       # unit_green, no_changes_in_dao_db
echo "n: [0,1]"       # patch_fn, add_tests

模型根据 /ai/hcml.maps.json 自行解释，无需你再写英文短语（更省 token）。

⸻

六、使用与验证

export RAW=1 TRACE=1 PANEL=1 MEM_MODE=hybrid
make plan
make patch           # 首轮可能触发 NEED_LIST → 自动抽片 → 复投
./ai/ai.sh explain   # 看本轮路由/上下文/NEED_LIST/结果
ls -lt state/.raw    # 查看原样面板与 ctx 快照（若 TRACE=2）

期望收益
	•	枚举压缩：c/k/n 三类字段 Token 再降约 5–8%。
	•	哈希头：rules/aliases/maps 不变时不重发（连续回合再降 5–10%）。
	•	自适应切片：降低“补片重试”的概率（回合数下降，尾部 Token 降 5–15%）。

⸻

需要我把以上变更整理成一个 统一的 diff 补丁（patch 文件） 吗？我可以按你当前的文件路径直接给出 git apply 可打的版本。