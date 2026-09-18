---
run_id: 20260918230108-53081
result: manual
pending: [AC-9]
checked: 2026-09-18
---

# Check：订单创建接口支持幂等键

环境探测：`docker ps` 成功（colima）；浏览器工具可用但本需求无可见交互，未使用；没有 AC 需要运行中的服务，未启动 dev。
执行 `./mvnw -q verify`，退出码 0。报告：core OrderAmountCalculatorTest 14/14、app OrderServiceTest 3/3、OrderControllerWebMvcTest 8/8（surefire）、OrderApiIT 10/10（failsafe，Testcontainers postgres:16-alpine），全部 failures=0 errors=0 skipped=0。容器由 Testcontainers / ryuk 回收；本轮没有自己创建资源。

| AC | 关键 | 验证方式 | 证据 | 结果 |
|----|------|---------|------|------|
| AC-1 带 k1 首次提交 → 201，库中 1 条、key=k1、hash 非空 | 是 | 集成测试（真实 Postgres） | `OrderApiIT.firstRequestWithIdempotencyKeyPersistsKeyAndHash` passed：201，无 Replayed 头，singleElement 的 idempotencyKey=k1，requestHash 长度 64 | ✅ |
| AC-2 同键同体（10 与 "10.00"）重放 → 201、响应体相同、带 Replayed 头、仍 1 条 | 是 | 集成测试（真实 Postgres） | `repeatedKeyWithSameBodyReplaysFirstResultWithoutInsert` passed：第二次 unitPrice "10.00" / discountRate "1.0"，201，`Idempotent-Replayed: true`，body 与首次 equals，count=1；另有 `existingOrderAboveLimitStillReplaysWithSameKeyAndBody` passed | ✅ |
| AC-3 同键同体 8 线程并发 → 全 201、id 相同、仅 1 条 | 是 | 集成测试（真实 Postgres 唯一约束） | `concurrentRequestsWithSameKeyInsertOnce` passed：8 线程经 latch 同时发起，全部 201，id 唯一，count=1；日志中出现多条 `uk_orders_order_no` duplicate key（并发失败方，属 plan 中预期） | ✅ |
| AC-4 同键不同体 → 422 IDEMPOTENCY_KEY_REUSED，库中 1 条且金额为首次值 | 是 | 集成测试（真实 Postgres） | `sameKeyWithDifferentBodyReturns422AndKeepsFirstOrder` passed：422，error=IDEMPOTENCY_KEY_REUSED，金额 10.00 | ✅ |
| AC-5 不带头行为不变；重复 orderNo 409 不落库；不同键同 orderNo 409 | 是 | 集成测试（真实 Postgres） | `createsOrderAndPersistsIt`、`duplicateOrderNoReturns409AndDoesNotInsert`、`roundsAmountHalfUpAndPersistsRoundedValue`、`differentKeysWithSameOrderNoReturn409` 全部 passed（409 且 count=1） | ✅ |
| AC-6 空白或超 64 字符 → 400 INVALID_IDEMPOTENCY_KEY，不调创建逻辑 | 是 | WebMvcTest 正反例 | `rejectsBlankIdempotencyKey` ×2、`rejectsIdempotencyKeyLongerThan64` passed（反例）；`passesValidIdempotencyKeyToServiceAndMarksReplay`、`createsWithoutIdempotencyKey` passed（正例） | ✅ |
| AC-9 生产 Kibana 按 orderNo 能检索到创建订单的 INFO 日志 | 否（理由属实：只看日志，不写数据、不改契约） | 待人工 | 本轮日志中已看到 `OrderService : order created orderNo=NO-402 id=3` 等 INFO 输出。步骤：1. 部署后创建一笔订单并记下 orderNo；2. 在生产 Kibana 按该 orderNo 检索；期望：能看到一条 `order created orderNo=<orderNo> id=<id>` 的 INFO 日志 | 👀 |

## 失败详情
- 无
