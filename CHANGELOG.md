# Changelog

本文件记录 fe-ai-workflow 的所有版本变更。
格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/)。

---

## [1.1.2] - 2026-09-19

### Fixed

- P15：Claude 派单前读取 `~/.claude.json`，匹配 `$PWD`、物理路径、git 根目录及 worktree 主仓库路径；任一为 `true` 即通过，无明确记录时只警告并继续，明确为 `false` 且没有候选为 `true` 时退出 2 并提示交互式信任。文件缺失或 node / python3 均不可用时跳过主动检测，保留日志关键字兜底；新增隔离 HOME 的派单测试。
- P20：plan / code 预检逐键给出 typecheck / lint / test / verify / e2e / dev 的推导来源，能推导出的键一条都不能省，推导不出的键省略且注明；dev 仅记录启动入口，预检不启动服务。
- P21：重复 init 仅对“项目信息”中的探测字段提差异；约定和禁区一律不提差异、不修改，并增加结构校验断言。README 与入口片段同步规则。

### 验证与已知限制

- Codex / colima：在原 writable_roots + DOCKER_HOST 基础上，禁用 Ryuk、再叠加 HOST_OVERRIDE 两个假设各试一次，完整 verify 均退出 0（27 单元 + 10 集成，零失败 / 错误 / 跳过）。README 和 init 写入最小通过组合：network_access=true、colima 可写目录、DOCKER_HOST、TESTCONTAINERS_RYUK_DISABLED=true；HOST_OVERRIDE 不默认写入。移除对应已知问题，记录禁用 Ryuk 的回收前提。
- spawn 支持项目“子进程参数”里的分组引号，以保留 Codex 环境配置的 TOML 字符串；不允许 shell 展开或运算符，解析后再次拒绝提权参数，补充参数传递和拒绝绕过测试。
- 发布检查：validate.sh、spawn.test.sh、install.test.sh、knowledge.test.sh。

## [1.1.1] - 2026-09-19

### Fixed

- P24：review 将源码缺回归测试视为 BLOCKING，S 档同样适用；只有 plan.md 对对应 AC 明确说明替代验证及理由才可免测。spawn 在派单前按本轮审查范围提示缺测试，覆盖首次审查与复审。
- P25：卡片模板与对话输出纪律同步进 AGENTS.snippet 并注入 AGENTS.md，以提高 Codex 遵从度；安装测试核对模板完整性。
- P26：节点卡标题白名单为 INIT / PLAN / CODE / REVIEW / CHECK / SHIP，每个节点完成时只输出一张；中途进度只允许 `· AC-n ✔ <测试名>` 单行，不得自造标题或制作进度、准备、收尾卡；review 复审通过必须输出 `✔ REVIEW` 卡。

## [1.1.0] - 2026-09-18

### 从 1.0.x 升级

1. 在项目根目录运行 `.workflow/fe-ai-workflow/scripts/upgrade.sh v1.1.0`。
2. **跑完后再运行一次同样的命令，或者直接重跑 `/viktor-init`（重复执行模式），回复"按探测结果更新"。** 第一次运行的是 1.0.x 里的旧版 upgrade.sh，它不会检测放行规则；部分 1.0.x 版本在 bash 3.2 下最后一行还会报 `unbound variable` 并以非零退出，这时 submodule 和安装产物其实已经更新好了。第二次运行的是 1.1.0 的脚本，它发现 `.claude/settings.json` 缺少 `knowledge.sh` 放行时会提示重跑 init。
3. 为什么必须重跑 init：1.1.0 的 review / check 子进程要执行 `knowledge.sh`、按需启动 `dev`，运行前提涉及 Docker 时还要 `docker ps/rm/run/stop`，老项目 init 时没有放行这些命令；子进程现在只执行给定命令，被拒就报 error、不再绕过，所以不重跑 init，第一次 flow 就会停在 review 需要处理卡。JVM 项目重跑 init 时还会写入 Codex 子进程参数（见 F16）。（F14）
4. 放行规则只在已信任的工作区生效：升级或接入后在项目目录交互式打开一次 Claude Code 并选择信任。

### Added（后端仓库支持与验收证据）

