---
run_id: 20260918214259-38717
result: blocked
pending:
  - "AC-1：关键（服务端数据写入 / 幂等）；Docker 未就绪（docker ps 失败），verify 无法运行，缺真实 Postgres 证据"
  - "AC-2：关键（幂等重放）；同上，缺真实 Postgres 证据"
  - "AC-3：关键（并发幂等、唯一约束）；同上，缺真实 Postgres 证据"
  - "AC-4：关键（幂等键复用 422、不落库）；同上，缺真实 Postgres 证据"
  - "AC-5：关键（对外接口契约兼容、409 不落库）；同上，缺真实 Postgres 证据"
checked: 2026-09-18
---

# Check：订单创建接口支持幂等键

## 环境探测
- 浏览器工具：有（Playwright），但本需求无可见交互 AC，未使用。
- dev server：不需要（没有 AC 要求运行中的服务，AC-1～AC-5 的证据入口是 `verify`），未启动。
- 容器运行时：`docker ps` 失败 → Docker 未就绪。按规则不重试、不换方案；`verify`（Testcontainers + 真实 Postgres）不执行，依赖它的 AC 标证据缺失，不用 mock 顶替。
- 本轮未创建临时目录 / 后台进程，`.check.resources` 无需登记；未拉起任何容器。

## 本轮运行
- `./mvnw -q test`：退出码 0。surefire 报告：OrderControllerWebMvcTest 8/8、OrderServiceTest 3/3、OrderAmountCalculatorTest 11/11，failures=0 errors=0 skipped=0（共 22 个）。
- `./mvnw -q verify`：未执行（运行前提 Docker 未满足）。

| AC | 关键 | 验证方式 | 证据 | 结果 |
|----|------|---------|------|------|
| AC-1 带键首次提交 201，库中 1 条且 key / request_hash 落库 | 是 | 证据缺失 | 需真实 Postgres 查库（OrderApiIT，verify 阶段）；Docker 未就绪，verify 未运行。`test` 里 WebMvcTest 用的是 mock service，不等价 | ⛔ |
| AC-2 同键同体（含 `10` / `10.00`）重放 201 + `Idempotent-Replayed: true`，仍 1 条 | 是 | 证据缺失 | 同上。WebMvcTest `passesValidIdempotencyKeyToServiceAndMarksReplay` 只证明 Controller 在 mock 返回 replayed 时加响应头，不能证明指纹规范化与库中计数 | ⛔ |
| AC-3 同键同体 8 线程并发全部 201 且 id 相同，库中 1 条 | 是 | 证据缺失 | 依赖真实 Postgres 唯一约束与事务语义；verify 未运行 | ⛔ |
| AC-4 同键不同体 → 422 `IDEMPOTENCY_KEY_REUSED`，不落库 | 是 | 证据缺失 | WebMvcTest `mapsReusedIdempotencyKeyTo422` 只覆盖异常→422 映射（mock）；"库中仍 1 条且金额为首次值"需真实库，verify 未运行 | ⛔ |
| AC-5 无键行为不变；重复 orderNo 409 不落库；不同键同 orderNo 409 | 是 | 证据缺失 | WebMvcTest `createsWithoutIdempotencyKey`、`mapsDuplicateOrderTo409` 只覆盖 Controller 层映射（mock）；"不落库"与"不同键同 orderNo 409"需真实库唯一约束，verify 未运行 | ⛔ |
| AC-6 空白 / 超 64 字符 → 400 `INVALID_IDEMPOTENCY_KEY`，不调用创建逻辑 | 是 | 单元测试（WebMvcTest，正反例） | `./mvnw -q test` 通过：`rejectsBlankIdempotencyKey` [""、"   "]、`rejectsIdempotencyKeyLongerThan64`（65 字符）断言 400 + `$.error=INVALID_IDEMPOTENCY_KEY` + `verifyNoInteractions(service)`；正例 `passesValidIdempotencyKeyToServiceAndMarksReplay`（64 字符）→ 201。纯请求校验，不涉及持久化，mock service 足够 | ✅ |
| AC-9 Kibana 按 orderNo 能检索到创建订单 INFO 日志（plan 标非关键） | 否 | 待人工 | 核对理由：该 AC 只关于日志可观测性，不涉及数据写入与接口契约，理由属实，按非关键。本轮辅助观察：`OrderServiceTest.logsCreatedOrderAtInfoWithOrderNo` 通过，输出含 `INFO ... OrderService : order created orderNo=NO-LOG-1`。步骤：1. 上线后调用 `POST /orders` 创建订单，记下 orderNo；2. 在生产 Kibana 按该 orderNo 检索；期望：能看到 `order created orderNo=<该值>` 的 INFO 日志 | 👀 |

## 失败详情
- 无观察到的失败。

## 解除阻塞
- 启动 Docker（Docker Desktop 或 colima），确认 `docker ps` 成功后重新运行 check；`./mvnw -q verify` 中的 OrderApiIT 将在 Testcontainers 拉起的 `postgres:16-alpine` 上提供 AC-1～AC-5 的证据（容器由 Testcontainers / ryuk 回收）。
