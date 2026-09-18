---
run_id: 20260918200610-84638
result: manual
pending: ["AC-9：生产 Kibana 按 orderNo 检索创建订单 INFO 日志，只能在生产日志平台人工确认"]
checked: 2026-09-18
---

# Check：订单创建接口支持幂等键

证据来源：本轮 `./mvnw verify`（Docker 就绪，Testcontainers `postgres:16-alpine`）→ BUILD SUCCESS；core OrderAmountCalculatorTest 6/6，OrderControllerWebMvcTest 8/8，OrderApiIT 8/8（真实 Postgres），0 failures / 0 errors。纯后端 API，不需要浏览器操作。

| AC | 关键 | 验证方式 | 证据 | 结果 |
|----|------|---------|------|------|
| AC-1 带 `k1` 首次提交 → 201，库中 1 条，key=k1、hash 非空 | 是（数据写入 / 幂等） | 集成测试（真实 Postgres） | OrderApiIT.firstRequestWithIdempotencyKeyPersistsKeyAndHash passed | ✅ |
| AC-2 同键同体（含 10 与 10.00）重放 → 201，id/orderNo/amount 相同，`Idempotent-Replayed: true`，库中仍 1 条 | 是（幂等 / 契约） | 集成测试（真实 Postgres） | OrderApiIT.repeatedKeyWithSameBodyReplaysFirstResultWithoutInsert passed（第二次用 "10.00"/"1.0"，断言响应头 true、repository.count()=1） | ✅ |
| AC-3 同键同体 8 线程并发 → 全 201 且 id 相同，库中 1 条 | 是（幂等 / 并发） | 集成测试（真实 Postgres 唯一约束） | OrderApiIT.concurrentRequestsWithSameKeyInsertOnce passed（线程池 + CountDownLatch 同时放行，断言 count=1） | ✅ |
| AC-4 同键不同体 → 422 `IDEMPOTENCY_KEY_REUSED`，库中仍 1 条且金额为首次值 | 是（幂等 / 契约） | 集成测试（真实 Postgres） | OrderApiIT.sameKeyWithDifferentBodyReturns422AndKeepsFirstOrder passed（断言 amount=10.00、count=1）；WebMvcTest.mapsReusedIdempotencyKeyTo422 passed | ✅ |
| AC-5 无请求头行为不变；重复 orderNo 409 不落库；不同键同 orderNo 409 | 是（契约 / 数据写入） | 集成测试（真实 Postgres） | OrderApiIT.createsOrderAndPersistsIt、duplicateOrderNoReturns409AndDoesNotInsert、roundsAmountHalfUpAndPersistsRoundedValue、differentKeysWithSameOrderNoReturn409 passed；日志中 `uk_orders_order_no` ERROR 为预期 | ✅ |
| AC-6 空白或 >64 字符 → 400 `INVALID_IDEMPOTENCY_KEY`，不调用创建逻辑 | 是（对外契约） | WebMvcTest 正反例 | rejectsBlankIdempotencyKey ×2、rejectsIdempotencyKeyLongerThan64 passed（verifyNoInteractions(service)）；正例 passesValidIdempotencyKeyToServiceAndMarksReplay、createsWithoutIdempotencyKey passed | ✅ |
| AC-9 生产 Kibana 按 orderNo 能检索到创建订单 INFO 日志 | 否（plan 理由：只影响运维排查体验，不涉及数据写入与接口契约——核对属实） | 待人工 | 步骤：1. 部署后调用 `POST /orders` 创建一个唯一 orderNo 的订单；2. 在生产 Kibana 按该 orderNo 检索；期望：能看到一条对应的创建订单 INFO 日志 | 👀 |

## 失败详情
- 无