- 提示词中立化：review / check 不再假设前端技术栈；review 按 diff 内容附加后端审查项（迁移安全与恢复、鉴权正反例、幂等、外部调用超时与副作用、分页 / N+1），前端仓库触发不到。
- 关键 AC 与最低证据：服务端数据写入 / 迁移 / 删除、权限与租户隔离、对外契约、资金计费、幂等重试默认关键；plan 里降级要写理由；check 按 AC 选最小充分证据，运行前提不满足不用 mock 顶替。
- check 结果五态：`pass` / `manual` / `failed` / `blocked` / `error`，混合时按 failed > blocked > error > manual > pass 取一个；`blocked` 对应 spawn 退出码 4，不改业务代码，处理环境后重验。
- 续接顺序：先对 `verified.review` 的代码指纹，再对 `verified.inputs` 的验收输入摘要（`viktor-spawn.sh inputs-digest`），blocked / error 节点重跑；任何情况不绕过 review。
- `viktor-init` 验证协议：命令逐条跑过才算"已验证"（test 看执行数 / 跳过数 / 目标模块），验证不了写原因、不换命令；记录运行前提。
- 未初始化的项目：plan / code 做不修改项目配置的预检，写进 plan.md `## 本轮运行配置`，review / check 派单以 `--checks` 传给子进程；项目出现 `viktor-checks` 块后以项目为准。
- 命令按用途分：`typecheck` / `lint` / `test` 是快速检查（hook 与 code 完成时执行），`verify` 是完整验收入口（只有 check 执行，可选），`dev` 是启动入口不等待退出；init 模板加 `### 运行前提` 节（环境与就绪条件），spawn 连同块一起交给子进程；工作目录只有一种约定——AGENTS.md 所在目录，子模块写进命令本身。
- spawn：子进程在独立进程组中运行，超时整组终止，正常结束后同组残留进程也收尾；check 登记的容器 / 目录按 run_id 归属、pid 按进程组归属，其余只报告；配置里没有任何一条非空的已支持命令时拒绝派单（退出码 2），子进程不自行探测；`inputs-digest` 找不到 `## 验收标准` 节直接报错。
- 续接：未进入审查的需求（stage 为 plan / code）直接按表恢复，不比指纹；无 viktor-checks 块不再作为停下的条件。

### Fixed（两轮后端真实模型验证后，见 docs/2026-09-18--validation-fixes.md）

- spawn 拒绝子进程提权：`VIKTOR_CLAUDE_ARGS` 含 `--dangerously-skip-permissions` / `bypassPermissions`、`VIKTOR_CODEX_ARGS` 含 `danger-full-access` / `--dangerously-bypass-approvals-and-sandbox` 时退出 2、不派单；Codex 需要更宽沙箱时只从 AGENTS.md 项目信息节的 `- 子进程参数：codex --sandbox <值>` 读取（同样拒绝 `danger-full-access`）。review / check 遇到退出码 2 不得改参数重跑。（F1）
- 未信任工作区：子进程失败或报 error 且日志含 `has not been trusted` 时，spawn 退出 2 并提示先在项目目录交互式信任；README 接入步骤与 viktor-init 同步说明，上级目录的信任不传递到独立 git 仓库。（F2）
- 子进程只执行本轮运行配置里的命令，认为命令有问题时报 `result: error`，不替换成 AGENTS.md / README 或自己推导的命令；spawn 对报告里引用的配置外构建命令给出警告（不拦）。（F3）
- viktor-init 放行清单固定：检查命令原样 + 构建工具通配 + `knowledge.sh` + `dev` + 运行前提涉及 Docker 时的 `docker ps/rm/run/stop`；check 只在 AC 需要运行中的服务时才启动 dev。（F4）
- 资源登记适配测试框架：子进程不自行创建容器，只登记直接创建的临时目录 / pid；Testcontainers 容器由 ryuk 回收，spawn 超时时兜底清理本轮新出现的 `org.testcontainers.sessionId` 容器。（F5）
- viktor-check / viktor-review 给出 blocked / error 需要处理卡模板，不再各自发挥。（F6）
- 交付报告的"待人工"只取 check.md 的 `pending`，条数与状态条一致；review 的 SUGGESTED 一律进剩余 SUGGESTED。（F7）
- 预检列全 `typecheck` / `lint` / `test` / `verify` / `e2e` / `dev`，完整验收放 `verify`、`e2e` 只放端到端测试；写 plan.md 去掉模板行尾注释；init 节点卡"检查命令"只用 ✅ / — / 未验证。（F8）
- L 档判据细化：给已有表加可空列、放宽或收紧请求校验边界按 M；影响已有数据可读性、需要迁移或改主键 / 唯一约束才算 L。（F9）
- spawn 默认给 claude 子进程加 `--output-format stream-json --verbose`，`.review.log` / `.check.log` 保留完整事件流。（F10）

