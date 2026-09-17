#!/usr/bin/env bash
# viktor-spawn.sh 测试：用假的 claude / codex 可执行文件模拟各种结果
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPAWN="$ROOT/scripts/viktor-spawn.sh"
fail(){ echo "FAIL: $1" >&2; exit 1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/proj/docs/changes/2026-09-16--x"
cd "$T/proj"; git init -q; git -c user.email=a@b -c user.name=t commit -q --allow-empty -m init
printf -- '- 主干分支：main\n' > AGENTS.md
printf -- '---\nstatus: in-progress\ntier: M\n---\n# x\n' > docs/changes/2026-09-16--x/plan.md
D="docs/changes/2026-09-16--x"
mkfake(){ # mkfake <name> <behaviour>
  cat > "$T/bin/$1" <<F
#!/usr/bin/env bash
# 记录收到的参数，便于断言
printf '%s\n' "\$@" > "$T/args.$1"
writeres(){ rid=\$(sed -n 's/^run_id:[[:space:]]*\([^ ]*\).*/\1/p' "$D/.\$1.prompt.md" | head -1); printf -- '---\nrun_id: %s\nresult: %s\n---\n# r\n%s\n' "\$rid" "\$2" "\${3:-}" > "$D/\$1.md"; }
$2
F
  chmod +x "$T/bin/$1"
}
unset CLAUDECODE CLAUDE_PROJECT_DIR; for v in $(env | grep -o "^CODEX_[A-Z_]*"); do unset "$v"; done
run(){ PATH="$T/bin:/usr/bin:/bin" VIKTOR_WORKFLOW_DIR="$ROOT" "$SPAWN" "$@"; }

# 1. claude 正常写 review.md → 0；提示词中变量已替换；默认参数传入
mkfake claude "writeres review pass"
rm -f "$T/bin/codex"
run review "$D" >/dev/null || fail "pass 应返回 0"
grep -q "{{" "$D/.review.prompt.md" && fail "提示词变量未替换" || true
grep -q "档位：M" "$D/.review.prompt.md" || fail "档位未从 plan.md 读取"
grep -q -- "--permission-mode" "$T/args.claude" || fail "claude 默认参数未传入"

# 2. blocked → 1
mkfake claude "writeres review blocked"
set +e; run review "$D" >/dev/null; rc=$?; set -e; [[ $rc -eq 1 ]] || fail "blocked 应返回 1，实际 $rc"

# 3. 进程退出但无产物 → 2（旧文件存在但未更新也算）
mkfake claude "true"; touch -d '2000-01-01' "$D/review.md" 2>/dev/null || touch -t 200001010000 "$D/review.md"
set +e; run review "$D" >/dev/null 2>&1; rc=$?; set -e; [[ $rc -eq 2 ]] || fail "无产物应返回 2，实际 $rc"

# 3b. 写完 pass 报告再异常退出 → 2；报告 run_id 不属于本轮 → 2
mkfake claude "writeres review pass; exit 9"
set +e; run review "$D" >/dev/null 2>"$T/err"; rc=$?; set -e; [[ $rc -eq 2 ]] && grep -q "异常退出" "$T/err" || fail "异常退出应返回 2，实际 $rc"
mkfake claude "true"; printf -- '---\nrun_id: stale\nresult: pass\n---\n' > "$D/review.md"
set +e; run review "$D" >/dev/null 2>"$T/err"; rc=$?; set -e; [[ $rc -eq 2 ]] && grep -q "不属于本轮" "$T/err" || fail "旧 run_id 应返回 2，实际 $rc"

# 4. 超时 → 2
mkfake claude "sleep 30"
set +e; VIKTOR_SPAWN_TIMEOUT=2 run review "$D" >/dev/null 2>&1; rc=$?; set -e; [[ $rc -eq 2 ]] || fail "超时应返回 2，实际 $rc"
grep -q TIMEOUT "$D/.review.log" || fail "超时未记录日志"

# 5. 无 CLI → 3，提示词文件存在
rm -f "$T/bin/claude"
set +e; run review "$D" >/dev/null 2>"$T/err"; rc=$?; set -e; [[ $rc -eq 3 ]] || fail "无 CLI 应返回 3，实际 $rc"
grep -q ".review.prompt.md" "$T/err" || fail "无 CLI 时未提示手动方式"

# 6. codex 回退 + check 的 manual → 0，failed → 1
mkfake codex "writeres check manual"
run check "$D" | grep -q "待人工" || fail "check manual 应返回 0 并提示"
grep -q "^exec$" "$T/args.codex" && grep -q -- "--sandbox" "$T/args.codex" || fail "codex 调用方式错误"
mkfake codex "writeres check failed"
set +e; run check "$D" >/dev/null; rc=$?; set -e; [[ $rc -eq 1 ]] || fail "check failed 应返回 1"

# 6b. result: error → 2；VIKTOR_CLAUDE_ARGS 含引号参数按 shell 规则解析
mkfake claude "writeres review error "无法执行 npm test""
set +e; run review "$D" >/dev/null 2>"$T/err"; rc=$?; set -e; [[ $rc -eq 2 ]] || fail "result: error 应返回 2，实际 $rc"
grep -q "无法执行" "$T/err" || fail "error 时未提示"
mkfake claude "writeres review pass"
VIKTOR_CLAUDE_ARGS='--permission-mode acceptEdits --allowedTools "Bash(npm test)"' run review "$D" >/dev/null || fail "带引号参数应能运行"
grep -qx "Bash(npm test)" "$T/args.claude" || fail "带引号的参数被切分"

# 6c. --agent 优先；指定工具不存在时不回退（退出码 3）；环境变量检测
mkfake claude "writeres review pass"
mkfake codex "writeres review pass"
rm -f "$T/args.claude" "$T/args.codex"
run review "$D" --agent codex >/dev/null && [[ -f "$T/args.codex" && ! -f "$T/args.claude" ]] || fail "--agent codex 应只调用 codex"
rm -f "$T/bin/codex"
set +e; run review "$D" --agent codex >/dev/null 2>"$T/err"; rc=$?; set -e
[[ $rc -eq 3 ]] && grep -q "不回退" "$T/err" || fail "指定工具不存在应返回 3 且不回退，实际 $rc"
mkfake codex "writeres review pass"
rm -f "$T/args.claude" "$T/args.codex"
CODEX_SANDBOX=1 run review "$D" >/dev/null && [[ -f "$T/args.codex" && ! -f "$T/args.claude" ]] || fail "CODEX_* 环境变量应选 codex"
rm -f "$T/args.claude" "$T/args.codex"
CLAUDECODE=1 run review "$D" >/dev/null && [[ -f "$T/args.claude" && ! -f "$T/args.codex" ]] || fail "CLAUDECODE 环境变量应选 claude"

# 6d. 指纹：写 plan.md / check.md / 日志不改变指纹；改业务代码才变；未跟踪文件也算
f_a="$("$SPAWN" fingerprint)"
printf 'verified: {review: %s}\n' "$f_a" >> "$D/plan.md"; printf 'x\n' > "$D/check.md"; printf 'log\n' > "$D/.review.log"
[[ "$("$SPAWN" fingerprint)" == "$f_a" ]] || fail "写运行产物后指纹不应变化"
printf 'more\n' > "$T/proj/new.ts"
[[ "$("$SPAWN" fingerprint)" != "$f_a" ]] || fail "新增未跟踪源码后指纹应变化"

# 6e. base_tree 隔离未提交的前一个需求；复审只看上一轮快照之后的变化；run_id 带注释也能识别
: > "$T/proj/prev-req.ts"                      # 前一个需求的未提交改动
tree="$(cd "$T/proj" && "$SPAWN" snapshot)"    # 本需求开始时的快照
printf -- '---\nstatus: in-progress\ntier: M\nbase_tree: %s   # 注释\n---\n# x\n' "$tree" > "$D/plan.md"
printf 'z\n' > "$T/proj/z.ts"                  # 本需求的改动
git -C "$T/proj" add -N z.ts prev-req.ts        # 与 spawn 一致：未跟踪文件 intent-to-add
git -C "$T/proj" diff "$tree" --stat -- . | grep -q "z.ts" || fail "base_tree diff 应含本需求文件"
git -C "$T/proj" diff "$tree" --stat -- . | grep -q "prev-req.ts" && fail "base_tree diff 不应含前一个需求的未提交文件" || true
mkfake claude "writeres review pass"
run review "$D" >/dev/null || fail "第一轮 review 应通过"
grep -q "git diff $tree" "$D/.review.prompt.md" || fail "提示词应使用 plan.md 的 base_tree"
[[ -s "$D/.review.tree" ]] || fail "review 后应记录本轮快照"
prev="$(cat "$D/.review.tree")"; printf 'w\n' > "$T/proj/w.ts"
run review "$D" >/dev/null || fail "复审应通过"
git -C "$T/proj" add -N w.ts
grep -q "git diff $prev" "$D/.review.prompt.md" || fail "复审提示词应使用上一轮快照"
git -C "$T/proj" diff "$prev" --stat | grep -q "w.ts" || fail "复审范围应含新改动"
git -C "$T/proj" diff "$prev" --stat | grep -q "z.ts" && fail "复审范围不应含上一轮已审内容" || true
# run_id 行尾带注释
mkfake claude "rid=\$(sed -n 's/^run_id:[[:space:]]*\([^ ]*\).*/\1/p' $D/.review.prompt.md | head -1); printf -- '---\nrun_id: %s   # 原样写入\nresult: pass\n---\n' \"\$rid\" > $D/review.md"
run review "$D" >/dev/null || fail "run_id 带行尾注释应能识别"
git -C "$T/proj" reset -q 2>/dev/null || true

# 7. VIKTOR_AGENT 强制选择；后台模式写 .done
mkfake claude "writeres review pass"
mkfake codex "exit 9"
VIKTOR_AGENT=claude run review "$D" >/dev/null || fail "VIKTOR_AGENT=claude 应选择 claude"
rm -f "$D/.review.done"; VIKTOR_AGENT=claude run review "$D" --background >/dev/null
for i in 1 2 3 4 5; do [[ -f "$D/.review.done" ]] && break; sleep 1; done
[[ "$(cat "$D/.review.done")" == "0" ]] || fail "后台模式未写 .done=0"
echo PASS
