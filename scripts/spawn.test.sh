#!/usr/bin/env bash
# viktor-spawn.sh 测试：用假的 claude / codex 可执行文件模拟各种结果
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPAWN="$ROOT/scripts/viktor-spawn.sh"
fail(){ echo "FAIL: $1" >&2; exit 1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/proj/docs/changes/2026-09-16--x"
cd "$T/proj"; git init -q; git -c user.email=a@b -c user.name=t commit -q --allow-empty -m init
printf -- '- 主干分支：main\n\n```viktor-checks\ntest: npm test -- --run\n```\n' > AGENTS.md
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

# 6f. 事后审查无 base_tree：基线 = 与主干的 merge-base（分支已提交 + 工作区改动都在内），创建 plan.md 不影响基线；
#     快照保留"已跟踪但被 gitignore"的文件；产物未跟踪 / 已跟踪 / 已暂存都不影响指纹；快照失败返回非零且无输出
mkdir -p "$T/p6"; cd "$T/p6"; git init -q -b main; printf -- '```viktor-checks\ntest: npm test -- --run\n```\n' > AGENTS.md; git add -A; git -c user.email=a@b -c user.name=t commit -q -m init
printf 'a\n' > app.ts; git add -A; git -c user.email=a@b -c user.name=t commit -qm base; mb=$(git rev-parse HEAD)
git checkout -q -b feat; printf 'b\n' > app.ts; git add -A; git -c user.email=a@b -c user.name=t commit -qm feat   # 功能已提交，工作区干净
mkdir -p "$D"; printf -- '---\nstatus: in-progress\ntier: S\n---\n' > "$D/plan.md"                                    # 创建 plan 让工作区变脏
mkfake claude "writeres review pass"
run review "$D" >/dev/null || fail "事后审查应能运行"
grep -q "git diff $mb" "$D/.review.prompt.md" || fail "无 base_tree 时基线应为与主干的 merge-base，不受 plan.md 影响"
git diff "$mb" --stat -- . ':!docs/changes' | grep -q app.ts || fail "基线 diff 应含已提交的分支改动"
# 指纹：产物三种状态都不影响
f0="$("$SPAWN" fingerprint)"
printf 'edit\n' >> "$D/plan.md"; [[ "$("$SPAWN" fingerprint)" == "$f0" ]] || fail "未跟踪产物修改不应影响指纹"
git add "$D/plan.md";               [[ "$("$SPAWN" fingerprint)" == "$f0" ]] || fail "暂存产物不应影响指纹"
git -c user.email=a@b -c user.name=t commit -qm plan
printf 'edit2\n' >> "$D/plan.md";  [[ "$("$SPAWN" fingerprint)" == "$f0" ]] || fail "已跟踪产物修改不应影响指纹"
git add "$D/plan.md";               [[ "$("$SPAWN" fingerprint)" == "$f0" ]] || fail "已跟踪产物暂存不应影响指纹"
git reset -q
# 已跟踪但被 gitignore 的文件
printf 'fixture\n' > fx.txt; git add fx.txt; git -c user.email=a@b -c user.name=t commit -qm fx; printf 'fx.txt\n' > .gitignore
f1="$("$SPAWN" fingerprint)"; printf 'changed\n' > fx.txt; f2="$("$SPAWN" fingerprint)"
[[ "$f1" != "$f2" ]] || fail "已跟踪但被 gitignore 的文件修改后指纹应变化"
mkdir nested && git -C nested init -q
set +e; out="$("$SPAWN" fingerprint 2>/dev/null)"; rc=$?; set -e
[[ $rc -ne 0 && -z "$out" ]] || fail "快照失败应返回非零且无输出，实际 rc=$rc out=$out"
rm -rf nested; cd "$T/proj"

# 6g. check blocked → 4；--checks 文件传入子进程；未初始化时提示词含"未找到检查命令"；超时清理按 run_id 登记的资源；进程组终止子孙进程
mkfake claude "writeres check blocked"
set +e; run check "$D" >/dev/null 2>"$T/err"; rc=$?; set -e; [[ $rc -eq 4 ]] && grep -q "阻塞" "$T/err" || fail "check blocked 应返回 4，实际 $rc"
printf '```viktor-checks\ntest: npm test -- --run\n```\n### 运行前提\n- 本地 Postgres 就绪\n' > "$T/checks.txt"
mkfake claude "writeres check pass"
run check "$D" --checks "$T/checks.txt" >/dev/null || fail "--checks 应可用"
grep -q "npm test -- --run" "$D/.check.prompt.md" && grep -q "本地 Postgres" "$D/.check.prompt.md" || fail "--checks 内容未传入提示词"
# 只有说明文字 / 空块 / 只有注释值 的 --checks 都拒绝；只有 verify 也算有命令
for bad in '### 运行前提\n- x\n' '```viktor-checks\n```\n' '```viktor-checks\ntest:\nfoo: bar\n```\n'; do
  printf "$bad" > "$T/checks.txt"; rm -f "$D/.check.prompt.md"
  set +e; run check "$D" --checks "$T/checks.txt" >/dev/null 2>"$T/err"; rc=$?; set -e
  [[ $rc -eq 2 ]] && [[ ! -f "$D/.check.prompt.md" ]] || fail "无可用命令的 --checks 应退出 2 且不派单：$bad"
done
printf '```viktor-checks\nverify: mvn verify\n```\n' > "$T/checks.txt"; run check "$D" --checks "$T/checks.txt" >/dev/null || fail "只有 verify 应可派单"
rm -f "$T/proj/AGENTS.md"; rm -f "$D/.check.prompt.md"
set +e; run check "$D" >/dev/null 2>"$T/err"; rc=$?; set -e
[[ $rc -eq 2 ]] && grep -q "未找到可用的检查命令" "$T/err" && [[ ! -f "$D/.check.prompt.md" ]] || fail "无配置时应退出 2 且不派单，实际 $rc"
# 运行前提两种写法都传入子进程；`### 运行前提` 是文件末节时最后一行不丢
printf -- '- 主干分支：main\n- 运行前提：ONLY_TEST_DB\n\n```viktor-checks\ntest: npm test -- --run\n```\n' > "$T/proj/AGENTS.md"
run check "$D" >/dev/null || fail "有块时应可派单"
grep -q "ONLY_TEST_DB" "$D/.check.prompt.md" || fail "行式运行前提未传入提示词"
printf -- '- 主干分支：main\n\n```viktor-checks\ntest: npm test -- --run\n```\n\n### 运行前提\n- 需要 docker\n- ONLY_LAST_DB\n' > "$T/proj/AGENTS.md"
run check "$D" >/dev/null || fail "有块时应可派单"
grep -q "ONLY_LAST_DB" "$D/.check.prompt.md" && grep -q "需要 docker" "$D/.check.prompt.md" || fail "末节运行前提丢行"
# AGENTS.md 只有运行前提没有块 / 块为空 → 拒绝
for bad in '### 运行前提\n- 需要 docker\n' '```viktor-checks\n```\n### 运行前提\n- x\n'; do
  printf -- "$bad" > "$T/proj/AGENTS.md"; rm -f "$D/.check.prompt.md"
  set +e; run check "$D" >/dev/null 2>"$T/err"; rc=$?; set -e
  [[ $rc -eq 2 ]] && [[ ! -f "$D/.check.prompt.md" ]] || fail "AGENTS.md 无可用命令应退出 2：$bad"
done
printf -- '- 主干分支：main\n\n```viktor-checks\ntest: npm test -- --run\n```\n' > "$T/proj/AGENTS.md"
# 正常结束：子进程登记的后台 pid 属于本轮进程组 → 被清理；不属于的只报告
mkfake claude "d=\$VIKTOR_RESOURCES; (sleep 61.8; true) & echo pid:\$! >> \$d; echo pid:1 >> \$d; writeres check pass"
run check "$D" >/dev/null 2>"$T/err" || fail "正常结束应返回 0"
sleep 1; pgrep -f "^sleep 61\.8$" >/dev/null && fail "正常结束后登记的后台进程仍在运行" || true
grep -q "未处理" "$T/err" || fail "非本轮进程应只报告"
# S 档 plan 没有验收标准节：inputs-digest 报错而不是给出可复用的摘要
printf -- '---\nstatus: in-progress\ntier: S\n---\n# x\n\n问题：示例\nAC-1：旧行为\n' > "$D/plan.md"
"$SPAWN" inputs-digest "$D" >/dev/null 2>&1 && fail "无验收标准节应失败" || true
printf -- '---\nstatus: in-progress\ntier: M\n---\n# x\n\n## 验收标准\n- [ ] AC-1：a\n' > "$D/plan.md"
# 超时：子进程登记一个带 run_id 的临时目录和一个不带的，前者被清理、后者只报告；子进程再起的孙进程也被终止
mkfake claude "d=\$VIKTOR_RESOURCES; mkdir -p $T/res-\$VIKTOR_RUN_ID $T/res-other; echo dir:$T/res-\$VIKTOR_RUN_ID >> \$d; echo dir:$T/res-other >> \$d; (sleep 61.7; true) & echo pid:\$! >> \$d; sleep 61.7"
set +e; VIKTOR_SPAWN_TIMEOUT=2 run check "$D" >/dev/null 2>"$T/err"; rc=$?; set -e
[[ $rc -eq 2 ]] || fail "超时应返回 2，实际 $rc"
ls -d "$T"/res-* 2>/dev/null | grep -v res-other | grep -q . && fail "带 run_id 的临时目录未被清理" || true
[[ -d "$T/res-other" ]] && grep -q "未处理" "$T/err" || fail "不带 run_id 的资源应保留并报告"
sleep 1; pgrep -f "^sleep 61\.7$" >/dev/null && fail "超时后孙进程仍在运行" || true
rm -rf "$T/res-other"

# 6h. inputs-digest：改验收标准或运行配置摘要变；改正文其他部分不变
printf -- '---\nstatus: in-progress\ntier: M\n---\n# x\n\n## 方案\nfoo\n\n## 验收标准\n- [ ] AC-1：a\n\n## 假设\n- b\n' > "$D/plan.md"
d0="$("$SPAWN" inputs-digest "$D")"
sed -i.bak 's/^foo$/bar/' "$D/plan.md"; rm -f "$D/plan.md.bak"; [[ "$("$SPAWN" inputs-digest "$D")" == "$d0" ]] || fail "改方案正文不应改变输入摘要"
sed -i.bak 's/AC-1：a/AC-1：a（证据：真实库）/' "$D/plan.md"; rm -f "$D/plan.md.bak"; [[ "$("$SPAWN" inputs-digest "$D")" != "$d0" ]] || fail "改验收标准应改变输入摘要"
printf -- '---\nstatus: in-progress\n---\n# x\n\n## 验收标准\n- [ ] AC-1：z\n' > "$D/plan.md"; d2="$("$SPAWN" inputs-digest "$D")"
printf -- '- [ ] AC-2：y\n' >> "$D/plan.md"; [[ "$("$SPAWN" inputs-digest "$D")" != "$d2" ]] || fail "验收标准是末节时追加 AC 应改变摘要"
d1="$("$SPAWN" inputs-digest "$D")"; printf '\n## 本轮运行配置\n```viktor-checks\ntest: x\n```\n' >> "$D/plan.md"
[[ "$("$SPAWN" inputs-digest "$D")" != "$d1" ]] || fail "加运行配置应改变输入摘要"

# 7. VIKTOR_AGENT 强制选择；后台模式写 .done
mkfake claude "writeres review pass"
mkfake codex "exit 9"
VIKTOR_AGENT=claude run review "$D" >/dev/null || fail "VIKTOR_AGENT=claude 应选择 claude"
rm -f "$D/.review.done"; VIKTOR_AGENT=claude run review "$D" --background >/dev/null
for i in 1 2 3 4 5; do [[ -f "$D/.review.done" ]] && break; sleep 1; done
[[ "$(cat "$D/.review.done")" == "0" ]] || fail "后台模式未写 .done=0"

# 8. 子进程不得提权：两种工具的提权参数都拒绝派单（退出码 2、不调用 CLI）；项目级沙箱值只接受 --sandbox，且同样拒绝 danger-full-access
mkfake claude "writeres review pass"; mkfake codex "writeres review pass"
for a in '--dangerously-skip-permissions' '--permission-mode bypassPermissions'; do
  rm -f "$T/args.claude"
  set +e; VIKTOR_CLAUDE_ARGS="$a" run review "$D" --agent claude >/dev/null 2>"$T/err"; rc=$?; set -e
  [[ $rc -eq 2 && ! -f "$T/args.claude" ]] && grep -q "拒绝派单" "$T/err" || fail "claude 提权参数应拒绝派单：${a}（rc=${rc}）"
done
for a in '--sandbox danger-full-access' '--dangerously-bypass-approvals-and-sandbox'; do
  rm -f "$T/args.codex"
  set +e; VIKTOR_CODEX_ARGS="$a" run review "$D" --agent codex >/dev/null 2>"$T/err"; rc=$?; set -e
  [[ $rc -eq 2 && ! -f "$T/args.codex" ]] && grep -q "拒绝派单" "$T/err" || fail "codex 提权参数应拒绝派单：${a}（rc=${rc}）"
done
cp "$T/proj/AGENTS.md" "$T/agents.bak"
printf -- '- 子进程参数：codex --sandbox read-only\n' >> "$T/proj/AGENTS.md"; rm -f "$T/args.codex"
run review "$D" --agent codex >/dev/null || fail "项目级沙箱值应可派单"
grep -qx "read-only" "$T/args.codex" && ! grep -qx "workspace-write" "$T/args.codex" || fail "项目级沙箱值未传给 codex"
cp "$T/agents.bak" "$T/proj/AGENTS.md"; printf -- '- 子进程参数：codex --sandbox danger-full-access\n' >> "$T/proj/AGENTS.md"; rm -f "$T/args.codex"
set +e; run review "$D" --agent codex >/dev/null 2>"$T/err"; rc=$?; set -e
[[ $rc -eq 2 && ! -f "$T/args.codex" ]] && grep -q "拒绝派单" "$T/err" || fail "项目级 danger-full-access 应拒绝派单（rc=${rc}）"
cp "$T/agents.bak" "$T/proj/AGENTS.md"
echo PASS
