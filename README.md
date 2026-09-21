# ai-workflow

AI 辅助开发工作流：一个命令跑完需求，中间只在计划确认和异常时找你。基于原生 Agent Skills，兼容 Claude Code、OpenAI Codex、Cursor；前端、后端（Java 等）仓库各自独立使用。

## 安装 / 升级

在项目根目录执行（前后端通用，只需要 git；Windows 在 Git Bash 里执行）：

```bash
curl -fsSL https://raw.githubusercontent.com/sorryljt/ai-workflow/main/bootstrap.sh | bash              # 最新稳定版
curl -fsSL https://raw.githubusercontent.com/sorryljt/ai-workflow/main/bootstrap.sh | bash -s -- v1.2.0 # 指定版本
git add -A && git commit -m "chore: ai-workflow"
```

升级就是再跑一次。内网仓库用 `AI_WORKFLOW_REPO=<git 地址>` 指定来源。

首次安装后：在项目目录交互式打开一次 Claude Code 并选择信任工作区，然后运行 `/viktor-init`。升级后 CHANGELOG 若提到需要重跑 `/viktor-init`，重开会话执行一次。

Windows：需要 Git for Windows，Claude Code 的 hook 与子进程都在 Git Bash 里运行；Codex 建议在 WSL 中使用。

## 使用

| 命令 | 作用 |
|------|------|
| `/viktor-flow <需求>` | 判档后自动跑完整流程；不带参数则续接自己上次停下的需求 |
| `/viktor-init` | 探测并验证检查命令，写入 AGENTS.md，放行子进程权限，建知识库 |
| `/viktor-plan` | 需求澄清 + 任务拆分，产出 plan.md；M/L 档唯一需要你确认的节点 |
| `/viktor-code` | TDD 实现 |
| `/viktor-review` | 独立进程审查 diff；有 BLOCKING 自动修复复审，最多 2 轮 |
| `/viktor-check` | 独立进程逐条验证验收标准 |
| `/viktor-ship` | 交付报告 + 沉淀知识 + 标记完成 |

Codex 里用 `$viktor-flow`；也可以用自然语言描述意图。

### 分档

| 档位 | 判据 | 流程 |
|------|------|------|
| S | 无需人拍板的取舍，改动集中 | code → review → check → ship（全程自动） |
| M | 单个模块，有口径或取舍需要确认 | plan（等你确认）→ code → review → check → ship |
| L | 新增或修改数据模型 / 持久化结构（影响已有数据可读性、需要迁移或改主键 / 唯一约束），或跨多个模块 | plan（含任务清单）→ code → review → check → ship |

AI 判档后输出一行声明，觉得不对直接说"按 L 走"。

### 续接

任何会话输入 `/viktor-flow` 不带参数，从自己上次停下的节点继续；同一会话说"继续"也行。停下时只有一张卡，最后一行写清可以回复什么。别人的未完成需求不会被提示。

### Codex 用户注意

JVM 项目（Maven / Gradle）在 Codex 默认沙箱里跑不起测试，`/viktor-init` 会在 AGENTS.md 项目信息节写入 `- 子进程参数：codex --sandbox workspace-write -c sandbox_workspace_write.network_access=true`（Docker / Testcontainers 项目还会加上 socket 与环境变量）。**这会放开 review / check 子进程的外网访问**，不接受就删掉这一行，代价是 Codex 下 JVM 项目的独立验收会报 error。

## 产物

```
docs/
├── changes/YYYY-MM-DD--<slug>/
│   ├── plan.md      # status / stage 是需求状态的唯一来源
│   ├── review.md
│   ├── check.md
│   └── report.md
└── knowledge/
    ├── index.md               # 脚本维护，不要手改
    ├── decisions/YYYY-MM/*.md # 决策：为什么这么做
    ├── pitfalls/YYYY-MM/*.md  # 踩坑：别这么做
    └── glossary/YYYY-MM/*.md  # 术语：这个词在这里指什么
```

检查命令在 AGENTS.md 的 `viktor-checks` 块里，由 `/viktor-init` 写入，可以手改；命令以 AGENTS.md 所在目录为工作目录，子模块写进命令本身。

## 发布（维护者）

安装只认 `vX.Y.Z` tag。每次功能改动合到 main 后：CHANGELOG 的 `[Unreleased]` 定版 → README 示例版本号 → `bash scripts/validate.sh` → `git commit` → `git tag vX.Y.Z` → `git push && git push --tags`。改节点语义或要求重跑 init 升 minor，其余升 patch。

工作机制与设计记录见 [docs/design.md](docs/design.md)。
