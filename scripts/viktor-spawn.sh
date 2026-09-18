#!/usr/bin/env bash
# viktor-spawn.sh — 在独立进程中运行 review / check
#
# 用法：viktor-spawn.sh <review|check> <changes-dir> [--agent claude|codex] [--checks <file>] [--tier S|M|L] [--main <branch>] [--background]
#   --checks 主会话解析出的本轮运行配置文件（viktor-checks 块 + 运行前提），显式传给子进程；不传则读 AGENTS.md 的块与运行前提；两者都没有则退出 2，子进程不自行探测
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
#                         未指定 --output-format 时追加 "--output-format stream-json --verbose"，.<role>.log 保留完整事件流
#   注意：子进程不继承会话授权，检查命令需由 viktor-init 写入 .claude/settings.json 的 permissions.allow
#   VIKTOR_CODEX_ARGS     传给 codex exec 的额外参数（默认 "--sandbox workspace-write"；项目需要其他参数时在 AGENTS.md 项目信息节写 `- 子进程参数：codex <参数>`，
#                         例如 JVM 项目 `- 子进程参数：codex --sandbox workspace-write -c sandbox_workspace_write.network_access=true`；没写 --sandbox 时补上默认沙箱）
#   两者含 --dangerously-*（跳过权限 / 沙箱）/ bypassPermissions / danger-full-access 时拒绝派单（退出码 2）
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
    [[ -n "$(section "## 验收标准" | grep -v '^## ' | grep -v '^[[:space:]]*$')" ]] || { echo "$DIR/plan.md 没有 '## 验收标准' 节，无法生成验收输入摘要" >&2; exit 2; }
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
  # 运行前提：`### 运行前提` 节（到下一个标题或文件末尾）或 `- 运行前提：…` 一行，两种写法都收
  PRE="$( { awk '/^#/{p=0} /^###[[:space:]]*运行前提/{p=1} p' AGENTS.md; grep -E '^[[:space:]]*-[[:space:]]*运行前提[：:]' AGENTS.md; } | tr -d '\r' | awk 'NF' | awk '!seen[$0]++')"
  [[ -n "$PRE" ]] && CHECKS="$CHECKS"$'\n'"$PRE"
fi
# 子进程不自行探测命令：配置里至少要有一条已支持的键（typecheck/lint/test/verify/e2e/dev）且值非空，否则不派单，由主会话预检后以 --checks 传入
has_cmd="$(printf '%s\n' "${CHECKS:-}" | sed -n '/^[[:space:]]*```viktor-checks[[:space:]]*$/,/^[[:space:]]*```[[:space:]]*$/p' | grep -E '^[[:space:]]*(typecheck|lint|test|verify|e2e|dev)[[:space:]]*:[[:space:]]*[^[:space:]#]' | head -1)"
[[ -n "$has_cmd" ]] || { echo "未找到可用的检查命令：需要 viktor-checks 块里至少一条非空的 typecheck/lint/test/verify/e2e/dev。AGENTS.md 没有就由主会话预检（写入 plan.md 的 '## 本轮运行配置'）后以 --checks 传入，或运行 /viktor-init。" >&2; exit 2; }

RUN_ID="$(date +%Y%m%d%H%M%S)-$$"
# 提示词里的工作流目录用相对项目根目录的路径，和 viktor-init 写的放行规则 `Bash(bash .workflow/<…>/scripts/knowledge.sh:*)` 一致；
# 工作流不在项目目录下时退回 python3 的 relpath，再不行才用绝对路径（此时放行规则匹配不上，只提示）
WF_REL=""
case "$WF" in "$PWD"/*) WF_REL="${WF#"$PWD"/}";; esac
[[ -z "$WF_REL" ]] && WF_REL="$(python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1]))' "$WF" 2>/dev/null)"
if [[ -z "$WF_REL" ]]; then WF_REL="$WF"; echo "警告：无法算出工作流目录的相对路径，提示词里用绝对路径 ${WF}；knowledge.sh 的放行规则需按这个路径补一条" >&2; fi
PROMPT="$(sed -e "s#{{RUN_ID}}#$RUN_ID#g" -e "s#{{PREV_TREE}}#$PREV_TREE#g" -e "s#{{CHANGES_DIR}}#$DIR#g" -e "s#{{TIER}}#$TIER#g" -e "s#{{DIFF_BASE}}#$BASE#g" -e "s#{{MAIN_BRANCH}}#$MAIN#g" -e "s#{{WORKFLOW_DIR}}#$WF_REL#g" "$PROMPT_TPL")"
PROMPT="${PROMPT//\{\{CHECKS\}\}/$CHECKS}"
# 与审查者使用同一范围；NUL 分隔兼容空格路径，删除测试不能充当回归测试。
if [[ "$ROLE" == review ]]; then
  REVIEW_BASE="$BASE"
  [[ "$PREV_TREE" != 无 ]] && REVIEW_BASE="$PREV_TREE"
  CHANGED_FILES="$(mktemp)" || exit 2
  git diff --name-status -z --no-renames --diff-filter=ACMTD "$REVIEW_BASE" -- . ':!docs/changes' ':!docs/knowledge' > "$CHANGED_FILES" || { rm -f "$CHANGED_FILES"; exit 2; }
  HAS_SOURCE=0; HAS_TEST=0
  while IFS= read -r -d '' status && IFS= read -r -d '' file; do
    # 目录名只能辅助分类，README、快照和 fixture 数据不是可执行测试。
    case "$file" in
      *.java|*.kt|*.kts|*.groovy|*.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs|*.vue|*.svelte|*.py|*.go|*.rs|*.rb|*.php|*.cs|*.c|*.h|*.cpp|*.cc|*.hpp|*.swift|*.scala|*.sh) ;;
      *) continue;;
    esac
    case "$file" in
      */test/*|*/tests/*|test/*|tests/*|*/__tests__/*|__tests__/*|*.test.*|*.spec.*|*Test.java|*Tests.java|*IT.java|*Test.kt|*Tests.kt|*Test.groovy|*Spec.groovy|test_*.py|*/test_*.py|*_test.py|*_test.go|*_spec.rb)
        [[ "$status" != D ]] && HAS_TEST=1;;
      *) HAS_SOURCE=1;;
    esac
  done < "$CHANGED_FILES"
  rm -f "$CHANGED_FILES"
  if [[ "$HAS_SOURCE" -eq 1 && "$HAS_TEST" -eq 0 ]]; then
    PROMPT="$PROMPT"$'\n\n注意：本次 diff 不含测试文件'
  fi
