---
run_id: 20260918201421-96187
result: pass
pending: []
checked: 2026-09-18
---

# Check：折扣率允许为 0（免单）

本轮执行：`./mvnw -q test`（退出 0）、`./mvnw -q verify`（退出 0；Testcontainers 连上 colima Docker 29.5.2，拉起 postgres:16-alpine）。
surefire：OrderAmountCalculatorTest 10/10、OrderControllerWebMvcTest 12/12；failsafe：OrderApiIT 9/9，全部 0 failure / 0 error / 0 skipped。

| AC | 关键 | 验证方式 | 证据 | 结果 |
|----|------|---------|------|------|
| AC-1 单价 10.00×3、折扣率 `0` / `0.00` → `total` 返回 `0.00`（含 scale） | 是（资金计算） | core 单测 | `zeroDiscountRateMeansFreeOrder` 通过；断言 `assertEquals(new BigDecimal("0.00"), …)`（BigDecimal.equals 同时比较 scale），覆盖 `BigDecimal.ZERO` 与 `"0.00"` | ✅ |
| AC-2 折扣率 -0.01 / 1.01 抛 IllegalArgumentException；折扣率 1 返回原价 | 是（资金计算） | core 单测 | `rejectsNegativeDiscountRate`、`rejectsDiscountRateAboveOne`、`fullDiscountRateKeepsOriginalPrice`（1.00 → 30.00）、`multipliesPriceByQuantity`（ONE → 30.00）均通过 | ✅ |
| AC-3 `POST /orders` 提交 `discountRate: 0` → 201，响应 amount 0.00，库中 amount 0.00 | 是（对外接口契约 + 数据写入） | 集成测试（真实 Postgres 16，Testcontainers） | `OrderApiIT.zeroDiscountRateCreatesFreeOrderAndPersistsZeroAmount` 通过：断言 201、响应 amount `isEqualTo(0.00)`、`repository.findAll()` 唯一记录 amount `isEqualTo(0.00)`；同套 IT 其余 8 条回归（幂等、409、422、并发）均通过 | ✅ |
| AC-4 `POST /orders` 提交 `discountRate: -0.01` / `1.01` → 400，不落库 | 是（对外接口契约） | WebMvc 切片测试 | `rejectsDiscountRateOutsideZeroToOne[-0.01]`、`[1.01]` 通过：断言 400 且 `verifyNoInteractions(service)`（校验层拦截，未进入 service，因而不会写库）；日志可见 DecimalMin `>= 0.00` / DecimalMax `<= 1.00` 拒绝。另 `acceptsZeroDiscountRate[0]`、`[0.00]` 返回 201 | ✅ |

## 失败详情
无。

## 备注
- 本轮未创建命名资源；verify 期间的 postgres / ryuk 容器由 Testcontainers 创建，并由 Ryuk 在 JVM 退出时回收，所以没有登记到 `.check.resources`。
- AC-4 的"不落库"由"service 未被调用"推出，没有在真实库上用反例验证；因为拒绝发生在 Bean Validation 层、在事务之前，判定为证据充分。
