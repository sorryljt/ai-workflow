# fe-ai-workflow

> 前端团队 AI 辅助开发工作流，基于原生 Agent Skills，兼容 Claude Code、OpenAI Codex、Cursor。

## 原则

1. 5 个节点都是标准 Agent Skill，一份源文件装到各端。
2. 按任务规模分档，小改动不走完整流程。
3. 门禁用命令而不是提示词：Stop hook 自动跑 typecheck / lint / test。
4. 只沉淀代码里读不出来的知识；按改动范围检索，不整目录读。
5. TDD 是核心；review 和 check 在独立进程里做，不自己审自己。
6. 一个入口自动跑完，人只在 plan 确认和异常时介入；状态只在磁盘，随时可停、可续。

## 节点

| 命令 | 作用 |
|------|------|
| `/viktor-flow <需求>` | 判档后自动跑完整流程；不带参数则续接自己上次停下的需求 |
| `/viktor-init` | 探测技术栈和检查命令，写入 AGENTS.md，放行子进程权限，建知识库 |
| `/viktor-plan` | 需求澄清 + 任务拆分，产出 plan.md；M/L 档唯一需要人确认的节点 |
| `/viktor-code` | TDD 实现，每一步有真实测试输出 |
| `/viktor-review` | 独立进程审查 diff，输出问题清单；有 BLOCKING 自动修复复审，最多 2 轮 |
| `/viktor-check` | 独立进程以用户视角逐条验证验收标准 |
| `/viktor-ship` | 交付报告 + 沉淀知识 + 标记完成 |

Codex 里用 `$viktor-flow`；也可以用自然语言描述意图。

### 分档

| 档位 | 判据 | 流程 |
|------|------|------|
| S | 无需人拍板的取舍，改动集中 | code → review → check → ship（全程自动） |
| M | 单个模块，有口径或取舍需要确认 | plan（等你确认）→ code → review → check → ship |
| L | 改数据模型或跨多个模块 | plan（含任务清单）→ code → review → check → ship |

AI 判档后输出一行声明，觉得不对直接说"按 L 走"。

### 什么时候停

只在五处：plan 确认、缺前置、计划偏离、2 轮复审仍有 BLOCKING、验收修不好。停下时只有一张卡，最后一行写清可以回复什么。

**续接**：任何会话输入 `/viktor-flow` 不带参数，从自己上次停下的节点继续；同一会话说"继续"也行。别人的未完成需求不会被提示。

### 独立审查与验收

review / check 通过 `scripts/viktor-spawn.sh` 用 `claude -p` 或 `codex exec` 起新进程，同步等待，默认 480 秒超时。审查深度按档位限制，diff 超过 800 行不自动审。子进程不继承会话授权，`viktor-init` 会把检查命令写进 `.claude/settings.json` 的 `permissions.allow`。`claude -p` 内没有浏览器工具，check 用测试作证据，UI 层面标 👀 待人工。

实测（Vite + React + Vitest）：M 档一个需求 40 分钟左右，S 档 8 分钟；review 一轮 2～5 分钟，check 2～4 分钟。

## 接入

```bash
git submodule add https://github.com/sorryljt/fe-ai-workflow.git .workflow/fe-ai-workflow
cd .workflow/fe-ai-workflow && git checkout v1.0.1 && cd ../..
.workflow/fe-ai-workflow/scripts/install.sh .workflow/fe-ai-workflow .
git add -A && git commit -m "chore: add fe-ai-workflow"
```

然后重开 AI 会话，运行 `/viktor-init`。升级：`.workflow/fe-ai-workflow/scripts/upgrade.sh <版本 tag>`。

安装脚本写入 `.claude/skills/`、`.agents/skills/`、`.claude/hooks/viktor-gate.sh`、`.claude/settings.json`（合并 Stop hook，保留已有配置）、`AGENTS.md` 标记段、`CLAUDE.md` 一行 `@AGENTS.md`。Cursor 会同时扫描 `.agents/skills` 和 `.claude/skills`，如出现重复技能可删掉后者。

可选 postinstall：项目没有 postinstall 时 `npm pkg set scripts.postinstall=".workflow/fe-ai-workflow/scripts/install.sh .workflow/fe-ai-workflow . || true"`；已有的话追加为 `原命令 && (…install.sh … || true)`。

## 门禁

`viktor-init` 在 AGENTS.md 写入：

```viktor-checks
typecheck: pnpm tsc --noEmit
test: pnpm vitest run
e2e: pnpm playwright test    # 可选
dev: pnpm dev                # 可选
```

Stop hook 只在源码改动指纹变化时运行 typecheck / lint / test；失败反馈给 Agent 修复，同一回合连续 3 次失败后放行并提示用户。支持 git worktree 和 monorepo 子包。命令必须是非 watch 模式。

## 产物

```
docs/
├── changes/YYYY-MM-DD--<slug>/
│   ├── plan.md      # status / stage 是需求状态的唯一来源
│   ├── review.md
│   ├── check.md
│   └── report.md
└── knowledge/
    ├── index.md               # 脚本维护
    ├── decisions/YYYY-MM/*.md
    ├── pitfalls/YYYY-MM/*.md
    └── glossary/YYYY-MM/*.md
```

知识一条一个文件，`scope` 写它约束的路径 / 模块 / 场景；各节点用 `scripts/knowledge.sh lookup <路径> <关键词>` 只读命中的条目。被推翻的条目标 `superseded` 保留；`rebuild` 时路径失效标 `?`。旧格式用 `knowledge.sh migrate` 拆分。

## 仓库结构

```
skills/viktor-*/SKILL.md       # 唯一真相源
prompts/review.md | check.md   # 独立进程的提示词
hooks/                         # Stop hook
templates/AGENTS.snippet.md    # 注入业务项目的入口段
scripts/                       # install / upgrade / validate / viktor-spawn / knowledge + 测试
```

开发本仓库：`bash scripts/validate.sh`，`bash scripts/install.test.sh`，`bash scripts/spawn.test.sh`，`bash scripts/knowledge.test.sh`。

设计文档：`docs/2026-09-15--v1-redesign.md`、`docs/2026-09-16--flow-and-independent-review.md`；审查记录：`docs/2026-09-15--v1-review.md`；验收记录：`docs/2026-09-16--demo-results.md`。
