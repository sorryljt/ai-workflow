# todolist demo 交接文档

> 目的：用一个真实的小项目端到端验证 v1.0 工作流，记录耗时、token 与需要修正的地方。在 CLI（Claude Code 或 Codex）里做，不在 Cowork 里做。

## 0. 前置

- 工作流仓库已 push 到 `main`（含 viktor-flow / check / spawn）。
- 本机已登录 `claude` 或 `codex` CLI（独立进程审查依赖它）。
- 新建 demo 仓库（与业务无关），例如 `~/personWorkSpace/viktor-todo-demo`。

## 1. 步骤

### 1.1 建项目（不走工作流，普通 vibe coding）

```bash
npm create vite@latest viktor-todo-demo -- --template react-ts
cd viktor-todo-demo && npm i && git init && git add -A && git commit -m "init"
```

在 CLI 里让 AI 做一个最简单的 todolist：新增 / 勾选完成 / 删除，localStorage 持久化，带 Vitest + Testing Library。提交。

### 1.2 接入工作流

```bash
git submodule add https://github.com/sorryljt/fe-ai-workflow.git .workflow/fe-ai-workflow
.workflow/fe-ai-workflow/scripts/install.sh .workflow/fe-ai-workflow .
git add -A && git commit -m "chore: add fe-ai-workflow"
```

然后在 CLI 里运行 `/viktor-init`，确认 AGENTS.md 里生成了 `viktor-checks` 块（typecheck / lint / test，命令必须是非 watch 模式）。

### 1.3 三个档位各跑一遍（都用 `/viktor-flow <需求>`）

| 档位 | 需求文案（直接粘贴） | 预期 |
|---|---|---|
| S | 修一个 bug：刷新页面后，已勾选完成的待办变回未完成 | 不出 plan，自动跑到 report |
| M | 增加按状态筛选：全部 / 未完成 / 已完成，筛选状态刷新后保留 | 出 plan 停一次，确认后自动跑完 |
| L | 增加任务分组：可新建分组、把待办拖到分组里、分组内拖拽排序；已有数据自动归入"默认分组" | plan 含任务清单；check 里拖拽大概率是 👀 待人工 |

跑 S 档之前，先故意在代码里制造这个 bug（比如持久化时漏掉 completed 字段），否则 S 档没东西可修。

### 1.4 续接与打断（在 M 或 L 档上顺带验证）

- flow 跑到 review 时按 Esc 打断，手工改一行代码，再输入 `/viktor-flow`，看是否从复审续上。
- 开一个新会话直接输入 `/viktor-flow`，看是否列出 in-progress 需求。

## 2. 要记录的数据（写到 `docs/demo-results.md`，之后合并进 README）

| 项 | S | M | L |
|---|---|---|---|
| 各节点耗时（plan / code / review / check / ship） | | | |
| review 进程耗时、轮数、token（CLI 结束时的用量统计） | | | |
| check 进程耗时、👀 条目数 | | | |
| 停车次数与原因 | | | |
| 人工介入次数 | | | |

## 3. 必须实测的不确定项

1. `claude -p --permission-mode acceptEdits` 能否读仓库、跑 test、写 review.md；不行就调 `VIKTOR_CLAUDE_ARGS`（例如加 `--allowedTools`）。Codex 对应 `VIKTOR_CODEX_ARGS`（默认 `--sandbox workspace-write`）。
2. spawn 是否会撞到工具的命令超时（Claude Code Bash 工具默认约 2 分钟，可用 `BASH_MAX_TIMEOUT_MS` 调大）；撞到就把 `VIKTOR_SPAWN_TIMEOUT` 调小或启用 `--background`。
3. Stop hook 放行时的 `systemMessage` 是否真的显示给用户。
4. macOS 自带 bash 3.2 下 `viktor-gate.sh` / `viktor-spawn.sh` 能否运行（`bash --version` 看 CLI 用的是哪个）。
5. `/viktor-flow` 无参数时的"我的 in-progress"判断是否正确（作者、14 天）。

## 4. 记录问题的方式

发现工作流本身的问题（Skill 文案不清、脚本报错、停车点不对）：记在 `docs/demo-results.md` 的"问题清单"里，格式与 review 报告一致（路径、现象、建议），不要在 demo 里顺手改工作流仓库，回到 Cowork 会话统一改。
