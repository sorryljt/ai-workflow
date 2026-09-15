#!/usr/bin/env bash
# upgrade.sh — 在业务项目根目录执行：切换 submodule 到指定版本并重新安装
# 用法：.workflow/fe-ai-workflow/scripts/upgrade.sh <version-tag> [--migrate]
set -euo pipefail
V="${1:-}"; [[ -n "$V" ]] || { echo "Usage: $0 <version-tag> [--migrate]" >&2; exit 1; }
W=".workflow/fe-ai-workflow"; [[ -d "$W" ]] || { echo "未找到 $W" >&2; exit 1; }
git -C "$W" fetch --tags && git -C "$W" checkout "$V"
"$W/scripts/install.sh" "$W" . ${2:-}
echo "已升级到 $V，请提交 $W 及安装产物"
