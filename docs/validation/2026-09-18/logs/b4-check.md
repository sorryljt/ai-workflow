---
run_id: 20260918200730-86340
result: blocked
pending:
  - "AC-1：OrderApiIT 整个类被 @Disabled（本轮 8 个用例全部 Skipped），缺少真实 Postgres 上的落库证据"
  - "AC-2：同上，缺少重放与库中计数的真实库证据"
  - "AC-3：同上，缺少并发下唯一约束生效的真实库证据"
  - "AC-4：同上，WebMvcTest 只覆盖 422 映射（service 是 mock），缺少“库中仍 1 条且金额为首次值”的证据"
  - "AC-5：同上，缺少无键兼容、重复 orderNo 409 不落库、不同键同 orderNo 409 的真实库证据"
checked: 2026-09-18
---

# Check：订单创建接口支持幂等键

证据来源：本轮 `./mvnw verify` → BUILD SUCCESS，但 OrderApiIT 输出 `Tests run: 8, Failures: 0, Errors: 0, Skipped: 8`。原因：`app/src/test/java/com/example/demo/app/order/OrderApiIT.java:33` 在类上标了 `@Disabled("临时：验证全部跳过不得通过")`。其余执行结果：core OrderAmountCalculatorTest 6/6 通过，OrderControllerWebMvcTest 8/8 通过（0 skipped）。

环境探测：Docker 就绪（`docker ps` 成功）；本会话不允许执行 `docker run`，所以没办法自己起 Postgres 再用 dev server + curl 补证据，这条路径已放弃（容器未创建，`docker ps -a` 确认无残留）。纯后端 API，不需要浏览器。

| AC | 关键 | 验证方式 | 证据 | 结果 |
|----|------|---------|------|------|
| AC-1 带 `k1` 首次提交 → 201，库中 1 条，key=k1、hash 非空 | 是（数据写入 / 幂等） | 证据缺失 | OrderApiIT 被 @Disabled，本轮 Skipped；无其他真实库证据 | ⛔ |
| AC-2 同键同体（含 10 与 10.00）重放 → 201，id/orderNo/amount 相同，`Idempotent-Replayed: true`，库中仍 1 条 | 是（幂等 / 契约） | 证据缺失 | OrderApiIT 被跳过；WebMvcTest.passesValidIdempotencyKeyToServiceAndMarksReplay 只证明 Controller 会输出响应头（service 是 mock），不证明重放与计数 | ⛔ |
| AC-3 同键同体 8 线程并发 → 全 201 且 id 相同，库中 1 条 | 是（幂等 / 并发） | 证据缺失 | OrderApiIT 并发用例被跳过；唯一约束兜底只能在真实库上验证 | ⛔ |
| AC-4 同键不同体 → 422 `IDEMPOTENCY_KEY_REUSED`，库中仍 1 条且金额为首次值 | 是（幂等 / 契约） | 证据缺失（仅部分覆盖） | WebMvcTest.mapsReusedIdempotencyKeyTo422 通过（只证明异常→422 的映射）；指纹比对与“不落库”在 OrderApiIT 中，被跳过 | ⛔ |
| AC-5 无请求头行为不变；重复 orderNo 409 不落库；不同键同 orderNo 409 | 是（契约 / 数据写入） | 证据缺失（仅部分覆盖） | WebMvcTest.createsWithoutIdempotencyKey、mapsDuplicateOrderTo409 通过（mock service）；真实库中的 409 与不落库在 OrderApiIT 中，被跳过 | ⛔ |
| AC-6 空白或 >64 字符 → 400 `INVALID_IDEMPOTENCY_KEY`，不调用创建逻辑 | 是（对外契约） | WebMvcTest 正反例 | 本轮执行通过：rejectsBlankIdempotencyKey ×2（"" 与 "   "）、rejectsIdempotencyKeyLongerThan64（断言 400 + 错误码 + verifyNoInteractions(service)）；正例：passesValidIdempotencyKeyToServiceAndMarksReplay（64 字符放行）、createsWithoutIdempotencyKey | ✅ |

## 失败详情
- 无（没有观察到行为错误；阻塞原因是关键 AC 缺少证据）。
- 解除阻塞：去掉 `OrderApiIT` 类上的 `@Disabled`，在 Docker 就绪的环境中重跑 `./mvnw -q verify`，确认 OrderApiIT 8 个用例都实际执行（Skipped 为 0）并通过。
