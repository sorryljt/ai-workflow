# fe-ai-workflow

> AI 辅助开发工作流，基于原生 Agent Skills，兼容 Claude Code、OpenAI Codex、Cursor。前端与后端（Java 等）仓库各自独立使用，框架差异交给模型判断，不维护模板表。

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
| `/viktor-init` | 探测并逐条验证检查命令，写入 AGENTS.md（含运行前提），放行子进程权限，建知识库 |
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
| L | 新增或修改数据模型 / 持久化结构（给已有表加可空列、放宽或收紧请求校验边界不算，这两类按 M；只有影响已有数据可读性、需要迁移或改主键 / 唯一约束的才算 L），或跨多个模块 | plan（含任务清单）→ code → review → check → ship |

AI 判档后输出一行声明，觉得不对直接说"按 L 走"。

### 什么时候停

只在五处：plan 确认、缺前置、计划偏离、2 轮复审仍有 BLOCKING、验收修不好。停下时只有一张卡，最后一行写清可以回复什么。

**续接**：任何会话输入 `/viktor-flow` 不带参数，从自己上次停下的节点继续；同一会话说"继续"也行。别人的未完成需求不会被提示。

### 独立审查与验收

review / check 通过 `scripts/viktor-spawn.sh` 用 `claude -p` 或 `codex exec` 起新进程，同步等待，默认 480 秒超时。审查深度按档位限制，diff 超过 800 行不自动审。子进程不继承会话授权，`viktor-init` 会把检查命令写进 `.claude/settings.json` 的 `permissions.allow`；这些规则只在已信任的工作区生效，spawn 派 Claude 子进程前读取 `~/.claude.json` 中当前目录实际绝对路径的信任字段；项目或字段缺失、值非 `true` 时退出 2 并提示先信任。配置文件缺失或 node / python3 均不可用时跳过主动检测，仍保留日志关键字检测兜底。check 按每条 AC 选最小充分证据：涉及服务端数据、权限、契约、资金、幂等的 AC 默认关键，证据缺失就 `blocked`（退出码 4，不改代码，处理环境后重验）；非关键项测不到标 👀 待人工。没跑过 `/viktor-init` 的项目，plan 会先做一次不改配置的预检，命令以本轮配置传给子进程。

子进程不得提权：spawn 拒绝 `--dangerously-skip-permissions`、`bypassPermissions`、`danger-full-access` 等参数（退出码 2），主会话遇到权限问题只输出需要处理卡、不改参数重跑。Codex 下 JVM 项目（Maven / Gradle）在默认 `workspace-write` 沙箱里跑不起测试（Mockito 等需要 JVM self-attach，被沙箱的网络限制拦下），需要 `--sandbox workspace-write -c sandbox_workspace_write.network_access=true`：viktor-init 探测到 Maven / Gradle 时会在 AGENTS.md 项目信息节写入 `- 子进程参数：codex --sandbox workspace-write -c sandbox_workspace_write.network_access=true`，并在节点卡上注明。**这会放开 review / check 子进程的外网访问**，不接受的话删掉这一行（Codex 下 JVM 项目的独立验收会报 error）。`read-only` 连报告都写不了；`danger-full-access` 和 `--dangerously-*` 无论写在环境变量还是这一行都会被拒绝。

验证范围：Claude Code 端的各档位、续接、blocked / manual、交付报告都做过真实模型验证；**Codex 端只验证了基本流程**（S 档派单、JVM 项目的沙箱参数、子进程不提权）。

Codex 的 workspace-write 沙箱（含 network_access=true）会挡住 colima 的 Docker socket，Testcontainers 集成测试在 Codex 子进程里无法执行；涉及真实库证据的关键 AC 在 Codex 端会判 blocked，需要在 Claude Code 端验收。

实测（Vite + React + Vitest）：M 档一个需求 40 分钟左右，S 档 8 分钟；review 一轮 2～5 分钟，check 2～4 分钟。

## 接入

```bash
git submodule add https://github.com/sorryljt/fe-ai-workflow.git .workflow/fe-ai-workflow
cd .workflow/fe-ai-workflow && git checkout v1.1.1 && cd ../..
.workflow/fe-ai-workflow/scripts/install.sh .workflow/fe-ai-workflow .
git add -A && git commit -m "chore: add fe-ai-workflow"
```

然后在项目目录**交互式**打开一次 Claude Code 并选择信任工作区（未被信任时，`claude -p` 子进程会忽略 `.claude/settings.json` 的放行规则，review / check 第一次就会报 error；上级目录的信任不传递到独立 git 仓库），再运行 `/viktor-init`。升级：`.workflow/fe-ai-workflow/scripts/upgrade.sh <版本 tag>`。从 1.0.x 升到 1.1.0 时，第一次运行的是旧版脚本，不会检测放行规则；跑完后再运行一次同样的命令，或直接重跑 `/viktor-init`（重复执行模式）补齐放行规则，详见 CHANGELOG 的"从 1.0.x 升级"。

安装脚本写入 `.claude/skills/`、`.agents/skills/`、`.claude/hooks/viktor-gate.sh`、`.claude/settings.json`（合并 Stop hook，保留已有配置）、`AGENTS.md` 标记段、`CLAUDE.md` 一行 `@AGENTS.md`。Cursor 会同时扫描 `.agents/skills` 和 `.claude/skills`，如出现重复技能可删掉后者。

可选 postinstall：项目没有 postinstall 时 `npm pkg set scripts.postinstall=".workflow/fe-ai-workflow/scripts/install.sh .workflow/fe-ai-workflow . || true"`；已有的话追加为 `原命令 && (…install.sh … || true)`。

## 门禁

`viktor-init` 在 AGENTS.md 写入：

```viktor-checks
typecheck: pnpm tsc --noEmit
test: pnpm vitest run
verify: mvn verify           # 可选，完整验收，只有 check 跑
e2e: pnpm playwright test    # 可选
dev: pnpm dev                # 可选，启动入口
```

命令一律以 AGENTS.md 所在目录为工作目录，子模块写进命令本身（`mvn -pl server test`）。块后面的 `### 运行前提` 节写外部环境（数据库、容器运行时），会一起交给独立进程。

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

审查验收覆盖是硬规则：源码改动没有新增或修改测试直接 BLOCKING，S 档同样需要回归测试；仅 plan.md 对相应 AC 明确写“替代验证”并说明理由才可免测。spawn 会把缺测试提示追加到审查提示词。

Codex 的对话输出纪律与待确认卡、需要处理卡同步注入 AGENTS.md；节点卡标题仅限 INIT / PLAN / CODE / REVIEW / CHECK / SHIP，每个节点完成时只输出一张，复审通过必须输出 `✔ REVIEW` 卡。中途进度仅允许 `· AC-n ✔ <测试名>` 单行，不得制作进度、准备、收尾卡或自造标题；卡片外仅允许该进度单行及规定的未初始化备注，模板源仍保留在 skills 中。