### Fixed（修复后回归，见 docs/2026-09-18--regression-0564e95.md、docs/2026-09-18--regression-fixes.md）

- check 环境探测直接执行命令：不再用 `timeout` 包裹（macOS 没有）、不把报错丢进 `/dev/null`；"命令不存在"不算环境不可用，换一条直接命令再探。修掉了 macOS 上 check 误判 blocked 的问题。（F11）
- review / check 的检查命令单独执行，不加管道、重定向、`;`、`&&`、`$?`（放行规则只匹配单条命令）；需要明细去读测试报告。（F12）
- 提示词里的 `knowledge.sh` 改用相对项目根目录的路径（`.workflow/fe-ai-workflow/…`），与 init 写的放行规则一致，子进程第一次调用不再被拒。（F13）
- upgrade.sh 检测到缺少 `knowledge.sh` 放行时提示重跑 `/viktor-init`；见本节开头的升级说明。（F14）
- 需要处理卡：卡片之外不输出任何文字（包括"备注"，未初始化提示除外）；review error 卡标题写当前 `review_round`（不加 1），首段固定为"检查命令无法执行："；所有节点要求中文回复。（F15）
- Codex 子进程参数：AGENTS.md 的 `- 子进程参数：codex <参数>` 支持完整参数串（只允许字母数字和 `_ . = : / , @ + -`，没写 `--sandbox` 时补默认沙箱），取代 F1 里只接受 `--sandbox <值>` 的限制；JVM 项目由 init 写入 `--sandbox workspace-write -c sandbox_workspace_write.network_access=true`（会放开子进程外网访问）。`danger-full-access` 与所有 `--dangerously-*` 参数无论来自环境变量还是这一行都拒绝派单。（F16）
- upgrade.sh 全部逻辑放进一个函数、最后一行调用：执行中脚本文件被原地覆盖也不会读到新内容；`git fetch` 失败时直接退出，不再跳过 checkout 去安装旧版本。（P22 的防御项；首次从 1.0.x 升级的问题见上面的升级说明）
- check 的 `error` 只用于检查命令本身无法执行（不存在、被权限拒绝、崩溃）；命令跑通但证据不足以证明关键 AC 时一律 `blocked`，在 `pending` 写明缺什么证据。（P23）

### 已知问题

- **Codex 端只验证了基本流程**：S 档派单、JVM 项目的沙箱参数（review / check 能跑 Maven 与 Testcontainers）、子进程不提权。M / L 档、续接、blocked / manual 路径、交付报告只在 Claude Code 端做过真实模型验证。

## [1.0.1] - 2026-09-18

### Fixed（独立 review 后）

- 续接看代码指纹：指纹是工作区快照的 tree（排除 docs/changes、docs/knowledge，写报告不会让自己失效）；review / check 通过时写进 plan.md `verified`，续接时指纹变了就回 review；draft 状态的 plan 也可续接。
- 审查范围统一：code 开始时用临时索引给工作区拍快照记为 `base_tree`（含未提交的前一个需求，天然隔离）；每轮 review 结束记录 `.review.tree`，复审范围 = 上一轮快照之后的全部变化（修复与手改都在内）；未跟踪文件用 `git add -N` 纳入 diff。
- 报告 `run_id` 解析忽略行尾注释与引号；模板不再带注释。
- 事后单独发起 review 时不再补拍当前状态当基线：一律用与主干的 merge-base（分支提交与工作区改动都在内，主干上即 HEAD），创建 plan.md 不会改变审查范围。
- 快照从真实索引复制（保留"已跟踪但被 gitignore"的文件与 intent-to-add）；指纹在临时索引里显式移除 docs/changes、docs/knowledge，产物未跟踪 / 已跟踪 / 已暂存都不影响指纹；任一步失败返回非零且不输出，`.review.tree` / `verified` 不采信失败结果。
- 门禁缓存键加入执行目录与 viktor-checks 内容，子包之间、改命令后不再误复用通过结果。
- spawn 成功条件收紧：进程退出码为 0、报告 `run_id` 属于本轮、结构有效三者同时满足；后台模式同样使用退出码。
- knowledge.sh 首次 `rebuild` 在目录不存在时的静默失败；重建失败返回非零。
- bash 3.2 兼容：变量紧邻中文标点处统一写 `${VAR}`。
- 规则漂移：code 改用 knowledge.sh 写 pitfall；ship 不再停下来确认知识条目（列在报告里）；snippet 判档口径与 README 一致。

