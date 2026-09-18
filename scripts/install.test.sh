#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail(){ echo "FAIL: $1" >&2; exit 1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
INSTALL="$ROOT/scripts/install.sh"; GATE="$ROOT/hooks/viktor-gate.sh"

# ── 1. 全新安装 ──
mkdir -p "$T/p1"; "$INSTALL" "$ROOT" "$T/p1" >/dev/null
for base in .claude/skills .agents/skills; do
  for n in init plan code review ship; do [[ -f "$T/p1/$base/viktor-$n/SKILL.md" ]] || fail "缺少 $base/viktor-$n"; done
done
[[ ! -d "$T/p1/.cursor/skills" ]] || fail "不应安装到 .cursor/skills"
[[ -x "$T/p1/.claude/hooks/viktor-gate.sh" ]] || fail "缺少 hook"
grep -q 'CLAUDE_PROJECT_DIR' "$T/p1/.claude/settings.json" || fail "hook 未用绝对路径"
grep -q "fe-ai-workflow-start" "$T/p1/AGENTS.md" || fail "AGENTS.md 未注入"
grep -q "^@AGENTS.md$" "$T/p1/CLAUDE.md" || fail "CLAUDE.md 未引用 AGENTS.md"
[[ ! -d "$T/p1/skills" && ! -d "$T/p1/references" ]] || fail "不应向项目根目录拷贝 skills/references"
[[ -z "$(ls -A "$ROOT" | grep -E '\.tmp$')" ]] || fail "源目录残留临时文件"

# 注入模板必须与技能源文一致，升级安装也保留两张卡。
python3 - "$ROOT" "$T/p1/AGENTS.md" <<'PYTEST'
from pathlib import Path
import sys
root, installed = Path(sys.argv[1]), Path(sys.argv[2]).read_text()
flow = (root / 'skills/viktor-flow/SKILL.md').read_text()
plan = (root / 'skills/viktor-plan/SKILL.md').read_text()
for source, title in [(plan, '━━ ⏸ PLAN 待确认'), (flow, '━━ ⚠ <节点> 需要处理')]:
    card = source[source.index(title):].split('```', 1)[0].rstrip()
    assert card in installed, title + '模板未完整注入'
discipline = flow.split('## 对话输出纪律（所有节点通用）', 1)[1].strip()
assert discipline in installed, '对话输出纪律未完整注入'
assert '卡片之外不输出任何文字' in installed
assert '- 节点卡标题只允许 INIT / PLAN / CODE / REVIEW / CHECK / SHIP 六种，每个节点完成时只输出一张；中途进度只允许 `· AC-n ✔ <测试名>` 这种单行，不得把进度、准备、收尾等汇报做成卡片，也不得自造标题。review 复审通过时必须输出 `✔ REVIEW` 卡，不能用其他文字代替。' in installed, '节点卡标题白名单、单行进度与复审通过规则未完整注入'
PYTEST

# ── 2. 幂等 + 保留用户内容 + 合并已有 hooks ──
mkdir -p "$T/p2/.claude"; printf 'user header\n' > "$T/p2/AGENTS.md"
echo '{"permissions":{"allow":["Bash(ls)"]},"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"echo pre"}]}]}}' > "$T/p2/.claude/settings.json"
"$INSTALL" "$ROOT" "$T/p2" >/dev/null; "$INSTALL" "$ROOT" "$T/p2" >/dev/null
[[ $(grep -c fe-ai-workflow-start "$T/p2/AGENTS.md") -eq 1 ]] || fail "标记重复"
grep -q "user header" "$T/p2/AGENTS.md" || fail "用户内容丢失"
grep -q '"echo pre"' "$T/p2/.claude/settings.json" || fail "已有 hooks 丢失"
grep -q 'Bash(ls)' "$T/p2/.claude/settings.json" || fail "permissions 丢失"
[[ $(grep -c viktor-gate.sh "$T/p2/.claude/settings.json") -eq 1 ]] || fail "hook 重复注入"

