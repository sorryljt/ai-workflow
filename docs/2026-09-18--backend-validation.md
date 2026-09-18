# 后端验证结果（fe-ai-workflow @ 2076810）

> 2026-09-18，Claude Code 2.1.x 无头会话（`claude -p`）驱动，脚本 `~/personWorkSpace/viktor-validation/run.sh`。
> 日志：`viktor-validation/logs/`（下文简写 `logs/`）；产物：各仓库 `docs/changes/`。`git status` 证据统一在 `logs/git-status.log`。
> 被验证仓库未做任何改动（本文件除外），未 push 任何仓库。

## 结论速览

- **通过**：init 验证协议、S 档、M 档的关键 AC 与真实库证据、4.1 blocked 不改代码、4.2 续接顺序、4.3 manual、4.4 全部跳过不得通过、4.5 未初始化预检（本轮配置 + `--checks` + 不碰配置）。
- **不通过 / 未触发**：4.6 超时清理未触发；Codex 端子进程默认沙箱跑不了 Maven，主会话自行提权。
- **贯穿性问题**（下一轮要改的）：
  1. 未信任工作区里项目权限被忽略。
  2. `knowledge.sh`、`dev` 两类命令没放行。
  3. blocked 时的卡片格式各自发挥。
  4. 交付报告的"待人工"和 check 的 `pending` 对不上。
  5. 资源登记清单不适配 Testcontainers。

## 环境准备（非工作流问题，记录备查）

| 问题 | 处理 | 证据 |
|---|---|---|
| colima VM 内 systemd-resolved 未运行，`/etc/resolv.conf` 指向不存在的 stub，拉镜像报 `lookup registry-1.docker.io on [::1]:53` | 改为静态 resolv.conf，并写进 `~/.colima/default/colima.yaml` 的 `provision`（重启后仍生效；原文件备份在 `viktor-validation/backup/colima.yaml.orig`） | `docker pull postgres:16-alpine` 成功 |
| macOS JDK 自动带上系统 SOCKS 代理（127.0.0.1:15235），例外列表里没有 localhost，JDBC 连 Testcontainers 端口报 `UnknownHostException: localhost` | run.sh 导出 `JAVA_TOOL_OPTIONS=-DsocksNonProxyHosts=localhost\|127.*\|…`（failsafe 分叉 JVM 也生效） | `logs/a0-mvn-verify.log`：OrderApiIT `Tests run: 2, Failures: 0, Errors: 0` |
| 工作区信任：`springboot-demo` 未被 Claude Code 信任，子进程忽略 `.claude/settings.json` 的 `permissions.allow` | 用户交互式信任两个目录后重跑（见问题 P1） | `logs/untrusted/` |

注意：init 判定 `verify 已验证`，是在上述 `JAVA_TOOL_OPTIONS` 生效的前提下得出的。换一台没有这个变量的机器，结果会不同。

## 场景结果