### Changed（Codex 端实测后）

- spawn 选工具改为"主会话是谁就派谁"：`--agent` > `VIKTOR_AGENT` > 环境变量 > 命令存在性；指定工具不可用直接退出码 3，不跨工具回退。
- review 提示词：固定七个维度（检查命令 / 验收覆盖 / 知识库一致性 / 正确性 / 数据兼容 / 安全 / 范围），lookup 命中的每条知识作为一条审查项，报告新增"维度结论"与"知识库对照"两张表；明确 review 只看代码与单元测试，行为验证归 check。
- check 提示词：先探测有无浏览器与能否监听端口，失败即放弃不重试；主会话有浏览器时可对 👀 项补验（只验 👀，不重验 ✅）。

## [1.0.0] - 2026-09-16

破坏性重构。按当前 Agent 能力重新设计，不再依赖 superpowers 的调度机制。

### Added（2026-09-16）

- **viktor-flow**：一个入口跑完整流程，M/L 档只在 plan 确认时停；不带参数续接自己未完成的需求（继续 / 归档 / 忽略，14 天内，别人的静默）。五个停车点，统一停车卡。
- **viktor-check**：独立进程以用户视角逐条验证 AC（e2e → 浏览器操作 → 手动步骤），输出 check.md。
- **独立审查**：viktor-review 改为派单器，`scripts/viktor-spawn.sh` 用 `claude -p` / `codex exec` 起新进程审查，按档位限制深度，最多 2 轮复审；提示词固化在 `prompts/`。
- **交付报告**：viktor-ship 生成 report.md，待人工确认项放最前。
- plan.md frontmatter 新增 `stage` / `stage_result` / `review_round` / `updated`；S 档也自动建 plan.md，续接逻辑统一。

### Added（2026-09-16，知识库）

- 知识库改为一条一个文件（`<类型>/YYYY-MM/<slug>.md`）+ `index.md`；`scripts/knowledge.sh` 提供 lookup（按适用范围 / 关键词确定性检索）、add、supersede、rebuild（路径失效标 ?）、migrate。各节点与 review / check 提示词改为只读命中的条目。

### Fixed（2026-09-16，todolist demo 第一轮后）

- viktor-init 把 `viktor-checks` 命令写入 `.claude/settings.json` permissions.allow，独立进程可直接跑检查；仓库无 commit 时提示先建基线。
- 审查者 / 验收者遇到命令无法执行时写 `result: error`，spawn 映射为退出码 2，flow 立即停车，不再消耗复审轮次。
- `VIKTOR_CLAUDE_ARGS` / `VIKTOR_CODEX_ARGS` 按 shell 规则解析，含空格的参数可加引号。
- check 无浏览器工具时不再启动 dev server、不跑 build，改为按 AC 过滤执行测试。
- flow 记录各节点耗时到 plan.md `timing`，report 增加耗时一节。
- 卡片改为纯文本（卡内不用 Markdown，终端里不会显示表格源码）；plan 待确认卡合并"关键决策 / 假设 / 需要你定"为"我替你做的决定 + 需要你选"，结尾固定一句"没问题回 OK，有要改的直接告诉我"；报告顶部状态条单行。
- 对话输出改为统一节点卡（结果 / 关键数字 / 产物 / 下一步），plan 确认卡带关键决策表与 AC 表，report 顶部状态条 + 全表格化，review.md 改为表格；对话里不再复述文件内容。

