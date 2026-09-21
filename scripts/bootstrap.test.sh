#!/usr/bin/env bash
# bootstrap.sh 测试：用本地裸仓库模拟远端，覆盖首装 / 取最新 tag / 指定版本 / 重复执行
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail(){ echo "FAIL: $1" >&2; exit 1; }
G=(git -c user.email=a@b -c user.name=t -c commit.gpgsign=false)

# 模拟远端：当前仓库内容 + 三个 tag（v1.2.0 最大，v1.10.0-rc 不算稳定版，v9.0.0 不存在）
mkdir -p "$T/src"; (cd "$ROOT" && tar -cf - --exclude=.git --exclude=docs .) | (cd "$T/src" && tar -xf -)
cp "$ROOT/bootstrap.sh" "$T/src/"
(cd "$T/src" && git init -q -b main && "${G[@]}" add -A && "${G[@]}" commit -q -m v1 && git tag v1.1.2 && git tag v1.2.0 && git tag v1.10.0-rc && git tag v1.9.0-beta.1)
git clone -q --bare "$T/src" "$T/remote.git"
export AI_WORKFLOW_REPO="$T/remote.git"

# 1. 首装取最新稳定版（v1.2.0，而不是 v1.10.0-rc）；产物齐全；docs / 测试 / .git 不带进项目
mkdir -p "$T/p1"; cd "$T/p1"; git init -q -b main; "${G[@]}" commit -q --allow-empty -m init
bash "$T/src/bootstrap.sh" >"$T/out1" 2>&1 || { cat "$T/out1"; fail "首装失败"; }
[[ "$(cat .workflow/version)" == v1.2.0 ]] || fail "应装最新稳定版 v1.2.0，实际 $(cat .workflow/version)"
[[ -f .workflow/ai-workflow/scripts/viktor-spawn.sh && -d .claude/skills/viktor-flow && -f .claude/hooks/viktor-gate.sh && -f AGENTS.md ]] || fail "安装产物不全"
[[ ! -d .workflow/ai-workflow/.git && ! -d .workflow/ai-workflow/docs ]] || fail "不应带 .git / docs"
ls .workflow/ai-workflow/scripts/*.test.sh >/dev/null 2>&1 && fail "不应带测试文件" || true
grep -q "viktor-init" "$T/out1" || fail "首装应提示运行 /viktor-init"

# 2. 指定版本 + 不带 v 前缀；重复执行幂等；不存在的版本报错且不破坏现有安装
bash "$T/src/bootstrap.sh" 1.1.2 >/dev/null 2>&1 || fail "指定版本失败"
[[ "$(cat .workflow/version)" == v1.1.2 ]] || fail "应为 v1.1.2"
bash "$T/src/bootstrap.sh" v1.1.2 >"$T/out2" 2>&1 || fail "重复执行应成功"
grep -q "已是 v1.1.2" "$T/out2" || fail "重复执行应提示已是该版本"
bash "$T/src/bootstrap.sh" v9.0.0 >/dev/null 2>&1 && fail "不存在的版本应失败" || true
[[ "$(cat .workflow/version)" == v1.1.2 && -f .workflow/ai-workflow/scripts/viktor-spawn.sh ]] || fail "失败后不应破坏现有安装"
grep -q "1.1.2 → " "$T/out2" && fail "同版本不应显示升级箭头" || true

# 5. 不在 git 仓库内 → 报错
mkdir -p "$T/p5"; cd "$T/p5"; bash "$T/src/bootstrap.sh" >/dev/null 2>&1 && fail "非 git 目录应失败" || true
echo PASS