fi
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
# Claude 信任配置不存在或没有 JSON 解析器时跳过；保留日志检测兜底。
if [[ "$AGENT" == claude && -f "$HOME/.claude.json" ]]; then
  trust_rc=0
  if command -v node >/dev/null 2>&1; then
    node -e 'try { const c = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")); process.exit(c.projects?.[process.argv[2]]?.hasTrustDialogAccepted === true ? 0 : 2); } catch (_) { process.exit(2); }' "$HOME/.claude.json" "$(pwd -P)" || trust_rc=$?
  elif command -v python3 >/dev/null 2>&1; then
    python3 - "$HOME/.claude.json" "$(pwd -P)" <<'PYTRUST' || trust_rc=$?
import json, sys
try:
    with open(sys.argv[1]) as f:
        config = json.load(f)
    trusted = config.get("projects", {}).get(sys.argv[2], {}).get("hasTrustDialogAccepted") is True
except (OSError, ValueError, AttributeError):
    trusted = False
sys.exit(0 if trusted else 2)
PYTRUST
  fi
  if [[ $trust_rc -ne 0 ]]; then
    echo '工作区未被 Claude Code 信任：请在项目目录交互式启动一次 claude 并选择信任，然后说「继续」' >&2
    exit 2
  fi
fi
# 子进程参数：环境变量 > AGENTS.md 项目信息节的 `- 子进程参数：codex <参数>`（仅 codex）> 默认
# 这一行来自仓库文件，会经 eval 切分：只允许字母数字和 _ . = : / , @ + - 与空格（不含引号、$、反引号、通配符），按空白切分；没写 --sandbox / -s 时补默认沙箱
PROJ_CODEX_ARGS=""
if [[ -f AGENTS.md ]]; then
  PROJ_CODEX_ARGS="$(sed -n 's/^- 子进程参数：[[:space:]]*codex[[:space:]][[:space:]]*//p' AGENTS.md | head -1 | tr -d '\r' | sed 's/[[:space:]]*$//')"
  if [[ -n "$PROJ_CODEX_ARGS" && ! "$PROJ_CODEX_ARGS" =~ ^[A-Za-z0-9_.=:/,@+\ -]+$ ]]; then
    echo "AGENTS.md 的“子进程参数”只能包含字母、数字、空格和 _ . = : / , @ + -（不支持引号和 shell 语法），实际为：${PROJ_CODEX_ARGS}" >&2; exit 2
  fi
  if [[ -n "$PROJ_CODEX_ARGS" && ! " $PROJ_CODEX_ARGS" =~ [[:space:]](--sandbox|-s)([[:space:]=]|$) ]]; then PROJ_CODEX_ARGS="--sandbox workspace-write $PROJ_CODEX_ARGS"; fi