### Changed

- **节点 9 → 7**：flow / init / plan / code / review / check / ship。think 与 plan 合并为 plan；contract 并入 plan/code（类型定义作为第一个任务直接写进 src）；删除 context、digest。
- **原生 Agent Skills**：5 个节点均为标准 SKILL.md，安装到 `.claude/skills/`（Claude Code）和 `.agents/skills/`（Codex、Cursor）；技能名三端一致，调用前缀按端区分（Claude Code / Cursor `/viktor-xxx`，Codex `$viktor-xxx`）。
- **S/M/L 分档**：小改动只走 code → review。
- **门禁改为 hook**：Claude Code Stop hook 自动运行 AGENTS.md `viktor-checks` 块中的 typecheck / lint / test，失败反馈给 Agent，连续 3 次后放行并提示用户；其他工具手动运行。
- **产物按需求组织**：`docs/changes/<日期>--<slug>/`；知识只沉淀非推导内容到 `docs/knowledge/`。
- **入口精简**：注入业务项目的入口段约 25 行，CLAUDE.md 只保留 `@AGENTS.md`。

### Removed

- 元调度器、1% 规则、反理由表、会话感知冷启动检测、六轴星级评分。
- `references/`（React/测试通用规范）、活文档体系（component-catalog / api-catalog / architecture）、`.cursor/rules/workflow.mdc`。
- `sync-workflow.sh` / `upgrade-workflow.sh` / `validate-workflow.sh`，由 `install.sh`（含 `--migrate`）/ `upgrade.sh` / `validate.sh` 替代。
- `commands/` 与 `.claude/commands/viktor/`（命令即技能名，不再需要别名）。
- 仓库自身 v0 时期的 `docs/` 产物（specs / plans / reviews / adrs / digest / 活文档）。以下历史条目中指向 `docs/adrs/…` 的链接已失效，仅作记录。

---

## [0.8.1] - 2026-05-21

### Added

- **validate-workflow.sh 用户文档**：README 新增"验证三端一致性"章节，team-workflow-guide 新增"场景四"，均包含脚本用法说明和 Git Bash / WSL 运行环境要求。([ADR-010](docs/adrs/2026-05-21--p4-codex-review-fixes--adr.md))
- **Workflow-Meta Lane 三端完整化**：AGENTS.md 补充完整对照表（4 维度），`.cursor/rules/workflow.mdc` 补充精简定义块，Workflow-Meta Lane 成为三端一等概念，Codex 和 Cursor 用户可感知。([ADR-010](docs/adrs/2026-05-21--p4-codex-review-fixes--adr.md))

### Fixed

- **旧 digest 触发描述修正**：team-workflow-guide 两处"ADR 累积到 5 的倍数才建议 digest"旧描述改为"每次 DOCUMENT 完成后导航卡固定提供选项"，与 ADR-005 实际行为对齐。([ADR-010](docs/adrs/2026-05-21--p4-codex-review-fixes--adr.md))
- **P3 产物 frontmatter 补全**：`docs/specs/2026-05-21--p3-framework-agnostic.md` 和对应 plan 补写 YAML frontmatter，DIGEST 可机读状态字段。([ADR-010](docs/adrs/2026-05-21--p4-codex-review-fixes--adr.md))
- **review 路径占位格式统一**：7 处旧写法 `YYYY-MM-DD--review.md` 统一为 `YYYY-MM-DD--<feature>--review.md`，涉及 skills/04-code-review/SKILL.md、skills/05-documentation/SKILL.md、workflow.mdc、team-workflow-guide.md。([ADR-010](docs/adrs/2026-05-21--p4-codex-review-fixes--adr.md))
- **team-workflow-guide 日期更新**：文档日期从 2026-05-19 更新为 2026-05-21，与当前 v0.8.0 版本对齐。([ADR-010](docs/adrs/2026-05-21--p4-codex-review-fixes--adr.md))

---

## [0.8.0] - 2026-05-21

### Added

