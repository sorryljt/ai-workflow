#!/usr/bin/env bash
# viktor-spawn.sh — 在独立进程中运行 review / check
#
# 用法：viktor-spawn.sh <review|check> <changes-dir> [--agent claude|codex] [--checks <file>] [--tier S|M|L] [--main <branch>] [--background]
#   --checks 主会话解析出的本轮运行配置文件（viktor-checks 块 + 运行前提），显式传给子进程；不传则退回读 AGENTS.md 的块
#       viktor-spawn.sh snapshot                    输出当前工作区快照的 tree（含未提交与未跟踪文件，不动索引），供 plan.md 的 base_tree 使用
#       viktor-spawn.sh fingerprint                 输出当前代码指纹（工作区快照 tree，排除 docs/changes 与 docs/knowledge），供 plan.md 的 verified 使用
#       viktor-spawn.sh inputs-digest <changes-dir> 输出验收输入摘要（plan.md 的验收标准节 + 本轮运行配置 + 项目 viktor-checks 块的哈希），供 verified.inputs 使用
#   --agent  主会话所在的工具；子进程只用同一个工具，不做跨工具回退
# 退出码：0 通过（check 含 manual：仅非关键项待人工）；1 有 BLOCKING / 观察到行为失败（修代码）；2 进程失败（超时、非零退出、无产物、run_id 不符、result: error）；
#         3 无可用 CLI；4 check blocked（关键 AC 证据缺失 / 环境不可用，不改业务代码）；3 无可用 CLI（提示词已打印，可手动开新窗口粘贴）
#
# 环境变量：
#   VIKTOR_AGENT          claude | codex（优先级：--agent > VIKTOR_AGENT > 环境变量 CLAUDECODE/CLAUDE_PROJECT_DIR/CODEX_* > 命令存在性）
#   VIKTOR_CLAUDE_ARGS    传给 claude 的额外参数（默认 "--permission-mode acceptEdits"；按 shell 规则解析，含空格的参数请加引号）
#   注意：子进程不继承会话授权，检查命令需由 viktor-init 写入 .claude/settings.json 的 permissions.allow
#   VIKTOR_CODEX_ARGS     传给 codex exec 的额外参数（默认 "--sandbox workspace-write"）
#   VIKTOR_SPAWN_TIMEOUT  秒，默认 480
#   VIKTOR_WORKFLOW_DIR   工作流仓库目录（默认取本脚本所在仓库），用于定位 prompts/
set -uo pipefail

ROLE="${1:-}"; DIR="${2:-}"
# 工作区快照：复制真实索引到临时文件（保留跟踪关系与 intent-to-add），再 add -A 更新内容，write-tree。
# 不动真实索引、不产生 commit。任一步失败返回非零且不输出，调用方不得采信。
snapshot_tree() {  # snapshot_tree [排除目录...]；排除的目录会从临时索引里显式移除，不只是不更新
  local idx real rc=0 tree
  idx="$(mktemp)" || return 1
  real="$(git rev-parse --git-path index 2>/dev/null)"
  if [[ -f "$real" ]]; then cp "$real" "$idx" || { rm -f "$idx"; return 1; }; else rm -f "$idx"; fi
  tree="$(
    export GIT_INDEX_FILE="$idx"
    [[ -f "$idx" ]] || git read-tree --empty || exit 1
    git add -A -- . || exit 1
    if [[ $# -gt 0 ]]; then git rm -r -q --cached --ignore-unmatch -- "$@" >/dev/null || exit 1; fi
    git write-tree || exit 1
  )"; rc=$?
  rm -f "$idx"
  [[ $rc -eq 0 && -n "$tree" ]] || { echo "快照失败（git add / write-tree 出错）" >&2; return 1; }
  printf '%s\n' "$tree"
}
case "$ROLE" in
  inputs-digest)
    [[ -f "$DIR/plan.md" ]] || { echo "缺少 $DIR/plan.md" >&2; exit 2; }
    section(){ awk -v h="$1" '/^## /{p=(index($0,h)==1)} p' "$DIR/plan.md"; }
    { section "## 验收标准"; section "## 本轮运行配置"
      [[ -f AGENTS.md ]] && sed -n '/^[[:space:]]*```viktor-checks[[:space:]]*$/,/^[[:space:]]*```[[:space:]]*$/p' AGENTS.md; } | tr -d '\r' | shasum | cut -c1-12
    exit 0;;
  snapshot)    snapshot_tree ; exit $?;;
  fingerprint) t="$(snapshot_tree docs/changes docs/knowledge)" || exit 1; printf '%s\n' "${t:0:12}"; exit 0;;