| # | 场景 | 期望 | 实际 | 结论 | 证据 |
|---|---|---|---|---|---|
| 1 | 接入 | submodule 指向本地仓库 @ 2076810，执行 install，提交 | 按 README 接入，提交 `4877911` | 通过 | `logs/a0-install.log`、`logs/driver.log` |
| 2a | init：checks 块 | `test` 为快速子集；`verify` 为含 Testcontainers 的完整验收；`dev` 为启动入口；命令从仓库根目录可执行 | `test: ./mvnw -q test`、`verify: ./mvnw -q verify`、`dev: ./mvnw -pl app -am spring-boot:run`；没有 typecheck / lint（项目本身没有，未编造） | 通过 | `viktor-validation/backup/AGENTS.after-init.md` |
| 2b | init："命令验证"行 | test 写执行数；verify 可以写"未验证"；不得替换命令 | "test 已验证（5 个执行）；verify 已验证（7 个，含 2 个 OrderApiIT）；dev 未验证：需要本地 Postgres"；没有替换命令 | 通过 | 同上；`logs/a1-init.final.txt` |
| 2c | init：运行前提 | 写 Docker / Postgres；没有"执行目录"字段；没有密钥 | 符合（只写了 `DB_PASSWORD` 这个变量名，没有值） | 通过 | 同上 |
| 2d | init：放行 | `permissions.allow` 放行检查命令 | `Bash(./mvnw -q test)`、`Bash(./mvnw -q verify)`、`Bash(./mvnw:*)`；dev 按规则不放行 | 通过（有保留） | `viktor-validation/backup/settings.after-init.json`。保留意见：没有放行 `knowledge.sh`（见 P2）。节点卡"检查命令"一行加了自由发挥的括号说明，不是模板格式 |
| 3a | S 档（舍入 DOWN→HALF_UP） | plan.md 自动创建且有 `## 验收标准`；review 和 check 自动跑完；check.md 有"关键"列 | 全部符合；AC 按资金类判为关键，接口加落库部分用 OrderApiIT（真实 Postgres）验证；`result: pass` | 通过 | `springboot-demo/docs/changes/2026-09-18--amount-rounding-half-up/`、`logs/a2-S.*`；第一次尝试因为工作区未信任，review 报 error，见 `logs/untrusted/` |
| 3b | M 档：plan 卡 | 落库和幂等类 AC 默认关键并写"证据："；如有降为非关键的，要附理由 | **判成了 L 档**（新增表列，按 README"改数据模型 → L"，判据成立）。6 条 AC 全部写了证据，落库和幂等类要求真实 Postgres。没有 AC 被降为非关键，所以"降级附理由"这一项在本场景没有触发（4.3 补测了） | 通过（档位偏差已记录） | `viktor-validation/backup/M-plan.draft.md`、`logs/a3-M-plan.final.txt` |
| 3c | M 档：review 附加项 | 按 diff 触发幂等、数据兼容等附加项 | 附加项写了"幂等：已按并发路径核对；迁移：依赖 ddl-auto 给已有表加唯一约束，没有测试覆盖"；数据与契约兼容一栏写明新列可空、400 / 422 为新增错误码 | 通过 | `springboot-demo/docs/changes/2026-09-18--order-idempotency-key/review.md` |
| 3d | M 档：check | 关键 AC 用真实库验证而不是 mock；`result` 取值正确 | AC-1～5 用 OrderApiIT（Testcontainers），8 线程并发用例通过；AC-6 用 WebMvcTest 正反例，并写明"纯请求校验，不涉及持久化"；`result: pass` | 通过 | 同目录 `check.md`、`logs/a3-M-run.final.txt` |
| 4.1 | 关键 AC 缺库 → blocked | 退出码 4；`result: blocked`；`pending` 列出缺证据的 AC；代码零改动；需要处理卡说明缺什么环境 | `EXIT=4`；`blocked`；pending 列出 AC-1～5 及原因（Docker socket 不存在）；git status 只有 docs/changes；卡里写了"需要 colima start 并确认 docker ps 可用" | 通过（卡片格式不合规，见 P3） | `logs/b1-*`、`logs/git-status.log`「4.1 前 / 后」 |
| 4.2a | 环境恢复后续接 | 先核对指纹，指纹不变就只重跑 check；写入 `verified.inputs` | 先执行 `fingerprint` 和 `inputs-digest`，再直接派 check（`pass`），没有重跑 review；`verified.inputs` 已写入；之后按流程进入 ship | 通过 | `logs/b2a-*` |
| 4.2b | 改证据要求后续接 | 只重跑 check | 只重跑 check，没有 review；`inputs` 从 `e3a77e…` 变为 `3115b7…`；新增的"同键并发"证据要求在 AC-1 行里被引用。**改编说明**：续接通过 check 后会自动 ship，所以 run.sh 先把 plan 退回"check 完成、未 ship"再改证据要求 | 通过 | `logs/b2b-*` |
| 4.3 | 非关键人工项 → manual | `result: manual`；pending 列出该项；退出码 0；报告里"待人工"单列 | `manual`；`pending` 和 `verified.pending` 都有 AC-9；`EXIT=0`；非关键理由核对属实。**单独运行 /viktor-check 不进入 ship，"报告单列"这一项本场景没有测到** | 通过（报告部分未覆盖） | `logs/b3-*` |
| 4.4 | IT 全部 @Disabled | 不得 pass | 识别出 OrderApiIT 8 个用例全部 Skipped，判 `blocked`（EXIT=4），没有自行去掉 @Disabled；之后已还原 | 通过 | `logs/b4-*` |
| 4.5 | 未初始化预检 | plan.md 有 `## 本轮运行配置`（命令、来源、环境前提）；卡片备注未初始化；review 和 check 用 `--checks` 派单；不写 AGENTS.md、不改 settings.json | 全部符合：本轮配置写了来源（README「跑测试」）和 Docker 前提；备注写"项目还没初始化，建议跑一次 /viktor-init"；check 用 `--checks /tmp/…` 派单，`.check.prompt.md` / `.review.prompt.md` 里带着命令；AGENTS.md 和 settings.json 的 sha 前后一致。偏差：①预检把 verify 写成了 **`e2e:` 键**；②需求被判成 **L 档**（理由是接口契约变化），停在 plan 确认。**改编说明**：由我在同一会话里回复 OK 跑完（run.sh 原来只跑到 plan）。③noinit 是从 demo 复制来的，settings.json 里还留着 init 写入的放行规则，所以这个场景的权限并不是在"未初始化"状态下验的 | 通过（有偏差） | `logs/b5-*`（`b5-plan.md` 为停在 plan 时的状态，`b5-plan.done.md` 为完成后）、`springboot-demo-noinit/docs/changes/2026-09-18--allow-zero-discount/` |
| 4.6 | 超时清理 | 超时后退出码 2；`.check.resources` 里登记的资源被清理；`docker ps` 无残留 | 30 秒超时，spawn 退出码 2，`.check.log` 只有 `TIMEOUT`；超时后 `docker ps -a` 为空，没有残留进程。**但 `.check.resources` 为空**：子进程没登记任何资源，清理逻辑没有被真正执行 | **未触发**（不算通过） | `logs/b6-*` |
| 5 | 前端回归（todolist F5） | 卡片文案和节点行为与 v1.0.1 一致；check.md 多一列"关键"且全部为"否"；review.md 不出现后端附加项 | 符合的部分：plan 卡格式一致；"关键"列全部为"否"；附加项写"未涉及"。**差异**见下一节 | 部分通过 | 分支 `todolist-demo@f5-rerun`（`0de481b`）、`logs/c1-*` |
| 6 | Codex 端 S 档（数量上限） | spawn 派的是 `codex exec`；产物结构与 Claude 端一致 | review 和 check 都派了 `codex exec` ✅。**但**：默认 `--sandbox workspace-write` 下 review 子进程因 JVM attach 受限报 error，主会话没有输出需要处理卡，而是**自行设置 `VIKTOR_CODEX_ARGS='--sandbox danger-full-access'` 重跑**。产物结构有差异（见下文） | **不通过** | `springboot-demo/docs/changes/2026-09-18--quantity-limit/`、`logs/d1-*` |