- **TDD SKILL 框架无关化**：`/viktor-code` 的 TDD 规范不再绑定 React/Next.js，新增框架→测试工具对照表（React/Vue/Svelte/其他），强制TDD/适度TDD 表格改为框架无关描述，代码示例保留并显式标注为"React/Next.js 参考实现"，其他框架按对应工具类比执行。([ADR-009](docs/adrs/2026-05-21--p3-framework-agnostic--adr.md))
- **三端一致性验证脚本**：新增 `scripts/validate-workflow.sh`，自动检查 9 个 viktor:* 命令在 CLAUDE.md / AGENTS.md / workflow.mdc 中的存在性（27 项）+ 10 个 Skill 文件存在于磁盘，彩色输出，exit 0/1，支持 CI 集成。([ADR-009](docs/adrs/2026-05-21--p3-framework-agnostic--adr.md))
- **产物文档 YAML frontmatter**：`/viktor-think`、`/viktor-plan`、`/viktor-cr` 生成的文件现在包含机器可读的状态字段（specs: `status/confirmed_at`，plans: `status/spec`，reviews: `result/reviewed_at/plan`），DIGEST 优先读取 frontmatter，向后兼容无 frontmatter 的历史文件。([ADR-008](docs/adrs/2026-05-21--p2-workflow-polish--adr.md))
- **Workflow-Meta Lane 正式化**：`skills/using-fe-workflow/SKILL.md` 新增独立章节，定义修改工作流文件时的专用通道（无 TDD、grep 验收、每文件 commit、三端同步粒度规则）；`CLAUDE.md` 流程图注释同步引用。([ADR-008](docs/adrs/2026-05-21--p2-workflow-polish--adr.md))
- **TDD commit 粒度建议**：TDD SKILL commit 步骤新增三模式说明（每任务提交为默认推荐，里程碑提交为可选，全量一次性提交为不推荐），并说明 tasks.md 里程碑标记机制。([ADR-008](docs/adrs/2026-05-21--p2-workflow-polish--adr.md))

### Fixed

- **git diff 检测范围修正**：`/viktor-doc` 工作流变更检测从 `HEAD~1 HEAD` 改为 `$(git merge-base HEAD main) HEAD`，多 commit feature 分支中早期的 `skills/` 变更不再被漏检。([ADR-007](docs/adrs/2026-05-21--p1-stability-fixes--adr.md))
- **TDD 合约遗漏提醒**：tasks.md 含 `[api]`/`[hook]`/`[store]` 类型任务但无合约文件时，TDD 冷启动输出非阻塞提醒，帮助用户感知跳过了 CONTRACT 节点。([ADR-007](docs/adrs/2026-05-21--p1-stability-fixes--adr.md))
- **DIGEST 技术债务可见性**：`/viktor-digest` 现从 review 文件提取 `[SUGGESTED]` 条目归入新增的"已知技术债务"章节（第 6 节），技术债务不再在摘要中消失。([ADR-007](docs/adrs/2026-05-21--p1-stability-fixes--adr.md))
- **BRAINSTORM 更新模式上下文遗漏**：更新已有 spec 时不再跳过 step 1（读取 `docs/project-context.md`），确保基于最新项目上下文修改文档。([ADR-007](docs/adrs/2026-05-21--p1-stability-fixes--adr.md))
- **编码规范约束**：新增 `.editorconfig` 和 `.gitattributes`，统一 UTF-8 编码和 LF 换行符，消除 Windows 环境 CRLF 混入问题。([ADR-007](docs/adrs/2026-05-21--p1-stability-fixes--adr.md))

