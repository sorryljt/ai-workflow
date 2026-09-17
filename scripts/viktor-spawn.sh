#!/usr/bin/env bash
# viktor-spawn.sh — 在独立进程中运行 review / check
#
# 用法：viktor-spawn.sh <review|check> <changes-dir> [--agent claude|codex] [--tier S|M|L] [--main <branch>] [--background]
#       viktor-spawn.sh fingerprint <changes-dir>   输出当前代码相对 base_sha 的指纹（含未跟踪文件），供 plan.md 的 verified 使用
#   --agent  主会话所在的工具；子进程只用同一个工具，不做跨工具回退
# 退出码：0 通过（check 含"仅待人工"）；1 有 BLOCKING / 失败项；2 进程失败（超时、非零退出、无产物、产物不属于本轮 run_id、result: error）；3 无可用 CLI（提示词已打印，可手动开新窗口粘贴）
#
# 环境变量：
#   VIKTOR_AGENT          claude | codex（优先级：--agent > VIKTOR_AGENT > 环境变量 CLAUDECODE/CLAUDE_PROJECT_DIR/CODEX_* > 命令存在性）
#   VIKTOR_CLAUDE_ARGS    传给 claude 的额外参数（默认 "--permission-mode acceptEdits"；按 shell 规则解析，含空格的参数请加引号）
#   注意：子进程不继承会话授权，检查命令需由 viktor-init 写入 .claude/settings.json 的 permissions.allow
#   VIKTOR_CODEX_ARGS     传给 codex exec 的额外参数（默认 "--sandbox workspace-write"）
#   VIKTOR_SPAWN_TIMEOUT  秒，默认 480
#   VIKTOR_WORKFLOW_DIR   工作流仓库目录（默认取本脚本所在仓库），用于定位 prompts/
set -uo pipefail

ROLE="${1:-}"; DIR="${2:-}"; shift 2 2>/dev/null || true
TIER=""; MAIN=""; BG=0; AGENT_ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent) AGENT_ARG="$2"; shift 2;;
    --tier) TIER="$2"; shift 2;;
    --main) MAIN="$2"; shift 2;;
    --background) BG=1; shift;;
    *) echo "未知参数：$1" >&2; exit 2;;
  esac
done
if [[ "$ROLE" == fingerprint ]]; then
  [[ -d "$DIR" ]] || { echo "需求目录不存在：${DIR}" >&2; exit 2; }
  B=""; [[ -f "$DIR/plan.md" ]] && B="$(sed -n '1,/^---$/{s/^base_sha:[[:space:]]*//p;}' "$DIR/plan.md" | head -1 | tr -d '\r')"
  [[ -n "$B" ]] && git cat-file -e "$B^{commit}" 2>/dev/null || B="$(git rev-parse HEAD 2>/dev/null || echo HEAD)"
  { git diff "$B" 2>/dev/null; git ls-files --others --exclude-standard -z 2>/dev/null | while IFS= read -r -d '' f; do printf '%s\0' "$f"; git hash-object -- "$f" 2>/dev/null; done; } | shasum | cut -c1-12
  exit 0
fi
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
# 审查基线：优先 plan.md 的 base_sha（code 开始时记录），否则与主干的 merge-base
BASE=""; [[ -f "$DIR/plan.md" ]] && BASE="$(sed -n '1,/^---$/{s/^base_sha:[[:space:]]*//p;}' "$DIR/plan.md" | head -1 | tr -d '\r')"
[[ -n "$BASE" ]] && git cat-file -e "$BASE^{commit}" 2>/dev/null || BASE="$(git merge-base HEAD "$MAIN" 2>/dev/null || git rev-parse HEAD 2>/dev/null || echo HEAD)"
# 未跟踪文件用 intent-to-add 纳入 diff（不改变提交内容，审查后可 git reset 还原）
git ls-files --others --exclude-standard -z 2>/dev/null | xargs -0 -r git add -N -- 2>/dev/null || true

RUN_ID="$(date +%Y%m%d%H%M%S)-$$"
PROMPT="$(sed -e "s#{{RUN_ID}}#$RUN_ID#g" -e "s#{{CHANGES_DIR}}#$DIR#g" -e "s#{{TIER}}#$TIER#g" -e "s#{{DIFF_BASE}}#$BASE#g" -e "s#{{MAIN_BRANCH}}#$MAIN#g" -e "s#{{WORKFLOW_DIR}}#$WF#g" "$PROMPT_TPL")"
printf '%s\n' "$PROMPT" > "$DIR/.$ROLE.prompt.md"