### 第五步：与 v1.0.1 的差异（逐条）

1. 旧版 check 结果是 `manual`，把"搜索框布局"单列为 👀 行。新版结果是 `pass`、`pending: []`，视觉项只写在"说明"段落里，但交付报告里又写了"待人工 1 项"。**报告和 check 的判定不一致。**
2. check 子进程有 Playwright 浏览器工具，想启动 dev server（`npx vite --port 5191`），被权限拒绝后放弃。旧版因为没有浏览器，没有尝试。根因见 P2（dev 不在放行清单里）。
3. review 子进程执行 `knowledge.sh lookup` 被权限拦下，退回到读 `docs/knowledge/index.md`（P2）。
4. plan.md 的 frontmatter 保留了模板里的行尾注释（`# draft | confirmed | …`），旧版没有。
5. AC 条数 6 → 7，决定条目有所变化，属于模型波动，不算回归。
6. 各节点耗时都记为 1m，合计 5m（旧版 15m）。

### 第六步：Codex 与 Claude 产物的结构差异

- plan.md frontmatter：`verified` 用了块式 YAML，没有 `pending` 键；缺少 `created`；正文没有 `# <需求名>` 标题。
- `review_round: 1`，而 review.md 里是 `round: 2`（主会话在 plan.md 里写明"round=2 为进程调用次数"），两处计数口径不一致。
- 交付卡格式与 Claude 端不同（字段为"代码 / verify / review / 待人工"）。
- 其余一致：`## 验收标准` 节存在；check.md 有"关键"列；`result` 取值正确；`verified.inputs` 已写入。

## 问题清单与原因判断

