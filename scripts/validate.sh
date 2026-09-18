#!/usr/bin/env bash
# validate.sh — 校验本仓库结构：5 个 skill 的 frontmatter、hook、入口片段
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
P=0; F=0
ok(){ echo "✅ $1"; P=$((P+1)); }; bad(){ echo "❌ $1"; F=$((F+1)); }
for n in flow init plan code review check ship; do
  f="skills/viktor-$n/SKILL.md"
  [[ -f $f ]] && ok "存在 $f" || { bad "缺少 $f"; continue; }
  grep -q "^name: viktor-$n$" "$f" && ok "  name 正确" || bad "  name 与目录不一致"
  d=$(sed -n 's/^description: //p' "$f"); [[ -n $d && ${#d} -le 1024 ]] && ok "  description 非空且 ≤1024 字" || bad "  description 缺失或过长"
  grep -q "viktor-$n" templates/AGENTS.snippet.md && ok "  入口片段提及该节点" || bad "  入口片段未提及该节点"
done
[[ -x hooks/viktor-gate.sh ]] && ok "hook 脚本可执行" || bad "hook 脚本不可执行"
for r in review check; do [[ -f prompts/$r.md ]] && grep -q "{{CHANGES_DIR}}" prompts/$r.md && ok "prompts/$r.md 存在且含变量" || bad "prompts/$r.md 缺失或无变量"; done
for r in review check; do grep -q "{{CHECKS}}" prompts/$r.md && ok "prompts/$r.md 接收运行配置 {{CHECKS}}" || bad "prompts/$r.md 缺 {{CHECKS}}"; done
grep -q "^pending:" prompts/check.md && grep -q "blocked" prompts/check.md && grep -q "关键 AC" prompts/check.md && ok "check.md 含五态与关键 AC 规则" || bad "check.md 缺五态 / 关键 AC 规则"
grep -q "verified.inputs" skills/viktor-flow/SKILL.md && grep -q "inputs-digest" skills/viktor-check/SKILL.md && ok "续接：flow 对 verified.inputs，check 写入" || bad "续接缺 verified.inputs"
for n in plan code review check; do grep -q "本轮运行配置\|--checks" skills/viktor-$n/SKILL.md && ok "viktor-$n 处理未初始化的运行配置" || bad "viktor-$n 未处理运行配置"; done
grep -q "未验证" skills/viktor-init/SKILL.md && ok "init 有命令验证协议" || bad "init 缺验证协议"
grep -q "不修改约定和禁区" skills/viktor-init/SKILL.md && ok "init 重复执行保留约定和禁区" || bad "init 缺用户内容保护规则"
[[ -x scripts/viktor-spawn.sh ]] && ok "viktor-spawn.sh 可执行" || bad "viktor-spawn.sh 不可执行"
[[ -x scripts/knowledge.sh ]] && ok "knowledge.sh 可执行" || bad "knowledge.sh 不可执行"
grep -q viktor-gate.sh hooks/settings.snippet.json && ok "settings 片段引用 hook" || bad "settings 片段未引用 hook"
[[ $(wc -l < templates/AGENTS.snippet.md) -le 110 ]] && ok "入口片段（含卡片模板）≤110 行" || bad "入口片段过长"
res=$(grep -rnE "viktor:[a-z]|superpowers|workflow\.mdc|1% 规则|反理由|活文档|/viktor-(think|cr|doc|contract|context|digest)" skills templates hooks README.md 2>/dev/null | grep -v "从 v0.8.x 升级\|migrate\|upgrade-workflow\|v0 的" || true)
[[ -z "$res" ]] && ok "skills/templates/hooks/README 无 v0 术语残留" || { bad "v0 术语残留："; echo "$res"; }
echo "----"; echo "$P 通过 / $F 失败"; [[ $F -eq 0 ]]
