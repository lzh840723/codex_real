#!/bin/bash

# === 变量区 ===
ROOT=$(git rev-parse --show-toplevel)
AI_DIR="$ROOT/ai"
STATE_DIR="$ROOT/state"
PROMPT_DIR="$AI_DIR/prompts"

# === 面板原样镜像 / 上下文快照 / 追踪 (v1.1) ===
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

# === v1.2 新增：配置读取与哈希工具 ===
yaml_get() { # yaml_get key default
  local k="$1" d="${2:-}"; awk -v k="$k" -F': *' '$1==k{print $2; found=1} END{if(!found) print "'"$d"'"}' "$AI_DIR/router.yml" 2>/dev/null
}
SLICE_DEF="$(yaml_get 'margin_default' 15)"
SLICE_MIN="$(yaml_get 'margin_min' 8)"
SLICE_MAX="$(yaml_get 'margin_max' 20)"
FN_SMALL="$(yaml_get 'fn_small_lines' 40)"
FN_LARGE="$(yaml_get 'fn_large_lines' 200)"
JAVA_BUMP="$(yaml_get '.java' 2)"
TS_BUMP="$(yaml_get '.ts' 1)"
PY_BUMP="$(yaml_get '.py' 0)"

short8(){ echo "$1" | cut -c1-8; }
file_sha(){ [ -f "$1" ] && shasum "$1" | awk '{print $1}' || echo "0"; }

RULES_PATH="$PROMPT_DIR/hcml.rules.txt"
MAPS_PATH="$AI_DIR/hcml.maps.json"
ALIASES_PATH="$STATE_DIR/aliases.json" # 假设别名文件路径

RULES_HASH="$(short8 "$(file_sha "$RULES_PATH")")"
MAPS_HASH="$(short8 "$(file_sha "$MAPS_PATH")")"
ALIASES_HASH="$(short8 "$(file_sha "$ALIASES_PATH")")"

# 模拟的缓存函数
CACHE_FILE="$STATE_DIR/.cache.json"
load_cache() { cat "$CACHE_FILE" 2>/dev/null || echo "{}"; }
save_cache() { echo "$1" > "$CACHE_FILE"; }

cache_set_hashes(){
  local json="$(load_cache)"
  json=$(echo "$json" | jq --arg r "$RULES_HASH" --arg m "$MAPS_HASH" --arg a "$ALIASES_HASH" \
         '.rules_hash=$r | .maps_hash=$m | .aliases_hash=$a')
  save_cache "$json"
}
cache_need_rules(){
  local json="$(load_cache)"
  local r=$(echo "$json" | jq -r '.rules_hash//""'); [ "$r" = "$RULES_HASH" ] || return 0; return 1
}
cache_need_maps(){
  local json="$(load_cache)"
  local m=$(echo "$json" | jq -r '.maps_hash//""'); [ "$m" = "$MAPS_HASH" ] || return 0; return 1
}
cache_need_aliases(){
  local json="$(load_cache)"
  local a=$(echo "$json" | jq -r '.aliases_hash//""'); [ "$a" = "$ALIASES_HASH" ] || return 0; return 1
}

emit_header(){
  echo "header:{rules_hash:$RULES_HASH, maps_hash:$MAPS_HASH, aliases_hash:$ALIASES_HASH}"
}

# 原样镜像供应商面板到 .raw/*.log (v1.1, 已修复兼容性)
run_and_panel(){ # 用法: run_and_panel <tag> <cmd...>
  local tag="$1"; shift
  local logfile="$RAW_DIR/${STAMP}_${tag}.log"
  if [ "$RAW" = "1" ]; then
    # 优先使用 stdbuf，因为它在不同系统上对于行缓冲的行为更一致
    if _has stdbuf; then
      stdbuf -oL -eL "$@" 2>&1 | tee "$logfile"
    # 其次尝试 script，但不使用 -f 标志，以兼容 BSD 版本
    elif _has script; then
      script -q "$logfile" "$@"
    # 最后回退到简单的 tee
    else
      "$@" 2>&1 | tee "$logfile"
    fi
  else
    "$@"
  fi
}