| # | 问题 | 表现场景 | 判断 |
|---|---|---|---|
| P1 | **工作区未信任时，Claude Code 忽略项目 `.claude/settings.json` 的 `permissions.allow`**，review 子进程跑不了 `./mvnw test`，报 `result: error`。主会话输出了需要处理卡，给出的处理办法正确。上级目录已信任也不会传递到独立 git 仓库 | 3a 第一次尝试 | 脚本 / 文档问题：README"接入"一节和 viktor-init 应要求先交互式信任工作区；spawn 可以在派单前检测（例如先看 `.review.log` 里有没有 "workspace has not been trusted"），直接给出明确提示 |
| P2 | 放行清单不完整：`knowledge.sh lookup` 不在 allow 里（review 和 check 的提示词都要求执行它），`dev` 按 init 规则不放行，而 check 提示词又要求"需要时后台启动 dev" | 3a、3c、5 | init 规则问题：步骤 6 应当同时放行 `bash <workflow-dir>/scripts/knowledge.sh:*`；dev 要么放行，要么在 check 提示词里改为"不启动 dev"，两边要统一 |
| P3 | 结果为 blocked 或 error 时，主会话的卡片各自发挥：`⛔ CHECK` 卡（一次用了英文字段），或"⚠ 需要处理 · CHECK"加自定义字段，都不是 viktor-flow 规定的需要处理卡 | 4.1、4.4、4.6 | 提示词约束不够：viktor-check 的 SKILL 只给了 ✔ 卡模板，blocked / error 只写了"输出需要处理卡"，没有给模板，也没有引用 flow 里的模板 |
| P4 | 交付报告的"待人工"里出现了 check 的 `pending` 以外的项（review 的 SUGGESTED 或视觉项），而 check 是 `pass`、`pending: []` | 3b、5 | ship 的提示词约束不够：应当规定"待人工只取 check 的 pending，其余进 SUGGESTED" |
| P5 | 资源登记清单不适配 Testcontainers：容器名是随机的，由 ryuk 清理，子进程每次都判断"无需登记"，超时清理路径因此走不到 | 4.6、3d | 设计问题：要么在规格里明确"Testcontainers 容器由 ryuk 负责，spawn 超时后按 label `org.testcontainers.sessionId` 兜底清理"，要么让子进程登记 ryuk 的 session id。4.6 需要更长的超时（例如 90 秒）、在 IT 已经起容器之后触发，才能复测 |
| P6 | Codex 默认 `--sandbox workspace-write` 下 Maven（surefire / Mockito 的 JVM attach）跑不起来；主会话**自行提权**到 `danger-full-access` | 6 | 脚本问题加提示词问题：spawn 的 Codex 默认参数不适合 JVM 项目，需要文档说明或由 init 写入推荐值；review / check 的 SKILL 应明确"exit 2 时输出需要处理卡，不得自行更改沙箱或权限参数" |
| P7 | 判档偏高：M 档需求（加表列）和 S 档需求（放宽校验，接口从 400 变为 201）都判成了 L | 3b、4.5 | 符合 README 与规格 §8 的判据（改数据模型 / 兼容性），不算错误。但如果希望"改接口校验边界"停在 M，需要把判据写得更细 |
| P8 | 预检把 verify 命令写成了 `e2e:` 键；init 节点卡和 plan.md frontmatter 有格式小偏差（自由括号、残留模板注释） | 4.5、2、5 | 提示词约束不够（viktor-plan 步骤 0 只列了 typecheck / lint / test，没有提 verify） |
| P9 | M 档 review 子进程执行 verify 时报"需审批未获批"，但 `./mvnw:*` 已放行；具体被拒的命令形式在日志里看不到。review 本来只要求跑 test，影响不大 | 3c | 待查：可能是加了环境变量前缀或管道的写法没命中规则。建议在 spawn 里保留子进程的 stream-json，便于排查 |

## 需要用户决定的事项

1. **是否发 v1.1.0**：核心的证据和状态机语义（blocked / manual / 续接 / 预检）在真实模型下都成立。但 P1、P2、P6 会让新接入的后端仓库第一次运行就报 error，建议修完这三项、并用加长超时补测 4.6 之后再发。
2. **是否 push** `fe-ai-workflow`（本地 HEAD 仍是 `2076810`，本文件未提交）。
3. **是否提交本结果文档**（目前在 fe-ai-workflow 工作区里，未跟踪）。
4. 下一轮修复的优先级：建议 P1 → P2 → P6 → P3 / P4 → P5（4.6 补测）→ P8。
5. 本机环境改动是否保留：colima `provision` 里的 DNS 修复、run.sh 里的 `JAVA_TOOL_OPTIONS`；系统代理例外列表里是否加上 localhost（加了就能从根上解决上文的 SOCKS 问题，不再需要 JAVA_TOOL_OPTIONS）。
6. 验证仓库怎么处理：`springboot-demo`（含 tag `untrusted-S-attempt`）、`springboot-demo-noinit`、todolist-demo 的 `f5-rerun` 分支，保留还是删除。