- **三端命令协议对齐**：`.cursor/rules/workflow.mdc` 中旧命令名（`/brainstorm`、`/analyze`、`/tdd`、`/review`）已统一更新为 `viktor:*` 协议，与 Claude Code 和 Codex 端保持一致。([ADR-006](docs/adrs/2026-05-20--p0-consistency-fixes--adr.md))
- **Cursor BRAINSTORM 策略对齐**：`workflow.mdc` 中 BRAINSTORM 步骤描述从"苏格拉底式逐个提问"更正为"批量最多 3 问"，与 SKILL.md 实际行为一致。([ADR-006](docs/adrs/2026-05-20--p0-consistency-fixes--adr.md))
- **技术栈去硬编码**：`workflow.mdc` 技术栈节不再写死 Next.js 14 版本，改为引用 `docs/project-context.md`（由 `/viktor-init` 生成）。([ADR-006](docs/adrs/2026-05-20--p0-consistency-fixes--adr.md))
- **REVIEW 框架名称统一**：`skills/04-code-review/SKILL.md` 内"五轴"全部更正为"六轴"（共 4 处：章节标题、step 3、验证清单、review 模板）。([ADR-006](docs/adrs/2026-05-20--p0-consistency-fixes--adr.md))
- **DIGEST 触发描述更正**：`skills/using-fe-workflow/SKILL.md` 命令速查表 digest 行从"ADR 累积到 5 的倍数"更正为"每次 DOCUMENT 完成后无条件触发"。([ADR-006](docs/adrs/2026-05-20--p0-consistency-fixes--adr.md))
- **CONTRACT 措辞修正**：`commands/viktor/contract.md` 第 5 节从"执行中 Hard Gate"重命名为"执行中约束（会话锁）"，避免与强制前置条件的"Hard Gate"概念混淆。([ADR-006](docs/adrs/2026-05-20--p0-consistency-fixes--adr.md))
- **DOCUMENT 活文档触发条件去框架专属**：`skills/05-documentation/SKILL.md` step 4 表格中"React 组件"改为"前端组件（React / Vue / Svelte 等）"，"Server Action"改为"接口函数"。([ADR-006](docs/adrs/2026-05-20--p0-consistency-fixes--adr.md))

### Added

- **`/viktor-context` 节点**：只读项目快照命令，读取 5 个活文档并格式化输出到对话，无副作用，随时可用。文件缺失时给出说明而非报错。([ADR-003](docs/adrs/2026-05-19--context-digest-nodes--adr.md))
- **`/viktor-digest` 节点**：阶段性文档整合命令，读取 `docs/` 下所有文档，生成 `docs/digest/YYYY-MM-DD--digest.md`，包含项目状态 / 完成需求 / 架构决策 / 活文档现状 / 待关注问题五个章节。([ADR-003](docs/adrs/2026-05-19--context-digest-nodes--adr.md))
- **`/viktor-context` 和 `/viktor-digest` 命令入口**：补全 `.claude/commands/viktor/context.md` 和 `digest.md`，两个命令现可在 Claude Code 命令列表中直接找到。([ADR-004](docs/adrs/2026-05-19--session-aware-confirmation--adr.md))
- **DOCUMENT references 变更检测**：`/viktor-doc` 第 1 步新增 `references/` 变更检测，若规范文件有变更则输出映射表，提示确认相关 Skill 是否需要同步。([ADR-005](docs/adrs/2026-05-19--workflow-completeness-polish--adr.md))

### Changed

- **BRAINSTORM 节点**：新增冷启动前置检测——扫描 `docs/specs/` 已有文件，询问新建还是更新；支持 PRD 文档输入路径（引用 `prd-input-template.md`，自动跳过提问轮次）；新增"新项目建议先 `/viktor-init`"非阻塞提示。([ADR-005](docs/adrs/2026-05-19--workflow-completeness-polish--adr.md))
- **INIT 节点**：幂等化——`project-context.md` 已存在时询问"重新扫描"或"仅补全缺失骨架"，重复执行安全；`CLAUDE.md` 新增 INIT 节点独立说明块。([ADR-005](docs/adrs/2026-05-19--workflow-completeness-polish--adr.md))
- **DOCUMENT 节点**：`/viktor-doc` 完成后，导航卡固定提供 `/viktor-digest` 非阻塞选项，不再依赖 ADR 数量倍数条件。([ADR-005](docs/adrs/2026-05-19--workflow-completeness-polish--adr.md))
- **CONTRACT / REVIEW 节点**：冷启动单文件场景"直接使用"逻辑明文化，消除隐含行为。([ADR-005](docs/adrs/2026-05-19--workflow-completeness-polish--adr.md))
- **三端入口同步**：`CLAUDE.md` / `AGENTS.md` / `.cursor/rules/workflow.mdc` 同步以上所有变更。
- **会话感知冷启动检测**：ANALYZE / CONTRACT / TDD / REVIEW / DOCUMENT 五个节点均新增前置检测步骤。对话内连续执行（在流模式）零打扰；跨会话冷启动时自动扫描历史产物，展示完成状态，让用户明确选择操作目标或重定向到 `/viktor-think`。([ADR-004](docs/adrs/2026-05-19--session-aware-confirmation--adr.md))