# ── 3. settings.json 非法：必须中止且不修改 ──
mkdir -p "$T/p3/.claude"; printf '{ // comment\n "permissions": {} }\n' > "$T/p3/.claude/settings.json"
cp "$T/p3/.claude/settings.json" "$T/p3.bak"
"$INSTALL" "$ROOT" "$T/p3" >/dev/null 2>&1 && fail "非法 settings.json 应中止" || true
cmp -s "$T/p3/.claude/settings.json" "$T/p3.bak" || fail "非法 settings.json 被修改"

# ── 4. --migrate 只删 v0 精确名单，保留用户自己的技能 ──
mkdir -p "$T/p4/skills/01-brainstorming" "$T/p4/skills/01-my-own" "$T/p4/references" "$T/p4/.cursor/rules" "$T/p4/.claude/commands/viktor" "$T/p4/.claude/skills/viktor-custom"
touch "$T/p4/.cursor/rules/workflow.mdc" "$T/p4/.claude/commands/viktor/think.md" "$T/p4/.claude/commands/viktor/my-deploy.md" "$T/p4/references/testing-patterns.md" "$T/p4/references/mine.md" "$T/p4/.claude/skills/viktor-custom/SKILL.md"
"$INSTALL" "$ROOT" "$T/p4" --migrate >/dev/null
[[ ! -d "$T/p4/skills/01-brainstorming" && ! -f "$T/p4/.cursor/rules/workflow.mdc" && ! -f "$T/p4/.claude/commands/viktor/think.md" && ! -f "$T/p4/references/testing-patterns.md" ]] || fail "migrate 未清理 v0 文件"
[[ -d "$T/p4/skills/01-my-own" && -f "$T/p4/.claude/commands/viktor/my-deploy.md" && -f "$T/p4/references/mine.md" && -f "$T/p4/.claude/skills/viktor-custom/SKILL.md" ]] || fail "migrate 误删用户文件"

# ── 5. 缺少 END 标记：中止，不丢内容 ──
mkdir -p "$T/p5"; printf 'head\n<!-- fe-ai-workflow-start -->\nold\nUSER TAIL\n' > "$T/p5/AGENTS.md"
"$INSTALL" "$ROOT" "$T/p5" >/dev/null 2>&1 && fail "缺少 END 标记应中止" || true
grep -q "USER TAIL" "$T/p5/AGENTS.md" || fail "缺少 END 标记时丢失内容"

# ── 6. CLAUDE.md 为软链接：跳过 ──
mkdir -p "$T/p6"; printf 'agents\n' > "$T/p6/AGENTS.md"; ln -s AGENTS.md "$T/p6/CLAUDE.md"
out="$("$INSTALL" "$ROOT" "$T/p6")"
[[ -L "$T/p6/CLAUDE.md" ]] || fail "软链接 CLAUDE.md 被替换"
grep -q "软链接" <<<"$out" || fail "软链接未提示"
[[ $(grep -c '@AGENTS.md' "$T/p6/AGENTS.md") -eq 0 ]] || fail "软链接场景下 AGENTS.md 混入 @AGENTS.md"

# ── 7. hook 门禁 ──
mk_repo(){ mkdir -p "$1"; git -C "$1" init -q; git -C "$1" -c user.email=a@b -c user.name=t commit -q --allow-empty -m init; }
gate(){ (cd "$1" && CLAUDE_PROJECT_DIR="$1" bash "$GATE"); }
json_ok(){ if command -v jq >/dev/null; then jq -e .systemMessage >/dev/null; else node -e 'JSON.parse(require("fs").readFileSync(0,"utf8")).systemMessage||process.exit(1)'; fi; }
mk_repo "$T/g"; cd "$T/g"; printf 'x\n' > a.ts
cat > AGENTS.md <<'A'
## 项目信息
   ```viktor-checks
   typecheck: printf 'C:\\src\t\033[31merror TS1 bad\033[0m\n'; false
   lint:  echo "a | b" | grep -q "a | b"  
   test: true
   ```
