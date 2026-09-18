---
run_id: 20260918195819-75330
result: pass
pending: []
checked: 2026-09-18
---

# Check：订单创建接口支持幂等键

环境探测：浏览器工具可用但本需求为纯后端接口，不需要；`docker ps` 成功，verify 前提已满足；未启动 dev server（verify 用 Testcontainers 真实 Postgres 已足够覆盖）。

本轮命令：`./mvnw verify` → BUILD SUCCESS
- core `OrderAmountCalculatorTest`：6 run, 0 failures
- app `OrderControllerWebMvcTest`：8 run, 0 failures
- app `OrderApiIT`（Testcontainers `postgres:16-alpine`）：8 run, 0 failures

| AC | 关键 | 验证方式 | 证据 | 结果 |
|----|------|---------|------|------|
| AC-1 带 `k1` 首次提交 → 201；库中 1 条，`idempotency_key = k1`、`request_hash` 非空 | 是（数据写入 / 幂等） | 集成测试（真实 Postgres） | `OrderApiIT.firstRequestWithIdempotencyKeyPersistsKeyAndHash` 通过：201、无 `Idempotent-Replayed` 头，查库只有 1 条，key=k1、hash 长度 64 | ✅ |
| AC-2 同键同体（`10` 与 `10.00` 等值写法）重放 → 201，响应相同，带 `Idempotent-Replayed: true`，库中仍 1 条 | 是（幂等） | 集成测试（真实 Postgres） | `repeatedKeyWithSameBodyReplaysFirstResultWithoutInsert` 通过：第二次请求体为 `"10.00"` / `"1.0"`，201，头值为 `true`，响应体与首次 equals（id/orderNo/amount），count=1 | ✅ |
| AC-3 同键同体 8 线程并发 → 全部 201 且 id 相同；库中仅 1 条 | 是（幂等 / 并发） | 集成测试（真实 Postgres 唯一约束） | `concurrentRequestsWithSameKeyInsertOnce` 通过：8 个结果均 201，id 全部相同，`findByIdempotencyKey("k2")` 存在，count=1 | ✅ |
| AC-4 同键不同体 → 422 `IDEMPOTENCY_KEY_REUSED`；库中仍 1 条且金额为首次值 | 是（幂等 / 数据写入） | 集成测试（真实 Postgres） | `sameKeyWithDifferentBodyReturns422AndKeepsFirstOrder` 通过：quantity 1→2，返回 422 且 `error=IDEMPOTENCY_KEY_REUSED`，库中唯一一条 amount=10.00 | ✅ |
| AC-5 不带头行为不变（201；重复 orderNo 409 不落库）；不同键同 orderNo → 409 | 是（对外契约兼容） | 集成测试（真实 Postgres）+ WebMvcTest | `createsOrderAndPersistsIt`、`roundsAmountHalfUpAndPersistsRoundedValue`、`duplicateOrderNoReturns409AndDoesNotInsert`、`differentKeysWithSameOrderNoReturn409`（409、count=1）通过；`createsWithoutIdempotencyKey` 验证无键时不带 `Idempotent-Replayed` 头 | ✅ |
| AC-6 键为空白或超 64 字符 → 400 `INVALID_IDEMPOTENCY_KEY`，不调用创建逻辑 | 是（对外契约） | WebMvcTest（纯请求校验逻辑，不涉及持久化） | `rejectsBlankIdempotencyKey`（`""`、`"   "`）与 `rejectsIdempotencyKeyLongerThan64`（65 字符）均 400 + 错误码且 `verifyNoInteractions(service)`；正例 `passesValidIdempotencyKeyToServiceAndMarksReplay`（64 字符）放行 201 | ✅ |

## 失败详情
- 无

## 备注
- 本轮资源仅为 Testcontainers 自动管理的 postgres / ryuk 容器，测试结束后 postgres 容器已被移除，ryuk 自行退出；未创建需登记到 `.check.resources` 的资源。