# 选择 CLI：主会话是谁就派谁，不做跨工具回退
AGENT=""; WHY=""
if [[ -n "$AGENT_ARG" ]]; then AGENT="$AGENT_ARG"; WHY="--agent 参数"
elif [[ -n "${VIKTOR_AGENT:-}" ]]; then AGENT="$VIKTOR_AGENT"; WHY="VIKTOR_AGENT"
elif [[ -n "${CLAUDECODE:-}" || -n "${CLAUDE_PROJECT_DIR:-}" ]]; then AGENT=claude; WHY="检测到 Claude Code 环境变量"
elif env | grep -q '^CODEX_'; then AGENT=codex; WHY="检测到 Codex 环境变量"
elif command -v claude >/dev/null 2>&1; then AGENT=claude; WHY="只找到 claude 命令"
elif command -v codex >/dev/null 2>&1; then AGENT=codex; WHY="只找到 codex 命令"
fi
if [[ -z "$AGENT" ]]; then
  echo "未找到 claude / codex 命令行。请开一个新窗口，把以下文件内容作为第一条消息发送：$DIR/.$ROLE.prompt.md" >&2
  exit 3
fi
if ! command -v "$AGENT" >/dev/null 2>&1; then
  echo "指定的工具 ${AGENT}（${WHY}）不在 PATH 中，不回退到其他工具。手动方式：把 $DIR/.$ROLE.prompt.md 作为新窗口的第一条消息发送" >&2
  exit 3
fi
echo "独立 ${ROLE}：使用 ${AGENT}（${WHY}）"
case "$AGENT" in
  claude) eval "EXTRA=(${VIKTOR_CLAUDE_ARGS:---permission-mode acceptEdits})"; CMD=(claude -p "$PROMPT" "${EXTRA[@]}");;
  codex)  eval "EXTRA=(${VIKTOR_CODEX_ARGS:---sandbox workspace-write})"; CMD=(codex exec "${EXTRA[@]}" "$PROMPT");;
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
verify() {  # verify <进程退出码>
  local rc="$1"
  [[ -f "$OUT" ]] || { echo "${ROLE} 进程结束但未产出 ${OUT}（日志：${LOG}）" >&2; return 2; }
  local rid; rid="$(sed -n '1,/^---$/{s/^run_id:[[:space:]]*//p;}' "$OUT" | head -1 | tr -d '\r')"
  [[ "$rid" == "$RUN_ID" ]] || { echo "${OUT} 不属于本轮（run_id=${rid:-无}，期望 ${RUN_ID}），日志：${LOG}" >&2; return 2; }
  local res; res="$(sed -n '1,/^---$/{s/^result:[[:space:]]*\([a-z]*\).*/\1/p;}' "$OUT" | head -1)"
  if [[ "$rc" -ne 0 && "$res" != error ]]; then echo "${ROLE} 进程异常退出（rc=${rc}），报告不采信，日志：${LOG}" >&2; return 2; fi
  case "$ROLE:$res" in
    review:pass|check:pass) echo "${ROLE} 通过：${OUT}"; return 0;;
    check:manual) echo "${ROLE} 通过，有待人工项：${OUT}"; return 0;;
    review:blocked|check:failed) echo "${ROLE} 有问题：${OUT}"; return 1;;
    *:error) echo "${ROLE} 无法执行（见 ${OUT} 的说明，通常是检查命令未放行）" >&2; return 2;;
    *) echo "${OUT} 的 result 字段无法识别（${res}）" >&2; return 2;;
  esac
}

if [[ $BG -eq 1 ]]; then
  ( run_with_timeout; rc=$?; if [[ $rc -eq 124 ]]; then echo 2 > "$DIR/.$ROLE.done"; else verify "$rc" >/dev/null 2>&1; echo "$?" > "$DIR/.$ROLE.done"; fi ) &
  echo "已在后台启动 ${ROLE}（${AGENT}），完成后 $DIR/.$ROLE.done 内为退出码"; exit 0
fi

run_with_timeout; rc=$?
if [[ $rc -eq 124 ]]; then echo "${ROLE} 超时（${TIMEOUT}s），日志：${LOG}" >&2; exit 2; fi
verify "$rc"
