#!/usr/bin/env bash
# knowledge.sh — docs/knowledge/ 的检索与维护
#
#   knowledge.sh lookup <路径或关键词>...   打印命中的 active 条目全文（按适用范围 / 标题做子串匹配，大小写不敏感）
#   knowledge.sh add --type decision|pitfall|glossary --title "…" --scope "a,b" [--source "…"] < 正文
#   knowledge.sh supersede <条目路径> <新条目路径>   把旧条目标为 superseded
#   knowledge.sh rebuild                    从条目 frontmatter 重建 index.md；适用范围路径不存在的标 ?
#   knowledge.sh migrate                    把旧的 decisions.md / pitfalls.md / glossary.md 拆成条目文件
#
# 目录：docs/knowledge/{decisions,pitfalls,glossary}/YYYY-MM/<slug>.md，index.md 每行：类型 | 状态 | 标题 | 适用范围 | 路径
set -uo pipefail
K="${VIKTOR_KNOWLEDGE_DIR:-docs/knowledge}"
IDX="$K/index.md"
cmd="${1:-}"; shift || true

fm() { sed -n '1,/^---$/{/^---$/d;p;}' "$1" | sed -n "s/^$2:[[:space:]]*//p" | head -1 | sed 's/^"\(.*\)"$/\1/'; }
slugify() { printf '%s' "$1" | tr -cs 'A-Za-z0-9一-鿿' '-' | sed 's/^-//; s/-$//' | cut -c1-60; }

