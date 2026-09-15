#!/usr/bin/env bash
# viktor-spawn.sh — 在独立进程中运行 review / check
#
# 用法：viktor-spawn.sh <review|check> <changes-dir> [--tier S|M|L] [--main <branch>] [--background]
# 退出码：0 通过（check 含"仅待人工"）；1 有 BLOCKING / 失败项；2 进程失败（超时、崩溃、无产物）；3 无可用 CLI（提示词已打印，可手动开新窗口粘贴）
#
# 环境变量：
#   VIKTOR_AGENT          claude | codex（默认自动检测，先 claude 后 codex）
#   VIKTOR_CLAUDE_ARGS    传给 claude 的额外参数（默认 "--permission-mode acceptEdits"）
#   VIKTOR_CODEX_ARGS     传给 codex exec 的额外参数（默认 "--sandbox workspace-write"）
#   VIKTOR_SPAWN_TIMEOUT  秒，默认 480
#   VIKTOR_WORKFLOW_DIR   工作流仓库目录（默认取本脚本所在仓库），用于定位 prompts/
set -uo pipefail

ROLE="${1:-}"; DIR="${2:-}"; shift 2 2>/dev/null || true
TIER=""; MAIN=""; BG=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tier) TIER="$2"; shift 2;;
    --main) MAIN="$2"; shift 2;;
    --background) BG=1; shift;;
    *) echo "未知参数：$1" >&2; exit 2;;
  esac
done
[[ "$ROLE" == "review" || "$ROLE" == "check" ]] || { echo "Usage: $0 <review|check> <changes-dir> [--tier S|M|L] [--main branch] [--background]" >&2; exit 2; }
[[ -d "$DIR" ]] || { echo "需求目录不存在：$DIR" >&2; exit 2; }

WF="${VIKTOR_WORKFLOW_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PROMPT_TPL="$WF/prompts/$ROLE.md"
[[ -f "$PROMPT_TPL" ]] || { echo "缺少提示词文件：$PROMPT_TPL" >&2; exit 2; }
TIMEOUT="${VIKTOR_SPAWN_TIMEOUT:-480}"
OUT="$DIR/$ROLE.md"

# 档位、主干分支、diff 基线
[[ -z "$TIER" && -f "$DIR/plan.md" ]] && TIER="$(sed -n 's/^tier:[[:space:]]*\([SML]\).*/\1/p' "$DIR/plan.md" | head -1)"
TIER="${TIER:-S}"
[[ -z "$MAIN" && -f AGENTS.md ]] && MAIN="$(sed -n 's/^- 主干分支：[[:space:]]*//p' AGENTS.md | head -1 | tr -d '\r')"
MAIN="${MAIN:-main}"
BASE="$(git merge-base HEAD "$MAIN" 2>/dev/null || git rev-parse HEAD 2>/dev/null || echo HEAD)"

PROMPT="$(sed -e "s#{{CHANGES_DIR}}#$DIR#g" -e "s#{{TIER}}#$TIER#g" -e "s#{{DIFF_BASE}}#$BASE#g" -e "s#{{MAIN_BRANCH}}#$MAIN#g" "$PROMPT_TPL")"
printf '%s\n' "$PROMPT" > "$DIR/.$ROLE.prompt.md"

# 选择 CLI
AGENT="${VIKTOR_AGENT:-}"
if [[ -z "$AGENT" ]]; then
  if command -v claude >/dev/null 2>&1; then AGENT=claude; elif command -v codex >/dev/null 2>&1; then AGENT=codex; fi
fi
if [[ -z "$AGENT" ]] || ! command -v "$AGENT" >/dev/null 2>&1; then
  echo "未找到 claude / codex 命令行。请开一个新窗口，把以下文件内容作为第一条消息发送：$DIR/.$ROLE.prompt.md" >&2
  exit 3
fi
case "$AGENT" in
  claude) read -r -a EXTRA <<<"${VIKTOR_CLAUDE_ARGS:---permission-mode acceptEdits}"; CMD=(claude -p "$PROMPT" "${EXTRA[@]}");;
  codex)  read -r -a EXTRA <<<"${VIKTOR_CODEX_ARGS:---sandbox workspace-write}"; CMD=(codex exec "${EXTRA[@]}" "$PROMPT");;
  *) echo "不支持的 VIKTOR_AGENT：$AGENT" >&2; exit 2;;
esac

START=$(date +%s)
LOG="$DIR/.$ROLE.log"
run_with_timeout() {  # 可移植的超时（macOS 无 timeout 命令）
  "${CMD[@]}" >"$LOG" 2>&1 &
  local pid=$! waited=0
  while kill -0 "$pid" 2>/dev/null; do
    sleep 1; waited=$((waited + 1))
    if [[ $waited -ge $TIMEOUT ]]; then kill "$pid" 2>/dev/null; sleep 1; kill -9 "$pid" 2>/dev/null; echo "TIMEOUT" >>"$LOG"; return 124; fi
  done
  wait "$pid"
}
verify() {
  [[ -f "$OUT" ]] || { echo "$ROLE 进程结束但未产出 $OUT（日志：$LOG）" >&2; return 2; }
  local mtime; mtime=$(stat -c %Y "$OUT" 2>/dev/null || stat -f %m "$OUT" 2>/dev/null || echo 0)
  [[ $mtime -ge $START ]] || { echo "$OUT 未被本次更新（日志：$LOG）" >&2; return 2; }
  local res; res="$(sed -n '1,/^---$/{s/^result:[[:space:]]*\([a-z]*\).*/\1/p;}' "$OUT" | head -1)"
  case "$ROLE:$res" in
    review:pass|check:pass) echo "$ROLE 通过：$OUT"; return 0;;
    check:manual) echo "$ROLE 通过，有待人工项：$OUT"; return 0;;
    review:blocked|check:failed) echo "$ROLE 有问题：$OUT"; return 1;;
    *) echo "$OUT 的 result 字段无法识别（$res）" >&2; return 2;;
  esac
}

if [[ $BG -eq 1 ]]; then
  ( run_with_timeout; rc=$?; verify >/dev/null 2>&1; echo "$?" > "$DIR/.$ROLE.done" ) &
  echo "已在后台启动 $ROLE（$AGENT），完成后 $DIR/.$ROLE.done 内为退出码"; exit 0
fi

run_with_timeout; rc=$?
if [[ $rc -eq 124 ]]; then echo "$ROLE 超时（${TIMEOUT}s），日志：$LOG" >&2; exit 2; fi
verify