A
perl -pi -e 's/\n/\r\n/' AGENTS.md   # CRLF + 缩进块都要能解析
set +e; echo '{}' | gate "$T/g" >/dev/null 2>"$T/err"; rc=$?; set -e
[[ $rc -eq 2 ]] || fail "hook 应返回 2，实际 $rc"
grep -q "typecheck 失败" "$T/err" || fail "未报告 typecheck 失败"
grep -q "lint 失败" "$T/err" && fail "含管道的 lint 命令解析错误" || true
grep -q "1/3" "$T/err" || fail "未显示拦截计数"
# 同一回合连续拦截到上限：放行 + 合法 JSON 的 systemMessage（含反斜杠/制表符/ANSI）
set +e; echo '{"stop_hook_active":true}' | gate "$T/g" >/dev/null 2>&1; echo '{"stop_hook_active":true}' | gate "$T/g" >"$T/out" 2>/dev/null; rc=$?; set -e
[[ $rc -eq 0 ]] || fail "达到上限应放行，实际 $rc"
json_ok < "$T/out" || fail "systemMessage 不是合法 JSON：$(cat "$T/out")"
grep -q "error TS1" "$T/out" || fail "systemMessage 未包含错误摘要"
# 新回合（stop_hook_active=false）计数重置：应再次拦截且显示 1/3
set +e; echo '{"stop_hook_active":false}' | gate "$T/g" >/dev/null 2>"$T/err"; rc=$?; set -e
[[ $rc -eq 2 ]] && grep -q "1/3" "$T/err" || fail "新回合计数未重置"
# 缺失项跳过；通过后记录指纹，再次调用直接放行（命令第二次执行会失败，能通过说明被跳过）；改动后重新检查
printf '```viktor-checks\ntest: test ! -f %s/ran && touch %s/ran\n```\n' "$T" "$T" > AGENTS.md
echo '{}' | gate "$T/g" || fail "只有 test 且通过时应返回 0"
[[ -f .git/viktor-gate/passed ]] || fail "未记录通过指纹"
echo '{}' | gate "$T/g" || fail "指纹未变化时应跳过检查"
printf '```viktor-checks\ntest: false\n```\n' > AGENTS.md
printf 'y\n' >> a.ts
set +e; echo '{}' | gate "$T/g" 2>/dev/null; rc=$?; set -e
[[ $rc -eq 2 ]] || fail "改动后应重新检查"
# 文件名含空格：指纹必须随内容变化
mk_repo "$T/gs"; cd "$T/gs"; printf '```viktor-checks\ntest: grep -q good "my file.ts"\n```\n' > AGENTS.md
printf 'good\n' > "my file.ts"; echo '{}' | gate "$T/gs" || fail "空格文件名：通过时应返回 0"
printf 'bad\n' > "my file.ts"
set +e; echo '{}' | gate "$T/gs" 2>/dev/null; rc=$?; set -e
[[ $rc -eq 2 ]] || fail "空格文件名：内容变化后应重新检查，实际 $rc"
# 缺少 viktor-checks 块：放行但提示，且不记录指纹
mk_repo "$T/gn"; cd "$T/gn"; printf '## 项目信息\n' > AGENTS.md; printf 'x\n' > a.ts
echo '{}' | gate "$T/gn" > "$T/out" || fail "无 viktor-checks 应放行"
json_ok < "$T/out" && grep -q "未找到 viktor-checks" "$T/out" || fail "无 viktor-checks 时应提示"
[[ ! -f .git/viktor-gate/passed ]] || fail "无 viktor-checks 时不应记录指纹"
# 纯文档改动跳过；docs/ 下源码不跳过；子目录 cwd；worktree；monorepo 子包会话；非 git
mk_repo "$T/g2"; mkdir -p "$T/g2/docs/changes/x" "$T/g2/pkg"; printf 'plan\n' > "$T/g2/docs/changes/x/plan.md"
printf '```viktor-checks\ntest: false\n```\n' > "$T/g2/AGENTS.md"
echo '{}' | gate "$T/g2" || fail "纯文档改动应放行"
printf 'x\n' > "$T/g2/docs/site.ts"
set +e; echo '{}' | gate "$T/g2" 2>/dev/null; rc=$?; set -e
[[ $rc -eq 2 ]] || fail "docs/ 下源码改动应触发检查"
printf 'x\n' > "$T/g2/pkg/a.ts"
set +e; (cd "$T/g2/pkg" && echo '{}' | CLAUDE_PROJECT_DIR="$T/g2" bash "$GATE" 2>/dev/null); rc=$?; set -e
[[ $rc -eq 2 ]] || fail "子目录 cwd 下门禁应生效"
git -C "$T/g2" -c user.email=a@b -c user.name=t add -A >/dev/null; git -C "$T/g2" -c user.email=a@b -c user.name=t commit -qm wip
git -C "$T/g2" worktree add -q "$T/wt" -b wt >/dev/null 2>&1; printf 'z\n' > "$T/wt/pkg/a.ts"
set +e; echo '{}' | gate "$T/wt" 2>/dev/null; rc=$?; set -e
[[ $rc -eq 2 ]] || fail "git worktree 中门禁应生效，实际 $rc"
# monorepo：会话从子包启动，子包有自己的 AGENTS.md，命令在子包执行
mkdir -p "$T/g2/pkg2"; printf '```viktor-checks\ntest: test -f pkg-marker\n```\n' > "$T/g2/pkg2/AGENTS.md"; touch "$T/g2/pkg2/pkg-marker"; printf 'x\n' > "$T/g2/pkg2/b.ts"
echo '{}' | gate "$T/g2/pkg2" || fail "子包会话应读取子包 AGENTS.md 并在子包执行命令"
# 子包会话：已跟踪文件通过后再修改，必须重新检查
printf '```viktor-checks\ntest: grep -q good x.ts\n```\n' > "$T/g2/pkg2/AGENTS.md"; printf 'good\n' > "$T/g2/pkg2/x.ts"
git -C "$T/g2" add -A >/dev/null; git -C "$T/g2" -c user.email=a@b -c user.name=t commit -qm pkg2
printf 'good2\n' > "$T/g2/pkg2/x.ts"; echo '{}' | gate "$T/g2/pkg2" || fail "子包已跟踪文件：通过时应返回 0"
printf 'bad\n' > "$T/g2/pkg2/x.ts"
set +e; echo '{}' | gate "$T/g2/pkg2" 2>/dev/null; rc=$?; set -e
[[ $rc -eq 2 ]] || fail "子包已跟踪文件：内容变化后应重新检查，实际 $rc"
mkdir -p "$T/nogit"; (cd "$T/nogit" && unset CLAUDE_PROJECT_DIR && echo '{}' | bash "$GATE") || fail "非 git 目录应放行"