rebuild() {
  mkdir -p "$K"
  { echo "# 知识索引（由 knowledge.sh rebuild 生成，不要手工编辑）"; echo; echo "类型 | 状态 | 标题 | 适用范围 | 路径"; }
  find "$K" -mindepth 2 -name '*.md' | sort | while read -r f; do
    t="$(fm "$f" type)"; st="$(fm "$f" status)"; ti="$(fm "$f" title)"; sc="$(fm "$f" scope)"
    [[ -z "$t" || -z "$ti" ]] && continue
    st="${st:-active}"; flag=""
    if [[ "$st" == active ]]; then
      IFS=',' read -ra parts <<<"$sc"
      for p in "${parts[@]}"; do p="$(printf '%s' "$p" | sed 's/^ *//; s/ *$//')"
        [[ "$p" != *" "* && ( "$p" == */* || "$p" == *.* ) && ! -e "$p" ]] && flag="?"; done
    fi
    echo "$t | ${flag}${st} | $ti | $sc | ${f#"$K"/}"
  done
} 
case "$cmd" in
  rebuild) rebuild > "$IDX.tmp" && mv "$IDX.tmp" "$IDX"; echo "已重建 $IDX（$(grep -c ' | ' "$IDX") 条，含表头）";;
  lookup)
    [[ -f "$IDX" ]] || { echo "无 $IDX" >&2; exit 0; }
    [[ $# -gt 0 ]] || { echo "Usage: knowledge.sh lookup <路径或关键词>..." >&2; exit 2; }
    hits=()
    while IFS= read -r line; do
      [[ "$line" == *" | "* ]] || continue
      st="$(printf '%s' "$line" | awk -F' \\| ' '{print $2}')"; [[ "$st" == active || "$st" == "?active" ]] || continue
      ti="$(printf '%s' "$line" | awk -F' \\| ' '{print $3}')"; sc="$(printf '%s' "$line" | awk -F' \\| ' '{print $4}')"; path="$(printf '%s' "$line" | awk -F' \\| ' '{print $5}')"
      hay="$(printf '%s %s' "$ti" "$sc" | tr 'A-Z' 'a-z')"
      for term in "$@"; do
        lt="$(printf '%s' "$term" | tr 'A-Z' 'a-z')"
        if [[ "$hay" == *"$lt"* ]]; then hits+=("$path"); break; fi
        # 适用范围是目录前缀时，路径术语也命中（scope "src/" vs term "src/App.tsx"）
        IFS=',' read -ra parts <<<"$sc"
        for p in "${parts[@]}"; do p="$(printf '%s' "$p" | sed 's/^ *//; s/ *$//' | tr 'A-Z' 'a-z')"; [[ -n "$p" && "$lt" == "$p"* ]] && { hits+=("$path"); break 2; }; done
      done
    done < "$IDX"
    [[ ${#hits[@]} -eq 0 ]] && { echo "（无相关知识）"; exit 0; }
    printf '%s\n' "${hits[@]}" | sort -u | while read -r p; do echo "===== $p"; cat "$K/$p"; echo; done;;
  add)
    type=""; title=""; scope=""; source=""
    while [[ $# -gt 0 ]]; do case "$1" in --type) type="$2"; shift 2;; --title) title="$2"; shift 2;; --scope) scope="$2"; shift 2;; --source) source="$2"; shift 2;; *) echo "未知参数 $1" >&2; exit 2;; esac; done
    case "$type" in decision) dir=decisions;; pitfall) dir=pitfalls;; glossary) dir=glossary;; *) echo "--type 必须是 decision|pitfall|glossary" >&2; exit 2;; esac
    [[ -n "$title" && -n "$scope" ]] || { echo "需要 --title 与 --scope" >&2; exit 2; }
    ym="$(date +%Y-%m)"; d="$K/$dir/$ym"; mkdir -p "$d"
    f="$d/$(slugify "$title").md"; n=2; while [[ -e "$f" ]]; do f="$d/$(slugify "$title")-$n.md"; n=$((n+1)); done
    body="$(cat)"
    { echo "---"; echo "type: $type"; echo "title: \"$title\""; echo "status: active"; echo "scope: $scope"; echo "source: $source"; echo "date: $(date +%F)"; echo "---"; echo; echo "$body"; } > "$f"
    "$0" rebuild >/dev/null; echo "$f";;
  supersede)
    old="$1"; new="$2"; [[ -f "$K/$old" || -f "$old" ]] || { echo "找不到 $old" >&2; exit 2; }
    f="$K/$old"; [[ -f "$f" ]] || f="$old"
    sed -i.bak "s/^status:.*/status: superseded/" "$f" && rm -f "$f.bak"
    grep -q '^superseded_by:' "$f" && sed -i.bak "s#^superseded_by:.*#superseded_by: $new#" "$f" && rm -f "$f.bak" || sed -i.bak "s#^status: superseded#status: superseded\nsuperseded_by: $new#" "$f" && rm -f "$f.bak"
    "$0" rebuild >/dev/null; echo "已标记 $f 为 superseded";;
  migrate)
    ym="$(date +%Y-%m)"
    for pair in decisions:decision pitfalls:pitfall glossary:glossary; do
      file="$K/${pair%%:*}.md"; type="${pair##*:}"; dir="$K/${pair%%:*}/$ym"
      [[ -f "$file" ]] || continue
      mkdir -p "$dir"
      awk -v dir="$dir" -v type="$type" '
        function flush(){ if(title!=""){ fn=title; gsub(/[ \t\/`:：,，。;；|｜()（）"'"'"'<>]+/,"-",fn); sub(/^-+/,"",fn); sub(/-+$/,"",fn); fn=dir "/" substr(fn,1,60) ".md";
          printf "---\ntype: %s\ntitle: \"%s\"\nstatus: active\nscope: %s\nsource: %s\ndate: %s\n---\n\n%s\n", type, title, scope, source, date, body > fn; close(fn); n++ }
          title=""; body=""; scope=""; source=""; date="" }
        /^## /{ flush(); title=substr($0,4); next }
        title!="" && /^- 日期：/{ line=$0; sub(/^- 日期：/,"",line); split(line,a,/ *[｜|] *来源：/); date=a[1]; source=a[2]; next }
        title!="" && /^- 适用范围：/{ line=$0; sub(/^- 适用范围：/,"",line); gsub(/`/,"",line); gsub(/[；、]/,",",line); gsub(/。$/,"",line); scope=line; next }
        title!="" && /^- 内容：/{ line=$0; sub(/^- 内容：/,"",line); body=body line "\n"; next }
        title!="" { body=body $0 "\n" }
        END{ flush(); print n+0 > "/dev/stderr" }' "$file" 2>&1 | tail -1 | xargs -I{} echo "$file → {} 条"
      mv "$file" "$file.migrated"
    done
    "$0" rebuild;;
  *) sed -n '2,12p' "$0"; exit 2;;
esac
