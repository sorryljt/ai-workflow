#!/usr/bin/env bash
# bootstrap.sh — 一条命令安装 / 升级 ai-workflow（前端、后端仓库通用，只需要 git；Windows 在 Git Bash 里执行）
#
#   curl -fsSL https://raw.githubusercontent.com/sorryljt/ai-workflow/main/bootstrap.sh | bash              # 最新稳定版
#   curl -fsSL https://raw.githubusercontent.com/sorryljt/ai-workflow/main/bootstrap.sh | bash -s -- v1.1.2 # 指定版本
#
# 做的事：把指定 tag 的纯文件副本（不带 .git）放到 .workflow/ai-workflow，写 .workflow/version，执行 install.sh。
# 版本以仓库里的 .workflow/version 为准，提交后团队拿到的是同一份；升级就是再跑一次。
# 内网仓库：AI_WORKFLOW_REPO=https://gitlab.example.com/x/ai-workflow.git
set -euo pipefail

main() {

  REPO="${AI_WORKFLOW_REPO:-https://github.com/sorryljt/ai-workflow.git}"
  W=".workflow/ai-workflow"
  V="${1:-}"

  command -v git >/dev/null 2>&1 || { echo "需要 git" >&2; exit 1; }
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "请在 git 仓库内执行（当前目录不在任何仓库里）" >&2; exit 1; }
  cd "$ROOT"

  # 最新稳定版 = 形如 vX.Y.Z 的最大 tag（不含预发布），不用 sort -V，macOS 也能跑
  if [[ -z "$V" ]]; then
    V="$(git ls-remote --tags --refs "$REPO" 'refs/tags/v*' 2>/dev/null \
        | awk -F/ '{print $NF}' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
        | sed 's/^v//' | awk -F. '{printf "%06d%06d%06d v%s\n",$1,$2,$3,$0}' | sort | tail -1 | cut -d' ' -f2)"
    [[ -n "$V" ]] || { echo "无法从 $REPO 取到版本 tag（网络或权限？）" >&2; exit 1; }
  fi
  [[ "$V" == v* ]] || V="v$V"

  CUR="$(cat .workflow/version 2>/dev/null || true)"
  [[ "$CUR" == "$V" ]] && echo "当前已是 ${V}，重新安装以修复产物" || echo "安装 ai-workflow ${V}${CUR:+（当前 ${CUR}）}"

  TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
  git clone -q --depth 1 --branch "$V" "$REPO" "$TMP/src" || { echo "拉取 ${V} 失败：tag 不存在或无法访问 $REPO" >&2; exit 1; }
  rm -rf "$TMP/src/.git" "$TMP/src/docs" "$TMP/src/Claude outputs"; rm -f "$TMP/src"/scripts/*.test.sh
  # Windows：项目若开了 autocrlf，靠这份 .gitattributes 保证脚本保持 LF
  [[ -f "$TMP/src/.gitattributes" ]] || printf '* text=auto\n*.sh text eol=lf\n' > "$TMP/src/.gitattributes"

  mkdir -p .workflow
  rm -rf "$W"; mv "$TMP/src" "$W"
  printf '%s\n' "$V" > .workflow/version

  bash "$W/scripts/install.sh" "$W" .

  echo
  if [[ -z "$CUR" ]]; then
    echo "完成。接下来：git add -A && git commit -m 'chore: add ai-workflow ${V}'，然后重开 AI 会话运行 /viktor-init"
  elif [[ "$CUR" == "$V" ]]; then
    echo "完成。已重新安装 ${V}，如有变化请提交"
  else
    echo "完成。接下来：git add -A && git commit -m 'chore: ai-workflow ${CUR} → ${V}'；CHANGELOG 若提到需要重跑 /viktor-init，重开会话后执行一次"
  fi
}

# 全部放进 main 再调用：本文件可能就在被替换的目录里，bash 边读边执行会读到新文件的中间
main "$@"; exit $?