esac
shift 2 2>/dev/null || true
TIER=""; MAIN=""; BG=0; AGENT_ARG=""; CHECKS_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent) AGENT_ARG="$2"; shift 2;;
    --checks) CHECKS_FILE="$2"; shift 2;;
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
# 审查基线：优先 plan.md 的 base_tree（需求开始时的工作区快照），其次 base_sha，最后与主干的 merge-base
BASE=""
if [[ -f "$DIR/plan.md" ]]; then
  BASE="$(sed -n '1,/^---$/{s/^base_tree:[[:space:]]*//p;}' "$DIR/plan.md" | head -1 | sed 's/[[:space:]]*#.*//' | tr -d '\r')"
  [[ -z "$BASE" ]] && BASE="$(sed -n '1,/^---$/{s/^base_sha:[[:space:]]*//p;}' "$DIR/plan.md" | head -1 | sed 's/[[:space:]]*#.*//' | tr -d '\r')"
fi
if [[ -z "$BASE" ]] || ! git cat-file -e "$BASE" 2>/dev/null; then
  # 事后发起的审查没有历史快照：一律审"分支相对主干的全部变化"（git diff <merge-base> 同时含分支提交与工作区改动；在主干上就是 HEAD）。
  # 绝不用当前状态补拍起点，也不靠工作区脏不脏判断——创建 plan.md 本身就会让它变脏。
  BASE="$(git merge-base HEAD "$MAIN" 2>/dev/null || git rev-parse HEAD 2>/dev/null || echo HEAD)"
fi
# 上一轮审查时的快照（复审只审此后的变化）
PREV_TREE="无"; [[ "$ROLE" == review && -f "$DIR/.review.tree" ]] && PREV_TREE="$(cat "$DIR/.review.tree")"
# 未跟踪文件用 intent-to-add 纳入 diff（不改变提交内容）
git ls-files --others --exclude-standard -z 2>/dev/null | xargs -0 -r git add -N -- 2>/dev/null || true

# 本轮运行配置：--checks 文件优先；否则读 AGENTS.md 的 viktor-checks 块 + "运行前提"节
if [[ -n "$CHECKS_FILE" ]]; then
  [[ -f "$CHECKS_FILE" ]] || { echo "--checks 文件不存在：${CHECKS_FILE}" >&2; exit 2; }
  CHECKS="$(cat "$CHECKS_FILE")"
elif [[ -f AGENTS.md ]]; then
  CHECKS="$(sed -n '/^[[:space:]]*```viktor-checks[[:space:]]*$/,/^[[:space:]]*```[[:space:]]*$/p' AGENTS.md | tr -d '\r')"
  PRE="$(sed -n '/^### 运行前提/,/^### /p' AGENTS.md | sed '$d' | tr -d '\r')"
  [[ -n "$PRE" ]] && CHECKS="$CHECKS"$'\n'"$PRE"
fi
[[ -n "${CHECKS:-}" ]] || CHECKS="（未找到检查命令：项目未初始化。能从仓库推断就用推断的命令并在报告里注明来源；推断不了写 result: error）"

RUN_ID="$(date +%Y%m%d%H%M%S)-$$"
PROMPT="$(sed -e "s#{{RUN_ID}}#$RUN_ID#g" -e "s#{{PREV_TREE}}#$PREV_TREE#g" -e "s#{{CHANGES_DIR}}#$DIR#g" -e "s#{{TIER}}#$TIER#g" -e "s#{{DIFF_BASE}}#$BASE#g" -e "s#{{MAIN_BRANCH}}#$MAIN#g" -e "s#{{WORKFLOW_DIR}}#$WF#g" "$PROMPT_TPL")"
PROMPT="${PROMPT//\{\{CHECKS\}\}/$CHECKS}"
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
RES="$DIR/.$ROLE.resources"; : > "$RES"
export VIKTOR_RUN_ID="$RUN_ID" VIKTOR_RESOURCES="$RES"

