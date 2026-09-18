#!/usr/bin/env bash
# upgrade.sh — 在业务项目根目录执行：切换 submodule 到指定版本并重新安装
# 用法：.workflow/fe-ai-workflow/scripts/upgrade.sh <version-tag> [--migrate]
#
# 本文件就在被升级的 submodule 里，执行途中会被 checkout 换成新版本。bash 边读边执行，
# 换文件后会按旧偏移读到新文件的中间。所以全部逻辑放进 main，最后一行调用并 exit：
# bash 先读完整个函数定义再执行，之后不再读本文件。
set -euo pipefail

main() {
  local V="${1:-}" W=".workflow/fe-ai-workflow"
  [[ -n "$V" ]] || { echo "Usage: $0 <version-tag> [--migrate]" >&2; return 1; }
  [[ -d "$W" ]] || { echo "未找到 $W" >&2; return 1; }
  git -C "$W" fetch --tags
  git -C "$W" checkout "$V"
  "$W/scripts/install.sh" "$W" . ${2:-}
  echo "已升级到 ${V}，请提交 $W 及安装产物"
  # 1.1.0 起 review / check 子进程要执行 knowledge.sh（以及 dev、docker 等），老项目 init 时没放行，升级后第一次派单就会报 error
  if ! grep -q 'scripts/knowledge\.sh' .claude/settings.json 2>/dev/null; then
    echo "注意：本版本要求重跑 /viktor-init（重复执行模式）补齐放行规则——.claude/settings.json 里还没有 knowledge.sh 的放行，review / check 子进程会被权限拦下"
  fi
}

main "$@"; exit $?