# 7b. 缓存不能跨子包 / 跨命令复用：A 子包通过后，B 子包失败仍须拦截；改命令后须重跑
mk_repo "$T/gc"; mkdir -p "$T/gc/a" "$T/gc/b"
printf '```viktor-checks\ntest: true\n```\n' > "$T/gc/a/AGENTS.md"; printf '```viktor-checks\ntest: false\n```\n' > "$T/gc/b/AGENTS.md"
printf 'x\n' > "$T/gc/a/x.ts"; printf 'y\n' > "$T/gc/b/y.ts"
echo '{}' | gate "$T/gc/a" || fail "子包 A 应通过"
set +e; echo '{}' | gate "$T/gc/b" 2>/dev/null; rc=$?; set -e; [[ $rc -eq 2 ]] || fail "子包 B 不应复用 A 的通过缓存，实际 $rc"
printf '```viktor-checks\ntest: false\n```\n' > "$T/gc/a/AGENTS.md"
set +e; echo '{}' | gate "$T/gc/a" 2>/dev/null; rc=$?; set -e; [[ $rc -eq 2 ]] || fail "改了检查命令后应重跑，实际 $rc"

# ── 8. 升级时替换旧的 hook 条目 ──
mkdir -p "$T/p8/.claude"; echo '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"bash .claude/hooks/viktor-gate.sh"}]},{"hooks":[{"type":"command","command":"echo keep"}]}]}}' > "$T/p8/.claude/settings.json"
"$INSTALL" "$ROOT" "$T/p8" >/dev/null
[[ $(grep -c viktor-gate.sh "$T/p8/.claude/settings.json") -eq 1 ]] && grep -q CLAUDE_PROJECT_DIR "$T/p8/.claude/settings.json" && grep -q '"echo keep"' "$T/p8/.claude/settings.json" || fail "旧 hook 条目未被替换或其他条目丢失"
# ── 9. upgrade.sh 执行途中被原地覆盖（同一个 inode）：旧写法（逐行读）会接着读新内容而出错或丢掉后半段，
#       新写法（main 函数 + 最后一行调用并 exit）已整体读入，不受影响。注：git checkout 是先删后建，不会触发这个问题；
#       这里由 vB 的 install.sh 桩原地改写 upgrade.sh 来模拟
up_test(){ # up_test <目录> <vA 的 upgrade.sh 文件>；输出到 <目录>/out，返回 upgrade.sh 的退出码
  local d="$1"; local up="$d/up" p="$d/proj"
  mkdir -p "$up/scripts" "$p/.claude"; git -C "$up" init -q
  printf '#!/usr/bin/env bash\necho install-stub\n' > "$up/scripts/install.sh"; chmod +x "$up/scripts/install.sh"
  cp "$2" "$up/scripts/upgrade.sh"; chmod +x "$up/scripts/upgrade.sh"
  git -C "$up" add -A; git -C "$up" -c user.email=a@b -c user.name=t commit -qm A; git -C "$up" tag vA
  # vB 的 install.sh 把 upgrade.sh 原地改写成 300 行 "echo CORRUPTED; exit 7"：不管旧写法从哪个偏移接着读，都会读到它
  printf '#!/usr/bin/env bash\necho install-stub\nfor i in $(seq 1 300); do echo "echo CORRUPTED; exit 7"; done > "$1/scripts/upgrade.sh"\n' > "$up/scripts/install.sh"
  git -C "$up" add -A; git -C "$up" -c user.email=a@b -c user.name=t commit -qm B; git -C "$up" tag vB
  git clone -q "$up" "$p/.workflow/fe-ai-workflow"; git -C "$p/.workflow/fe-ai-workflow" checkout -q vA
  echo '{"permissions":{"allow":["Bash(npm test)"]}}' > "$p/.claude/settings.json"
  (cd "$p" && .workflow/fe-ai-workflow/scripts/upgrade.sh vB > "$d/out" 2>&1)
}
cat > "$T/upgrade.old.sh" <<'OLD'
#!/usr/bin/env bash
# upgrade.sh — 在业务项目根目录执行：切换 submodule 到指定版本并重新安装
# 用法：.workflow/fe-ai-workflow/scripts/upgrade.sh <version-tag> [--migrate]
set -euo pipefail
V="${1:-}"; [[ -n "$V" ]] || { echo "Usage: $0 <version-tag> [--migrate]" >&2; exit 1; }
W=".workflow/fe-ai-workflow"; [[ -d "$W" ]] || { echo "未找到 $W" >&2; exit 1; }
git -C "$W" fetch --tags && git -C "$W" checkout "$V"
"$W/scripts/install.sh" "$W" . ${2:-}
echo "已升级到 ${V}，请提交 $W 及安装产物"
# 1.1.0 起 review / check 子进程要执行 knowledge.sh（以及 dev、docker 等），老项目 init 时没放行，升级后第一次派单就会报 error
if ! grep -q 'scripts/knowledge\.sh' .claude/settings.json 2>/dev/null; then
  echo "注意：本版本要求重跑 /viktor-init（重复执行模式）补齐放行规则——.claude/settings.json 里还没有 knowledge.sh 的放行，review / check 子进程会被权限拦下"
fi
OLD
set +e; up_test "$T/u-old" "$T/upgrade.old.sh"; rc_old=$?; up_test "$T/u-new" "$ROOT/scripts/upgrade.sh"; rc_new=$?; set -e
{ [[ $rc_old -ne 0 ]] || ! grep -q "重跑 /viktor-init" "$T/u-old/out"; } || fail "旧写法的 upgrade.sh 被原地覆盖后应出错或丢掉后半段（用例本身没能复现问题）"
[[ $rc_new -eq 0 ]] && grep -q "install-stub" "$T/u-new/out" && grep -q "已升级到 vB" "$T/u-new/out" && grep -q "重跑 /viktor-init" "$T/u-new/out" \
  || { cat "$T/u-new/out" >&2; fail "新写法的 upgrade.sh 执行中被原地覆盖后应正常完成并打印重跑 init 的提示（rc=${rc_new}）"; }
[[ "$(git -C "$T/u-new/proj/.workflow/fe-ai-workflow" describe --tags)" == vB ]] || fail "升级后 submodule 应在 vB"

echo "PASS"
