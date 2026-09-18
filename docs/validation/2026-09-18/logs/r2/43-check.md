---
run_id: 20260918204618-21654
result: manual
pending: [AC-9]
checked: 2026-09-18
---

# Check：订单创建接口支持幂等键

环境探测：浏览器工具有（本需求是纯后端接口，不需要）；Docker（colima）已就绪，`docker ps` 成功；本地 Postgres 没有探测，因为 verify 通过 Testcontainers 提供了真实 Postgres，不需要启动 dev。
本轮执行 `./mvnw -q verify`，退出码 0：core 单测 8 个通过；app 的 surefire 9 个通过（OrderControllerWebMvcTest 8 + OrderServiceTest 1）；failsafe `OrderApiIT` 8 个通过（postgres:16-alpine）。errors、failures、skipped 都是 0。本轮没有创建需要登记或清理的资源；Testcontainers 容器由 Ryuk 随 JVM 退出自动回收。

| AC | 关键 | 验证方式 | 证据 | 结果 |
|----|------|---------|------|------|
| AC-1 带 `k1` 首次提交 → 201，库中 1 条，key=k1，hash 非空 | 是（数据写入 / 接口契约） | 集成测试（真实 Postgres）| `OrderApiIT.firstRequestWithIdempotencyKeyPersistsKeyAndHash` 通过：201，没有 `Idempotent-Replayed`，查库得到单条记录，`idempotency_key=k1`，`request_hash` 长 64 | ✅ |
| AC-2 同键同体（`10` 与 `10.00`）重放 → 201，响应相同，带 `Idempotent-Replayed: true`，库中仍 1 条 | 是（幂等） | 集成测试（真实 Postgres）| `repeatedKeyWithSameBodyReplaysFirstResultWithoutInsert` 通过：第二次请求用 `"10.00"` / `"1.0"` 写法，返回 201，header 为 `true`，响应体与首次 equals，count=1 | ✅ |
| AC-3 同键 8 线程并发 → 全部 201，id 相同，库中仅 1 条 | 是（幂等 / 并发） | 集成测试（真实 Postgres 唯一约束）| `concurrentRequestsWithSameKeyInsertOnce` 通过：8 个响应都是 201，id 全部相同，count=1。日志里 NO-402 有多条 `duplicate key ... uk_orders_order_no`，并发时失败的一方被唯一约束拦下后走了重放，与 plan 的风险说明一致 | ✅ |
| AC-4 同键不同体 → 422 `IDEMPOTENCY_KEY_REUSED`，库中 1 条，金额为首次值 | 是（幂等 / 契约） | 集成测试（真实 Postgres）| `sameKeyWithDifferentBodyReturns422AndKeepsFirstOrder` 通过：quantity 从 1 改成 2 后返回 422，`error=IDEMPOTENCY_KEY_REUSED`；库中只有 1 条，amount=10.00 | ✅ |
| AC-5 不带头时行为不变；重复 orderNo 409 不落库；不同键同 orderNo 409 | 是（契约兼容 / 数据写入） | 集成测试（真实 Postgres）+ WebMvcTest | `createsOrderAndPersistsIt`、`roundsAmountHalfUpAndPersistsRoundedValue`、`duplicateOrderNoReturns409AndDoesNotInsert`（409，count=1）、`differentKeysWithSameOrderNoReturn409`（k1/k3，409，count=1）都通过；WebMvc `createsWithoutIdempotencyKey` 通过 | ✅ |
| AC-6 空白或超过 64 字符 → 400 `INVALID_IDEMPOTENCY_KEY`，不调用创建逻辑 | 是（接口契约） | WebMvcTest 正反例 | 反例：`rejectsBlankIdempotencyKey` 测了 `""` 和 `"   "`，`rejectsIdempotencyKeyLongerThan64` 测了超长键，都返回 400 `INVALID_IDEMPOTENCY_KEY`。正例：`passesValidIdempotencyKeyToServiceAndMarksReplay` 通过。测试没有用 `verify(never())` 断言 service 未被调用；`OrderController.java:33-37` 在调用 `service.create` 之前就抛出异常，所以非法键不会进入创建逻辑 | ✅ |
| AC-9 生产 Kibana 按 orderNo 能检索到创建订单的 INFO 日志 | 否（plan 的理由核对属实：只输出日志，不写数据，也不改接口契约） | 待人工 | 本地证据：`OrderServiceTest.logsCreatedOrderAtInfoWithOrderNo` 通过；IT 运行日志中有 `INFO ... OrderService : order created orderNo=NO-200 id=1`。待人工步骤：1. 部署到生产后，用 orderNo X 创建一笔订单；2. 在 Kibana 用 `order created orderNo=X` 检索；3. 期望看到 1 条 INFO 级别日志，logger 为 `c.example.demo.app.order.OrderService`，里面带 orderNo 和 id | 👀 |

## 失败详情
- 无
