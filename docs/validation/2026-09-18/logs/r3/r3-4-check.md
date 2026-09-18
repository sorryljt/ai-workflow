---
run_id: 20260918214656-42179
result: manual
pending: [AC-9]
checked: 2026-09-18
---

# Check：订单创建接口支持幂等键

本轮执行 `./mvnw -q verify`（Docker/colima 已就绪，`docker ps` 成功），命令成功退出。报告：
- failsafe `OrderApiIT`：Tests run: 10, Failures: 0, Errors: 0（真实 Postgres：Testcontainers `postgres:16-alpine`）
- surefire `OrderControllerWebMvcTest` 8 / `OrderServiceTest` 3 / core `OrderAmountCalculatorTest` 11，全部 0 失败
- 日志里的 `duplicate key ... uk_orders_order_no` ERROR 来自 409 用例和并发用例的失败方，属预期；`订单金额不能超过 1000000.00` 堆栈来自 `amountAboveLimitIsRejectedAndNotPersisted`，该用例通过。
- 容器由 Testcontainers / ryuk 回收。本轮没有启动 dev，也没有创建临时目录或进程，`.check.resources` 无需登记。

| AC | 关键 | 验证方式 | 证据 | 结果 |
|----|------|---------|------|------|
| AC-1 带 `k1` 首次提交 → 201，库中 `idempotency_key=k1`、`request_hash` 非空 | 是 | 集成测试（真实 Postgres） | `OrderApiIT.firstRequestWithIdempotencyKeyPersistsKeyAndHash` 通过：201、无 Replayed 头、库中仅 1 条，key=k1，hash 长度 64 | ✅ |
| AC-2 同键同体（`10` 与 `"10.00"`）重放 → 201、响应相同、`Idempotent-Replayed: true`、仍 1 条 | 是 | 集成测试（真实 Postgres） | `repeatedKeyWithSameBodyReplaysFirstResultWithoutInsert` 通过：第二次用 `"10.00"` / `"1.0"`，响应体与首次 equals，头为 `true`，count=1 | ✅ |
| AC-3 同键同体 8 线程并发 → 全部 201 且 id 相同，库中 1 条 | 是 | 集成测试（真实 Postgres，并发） | `concurrentRequestsWithSameKeyInsertOnce` 通过：8 线程用 latch 同时发出，全部 201，id 唯一，count=1；日志里有多条 23505，说明唯一约束确实触发、兜底路径被走到 | ✅ |
| AC-4 同键不同体 → 422 `IDEMPOTENCY_KEY_REUSED`，库中仍 1 条且金额为首次值 | 是 | 集成测试（真实 Postgres） | `sameKeyWithDifferentBodyReturns422AndKeepsFirstOrder` 通过：quantity 1→2 时返回 422，error=IDEMPOTENCY_KEY_REUSED，库中单条，amount=10.00 | ✅ |
| AC-5 不带头行为不变；重复 orderNo 409 不落库；不同键同 orderNo 409 | 是 | 集成测试（真实 Postgres）+ WebMvcTest | `createsOrderAndPersistsIt`、`roundsAmountHalfUpAndPersistsRoundedValue`、`duplicateOrderNoReturns409AndDoesNotInsert`（409、count=1）、`differentKeysWithSameOrderNoReturn409`（k1/k3 → 409、count=1）全部通过；WebMvc `createsWithoutIdempotencyKey` 验证无头时不带 Replayed 头 | ✅ |
| AC-6 空白或超 64 字符 → 400 `INVALID_IDEMPOTENCY_KEY`，不调用创建逻辑 | 是 | WebMvcTest 正反例 | 反例：`rejectsBlankIdempotencyKey` 覆盖 `""` 和 `"   "`，`rejectsIdempotencyKeyLongerThan64` 覆盖 65 字符，都返回 400 + INVALID_IDEMPOTENCY_KEY 且 `verifyNoInteractions(service)`；正例：`passesValidIdempotencyKeyToServiceAndMarksReplay` 用 64 字符放行，得到 201。该条只关心请求校验逻辑，mock service 足以证明 | ✅ |
| AC-9 生产 Kibana 按 orderNo 能检到创建订单的 INFO 日志 | 否（plan 理由属实：只写日志，不写业务数据，不改接口契约） | 待人工 | 本地旁证：`OrderServiceTest.logsCreatedOrderAtInfoWithOrderNo` 通过，本轮日志里也有 `INFO ... OrderService : order created orderNo=NO-100 id=16`。生产侧步骤：1. 上线后在生产用任一 orderNo 创建订单；2. 在 Kibana 中按该 orderNo 检索（logger `c.example.demo.app.order.OrderService`）；期望：能看到一条 INFO 级 `order created orderNo=<该值> id=<订单 id>` | 👀 |

## 失败详情
- 无