# 保存上下文快照（TRACE=2 时）(v1.1)
save_ctx(){ # save_ctx <mode> <file>
  [ "$TRACE" = "2" ] && cp "$2" "$RAW_DIR/${STAMP}_ctx_${1}.snapshot" || true
}

# === v1.2 新增：自适应切片 ===
line_count(){ [ -f "$1" ] && wc -l < "$1" | tr -d ' ' || echo 0; }

fn_range(){ # fn_range <path> <symbol> -> start end
  local path="$1" sym="$2"
  # ctags 需要安装
  [ !_has ctags ] && return 0
  local start end
  start=$(ctags -x --languages=Java,Go,Python,TypeScript,JavaScript "$path" \
           | awk -v s="$sym" '$1==s {print $3}' | head -n1)
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
    .java) bump=$JAVA_BUMP ;;
    .ts)   bump=$TS_BUMP ;;
    .py)   bump=$PY_BUMP ;;
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

needlist_to_slices(){ # stdin: NEED_LIST 文本 -> /tmp/_slices.ctx
  : > /tmp/_slices.ctx
  while read -r line; do
    if [[ "$line" =~ ^(.+)::([A-Za-z0-9_]+)$ ]]; then
      p="${BASH_REMATCH[1]}"; s="${BASH_REMATCH[2]}"
      [ -f "$p" ] && extract_slice "$p" "" "" "$s" >> /tmp/_slices.ctx
    elif [[ "$line" =~ ^(.+)#L([0-9]+)-L([0-9]+)$ ]]; then
      p="${BASH_REMATCH[1]}"; L="${BASH_REMATCH[2]}"; R="${BASH_REMATCH[3]}"
      [ -f "$p" ] && extract_slice "$p" "$L" "$R" "" >> /tmp/_slices.ctx
    fi
  done
}

# === 上下文构建函数 (v1.2 更新) ===
make_aliases() { echo "{}"; } # 模拟
build_hcml(){
  make_aliases > "$ALIASES_PATH"
  ALIASES_HASH="$(short8 "$(file_sha "$ALIASES_PATH")")"
  {
    emit_header
    echo "# HCML v0.3 — see /ai/prompts/hcml.rules.txt"
    echo "t: AUTO"
    echo "g: follow SPEC/PLAN, fix failures"
    if [ "${MEM_MODE:-hybrid}" = "stateless" ] || cache_need_aliases; then
      echo -n "a: "; cat "$ALIASES_PATH" 2>/dev/null || echo "{}"
    else
      echo "a_ref: $ALIASES_HASH"
    fi
    echo "n: [0,1]"
    echo "k: [0,2]"
  }
  cache_set_hashes
}

build_ctx_micro() { echo "Micro context"; }
build_ctx_thin() {
  {
    echo "Thin context for the model."
  } | tee /tmp/_ctx_thin.$$ | cat
  save_ctx thin /tmp/_ctx_thin.$$
  if [ "$TRACE" != "0" ]; then
    CTOK=$(python3 -c 'import sys; print(int(len(sys.stdin.read().encode())/4))' < /tmp/_ctx_thin.$$)
    DF=0
    trace "{\"event\":\"ctx\",\"mode\":\"thin\",\"approx_tokens\":$CTOK,\"diff_files\":$DF}"
  fi
  rm -f /tmp/_ctx_thin.$$
}
build_ctx_full() { echo "Full context"; }

# === 模型调用 (v1.2 更新) ===
call_gemini(){
  local prompt="$1"
  local mode="$2"
  case "$mode" in
    micro) build_ctx_micro > /tmp/ai_ctx.md ;;
    thin)  build_ctx_thin  > /tmp/ai_ctx.md ;;
    full)  build_ctx_full  > /tmp/ai_ctx.md ;;
  esac
  
  if [ "${MEM_MODE:-hybrid}" = "stateless" ] || cache_need_rules; then
    [ -f "$RULES_PATH" ] && cat "$RULES_PATH" >> /tmp/ai_ctx.md
  fi
  if [ "${MEM_MODE:-hybrid}" = "stateless" ] || cache_need_maps; then
    [ -f "$MAPS_PATH" ] && { echo; echo "## MAPS"; cat "$MAPS_PATH"; } >> /tmp/ai_ctx.md
  fi

  panel_note "CTX" "gemini model=$G_MODEL file=/tmp/ai_ctx.md"
  run_and_panel "gemini" echo "Gemini Call: model=$G_MODEL, prompt=$prompt"
}

