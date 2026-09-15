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
$2
F
  chmod +x "$T/bin/$1"
}
run(){ PATH="$T/bin:/usr/bin:/bin" VIKTOR_WORKFLOW_DIR="$ROOT" "$SPAWN" "$@"; }

# 1. claude 正常写 review.md → 0；提示词中变量已替换；默认参数传入
mkfake claude "printf -- '---\nresult: pass\n---\n# r\n' > $D/review.md"
rm -f "$T/bin/codex"
run review "$D" >/dev/null || fail "pass 应返回 0"
grep -q "{{" "$D/.review.prompt.md" && fail "提示词变量未替换" || true
grep -q "档位：M" "$D/.review.prompt.md" || fail "档位未从 plan.md 读取"
grep -q -- "--permission-mode" "$T/args.claude" || fail "claude 默认参数未传入"

# 2. blocked → 1
mkfake claude "printf -- '---\nresult: blocked\n---\n' > $D/review.md"
set +e; run review "$D" >/dev/null; rc=$?; set -e; [[ $rc -eq 1 ]] || fail "blocked 应返回 1，实际 $rc"

# 3. 进程退出但无产物 → 2（旧文件存在但未更新也算）
mkfake claude "true"; touch -d '2000-01-01' "$D/review.md" 2>/dev/null || touch -t 200001010000 "$D/review.md"
set +e; run review "$D" >/dev/null 2>&1; rc=$?; set -e; [[ $rc -eq 2 ]] || fail "无产物应返回 2，实际 $rc"

# 4. 超时 → 2
mkfake claude "sleep 30"
set +e; VIKTOR_SPAWN_TIMEOUT=2 run review "$D" >/dev/null 2>&1; rc=$?; set -e; [[ $rc -eq 2 ]] || fail "超时应返回 2，实际 $rc"
grep -q TIMEOUT "$D/.review.log" || fail "超时未记录日志"

# 5. 无 CLI → 3，提示词文件存在
rm -f "$T/bin/claude"
set +e; run review "$D" >/dev/null 2>"$T/err"; rc=$?; set -e; [[ $rc -eq 3 ]] || fail "无 CLI 应返回 3，实际 $rc"
grep -q ".review.prompt.md" "$T/err" || fail "无 CLI 时未提示手动方式"

# 6. codex 回退 + check 的 manual → 0，failed → 1
mkfake codex "printf -- '---\nresult: manual\n---\n' > $D/check.md"
run check "$D" | grep -q "待人工" || fail "check manual 应返回 0 并提示"
grep -q "^exec$" "$T/args.codex" && grep -q -- "--sandbox" "$T/args.codex" || fail "codex 调用方式错误"
mkfake codex "printf -- '---\nresult: failed\n---\n' > $D/check.md"
set +e; run check "$D" >/dev/null; rc=$?; set -e; [[ $rc -eq 1 ]] || fail "check failed 应返回 1"

# 7. VIKTOR_AGENT 强制选择；后台模式写 .done
mkfake claude "printf -- '---\nresult: pass\n---\n' > $D/review.md"
mkfake codex "exit 9"
VIKTOR_AGENT=claude run review "$D" >/dev/null || fail "VIKTOR_AGENT=claude 应选择 claude"
rm -f "$D/.review.done"; VIKTOR_AGENT=claude run review "$D" --background >/dev/null
for i in 1 2 3 4 5; do [[ -f "$D/.review.done" ]] && break; sleep 1; done
[[ "$(cat "$D/.review.done")" == "0" ]] || fail "后台模式未写 .done=0"
echo PASS
