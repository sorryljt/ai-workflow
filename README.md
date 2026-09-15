# fe-ai-workflow

> 前端团队 AI 辅助开发工作流 v1.0，基于原生 Agent Skills，兼容 Claude Code、OpenAI Codex、Cursor。
>
> 状态：v1.0.0 开发中，已通过三轮独立审查（见 `docs/2026-09-15--v1-review.md`），等待 todolist demo 按 S/M/L 完成端到端验收后打 tag。

## 设计原则

1. **原生优先**：5 个节点全部是标准 Agent Skill（SKILL.md），按 description 自动触发，也可用命令显式调用。一份源文件安装到各端的技能目录。
2. **按规模分档**：流程的重量由任务大小决定。小改动只走 code → review，不强迫走完整流程。
3. **确定性门禁**：能用命令检查的不写成 prompt 规则。Claude Code 通过 Stop hook 自动运行 typecheck / lint / test，失败则反馈给 Agent 修复（连续 3 次失败后放行并提示用户）；其他工具在结束前手动运行。
4. **只沉淀非推导知识**：Agent 能直接读代码，所以不维护组件清单、接口清单。只记录决策原因、踩坑和业务术语。
5. **TDD 是核心**：测试是验收标准的可执行形式，也是 Agent 最可靠的自我纠错信号。
6. **不自己审自己**：review 和 check 在独立进程中执行（同一工具、新会话），审查者没有实现过程的记忆，只看 diff 和验收标准。
7. **自动执行，磁盘即状态**：一个入口跑完整个流程，人只在 plan 确认和异常时介入；状态只存在 plan.md 里，人随时可以停、插话、手工改，再用 viktor-flow 续接。

## 节点

| 命令 | 节点 | 作用 |
|------|------|------|
| `/viktor-flow` | 流水线 | `/viktor-flow <需求>` 跑完整流程：判档 → plan（M/L 档人确认）→ code → review → check → ship；`/viktor-flow` 不带参数续接自己未完成的需求（继续 / 归档 / 忽略） |
| `/viktor-init` | 初始化 | 探测技术栈和检查命令，写入 AGENTS.md 项目信息，创建 `docs/knowledge/`；可重复执行 |
| `/viktor-plan` | 计划 | 需求澄清 + 任务拆分合并为一份 plan.md（目标 / 方案 / 影响范围 / 验收标准 / 假设）；M/L 档唯一需要人工确认的环节 |
| `/viktor-code` | 实现 | TDD 循环：RED → GREEN → REFACTOR，每一步都要有真实运行的测试输出；类型定义作为第一个任务直接写进 src |
| `/viktor-review` | 审查 | 派发独立进程基于 diff 审查，输出问题清单（BLOCKING / SUGGESTED）；有 BLOCKING 自动修复并复审，最多 2 轮复审 |
| `/viktor-check` | 验收 | 派发独立进程以用户视角逐条验证 AC：e2e → 浏览器实际操作 → 给出手动步骤（👀 待人工） |
| `/viktor-ship` | 收尾 | 生成交付报告 report.md（待人工确认项放最前、本轮做了什么、审查记录），沉淀非推导知识，标记需求完成 |

三端统一使用技能名：Claude Code、Cursor 输入 `/viktor-plan` 等，Codex 输入 `$viktor-plan` 或直接提到技能名；也可以用自然语言描述意图。

### 分档

| 档位 | 场景 | 流程 |
|------|------|------|
| S | 不新增数据结构，改动集中在 1～2 个文件 | code → review → check → ship（全自动） |
| M | 不新增持久化结构，单个模块，2～5 个验收标准 | plan（人确认）→ code → review → check → ship |
| L | 新增/修改数据模型或持久化结构，或跨两个以上模块 | plan（含任务清单，人确认）→ code → review → check → ship |

Agent 在开始时声明档位，用户可以修改。

### 停车点

流程只在五处停：plan 确认、缺前置（无 viktor-checks / 无测试框架）、计划偏离或需升档、2 轮复审后仍有 BLOCKING、验收修复一次后仍失败。其余情况不问不等。停下后人可以手工改代码、在会话里补要求、或者干脆不管；`/viktor-flow` 从停下的节点续接，别人留下的未完成需求不会被提示。

### 独立审查与验收的成本

review / check 通过 `scripts/viktor-spawn.sh` 用 `claude -p` 或 `codex exec` 起新进程，同步等待，默认 480 秒超时。审查者只审 diff 范围、按档位限制深度（S 只看 diff 并重跑 test；M 对照 AC；L 才允许隔离实验），diff 超过 800 行不自动审。复审只审修复部分。两个 CLI 都没有时打印提示词，人开新窗口粘贴即可。

各端的权限参数（`VIKTOR_CLAUDE_ARGS` / `VIKTOR_CODEX_ARGS`）、一次审查的耗时和 token 用量待 demo 实测后补充到这里。

## 接入

在业务项目根目录执行：