fi
case "$AGENT" in
  claude) ARGS_SRC="VIKTOR_CLAUDE_ARGS"; ARGS="${VIKTOR_CLAUDE_ARGS:---permission-mode acceptEdits}";;
  codex)  if [[ -n "${VIKTOR_CODEX_ARGS:-}" ]]; then ARGS_SRC="VIKTOR_CODEX_ARGS"; ARGS="$VIKTOR_CODEX_ARGS"
          elif [[ -n "$PROJ_CODEX_ARGS" ]]; then ARGS_SRC="AGENTS.md 子进程参数"; ARGS="$PROJ_CODEX_ARGS"
          else ARGS_SRC="默认参数"; ARGS="--sandbox workspace-write"; fi;;
  *) echo "不支持的 VIKTOR_AGENT：$AGENT" >&2; exit 2;;
esac
# 子进程不得提权：跳过权限检查、全权限沙箱一律拒绝，不派单
case "$ARGS" in
  *danger-full-access*|*--dangerously-*|*dangerously-skip-permissions*|*bypassPermissions*)
    echo "拒绝派单：${ARGS_SRC} 含提权参数（${ARGS}）。子进程只能在项目放行的权限内运行：命令被拦就运行 /viktor-init 补齐放行规则；Codex 需要更宽的沙箱时，在 AGENTS.md 项目信息节写一行 '- 子进程参数：codex <参数>'（JVM 项目：--sandbox workspace-write -c sandbox_workspace_write.network_access=true；danger-full-access 同样拒绝）" >&2
    exit 2;;
esac
echo "独立 ${ROLE}：使用 ${AGENT}（${WHY}）"
case "$AGENT" in
  claude) # 日志保留完整事件流（含被拒的命令），便于排查；verify() 仍只读 .md 报告
          [[ "$ARGS" == *--output-format* ]] || ARGS="$ARGS --output-format stream-json --verbose"
          eval "EXTRA=(${ARGS})"; CMD=(claude -p "$PROMPT" "${EXTRA[@]}");;
  codex)  eval "EXTRA=(${ARGS})"; CMD=(codex exec "${EXTRA[@]}" "$PROMPT");;
esac

START=$(date +%s)
LOG="$DIR/.$ROLE.log"
RES="$DIR/.$ROLE.resources"; : > "$RES"
export VIKTOR_RUN_ID="$RUN_ID" VIKTOR_RESOURCES="$RES"