---

## [0.4.0] - 2026-05-18

### Added

- **活文档体系**（5 文件 Markdown）：`/viktor-init` 新增第 6 步，在生成知识地图后自动创建 `docs/component-catalog.md`、`docs/api-catalog.md`、`docs/architecture.md`、`docs/adrs/README.md` 四个骨架文件（已存在则跳过）。
- **ADR 自动编号**：`/viktor-doc` 自动读取 `docs/adrs/` 文件数推算三位数编号（ADR-001、ADR-002 等），不再需要手动填写占位符。
- **ADR 替代流程**：`/viktor-doc` 询问本次是否替代历史 ADR，用户指定编号后自动将旧 ADR 状态字段更新为 `已替代（见 ADR-XXX）`。
- **ADR 状态机制**：ADR 模板新增四个合法状态：`草稿 / 已接受 / 已废弃 / 已替代（见 ADR-XXX）`，写入模板和 `references/living-docs-conventions.md`。
- **工作流自身变更检测**：`/viktor-doc` 第 1 步自动检测本次是否修改了 `skills/` 或 `commands/`，若是则输出专项提示，引导更新三端入口文件。
- **条件更新活文档**：`/viktor-doc` 新增第 4 步，根据变更类型有条件地更新 `component-catalog.md`、`api-catalog.md`、`architecture.md`、`adrs/README.md`。
- **活文档规范**：新增 `references/living-docs-conventions.md`，定义 5 文件职责、更新原则、ADR 状态机制、工作流同步规范、退化识别与修复指南。

### Changed

- **INIT 节点**：`skills/06-project-init/SKILL.md` 新增第 6 步，导航卡更新显示 5 个产物文件。
- **DOCUMENT 节点**：`skills/05-documentation/SKILL.md` 步骤重编号（原 4/5/6 步 → 5/6/7 步），新增第 4 步「条件更新活文档」。
- **三端入口同步**：`CLAUDE.md` / `AGENTS.md` / `.cursor/rules/workflow.mdc` 全部更新，包含 INIT 和 DOCUMENT 新能力描述及新产物目录。
- **版本号**：README.md 和 docs/team-workflow-guide.md 版本更新至 v0.4.0。

---

## [0.3.0] - 2026-05-18

### Added

- **CONTRACT 节点**（`/viktor-contract`）：新增可选的类型合约生成节点，位于 ANALYZE 和 TDD 之间。从 `tasks.md` 或 `design.md` 提取结构化 TypeScript 类型定义，输出 `docs/contracts/YYYY-MM-DD--<feature>.types.ts`，作为 TDD 实现和 REVIEW 检查的共享类型锚点。([ADR](docs/adrs/2026-05-18--contract-node--adr.md))
- **ANALYZE 智能推荐**：`/viktor-plan` 完成后，根据任务构成（是否含 `[api]`/`[hook]`/`[store]` 类型任务）自动给出是否建议执行 CONTRACT 的双路导航卡，用户最终决定。
- **REVIEW 第六检查轴**：在合约文件存在时，`/viktor-cr` 新增类型合约一致性检查（实现类型是否与合约一致、是否有未声明的新类型、API 类型是否匹配）。

### Changed

- **TDD 节点**：`/viktor-code` 进入任务循环前新增前置步骤，自动感知 `docs/contracts/` 目录，存在合约文件时在上下文中标注，引导实现时 import 合约类型。
- **工作流图**：全流程从五节点扩展为六节点（CONTRACT 为可选）：`think → plan → [contract] → code → cr → doc`。
- **三端入口同步**：`CLAUDE.md` / `AGENTS.md` / `.cursor/rules/workflow.mdc` / `skills/using-fe-workflow/SKILL.md` 全部更新，包含 CONTRACT 节点定义、命令路由和产物目录。
- **版本号**：README.md 和 docs/team-workflow-guide.md 版本更新至 v0.3.0。
