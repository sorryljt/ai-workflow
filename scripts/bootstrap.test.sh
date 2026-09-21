#!/usr/bin/env bash
# bootstrap.sh 测试：用本地裸仓库模拟远端，覆盖首装 / 取最新 tag / 指定版本 / submodule 转换 / 重复执行
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail(){ echo "FAIL: $1" >&2; exit 1; }
G=(git -c user.email=a@b -c user.name=t -c commit.gpgsign=false)

# 模拟远端：当前仓库内容 + 三个 tag（v1.2.0 最大，v1.10.0-rc 不算稳定版，v9.0.0 不存在）
mkdir -p "$T/src"; (cd "$ROOT" && git ls-files -z | tar --null -T - -cf - 2>/dev/null || tar -cf - .) | (cd "$T/src" && tar -xf -)
cp "$ROOT/bootstrap.sh" "$T/src/"; cp "$ROOT/scripts/upgrade.sh" "$T/src/scripts/"
(cd "$T/src" && git init -q -b main && "${G[@]}" add -A && "${G[@]}" commit -q -m v1 && git tag v1.1.2 && git tag v1.2.0 && git tag v1.10.0-rc && git tag v1.9.0-beta.1)
git clone -q --bare "$T/src" "$T/remote.git"
export FE_AI_WORKFLOW_REPO="$T/remote.git"

# 1. 首装取最新稳定版（v1.2.0，而不是 v1.10.0-rc）；产物齐全；docs / 测试 / .git 不带进项目
mkdir -p "$T/p1"; cd "$T/p1"; git init -q -b main; "${G[@]}" commit -q --allow-empty -m init
bash "$T/src/bootstrap.sh" >"$T/out1" 2>&1 || { cat "$T/out1"; fail "首装失败"; }
[[ "$(cat .workflow/version)" == v1.2.0 ]] || fail "应装最新稳定版 v1.2.0，实际 $(cat .workflow/version)"
[[ -f .workflow/fe-ai-workflow/scripts/viktor-spawn.sh && -d .claude/skills/viktor-flow && -f .claude/hooks/viktor-gate.sh && -f AGENTS.md ]] || fail "安装产物不全"
[[ ! -d .workflow/fe-ai-workflow/.git && ! -d .workflow/fe-ai-workflow/docs ]] || fail "不应带 .git / docs"
ls .workflow/fe-ai-workflow/scripts/*.test.sh >/dev/null 2>&1 && fail "不应带测试文件" || true
grep -q "viktor-init" "$T/out1" || fail "首装应提示运行 /viktor-init"

# 2. 指定版本 + 不带 v 前缀；重复执行幂等；不存在的版本报错且不破坏现有安装
bash "$T/src/bootstrap.sh" 1.1.2 >/dev/null 2>&1 || fail "指定版本失败"
[[ "$(cat .workflow/version)" == v1.1.2 ]] || fail "应为 v1.1.2"
bash "$T/src/bootstrap.sh" v1.1.2 >"$T/out2" 2>&1 || fail "重复执行应成功"
grep -q "已是 v1.1.2" "$T/out2" || fail "重复执行应提示已是该版本"
bash "$T/src/bootstrap.sh" v9.0.0 >/dev/null 2>&1 && fail "不存在的版本应失败" || true
[[ "$(cat .workflow/version)" == v1.1.2 && -f .workflow/fe-ai-workflow/scripts/viktor-spawn.sh ]] || fail "失败后不应破坏现有安装"
grep -q "1.1.2 → " "$T/out2" && fail "同版本不应显示升级箭头" || true

# 3. 老项目：submodule → 纯文件副本，.gitmodules 与 .git/modules 清干净，安装产物照旧
mkdir -p "$T/p3"; cd "$T/p3"; git init -q -b main; "${G[@]}" commit -q --allow-empty -m init
git -c protocol.file.allow=always submodule add -q "$T/remote.git" .workflow/fe-ai-workflow 2>/dev/null
"${G[@]}" commit -q -m sub
bash "$T/src/bootstrap.sh" v1.2.0 >"$T/out3" 2>&1 || { cat "$T/out3"; fail "submodule 项目安装失败"; }
grep -q "submodule" "$T/out3" || fail "应提示转换 submodule"
[[ ! -f .gitmodules && ! -d .git/modules/.workflow ]] || fail "submodule 痕迹未清理"
[[ ! -d .workflow/fe-ai-workflow/.git ]] || fail "转换后不应有 .git"
git ls-files -s .workflow/fe-ai-workflow | grep -q "^160000" && fail "索引里仍是 gitlink" || true
"${G[@]}" add -A && "${G[@]}" commit -q -m upgrade && git ls-files .workflow/fe-ai-workflow/scripts/viktor-spawn.sh | grep -q . || fail "纯文件副本应可提交"

# 4. upgrade.sh 兼容入口：在被替换的目录里执行也能完整跑完
bash .workflow/fe-ai-workflow/scripts/upgrade.sh v1.1.2 >/dev/null 2>&1 || fail "upgrade.sh 转发失败"
[[ "$(cat .workflow/version)" == v1.1.2 ]] || fail "upgrade.sh 应升到 v1.1.2"

# 5. 不在 git 仓库内 → 报错
mkdir -p "$T/p5"; cd "$T/p5"; bash "$T/src/bootstrap.sh" >/dev/null 2>&1 && fail "非 git 目录应失败" || true
echo PASS
