---
run_id: 20260918200402-82514
result: pass
pending: []
checked: 2026-09-18
---

# Check：订单创建接口支持幂等键

环境探测：
- 浏览器：没用上。这是纯后端接口，没有可见交互。
- dev server：没启动。verify 已经在真实 Postgres 上覆盖了全部 AC，不需要再起 dev server。
- 容器运行时：`docker ps` 成功（colima，`unix:///Users/dawson/.colima/default/docker.sock`）。Testcontainers 拉起了 `postgres:16-alpine`，跑完后已被自动移除（`docker ps -a --filter ancestor=postgres:16-alpine` 结果为空）。本轮没有手动创建容器、目录或进程，`.check.resources` 里没有需要登记的内容。

本轮实际运行：`./mvnw -q verify`，没有失败输出。报告文件时间戳为 20:04（本轮），具体结果：
- `OrderAmountCalculatorTest`（surefire）：tests=6，failures=0，errors=0
- `OrderControllerWebMvcTest`（surefire）：tests=8，failures=0，errors=0
- `OrderApiIT`（failsafe，Testcontainers 真实 Postgres 16）：tests=8，failures=0，errors=0
- 日志里出现的 `duplicate key ... uk_orders_order_no` ERROR 来自 409 用例和并发用例中冲突的一方，属于预期输出。

| AC | 关键 | 验证方式 | 证据 | 结果 |
|----|------|---------|------|------|
| AC-1 带 `Idempotency-Key: k1` 首次提交 → 201，库中 1 条，`idempotency_key = k1`，`request_hash` 非空；另需覆盖同键并发 | 是（数据写入、幂等） | 集成测试（真实 Postgres）| `OrderApiIT.firstRequestWithIdempotencyKeyPersistsKeyAndHash` 通过：返回 201，没有 `Idempotent-Replayed` 头；`findAll()` 只有 1 条，key=`k1`，hash 长度为 64。同键并发由 AC-3 的 8 线程用例覆盖 | ✅ |
| AC-2 同键同体（含 `10` 与 `10.00`）重放 → 201，响应与首次相同，带 `Idempotent-Replayed: true`，库中仍 1 条 | 是（幂等） | 集成测试（真实 Postgres）| `repeatedKeyWithSameBodyReplaysFirstResultWithoutInsert` 通过：第二次请求体用 `"10.00"` / `"1.0"`，返回 201，响应头 `Idempotent-Replayed: true`，响应体与首次完全相同（`isEqualTo(first.getBody())`），count=1 | ✅ |
| AC-3 同键同体 8 线程并发 → 全部 201 且 id 相同，库中该键仅 1 条 | 是（并发幂等、唯一约束） | 集成测试（真实 Postgres，8 线程由 latch 同时放行）| `concurrentRequestsWithSameKeyInsertOnce` 通过：8 个请求全部返回 201，id 全部相同；`findByIdempotencyKey("k2")` 能查到，count=1。日志显示有 3 个线程命中唯一约束冲突后走了重放路径 | ✅ |
| AC-4 同键异体 → 422 `IDEMPOTENCY_KEY_REUSED`，库中仍 1 条且金额为首次值 | 是（幂等、数据写入） | 集成测试（真实 Postgres）| `sameKeyWithDifferentBodyReturns422AndKeepsFirstOrder` 通过：quantity 从 1 改为 2 后返回 422，`error=IDEMPOTENCY_KEY_REUSED`；库中只有 1 条，amount=10.00（首次值） | ✅ |
| AC-5 不带头时行为不变（201；重复 orderNo 返回 409 且不落库）；不同键但 orderNo 相同 → 409 | 是（对外契约、数据写入） | 集成测试（真实 Postgres）| `createsOrderAndPersistsIt`（201，count=1）、`roundsAmountHalfUpAndPersistsRoundedValue`、`duplicateOrderNoReturns409AndDoesNotInsert`（409，count=1）、`differentKeysWithSameOrderNoReturn409`（k1 / k3 用相同 orderNo → 409，count=1）全部通过 | ✅ |
| AC-6 空白或超过 64 字符 → 400 `INVALID_IDEMPOTENCY_KEY`，不调用创建逻辑 | 是（对外契约） | WebMvcTest 正反例 | 反例：`rejectsBlankIdempotencyKey`（`""`、`"   "`）和 `rejectsIdempotencyKeyLongerThan64`（65 字符）→ 400 + `INVALID_IDEMPOTENCY_KEY` + `verifyNoInteractions(service)`。正例：`passesValidIdempotencyKeyToServiceAndMarksReplay`（恰好 64 字符）→ 201。这条只验证 Controller 层的请求头校验，不涉及持久化，用 mock 的 service 就足以证明 | ✅ |

## 失败详情
- 无。
