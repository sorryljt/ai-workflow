---
status: in-progress
tier: L              # S | M | L
stage: check
stage_result: blocked
review_round: 2
base_tree: cfd90cb07209028875531029d432308501727657
verified: {review: a909bd6e1714, check: 7056f88a1a17, inputs: e3a77e6fbc11, pending: []}
timing: {plan: 1m, code: 3m, review: 2m×2, check: 1m+3m, ship: 1m}
created: 2026-09-18
updated: 2026-09-18
---

# 订单创建接口支持幂等键

## 目标
`POST /orders` 支持可选请求头 `Idempotency-Key`：同一幂等键重复提交（含并发）只落库一条，后续请求返回首次创建的结果。
不做：幂等键过期 / 清理、按用户或租户隔离幂等键（当前无用户体系）、对其他接口的幂等支持、不带幂等键时的行为变化。

## 方案
- **契约**：请求头 `Idempotency-Key`，可选；1–64 个字符，非法（空白或超长）返回 400 `INVALID_IDEMPOTENCY_KEY`。不带头时行为与现在完全一致（重复 orderNo 仍 409）。
- **存储**：在 `orders` 表新增两列，而不是单独建幂等表——当前响应完全由 Order 推导，重放只需查回订单：
  - `idempotency_key varchar(64)` 可空，唯一约束 `uk_orders_idempotency_key`（Postgres 唯一约束允许多个 NULL，历史订单与无键请求互不影响）；
  - `request_hash char(64)` 可空，请求体指纹（SHA-256，对 orderNo / unitPrice / quantity / discountRate 规范化后计算，BigDecimal 去尾零，使 `10` 与 `10.00` 视为相同）。
  - 备选：独立 `idempotency_records` 表存响应快照。不选：响应可由订单推导，多一张表只增加一致性维护成本；将来要做 TTL 或跨接口复用时再拆。
- **重放**：先按键查，已存在且指纹一致 → 返回该订单，状态码 201、响应体同首次，额外带响应头 `Idempotent-Replayed: true`；指纹不一致 → 422 `IDEMPOTENCY_KEY_REUSED`，不落库。
- **并发**：不加锁，靠唯一约束兜底。插入抛 `DataIntegrityViolationException` 后按键再查一次：查到 → 走重放逻辑（指纹一致返回首单，不一致 422）；查不到 → 说明是 orderNo 冲突，仍抛 `DuplicateOrderException`（409）。`OrderService` 不开外层事务，`saveAndFlush` 失败后再查询走新事务，不受 Postgres 事务 aborted 状态影响。
- **与 orderNo 的关系**：同键同体重放返回 201（不是 409）；不同键但 orderNo 重复仍 409。
- **兼容 / 迁移**：沿用 `ddl-auto: update` 自动加列与约束；历史订单两列为 NULL，不回填。

## 影响范围
- `app/.../order/Order.java`：新增两列与唯一约束
- `app/.../order/OrderRepository.java`：`findByIdempotencyKey`
- `app/.../order/OrderService.java`：幂等创建逻辑、指纹计算
- `app/.../order/OrderController.java`：读取请求头、校验、`Idempotent-Replayed` 响应头、400 / 422 映射
- 新增 `IdempotencyKeyReusedException`（及可能的创建结果包装类型）
- 测试：`OrderControllerWebMvcTest`（头校验、异常映射）、`OrderApiIT`（真实 Postgres 行为与并发）
- 对外契约：新增可选请求头与 422 / 400 错误码，向后兼容

## 验收标准
- [x] AC-1：带 `Idempotency-Key: k1` 首次提交合法订单 → 201，返回订单；库中 1 条且 `idempotency_key = k1`、`request_hash` 非空。证据：OrderApiIT，真实 Postgres 查库
- [x] AC-2：同一 `k1`、同一请求体（含 `10` 与 `10.00` 这种等值写法）再次提交 → 201，响应 id / orderNo / amount 与首次相同，带 `Idempotent-Replayed: true`；库中仍 1 条。证据：OrderApiIT，真实 Postgres 计数
- [x] AC-3：同一 `k2`、同一请求体 8 个线程并发提交 → 全部 201 且 id 相同；库中该键仅 1 条。证据：OrderApiIT 并发用例，真实 Postgres 唯一约束生效
- [x] AC-4：同一 `k1`、请求体不同（如 quantity 改变）→ 422 `IDEMPOTENCY_KEY_REUSED`；库中仍 1 条且金额为首次值。证据：OrderApiIT，真实 Postgres
- [x] AC-5：不带请求头 → 行为不变：正常 201；重复 orderNo 409 且不落库；不同幂等键但 orderNo 重复 → 409。证据：OrderApiIT（现有 3 个用例保持通过 + 新增不同键同 orderNo 用例）
- [x] AC-6：`Idempotency-Key` 为空白或超过 64 字符 → 400 `INVALID_IDEMPOTENCY_KEY`，不调用创建逻辑。证据：WebMvcTest 正反例（合法键放行、非法键 400）
- [ ] AC-9（非关键，理由：只影响运维排查体验，不涉及数据写入与接口契约）：在生产日志平台（Kibana）按 orderNo 检索，能看到创建订单的 INFO 日志；只能在生产日志平台人工确认

## 任务（仅 L 档）
- [x] T1 契约与类型：`Order` 新列与唯一约束、`OrderRepository.findByIdempotencyKey`、`IdempotencyKeyReusedException`、Controller 请求头参数签名；以 `./mvnw -q test` 编译通过验证
- [x] T2 首次创建与顺序重放（对应 AC-1、AC-2；依赖 T1）
- [x] T3 同键不同体返回 422（对应 AC-4；依赖 T2）
- [x] T4 并发同键只落一条（对应 AC-3；依赖 T2）
- [x] T5 请求头校验与无键兼容、不同键同 orderNo 409（对应 AC-5、AC-6；依赖 T1）

## 假设与风险
- 假设：幂等键全局唯一，无用户 / 租户维度（当前无鉴权体系）。
- 假设：幂等键永久有效，不做过期；表增长跟随订单表本身。
- 假设：只对成功创建的请求记录幂等；首次请求失败（400 / 409）不占用该键，可用同键重试。
- 风险：`ddl-auto: update` 在生产上加唯一约束依赖 Hibernate 行为；本项目无迁移工具，沿用现状。上线到已有数据的库时，新列全为 NULL，约束可直接建立。
- 风险：并发时失败方会在日志中打印一条唯一约束 ERROR（同现有 409 用例），属预期。

## 变更记录