kill_tree() {  # 递归终止进程树（无 setsid 的可移植做法）
  local p="$1" c; for c in $(pgrep -P "$p" 2>/dev/null); do kill_tree "$c"; done
  kill "$p" 2>/dev/null; sleep 0.2; kill -9 "$p" 2>/dev/null
}
CHILD_PID=""; CHILD_PGID=""; OWN_PG=0
run_with_timeout() {  # 可移植的超时（macOS 无 timeout / setsid）；有 perl 时把子进程放进独立进程组
  local pid waited=0
  if command -v perl >/dev/null 2>&1; then
    perl -e 'setpgrp(0,0); exec @ARGV or die' -- "${CMD[@]}" >"$LOG" 2>&1 & pid=$!; OWN_PG=1
  else
    "${CMD[@]}" >"$LOG" 2>&1 & pid=$!
  fi
  CHILD_PID="$pid"
  # 本轮进程组：setpgrp 后子进程的 pgid 就是它的 pid；ps 报不出这个值（受限环境）就视为不可判定，pid 类资源只报告不杀
  if [[ $OWN_PG -eq 1 && "$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')" == "$pid" ]]; then CHILD_PGID="$pid"; else CHILD_PGID=""; fi
  while kill -0 "$pid" 2>/dev/null; do
    sleep 1; waited=$((waited + 1))
    if [[ $waited -ge $TIMEOUT ]]; then
      if [[ $OWN_PG -eq 1 ]]; then kill -- "-$pid" 2>/dev/null; sleep 1; kill -9 -- "-$pid" 2>/dev/null; else kill_tree "$pid"; fi
      echo "TIMEOUT" >>"$LOG"; return 124
    fi
  done
  wait "$pid"
}
reap_group() {  # 子进程结束后（正常、失败、超时都一样），同一进程组里的残留进程一律终止
  [[ $OWN_PG -eq 1 && -n "$CHILD_PID" ]] || return 0
  kill -- "-$CHILD_PID" 2>/dev/null || return 0
  sleep 0.5; kill -9 -- "-$CHILD_PID" 2>/dev/null || true
}
cleanup_resources() {  # 只清理本轮创建的资源：container:<name> / dir:<path> 要求名字含 run_id；pid:<n> 要求属于本轮子进程的进程组；其余只报告
  [[ -s "$RES" ]] || return 0
  local line kind id left="" pg
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    kind="${line%%:*}"; id="${line#*:}"
    case "$kind" in
      container) [[ "$id" == *"$RUN_ID"* ]] || { left+="  未处理（不含本轮 run_id）：$line"$'\n'; continue; }
                 command -v docker >/dev/null 2>&1 && docker rm -f "$id" >/dev/null 2>&1 || left+="  容器未清理：$id"$'\n';;
      dir)       [[ "$id" == *"$RUN_ID"* ]] || { left+="  未处理（不含本轮 run_id）：$line"$'\n'; continue; }
                 [[ -d "$id" ]] && rm -rf -- "$id" || true;;
      pid)       [[ "$id" =~ ^[0-9]+$ && "$id" -gt 1 && "$id" != "$$" && "$id" != "$PPID" ]] || { left+="  未处理（非法 pid）：$line"$'\n'; continue; }
                 kill -0 "$id" 2>/dev/null || continue
                 pg="$(ps -o pgid= -p "$id" 2>/dev/null | tr -d ' ')"
                 if [[ -n "$CHILD_PGID" && "$pg" == "$CHILD_PGID" ]]; then kill_tree "$id"; else left+="  未处理（不属于本轮进程组）：$line"$'\n'; fi;;
      *)         left+="  未知类型：$line"$'\n';;
    esac
  done < "$RES"
  [[ -n "$left" ]] && { echo "资源清理残留："; printf '%s' "$left"; } >&2
  return 0
}
# Testcontainers 兜底（仅超时时）：子进程不登记测试框架创建的容器，正常结束由 ryuk 回收；超时被整组终止时，
# 本轮开始时不存在（即创建时间晚于本轮开始）的 org.testcontainers.sessionId 容器一律 rm -f，本轮之前已有的只报告
tc_ids() { command -v docker >/dev/null 2>&1 && docker ps -aq --no-trunc --filter label=org.testcontainers.sessionId 2>/dev/null; return 0; }
cleanup_testcontainers() {
  command -v docker >/dev/null 2>&1 || return 0
  local id left=""
  for id in $(tc_ids); do
    if printf '%s\n' "$TC_BEFORE" | grep -qxF -- "$id"; then left+="  未处理（本轮开始前已存在的 Testcontainers 容器）：${id:0:12}"$'\n'
    else docker rm -f "$id" >/dev/null 2>&1 || left+="  Testcontainers 容器未清理：${id:0:12}"$'\n'; fi
  done
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

warn_foreign_cmds() {  # 报告里引用了运行配置之外的构建命令：无法可靠判断，只警告不拦
  [[ -f "$OUT" ]] || return 0
  local allowed found cmd need have a w ok hit=""
  allowed="$(printf '%s\n' "${CHECKS:-}" | sed -n '/^[[:space:]]*```viktor-checks[[:space:]]*$/,/^[[:space:]]*```[[:space:]]*$/p' | sed -n 's/^[[:space:]]*[a-z0-9_-]*[[:space:]]*:[[:space:]]*//p')"
  found="$(awk 'NR==1&&/^---/{fm=1;next} fm&&/^---/{fm=0;next} !fm' "$OUT" | grep -o '`[^`]*`' | tr -d '`' \
    | grep -E '^(\./mvnw|mvn|\./gradlew|gradle|npm|pnpm|yarn|npx|bun|go|cargo|pytest|make)( |$)' | sed 's/[[:space:]][0-9]*[<>].*$//; s/[|;&<>].*$//; s/[[:space:]]*$//' | sort -u)"
  [[ -n "$found" ]] || return 0
  set -f
  while IFS= read -r cmd; do
    [[ -z "$cmd" ]] && continue
    need=""; for w in $cmd; do [[ "$w" == -* ]] || need+=" $w"; done
    ok=0
    while IFS= read -r a; do
      [[ -z "$a" ]] && continue
      have=" $a "; ok=1
      for w in $need; do [[ "$have" == *" $w "* ]] || { ok=0; break; }; done
      [[ $ok -eq 1 ]] && break
    done <<< "$allowed"
    [[ $ok -eq 1 ]] || hit+="  ${cmd}"$'\n'
  done <<< "$found"
  set +f
  [[ -n "$hit" ]] && { echo "警告：${OUT} 引用了本轮运行配置之外的命令（子进程应只执行运行配置里的命令，请核对报告依据）："; printf '%s' "$hit"; }
  return 0
}

# 未信任的工作区：Claude Code 忽略项目 .claude/settings.json 的 permissions.allow（日志里有 "has not been trusted"）
untrusted() { grep -q "has not been trusted" "$LOG" 2>/dev/null; }
TRUST_MSG="工作区未被 Claude Code 信任（未被信任时，子进程会忽略 .claude/settings.json 的放行规则）；请在项目目录（$(pwd)）交互式启动一次 claude 并选择信任，然后说「继续」。上级目录的信任不传递到独立 git 仓库"

if [[ $BG -eq 1 ]]; then
  TC_BEFORE="$(tc_ids)"
  ( run_with_timeout; rc=$?; cleanup_resources; reap_group; [[ $rc -eq 124 ]] && cleanup_testcontainers >> "$LOG" 2>&1
    if [[ $rc -eq 124 ]]; then vrc=2; else verify "$rc" >/dev/null 2>&1; vrc=$?; fi
    if { [[ $rc -ne 0 ]] || [[ $vrc -eq 2 ]]; } && untrusted; then vrc=2; echo "$TRUST_MSG" >> "$LOG"; fi
    [[ $vrc -eq 2 ]] || warn_foreign_cmds >> "$LOG" 2>&1
    echo "$vrc" > "$DIR/.$ROLE.done" ) &
  echo "已在后台启动 ${ROLE}（${AGENT}），完成后 $DIR/.$ROLE.done 内为退出码"; exit 0
fi

TC_BEFORE="$(tc_ids)"
run_with_timeout; rc=$?
cleanup_resources
reap_group
[[ $rc -eq 124 ]] && cleanup_testcontainers
if [[ $rc -eq 124 ]]; then echo "${ROLE} 超时（${TIMEOUT}s），日志：${LOG}" >&2; untrusted && echo "$TRUST_MSG" >&2; exit 2; fi
verify "$rc"; vrc=$?
if { [[ $rc -ne 0 ]] || [[ $vrc -eq 2 ]]; } && untrusted; then echo "$TRUST_MSG" >&2; exit 2; fi
[[ $vrc -eq 2 ]] || warn_foreign_cmds >&2
if [[ "$ROLE" == review && $vrc -le 1 ]]; then t="$(snapshot_tree)" && printf '%s\n' "$t" > "$DIR/.review.tree" || echo "警告：本轮快照失败，未更新 .review.tree" >&2; fi
exit $vrc
