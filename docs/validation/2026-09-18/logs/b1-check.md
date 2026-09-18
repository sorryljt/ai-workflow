---
run_id: 20260918200033-78048
result: blocked
pending:
  - "AC-1：需要真实 Postgres 验证落库列值；Docker 未就绪（colima docker.sock 不存在），verify 无法执行"
  - "AC-2：需要真实 Postgres 计数验证重放不落库；Docker 未就绪"
  - "AC-3：并发同键依赖 Postgres 唯一约束兜底；Docker 未就绪"
  - "AC-4：同键异体 422 且不落库需真实库验证；Docker 未就绪"
  - "AC-5：无键 / 异键同 orderNo 的 409 依赖真实唯一约束；Docker 未就绪"
checked: 2026-09-18
---

# Check：订单创建接口支持幂等键

环境探测：
- 浏览器：不需要（纯后端接口）。
- dev server：需要本地 Postgres，未探测到可用库，未启动。
- 容器运行时：`docker ps` 失败 —— `failed to connect to the docker API at unix:///Users/dawson/.colima/default/docker.sock ... no such file or directory`。因此 `./mvnw -q verify`（OrderApiIT，Testcontainers）无法执行，本轮未运行。
- 本轮未创建任何容器、临时目录或进程，无需登记和清理资源。

本轮实际运行：`./mvnw test` → BUILD SUCCESS；`OrderAmountCalculatorTest` 6 个通过，`OrderControllerWebMvcTest` 8 个通过，0 失败。

| AC | 关键 | 验证方式 | 证据 | 结果 |
|----|------|---------|------|------|
| AC-1 带 `Idempotency-Key: k1` 首次提交 → 201，库中 1 条，`idempotency_key = k1`，`request_hash` 非空 | 是（数据写入、幂等） | 证据缺失 | 需要 OrderApiIT `firstRequestWithIdempotencyKeyPersistsKeyAndHash` 在真实 Postgres 上运行；Docker 未就绪，verify 未执行 | ⛔ |
| AC-2 同键同体（含 `10` 与 `10.00`）重放 → 201，id/orderNo/amount 与首次相同，带 `Idempotent-Replayed: true`，库中仍 1 条 | 是（幂等） | 证据缺失 | WebMvcTest `passesValidIdempotencyKeyToServiceAndMarksReplay` 只证明 Controller 在 service 返回 replayed=true 时输出该响应头（service 是 mock）；指纹等值判断和"不重复落库"需 OrderApiIT `repeatedKeyWithSameBodyReplaysFirstResultWithoutInsert` 在真实库上运行，本轮未执行 | ⛔ |
| AC-3 同键同体 8 线程并发 → 全部 201 且 id 相同，库中该键仅 1 条 | 是（并发幂等、唯一约束） | 证据缺失 | 需要 OrderApiIT `concurrentRequestsWithSameKeyInsertOnce` 在真实库上运行；Docker 未就绪 | ⛔ |
| AC-4 同键异体 → 422 `IDEMPOTENCY_KEY_REUSED`，库中仍 1 条且金额为首次值 | 是（幂等、数据写入） | 证据缺失 | WebMvcTest `mapsReusedIdempotencyKeyTo422` 只证明异常到 422 的映射（mock service）；异体检测和不落库需 OrderApiIT `sameKeyWithDifferentBodyReturns422AndKeepsFirstOrder`，本轮未执行 | ⛔ |
| AC-5 不带头行为不变（201 / 重复 orderNo 409 且不落库）；异键同 orderNo → 409 | 是（对外契约、数据写入） | 证据缺失 | WebMvcTest `createsWithoutIdempotencyKey`、`mapsDuplicateOrderTo409` 通过，但只覆盖 Controller 层映射；409 依赖 Postgres 唯一约束和重查逻辑，需要 OrderApiIT `duplicateOrderNoReturns409AndDoesNotInsert` / `differentKeysWithSameOrderNoReturn409`，本轮未执行 | ⛔ |
| AC-6 空白或超过 64 字符 → 400 `INVALID_IDEMPOTENCY_KEY`，不调用创建逻辑 | 是（对外契约） | WebMvcTest 正反例 | `./mvnw test`：OrderControllerWebMvcTest 8 passed。反例：`rejectsBlankIdempotencyKey`（`""`、`"   "`）和 `rejectsIdempotencyKeyLongerThan64`（65 字符）→ 400 + `INVALID_IDEMPOTENCY_KEY` + `verifyNoInteractions(service)`；正例：`passesValidIdempotencyKeyToServiceAndMarksReplay`（恰好 64 字符）→ 201 | ✅ |

## 失败详情
- 无观察到的失败。AC-1～AC-5 是关键 AC，只能在真实 Postgres 上验证，本轮缺少证据。解除阻塞：启动 colima（`colima start`）或 Docker Desktop，确认 `docker ps` 成功后重新运行 check（`./mvnw -q verify`）。