kill_tree() {  # 递归终止进程树（无 setsid 的可移植做法）
  local p="$1" c; for c in $(pgrep -P "$p" 2>/dev/null); do kill_tree "$c"; done
  kill "$p" 2>/dev/null; sleep 0.2; kill -9 "$p" 2>/dev/null
}
run_with_timeout() {  # 可移植的超时（macOS 无 timeout / setsid）；有 perl 时把子进程放进独立进程组
  local pid waited=0 pg=0
  if command -v perl >/dev/null 2>&1; then
    perl -e 'setpgrp(0,0); exec @ARGV or die' -- "${CMD[@]}" >"$LOG" 2>&1 & pid=$!; pg=1
  else
    "${CMD[@]}" >"$LOG" 2>&1 & pid=$!
  fi
  while kill -0 "$pid" 2>/dev/null; do
    sleep 1; waited=$((waited + 1))
    if [[ $waited -ge $TIMEOUT ]]; then
      if [[ $pg -eq 1 ]]; then kill -- "-$pid" 2>/dev/null; sleep 1; kill -9 -- "-$pid" 2>/dev/null; else kill_tree "$pid"; fi
      echo "TIMEOUT" >>"$LOG"; return 124
    fi
  done
  wait "$pid"
}
cleanup_resources() {  # 只清理本轮创建且带 run_id 的资源：container:<name> / dir:<path> / pid:<n>；其余只报告
  [[ -s "$RES" ]] || return 0
  local line kind id left=""
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    kind="${line%%:*}"; id="${line#*:}"
    if [[ "$id" != *"$RUN_ID"* ]]; then left+="  未处理（不含本轮 run_id）：$line"$'\n'; continue; fi
    case "$kind" in
      container) command -v docker >/dev/null 2>&1 && docker rm -f "$id" >/dev/null 2>&1 || left+="  容器未清理：$id"$'\n';;
      dir)       [[ -d "$id" ]] && rm -rf -- "$id" || true;;
      pid)       kill_tree "$id";;
      *)         left+="  未知类型：$line"$'\n';;
    esac
  done < "$RES"
  [[ -n "$left" ]] && { echo "资源清理残留："; printf '%s' "$left"; } >&2
  return 0
}
verify() {  # verify <进程退出码>
  local rc="$1"
  [[ -f "$OUT" ]] || { echo "${ROLE} 进程结束但未产出 ${OUT}（日志：${LOG}）" >&2; return 2; }
  local rid; rid="$(sed -n '1,/^---$/{s/^run_id:[[:space:]]*//p;}' "$OUT" | head -1 | sed 's/[[:space:]]*#.*//; s/[[:space:]]*$//' | tr -d '\r"')"
  [[ "$rid" == "$RUN_ID" ]] || { echo "${OUT} 不属于本轮（run_id=${rid:-无}，期望 ${RUN_ID}），日志：${LOG}" >&2; return 2; }
  local res; res="$(sed -n '1,/^---$/{s/^result:[[:space:]]*\([a-z]*\).*/\1/p;}' "$OUT" | head -1)"
  if [[ "$rc" -ne 0 && "$res" != error ]]; then echo "${ROLE} 进程异常退出（rc=${rc}），报告不采信，日志：${LOG}" >&2; return 2; fi
  case "$ROLE:$res" in
    review:pass|check:pass) echo "${ROLE} 通过：${OUT}"; return 0;;
    check:manual) echo "${ROLE} 通过，有待人工项：${OUT}"; return 0;;
    review:blocked|check:failed) echo "${ROLE} 有问题：${OUT}"; return 1;;
    check:blocked) echo "${ROLE} 阻塞：关键 AC 证据缺失或环境不可用，见 ${OUT}（不改业务代码）" >&2; return 4;;
    *:error) echo "${ROLE} 无法执行（见 ${OUT} 的说明，通常是检查命令未放行）" >&2; return 2;;
    *) echo "${OUT} 的 result 字段无法识别（${res}）" >&2; return 2;;
  esac
}

if [[ $BG -eq 1 ]]; then
  ( run_with_timeout; rc=$?; cleanup_resources; if [[ $rc -eq 124 ]]; then echo 2 > "$DIR/.$ROLE.done"; else verify "$rc" >/dev/null 2>&1; echo "$?" > "$DIR/.$ROLE.done"; fi ) &
  echo "已在后台启动 ${ROLE}（${AGENT}），完成后 $DIR/.$ROLE.done 内为退出码"; exit 0
fi

run_with_timeout; rc=$?
cleanup_resources
if [[ $rc -eq 124 ]]; then echo "${ROLE} 超时（${TIMEOUT}s），日志：${LOG}" >&2; exit 2; fi
verify "$rc"; vrc=$?
if [[ "$ROLE" == review && $vrc -le 1 ]]; then t="$(snapshot_tree)" && printf '%s\n' "$t" > "$DIR/.review.tree" || echo "警告：本轮快照失败，未更新 .review.tree" >&2; fi
exit $vrc
