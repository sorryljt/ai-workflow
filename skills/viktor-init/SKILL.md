---
name: viktor-init
description: 首次接入 viktor 工作流时初始化项目：探测技术栈和检查命令，把项目信息写入 AGENTS.md，并创建 docs/knowledge/。用户输入 /viktor-init 或提到 viktor-init、首次接入工作流，或者其他节点发现 AGENTS.md 缺少 viktor-checks 块时使用。可以重复执行。
---

# viktor-init：项目初始化

目标是给 Agent 提供它从代码里不容易得到、却每次都需要的信息：检查命令、主干分支、非显而易见的约定、禁区。

## 步骤

1. **探测**：框架、包管理器、测试框架，以及 dev / build / lint / typecheck / test 对应的命令。
2. **补齐测试能力**：没有测试框架时，推荐一个与技术栈匹配的方案并说明理由，用户同意后再安装。
3. **询问**（一次性提出）：探测不到的约定和禁区，例如生成代码的目录、禁止修改的文件、提交规范、主干分支名。
4. **写入 AGENTS.md**：在 `<!-- fe-ai-workflow-end -->` 标记之后写入或更新“项目信息”节。这一节在标记之外，重新安装工作流时不会被覆盖。

   ````markdown
   ## 项目信息（viktor-init）
   - 技术栈：<框架 / 语言 / 状态管理 / 测试框架>
   - 包管理器：<pnpm / npm / yarn>
   - 主干分支：main

   ```viktor-checks
   typecheck: pnpm tsc --noEmit
   lint: pnpm eslint .
   test: pnpm vitest run
   e2e: pnpm playwright test
   dev: pnpm dev
   ```

   ### 约定（只写不明显的）
   - …

   ### 禁区
   - …（不要写 ".claude/ 由安装脚本维护"：settings.json 的 permissions 由本节点维护，用户也可以手工改）
   ````

   `viktor-checks` 块的规则（Stop hook 会直接执行它）：
   - 每行 `key: 命令`，命令必须单行、非交互、非 watch 模式（例如用 `vitest run` 而不是 `vitest`）。
   - 项目没有的检查直接省略该行，不写占位符。
   - monorepo：AGENTS.md 放在哪个目录，命令就在哪个目录执行；会话从子包启动时优先读子包的 AGENTS.md。
   - `e2e`、`dev` 供 viktor-code / viktor-check 使用，hook 不执行。
5. **放行检查命令**：review / check 在独立进程（`claude -p`）中运行，不继承当前会话的授权。把 `viktor-checks` 里的每条命令（`dev` 除外）写进 `.claude/settings.json` 的 `permissions.allow`，形如 `Bash(npm test)`、`Bash(npm run typecheck)`；测试框架的直接调用也放行一条（例如 `Bash(npx vitest run:*)`）。已有的规则保留，不重复添加。`install.sh` / `upgrade.sh` 合并 settings.json 时只替换 viktor-gate 的 hook 条目，`permissions` 原样保留。
6. **确保有基线 commit**：`git rev-parse HEAD` 失败（仓库还没有任何提交）时，提示用户先提交一次，否则独立审查拿不到 diff。
7. **创建知识目录**：运行 `bash <workflow-dir>/scripts/knowledge.sh rebuild` 生成 `docs/knowledge/index.md`（目录不存在会创建）。若发现旧格式的 `docs/knowledge/decisions.md` / `pitfalls.md` / `glossary.md`，先运行 `knowledge.sh migrate` 拆成条目文件。

## 节点卡（完成后只输出这个）

```
━━ ✔ INIT ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
技术栈    <框架 / 测试框架 / 包管理器>
检查命令  typecheck ✅ lint ✅ test ✅ e2e — dev ✅（已放行 <n> 条）
产物      AGENTS.md 项目信息 · docs/knowledge/ · .claude/settings.json
下一步    /viktor-flow <需求>
```

## 重复执行

已有“项目信息”节时，只提出与探测结果的差异，用户确认后再更新；不修改用户在其他位置写的内容。
