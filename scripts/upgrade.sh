#!/usr/bin/env bash
# upgrade.sh — 兼容入口：转发给 bootstrap.sh（安装和升级现在是同一条命令）
# 用法：.workflow/fe-ai-workflow/scripts/upgrade.sh [version-tag]
set -euo pipefail
main() {
  local here tmp; here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; tmp="$(mktemp)"
  if [[ -f "$here/bootstrap.sh" ]]; then cp "$here/bootstrap.sh" "$tmp"; bash "$tmp" "$@"; rm -f "$tmp"
  else curl -fsSL https://raw.githubusercontent.com/sorryljt/fe-ai-workflow/main/bootstrap.sh | bash -s -- "$@"; fi
}
main "$@"; exit $?
