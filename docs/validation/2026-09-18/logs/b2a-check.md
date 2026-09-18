---
run_id: 20260918200209-80277
result: pass
pending: []
checked: 2026-09-18
---

# Check：订单创建接口支持幂等键

环境探测：
- 浏览器：不需要（纯后端接口）。
- dev server：未启动。verify 已经用真实 Postgres 覆盖全部 AC，不需要再启动 dev server。
- 容器运行时：`docker ps` 成功（Docker 已就绪）。Testcontainers 拉起了 `postgres:16-alpine`，用完已自动移除，只剩 Testcontainers 自带的 ryuk 清理容器（会自行退出）。本轮没有手动创建容器、目录或进程，没有需要登记的资源。

本轮实际运行：`./mvnw verify` → BUILD SUCCESS
- `OrderAmountCalculatorTest`：6 个运行，0 失败
- `OrderControllerWebMvcTest`：8 个运行，0 失败
- `OrderApiIT`（Testcontainers，真实 Postgres 16）：8 个运行，0 失败

| AC | 关键 | 验证方式 | 证据 | 结果 |
|----|------|---------|------|------|
| AC-1 带 `Idempotency-Key: k1` 首次提交 → 201，库中 1 条，`idempotency_key = k1`，`request_hash` 非空 | 是（数据写入、幂等） | 集成测试（真实 Postgres）| `OrderApiIT.firstRequestWithIdempotencyKeyPersistsKeyAndHash` 通过：201，没有 `Idempotent-Replayed` 头；`findAll()` 只有 1 条，key=`k1`，hash 长度 64 | ✅ |
| AC-2 同键同体（含 `10` 与 `10.00`）重放 → 201，响应与首次相同，带 `Idempotent-Replayed: true`，库中仍 1 条 | 是（幂等） | 集成测试（真实 Postgres）| `repeatedKeyWithSameBodyReplaysFirstResultWithoutInsert` 通过：第二次请求体用 `"10.00"` / `"1.0"`，得到 201，响应头 `Idempotent-Replayed: true`，响应体与首次完全相同（id / orderNo / amount），count=1 | ✅ |
| AC-3 同键同体 8 线程并发 → 全部 201 且 id 相同，库中该键仅 1 条 | 是（并发幂等、唯一约束） | 集成测试（真实 Postgres，8 线程由 latch 同时放行）| `concurrentRequestsWithSameKeyInsertOnce` 通过：8 个请求全部 201，id 全部相同；按 `findByIdempotencyKey("k2")` 能查到，count=1 | ✅ |
| AC-4 同键异体 → 422 `IDEMPOTENCY_KEY_REUSED`，库中仍 1 条且金额为首次值 | 是（幂等、数据写入） | 集成测试（真实 Postgres）| `sameKeyWithDifferentBodyReturns422AndKeepsFirstOrder` 通过：quantity 从 1 改为 2 后得到 422，`error=IDEMPOTENCY_KEY_REUSED`；库中只有 1 条，amount 为 10.00（首次值）| ✅ |
| AC-5 不带头行为不变（201 / 重复 orderNo 409 且不落库）；异键同 orderNo → 409 | 是（对外契约、数据写入） | 集成测试（真实 Postgres）| `createsOrderAndPersistsIt`（201，count=1）、`roundsAmountHalfUpAndPersistsRoundedValue`、`duplicateOrderNoReturns409AndDoesNotInsert`（409，count=1）、`differentKeysWithSameOrderNoReturn409`（k1 / k3 使用相同 orderNo → 409，count=1）全部通过 | ✅ |
| AC-6 空白或超过 64 字符 → 400 `INVALID_IDEMPOTENCY_KEY`，不调用创建逻辑 | 是（对外契约） | WebMvcTest 正反例 | 反例：`rejectsBlankIdempotencyKey`（`""`、`"   "`）和 `rejectsIdempotencyKeyLongerThan64`（65 字符）→ 400 + `INVALID_IDEMPOTENCY_KEY` + `verifyNoInteractions(service)`。正例：`passesValidIdempotencyKeyToServiceAndMarksReplay`（恰好 64 字符）→ 201。这条只关心请求头校验逻辑，mock 的 service 足以证明 | ✅ |

## 失败详情
- 无。
