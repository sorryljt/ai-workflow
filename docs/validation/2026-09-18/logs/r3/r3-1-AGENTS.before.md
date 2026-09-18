<!-- fe-ai-workflow-start -->
## fe-ai-workflow（viktor）

本项目使用 viktor AI 开发工作流。技能：viktor-flow（自动流水线 / 续接），以及可单独调用的 viktor-init、viktor-plan、viktor-code、viktor-review、viktor-check、viktor-ship。

### 开始任何开发任务前：先判断档位，只输出一行声明（`▶ M 档  plan（等你确认）→ code → …`，不写理由；用户可以改）

| 档位 | 判据 | 流程 |
|------|------|------|
| S | 没有需要人拍板的口径或取舍，改动集中 | code → review → check → ship（全自动） |
| M | 有口径或取舍需要确认，单个模块 | plan（人确认）→ code → review → check → ship |
| L | 新增或修改数据模型 / 持久化结构（给已有表加可空列、放宽或收紧请求校验边界不算，这两类按 M；只有影响已有数据可读性、需要迁移或改主键 / 唯一约束的才算 L） / 对外接口契约，或跨两个以上模块 | plan（含任务清单，人确认）→ code → review → check → ship |

判档首先看"有没有需要人拍板的取舍"，有就至少 M；再看兼容性、数据影响、恢复成本；文件数和验收数只作参考。

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
<!-- fe-ai-workflow-end -->

## 项目信息（viktor-init）
- 技术栈：Java 17 / Spring Boot 3.3.5（Web + Data JPA + Validation，PostgreSQL）/ JUnit 5 + Spring Boot Test + Testcontainers 1.21.4
- 构建工具：Maven 多模块（core、app），用仓库自带的 `./mvnw`
- 主干分支：main
- 命令验证：test 已验证（5 个执行：core 3 + app WebMvc 2）；verify 已验证（7 个执行，含 2 个 OrderApiIT）；typecheck / lint 项目未配置（编译由 test 覆盖）；dev 未验证：需要本地 Postgres

```viktor-checks
test: ./mvnw -q test
verify: ./mvnw -q verify
dev: ./mvnw -pl app -am spring-boot:run
```

### 运行前提
- test：只需 JDK 17+，不需要 Docker。
- verify：需要 Docker（Docker Desktop 或 colima），`docker ps` 能成功即就绪；Testcontainers 会拉起 `postgres:16-alpine`。日志中 `duplicate key ... uk_orders_order_no` 的 ERROR 是 409 用例的预期输出。
- dev：需要本地 Postgres（默认 `jdbc:postgresql://localhost:5432/demo`，可用 `DB_URL` / `DB_USER` / `DB_PASSWORD` 覆盖）。

### 约定（只写不明显的）
- 提交信息用 Conventional Commits（`feat:` / `fix:` / `chore:` …）。
- 测试按命名分流：`*Test` 由 surefire 在 `test` 阶段执行（快速、不依赖 Docker）；`*IT` 由 failsafe 在 `verify` 阶段执行（真实 Postgres）。需要数据库的测试必须命名为 `*IT`。

### 禁区
- 无
