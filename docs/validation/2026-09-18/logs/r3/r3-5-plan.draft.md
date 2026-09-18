---
status: draft
tier: M
stage: plan
stage_result: ok
review_round: 0
base_tree:
verified: {}
timing: {}
created: 2026-09-18
updated: 2026-09-18
---

# 订单数量上限 999

## 目标
订单金额计算的数量 quantity 增加上限：超过 999（即 ≥ 1000）时抛 `IllegalArgumentException`，999 仍合法；合法区间由 [1, +∞) 收紧为 [1, 999]。
不做：按商品 / 用户区分的上限、上限可配置化、历史订单处理。

## 方案
- core：`OrderAmountCalculator` 新增常量 `QUANTITY_MAX = 999`，在 `quantity <= 0` 校验之后增加 `quantity > QUANTITY_MAX` 校验，异常文案 `quantity 不能超过 999`；类注释补充数量区间 [1, 999]。
- app：`CreateOrderRequest.quantity` 增加 `@Max(OrderAmountCalculator.QUANTITY_MAX)`（注解属性需编译期常量，`static final int` 满足）。
  理由：只改 core 的话，`POST /orders` 提交 1000 时 `IllegalArgumentException` 未被映射，会冒成 500；与现有数量下界 `@Min(1)` 一样在参数校验层返回 400 更一致。
  备选：只改 core，接口层保持不变（1000 → 500）。不选：把客户端输入错误报成服务端错误。
- 持久化：不存 quantity，只存 amount；历史订单不受影响，不需要迁移。
- 对外契约变化：`quantity >= 1000` 的请求由 201 变为 400。
- 幂等：同一幂等键下首次以 quantity ≥ 1000 创建过的订单，上线后以相同请求重放会在参数校验层返回 400，而不是重放 201（见风险）。

## 影响范围
- `core/src/main/java/com/example/demo/core/OrderAmountCalculator.java`：新增常量与校验、类注释
- `core/src/test/java/com/example/demo/core/OrderAmountCalculatorTest.java`：999 / 1000 边界用例
- `app/src/main/java/com/example/demo/app/order/CreateOrderRequest.java`：`quantity` 增加 `@Max`
- `app/src/test/java/com/example/demo/app/order/OrderControllerWebMvcTest.java`：999 返回 201、1000 返回 400
- 接口：`POST /orders` 请求体 `quantity` 取值范围 [1, +∞) → [1, 999]

## 验收标准
- [ ] AC-1：给定单价 10.00、折扣率 1，数量 999 时 `OrderAmountCalculator.total` 返回 `9990.00`；数量 1000 及 `Integer.MAX_VALUE` 时抛 `IllegalArgumentException`。　证据：core 单测覆盖 999 / 1000 两侧边界。
- [ ] AC-2：`POST /orders` 提交 `quantity: 1000` 返回 400 且 service 未被调用；提交 `quantity: 999` 返回 201。　证据：WebMvc 切片测试断言状态码与 service 调用次数。

## 假设与风险
- 假设："超过 999"指严格大于，999 本身合法。
- 假设：上限对所有订单统一，不需要开关或配置。
- 风险：已有调用方若传 ≥ 1000 的数量，上线后由 201 变为 400；本仓库内无此类调用方，外部调用方需知会。
- 风险：以 quantity ≥ 1000 创建过的幂等键，重放将得到 400 而非原订单。

## 变更记录

## 本轮运行配置
```viktor-checks
test: ./mvnw -q test
verify: ./mvnw -q verify
```
- 环境前提 / 来源：README.md「跑测试」一节；以仓库根目录为工作目录。`test` 跑 core 单测 + app WebMvc 切片（不需要 Docker）；`verify` 追加 app 的 `*IT`（failsafe，Testcontainers 拉起 postgres:16-alpine，需要 Docker）。无独立 typecheck / lint，编译在 test 阶段完成。
