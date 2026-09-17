#!/usr/bin/env bash
# viktor-gate.sh — Claude Code Stop hook 门禁
# 读取 AGENTS.md 中 ```viktor-checks 块里的 typecheck / lint / test 命令并执行；
# 失败时 exit 2 阻止结束并把输出反馈给 Agent；同一回合连续失败 MAX_BLOCKS 次后放行并向用户提示。
# 只在源码改动的指纹变化时运行；纯文档改动、无改动、非 git 目录直接放行。
set -uo pipefail
MAX_BLOCKS="${VIKTOR_GATE_MAX_BLOCKS:-3}"

START_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
TOP="$(git -C "$START_DIR" rev-parse --show-toplevel 2>/dev/null)" || exit 0
GITDIR="$(git -C "$START_DIR" rev-parse --absolute-git-dir 2>/dev/null)" || exit 0
# AGENTS.md：先找会话目录（monorepo 子包），再找仓库根
if [[ -f "$START_DIR/AGENTS.md" ]]; then WORK="$START_DIR"; elif [[ -f "$TOP/AGENTS.md" ]]; then WORK="$TOP"; else exit 0; fi
cd "$WORK" || exit 0
STATE="$GITDIR/viktor-gate"; mkdir -p "$STATE"

INPUT="$(cat 2>/dev/null || true)"
ACTIVE=0; printf '%s' "$INPUT" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true' && ACTIVE=1

emit_msg() {  # 向用户输出合法 JSON 的 systemMessage
  local msg; msg="$(printf '%s' "$1" | sed "s/$(printf '\033')\[[0-9;]*[A-Za-z]//g" | tr -d '\000-\010\013\014\016-\037' | awk '{ s = s (NR>1?" ":"") $0 } END { print substr(s, 1, 500) }')"
  if command -v jq >/dev/null 2>&1; then jq -cn --arg m "$msg" '{systemMessage:$m}'
  elif command -v node >/dev/null 2>&1; then node -e 'console.log(JSON.stringify({systemMessage:process.argv[1]}))' "$msg"
  elif command -v python3 >/dev/null 2>&1; then python3 -c 'import json,sys;print(json.dumps({"systemMessage":sys.argv[1]},ensure_ascii=False))' "$msg"
  else printf '{"systemMessage":"viktor-gate: %s"}\n' "$(printf '%s' "$msg" | tr -cd 'A-Za-z0-9 :./_-' | cut -c1-300)"; fi
}

# 改动文件（NUL 分隔，路径相对仓库根，排除文档）；所有 git 操作在 $TOP 执行，只有检查命令在 $WORK 执行
G=(git -C "$TOP")
declare -a FILES=()
while IFS= read -r -d '' f; do
  case "$f" in docs/changes/*|docs/knowledge/*|*.md|AGENTS.md|CLAUDE.md) continue;; esac
  FILES+=("$f")
done < <( { "${G[@]}" diff -z --name-only HEAD; "${G[@]}" diff -z --name-only --cached; "${G[@]}" ls-files -z --others --exclude-standard; } 2>/dev/null | tr '\0' '\n' | sort -u | tr '\n' '\0')
[[ ${#FILES[@]} -eq 0 ]] && exit 0
# 缓存键 = 代码指纹 + 执行目录 + viktor-checks 块内容（换子包或改命令都会失效）
checks_blob="$(sed -n '/^[[:space:]]*```viktor-checks[[:space:]]*$/,/^[[:space:]]*```[[:space:]]*$/p' AGENTS.md | tr -d '\r')"
fp="$( { printf '%s\0%s\0' "$WORK" "$checks_blob"; "${G[@]}" diff HEAD -- "${FILES[@]}"; for f in "${FILES[@]}"; do "${G[@]}" ls-files --error-unmatch -- "$f" >/dev/null 2>&1 || { printf '%s\0' "$f"; "${G[@]}" hash-object -- "$TOP/$f" 2>/dev/null; }; done; } | shasum | cut -d' ' -f1 )"
[[ -f "$STATE/passed" && "$(cat "$STATE/passed")" == "$fp" ]] && exit 0

# 读取检查命令：```viktor-checks 块内每行 key: command（允许行首空白）
read_cmd() {
  sed -n '/^[[:space:]]*```viktor-checks[[:space:]]*$/,/^[[:space:]]*```[[:space:]]*$/p' AGENTS.md | tr -d '\r' \
    | sed -n "s/^[[:space:]]*$1:[[:space:]]*//p" | head -1 | sed 's/[[:space:]]*$//'
}

FAILED=""; SUMMARY=""; RAN=0
for kind in typecheck lint test; do
  cmd="$(read_cmd "$kind")"; [[ -z "$cmd" ]] && continue
  RAN=1
  out="$(bash -c "$cmd" 2>&1)"; rc=$?
  if [[ $rc -ne 0 ]]; then
    total=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
    if [[ $total -gt 40 ]]; then
      excerpt="$(printf '%s\n' "$out" | head -20)"$'\n'"... （共 $total 行，省略中间部分）"$'\n'"$(printf '%s\n' "$out" | tail -20)"
    else excerpt="$out"; fi
    FAILED+="[$kind 失败 rc=$rc] $cmd"$'\n'"$excerpt"$'\n\n'
    SUMMARY+="$kind 失败：$(printf '%s\n' "$out" | sed "s/$(printf '\033')\[[0-9;]*[A-Za-z]//g" | grep -m1 -iE 'error|fail|✗|×' || printf '%s\n' "$out" | grep -m1 .)；"
  fi
done

if [[ $RAN -eq 0 ]]; then
  emit_msg "viktor-gate：AGENTS.md 中未找到 viktor-checks 块，门禁未生效，请运行 /viktor-init。"; exit 0
fi
if [[ -z "$FAILED" ]]; then
  printf '%s' "$fp" > "$STATE/passed"; rm -f "$STATE/blocks"; exit 0
fi

# 同一回合内连续拦截计数：stop_hook_active 为 false 表示新回合，从 1 开始
if [[ $ACTIVE -eq 1 && -f "$STATE/blocks" ]]; then count=$(( $(cat "$STATE/blocks") + 1 )); else count=1; fi
printf '%s' "$count" > "$STATE/blocks"
if [[ $count -ge $MAX_BLOCKS ]]; then
  rm -f "$STATE/blocks"
  emit_msg "viktor-gate：检查连续 ${MAX_BLOCKS} 次失败，已放行，请人工处理（失败也可能与本次改动无关）。${SUMMARY}"
  exit 0
fi
printf '%s' "$FAILED" >&2
printf '（第 %s/%s 次拦截）修复后再结束回合。\n' "$count" "$MAX_BLOCKS" >&2
exit 2