```bash
git submodule add https://github.com/sorryljt/fe-ai-workflow.git .workflow/fe-ai-workflow
cd .workflow/fe-ai-workflow && git checkout <版本 tag> && cd ../..
.workflow/fe-ai-workflow/scripts/install.sh .workflow/fe-ai-workflow .
git add -A && git commit -m "chore: add fe-ai-workflow"
```

然后在 AI 工具中运行 `/viktor-init`。

可选：让 `npm install` 自动重新安装。项目**没有** postinstall 时执行
`npm pkg set scripts.postinstall=".workflow/fe-ai-workflow/scripts/install.sh .workflow/fe-ai-workflow . || true"`；
已有 postinstall（husky、patch-package、prisma generate 等）时，改为 `原命令 && (.workflow/fe-ai-workflow/scripts/install.sh .workflow/fe-ai-workflow . || true)`，不要覆盖原命令，也不要让 `|| true` 吞掉原命令的失败。

### 从 v0.8.x 升级

v0 的 `upgrade-workflow.sh` 依赖已删除的 `sync-workflow.sh`，不能直接用。步骤：

```bash
cd .workflow/fe-ai-workflow && git fetch --tags && git checkout <版本 tag> && cd ../..
.workflow/fe-ai-workflow/scripts/install.sh .workflow/fe-ai-workflow . --migrate
```

`--migrate` 只删除 v0.8.x 实际分发过的文件（`skills/01-*`…`09-*`、`using-fe-workflow`、`references/` 中的 4 个规范、`.claude/commands/viktor/` 中的 9 个命令、`.cursor/rules/workflow.mdc`），不碰用户自己的文件。业务项目 `docs/` 下的 v0 产物（specs / plans / contracts / reviews / adrs / project-context 等）不会被删除，由你决定保留或清理。

安装脚本会写入：

```
.claude/skills/viktor-*/      # Claude Code
.agents/skills/viktor-*/      # Codex、Cursor
.claude/hooks/viktor-gate.sh  # Stop hook 门禁（合并进 .claude/settings.json，需要 node 或 jq）
AGENTS.md                     # 标记段内注入入口说明，用户内容保留
CLAUDE.md                     # 标记段内一行 @AGENTS.md；CLAUDE.md 是软链接时跳过
```

Cursor 会同时扫描 `.agents/skills` 和 `.claude/skills`，是否对同名技能去重未经确认；如果出现重复，删除 `.claude/skills/viktor-*` 不影响 Cursor 使用。

v1 内升级：`.workflow/fe-ai-workflow/scripts/upgrade.sh v1.x.x`

### 门禁工作方式

`viktor-init` 会在 AGENTS.md 项目信息中写入一个 `viktor-checks` 块：

```viktor-checks
typecheck: pnpm tsc --noEmit
test: pnpm vitest run
e2e: pnpm playwright test    # 可选，viktor-check 使用
dev: pnpm dev                # 可选，viktor-check 用浏览器验证时启动
```

Stop hook 在回合结束前读取它（支持 git worktree 和 monorepo 子包：AGENTS.md 先在会话目录找，再到仓库根找，命令在找到的目录执行）。只有源码有改动、且改动指纹与上次通过时不同才运行；纯文档改动（`docs/changes/`、`docs/knowledge/`、`*.md`）、非 git 目录直接放行。失败则把输出反馈给 Agent（exit 2），同一回合连续 3 次失败后放行并通过 `systemMessage` 提示用户；找不到 `viktor-checks` 块时也会提示。hook 超时 300 秒，命令必须是非 watch 模式。

## 产物

```
docs/
├── changes/YYYY-MM-DD--<slug>/
│   ├── plan.md        # frontmatter：status / tier / stage / stage_result / review_round，需求状态的唯一来源
│   ├── review.md      # 独立审查结果
│   ├── check.md       # 独立验收结果
│   └── report.md      # 交付报告
└── knowledge/
    ├── decisions.md   # 有被否决备选方案、且理由从代码看不出来的决策
    ├── pitfalls.md    # 踩坑、必须确认事项、高危约束
    └── glossary.md    # 业务术语、枚举语义、隐含规则
```

## 仓库结构

```
skills/viktor-*/SKILL.md       # 唯一真相源（flow / init / plan / code / review / check / ship）
prompts/review.md | check.md   # 独立进程使用的审查 / 验收提示词
hooks/                         # Stop hook 门禁脚本与 settings 片段
templates/AGENTS.snippet.md    # 注入业务项目的入口段
scripts/install.sh | upgrade.sh | validate.sh | viktor-spawn.sh
scripts/install.test.sh | spawn.test.sh
```

开发本仓库：`bash scripts/validate.sh` 校验结构，`bash scripts/install.test.sh` 跑安装与 hook 测试，`bash scripts/spawn.test.sh` 跑独立进程派发测试。

## 相关文档

- `docs/2026-09-15--v1-redesign.md`：v1.0 重构方案与最终决定
- `docs/2026-09-15--v1-review.md`：三轮独立审查报告及处理记录
- `docs/2026-09-16--flow-and-independent-review.md`：viktor-flow 自动流水线与独立审查 / 验收的设计
- `CHANGELOG.md`：版本变更
