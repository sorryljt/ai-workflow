#!/usr/bin/env bash
# validate.sh — 校验本仓库结构：5 个 skill 的 frontmatter、hook、入口片段
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
P=0; F=0
ok(){ echo "✅ $1"; P=$((P+1)); }; bad(){ echo "❌ $1"; F=$((F+1)); }
for n in init plan code review ship; do
  f="skills/viktor-$n/SKILL.md"
  [[ -f $f ]] && ok "存在 $f" || { bad "缺少 $f"; continue; }
  grep -q "^name: viktor-$n$" "$f" && ok "  name 正确" || bad "  name 与目录不一致"
  d=$(sed -n 's/^description: //p' "$f"); [[ -n $d && ${#d} -le 1024 ]] && ok "  description 非空且 ≤1024 字" || bad "  description 缺失或过长"
  grep -q "viktor-$n" templates/AGENTS.snippet.md && ok "  入口片段提及该节点" || bad "  入口片段未提及该节点"
done
[[ -x hooks/viktor-gate.sh ]] && ok "hook 脚本可执行" || bad "hook 脚本不可执行"
grep -q viktor-gate.sh hooks/settings.snippet.json && ok "settings 片段引用 hook" || bad "settings 片段未引用 hook"
[[ $(wc -l < templates/AGENTS.snippet.md) -le 40 ]] && ok "入口片段 ≤40 行" || bad "入口片段过长"
res=$(grep -rnE "viktor:[a-z]|superpowers|workflow\.mdc|1% 规则|反理由|活文档|/viktor-(think|cr|doc|contract|context|digest)" skills templates hooks README.md 2>/dev/null | grep -v "从 v0.8.x 升级\|migrate\|upgrade-workflow\|v0 的" || true)
[[ -z "$res" ]] && ok "skills/templates/hooks/README 无 v0 术语残留" || { bad "v0 术语残留："; echo "$res"; }
echo "----"; echo "$P 通过 / $F 失败"; [[ $F -eq 0 ]]
