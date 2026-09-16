## fe-ai-workflow（viktor）

本项目使用 viktor AI 开发工作流。技能：viktor-flow（自动流水线 / 续接），以及可单独调用的 viktor-init、viktor-plan、viktor-code、viktor-review、viktor-check、viktor-ship。

### 开始任何开发任务前：先判断档位，只输出一行声明（`▶ M 档  plan（等你确认）→ code → …`，不写理由；用户可以改）

| 档位 | 判据 | 流程 |
|------|------|------|
| S | 不新增数据结构，改动集中在 1～2 个文件，一个 TDD 循环能完成 | code → review → check → ship（全自动） |
| M | 不新增持久化数据结构，涉及单个模块，2～5 个验收标准 | plan（人确认）→ code → review → check → ship |
| L | 新增或修改数据模型 / 持久化结构，或跨两个以上模块，或需要拆成多个任务 | plan（含任务清单，人确认）→ code → review → check → ship |

给出完整需求时优先用 viktor-flow 跑完整流程；用户说“继续”“接着上次的”时用 viktor-flow 续接。做到一半发现范围超出档位：停下来说明，建议升档。流程停下时只输出待确认卡或需要处理卡，卡片之外不写段落，卡里不写续接命令。

调用方式：Claude Code、Cursor 输入 `/viktor-flow` 等；Codex 输入 `$viktor-flow`；或用自然语言描述意图。首次接入先运行 viktor-init。

### 约定

- 需求产物放在 `docs/changes/YYYY-MM-DD--<slug>/`（slug 用英文 kebab-case）：plan.md、review.md、check.md、report.md。plan.md frontmatter 的 `status` / `stage` / `stage_result` 是需求状态的唯一来源；每个节点只从磁盘取输入，人随时可以停、插话、手工修改，之后用 viktor-flow 续接。
- Agent 能直接读代码，所以不维护组件清单、接口清单；`docs/knowledge/` 只放代码里读不出来的知识（decisions / pitfalls / glossary，一条一个文件）。取知识只用 `bash .workflow/fe-ai-workflow/scripts/knowledge.sh lookup <路径或关键词>`，不要整目录读。
- M/L 档：plan 经用户确认之前，不写实现代码。
- review 和 check 在独立进程中执行（`scripts/viktor-spawn.sh`），避免自己审自己。
- 所有“已完成”“已通过”的说法，都要有本轮真实运行命令的输出作为依据。
- 检查命令记录在下方 `viktor-checks` 块中。Claude Code 中 Stop hook 会自动运行 typecheck / lint / test；其他工具中，结束前手动运行。
- 除非用户要求，不自动 commit。
