#!/usr/bin/env bash
# install.sh — 把 ai-workflow 安装到业务项目
#
# 用法：<workflow-dir>/scripts/install.sh <workflow-dir> <project-dir>
#
# 安装内容：
#   skills/viktor-*             → .claude/skills/（Claude Code）、.agents/skills/（Codex、Cursor）
#   hooks/viktor-gate.sh        → .claude/hooks/
#   hooks/settings.snippet.json → 合并进 .claude/settings.json（需要 node 或 jq）
#   templates/AGENTS.snippet.md → AGENTS.md 标记段（保留用户内容）
#   CLAUDE.md                   → 标记段内一行 @AGENTS.md（CLAUDE.md 为软链接时跳过）
set -euo pipefail

SRC="${1:-}"; DST="${2:-}"
if [[ -z "$SRC" || -z "$DST" || ! -d "$SRC/skills" ]]; then
  echo "Usage: $0 <workflow-dir> <project-dir>" >&2; exit 1
fi
SRC="$(cd "$SRC" && pwd)"; mkdir -p "$DST"; DST="$(cd "$DST" && pwd)"
SETTINGS="$DST/.claude/settings.json"; SNIP="$SRC/hooks/settings.snippet.json"
if [[ -f "$SETTINGS" ]] && ! command -v node >/dev/null 2>&1 && ! command -v jq >/dev/null 2>&1; then
  echo "错误：需要 node 或 jq 才能把 hook 合并进已有的 ${SETTINGS}。请先安装其中一个，或手动合并 $SNIP 的内容" >&2; exit 1
fi

START="<!-- ai-workflow-start -->"
END="<!-- ai-workflow-end -->"
WARN=()

inject() {  # inject <snippet-file> <target-file>
  local snippet="$1" target="$2"
  if [[ ! -f "$target" ]]; then
    { echo "$START"; cat "$snippet"; echo "$END"; } > "$target"
  elif grep -qF "$START" "$target"; then
    if ! grep -qF "$END" "$target"; then
      echo "错误：$target 有起始标记但缺少结束标记，为避免丢失内容已跳过，请手动修复" >&2; exit 1
    fi
    awk -v s="$START" -v e="$END" -v src="$snippet" '
      $0==s { print; while ((getline l < src) > 0) print l; close(src); skip=1; next }
      $0==e { skip=0; print; next }
      !skip { print }' "$target" > "$target.tmp" && mv "$target.tmp" "$target"
  else
    { echo; echo "$START"; cat "$snippet"; echo "$END"; } >> "$target"
  fi
}

# 1. skills + prompts（prompts 由 viktor-spawn.sh 从工作流目录读取，无需拷贝）
for base in .claude/skills .agents/skills; do
  mkdir -p "$DST/$base"
  for s in "$SRC"/skills/viktor-*; do
    rm -rf "$DST/$base/$(basename "$s")"; cp -R "$s" "$DST/$base/"
  done
done

# 2. hook 脚本 + settings 合并（已有 viktor-gate 条目时用最新 snippet 替换）
mkdir -p "$DST/.claude/hooks"
cp "$SRC/hooks/viktor-gate.sh" "$DST/.claude/hooks/viktor-gate.sh"; chmod +x "$DST/.claude/hooks/viktor-gate.sh"
printf '*.sh text eol=lf\n' > "$DST/.claude/hooks/.gitattributes"   # Windows 下 autocrlf 不得把 hook 转成 CRLF
if [[ ! -f "$SETTINGS" ]]; then
  cp "$SNIP" "$SETTINGS"
elif command -v node >/dev/null 2>&1; then
  node - "$SETTINGS" "$SNIP" <<'JS' || { echo "错误：$SETTINGS 不是合法 JSON，未修改。请手动把 hooks/settings.snippet.json 的内容合并进去" >&2; exit 1; }
const fs=require('fs');const [,,target,snip]=process.argv;
const add=JSON.parse(fs.readFileSync(snip,'utf8'));
const cur=JSON.parse(fs.readFileSync(target,'utf8'));
cur.hooks=cur.hooks||{};
for(const ev of Object.keys(add.hooks)){
  const kept=(cur.hooks[ev]||[]).filter(e=>!JSON.stringify(e).includes('viktor-gate.sh'));
  cur.hooks[ev]=[...kept,...add.hooks[ev]];
}
fs.writeFileSync(target,JSON.stringify(cur,null,2)+'\n');
JS
else
  jq -s '.[0] as $c | .[1] as $a | $c | .hooks = (($c.hooks // {}) + {Stop: ([(($c.hooks // {}).Stop // [])[] | select((tostring|contains("viktor-gate.sh"))|not)] + $a.hooks.Stop)})' "$SETTINGS" "$SNIP" > "$SETTINGS.tmp" \
    && mv "$SETTINGS.tmp" "$SETTINGS" || { rm -f "$SETTINGS.tmp"; echo "错误：$SETTINGS 不是合法 JSON，未修改" >&2; exit 1; }
fi

# 3. AGENTS.md 注入段 + CLAUDE.md 引用
inject "$SRC/templates/AGENTS.snippet.md" "$DST/AGENTS.md"
if [[ -L "$DST/CLAUDE.md" ]]; then
  WARN+=("CLAUDE.md 是软链接，未修改")
else
  TMP="$(mktemp)"; printf '@AGENTS.md\n' > "$TMP"; inject "$TMP" "$DST/CLAUDE.md"; rm -f "$TMP"
  if [[ $(grep -cv '^\s*$\|ai-workflow-\|^@AGENTS.md$' "$DST/CLAUDE.md") -gt 0 ]]; then
    WARN+=("CLAUDE.md 已有其他内容，请检查是否与 AGENTS.md 重复")
  fi
fi

echo "ai-workflow 已安装到 $DST"
for w in "${WARN[@]:-}"; do [[ -n "$w" ]] && echo "提示：$w"; done
echo "下一步：在项目中运行 /viktor-init 生成项目信息"