call_codex(){
  local prompt="$1"
  local mode="$2"
  case "$mode" in
    micro) build_hcml > /tmp/ai_ctx.json ;;
    thin)  { build_hcml; echo; build_ctx_thin; } > /tmp/ai_ctx.json ;;
    full)  { build_hcml; echo; build_ctx_full; } > /tmp/ai_ctx.json ;;
  esac
  panel_note "CTX" "codex ctx=/tmp/ai_ctx.json"
  run_and_panel "codex" echo "Codex Call: prompt=$prompt" \
  || { echo "[warn] Codex failed, fallback to Gemini" >&2; call_gemini "$prompt" "$mode"; }
}

# === 主逻辑 ===
CMD=${1:-default}
shift

trace "{\"event\":\"route\",\"cmd\":\"$CMD\",\"mode\":\"thin\",\"mem\":\"${MEM_MODE:-hybrid}\",\"target\":\"unknown\",\"codex_hint\":\"unknown\"}"
panel_note "CALL" "cmd=$CMD mode=thin mem=${MEM_MODE:-hybrid}"

case "$CMD" in
  plan|patch|spec)
    call_gemini "$PROMPT_DIR/${CMD}.prompt.txt" "thin" > /tmp/model.out
    ;;
  explain)
    LAST=$(ls -t "$TRACE_DIR"/*.jsonl 2>/dev/null | head -n1)
    [ -z "$LAST" ] && { echo "No trace found."; exit 0; }
    echo "Last execution summary: $LAST"
    # jq 需要安装
    if _has jq; then
        echo "---- ROUTE ----";  grep '"event":"route"' "$LAST" | tail -n1 | jq .
        echo "---- CONTEXT ---"; grep '"event":"ctx"' "$LAST" | tail -n1 | jq .
        echo "---- NEED_LIST -"; grep '"event":"need_list"' "$LAST" | tail -n1 | jq -r '.items' | fold -s -w 120
        echo "---- RESULT ----";  grep '"event":"result"' "$LAST" | tail -n1 | jq .
    else
        cat "$LAST"
    fi
    ;;
  *)
    echo "Usage: $0 [plan|patch|spec|explain]"
    ;;
esac

if [ -f /tmp/model.out ]; then
  if grep -q "^NEED_LIST" /tmp/model.out; then
    grep "^NEED_LIST" /tmp/model.out > /tmp/NEED_LIST.txt
    NL_CONTENT=$(cat /tmp/NEED_LIST.txt)
    trace "{\"event\":\"need_list\",\"items\":\"$NL_CONTENT\"}"
    panel_note "NEED_LIST" "$(echo "$NL_CONTENT" | fold -s -w 120)"
    needlist_to_slices < /tmp/NEED_LIST.txt
    cat /tmp/_slices.ctx >> /tmp/ai_ctx.md
    # 再次调用模型
    # call_gemini ...
  fi
  HAS_PATCH=$(grep -qc '^PATCH' /tmp/model.out && echo 1 || echo 0)
  trace "{\"event\":\"result\",\"has_patch\":$HAS_PATCH,\"status\":\"ok\"}"
  panel_note "RESULT" "has_patch=$HAS_PATCH"
fi