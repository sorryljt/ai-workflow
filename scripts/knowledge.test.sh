#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; KS="$ROOT/scripts/knowledge.sh"
fail(){ echo "FAIL: $1" >&2; exit 1; }
lk(){ "$KS" lookup "$@" > "$T/lk.out" || true; cat "$T/lk.out"; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cd "$T"; mkdir -p src docs/knowledge; touch src/App.tsx src/useTodos.ts

# 1. add + rebuild + index 格式
f1=$(printf '不加 maxLength，否则提示永远不出现\n' | "$KS" add --type pitfall --title "输入框不能加 maxLength" --scope "src/App.tsx, 编辑框" --source "docs/changes/x/")
[[ -f "$f1" ]] || fail "add 未创建文件"
grep -q "^pitfall | active | 输入框不能加 maxLength | src/App.tsx, 编辑框 | pitfalls/" docs/knowledge/index.md || fail "索引行格式错误：$(cat docs/knowledge/index.md)"
f2=$(printf '按码点数计\n' | "$KS" add --type decision --title "长度按码点数计" --scope "src/validateTodoText.ts")
f3=$(printf '两条都未完成且 trim 后全等\n' | "$KS" add --type glossary --title "待办重复的判定口径" --scope "查重, src/")
[[ $(grep -c ' | ' docs/knowledge/index.md) -eq 4 ]] || fail "索引应有 3 条 + 表头"

# 2. lookup：路径命中、目录前缀命中、关键词命中、不命中
lk src/App.tsx | grep -q "maxLength" || fail "路径未命中"
lk src/App.tsx | grep -q "长度按码点数计" && fail "不相关条目被命中" || true
lk src/useTodos.ts | grep -q "待办重复" || fail "目录前缀 scope（src/）未命中"
lk 查重 | grep -q "待办重复" || fail "关键词未命中"
lk nothing-here | grep -q "无相关知识" || fail "无命中时应提示"

# 3. supersede：旧条目不再被检索；索引状态更新
f4=$(printf '改为字素簇\n' | "$KS" add --type decision --title "长度按字素簇计" --scope "src/validateTodoText.ts")
"$KS" supersede "${f2#docs/knowledge/}" "${f4#docs/knowledge/}" >/dev/null
grep -q "^status: superseded" "$f2" && grep -q "^superseded_by: " "$f2" || fail "supersede 未写入状态"
lk src/validateTodoText.ts | grep -q "码点数" && fail "superseded 条目仍被检索" || true
lk src/validateTodoText.ts | grep -q "字素簇" || fail "新条目未被检索"

# 4. rebuild：scope 路径不存在时标 ?，且仍可检索（只是提示）
rm src/App.tsx; "$KS" rebuild >/dev/null
grep -q "^pitfall | ?active | 输入框不能加 maxLength" docs/knowledge/index.md || fail "路径消失未标 ?"
lk src/App.tsx | grep -q "maxLength" || fail "?active 应仍可检索"

# 5. migrate：旧三文件拆分
mkdir -p "$T/m/docs/knowledge"; cd "$T/m"
cat > docs/knowledge/pitfalls.md <<'M'
# 踩坑记录（pitfalls）

## 新待办输入框不能加 HTML maxLength
- 日期：2026-09-16 ｜ 来源：docs/changes/2026-09-16--input-validation/
- 内容：故意不设 maxLength，否则提示永远不出现。
- 适用范围：`src/App.tsx` 的 `.add-form` input；将来编辑框同理。

## 子进程需要预先放行
- 日期：2026-09-16 ｜ 来源：docs/changes/2026-09-16--input-validation/
- 内容：在 settings.json 放行检查命令。
  第二行内容。
- 适用范围：`.claude/settings.json`
M
"$KS" migrate >/dev/null
[[ $(find docs/knowledge/pitfalls -name '*.md' | wc -l) -eq 2 ]] || fail "migrate 应拆出 2 条，实际 $(find docs/knowledge/pitfalls -name '*.md')"
[[ -f docs/knowledge/pitfalls.md.migrated && ! -f docs/knowledge/pitfalls.md ]] || fail "旧文件未改名"
lk src/App.tsx | grep -q "maxLength" || fail "迁移后检索失败"
lk .claude/settings.json | grep -q "第二行内容" || fail "多行内容丢失"
echo PASS
