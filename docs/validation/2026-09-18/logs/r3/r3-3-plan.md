---
status: in-progress
tier: M
stage: check
stage_result: blocked
review_round: 1
base_tree: 4c47f9619740f978b2a74e94b11a834c172cd26f
verified: {review: a909bd6e1714, check: a909bd6e1714, inputs: 6054479a171a, pending: []}
timing: {plan: 1m, code: 2m, review: 1m, check: 1m, ship: 1m}
created: 2026-09-18
updated: 2026-09-18
---

# 订单金额上限 100 万

## 目标
OrderAmountCalculator.total 的计算结果超过 1000000.00 时抛 IllegalArgumentException，阻止新建超限订单。
不做：不改请求体校验（CreateOrderRequest 不加金额相关约束）、不改 IllegalArgumentException 的 HTTP 映射、不处理已落库的历史订单。

## 方案
1. 上限比较在舍入之后：先按 HALF_UP 保留 2 位，再与 `1000000.00` 比较，严格大于才抛。
   - 需求原文是"计算结果超过 100 万"，计算结果即舍入后的金额；1000000.00 本身允许。
   - 于是 1000000.004 → 1000000.00 放行，1000000.005 → 1000000.01 拒绝。
   - 上限作为 `OrderAmountCalculator.MAX_TOTAL` 公开常量，与 `SCALE` 并列。
2. OrderService.create 把金额计算挪到幂等键回查未命中之后。
   - 依据 pitfall《OrderService.create 先算金额再按幂等键回查，重放也受当前金额校验约束》：当前先算金额，库里已有的超限带键订单（上限生效前创建）重放会得到 500 而不是首单 201，违背"永久有效"口径；知识条目要求下次收紧校验时先挪计算。
   - 挪动后：带键且命中 → 直接重放（不再算金额，requestHash 比较照旧）；未命中或不带键 → 算金额（可能抛超限）→ 插入。插入冲突后的回查分支不涉及金额计算，不变。
   - 备选：不挪，保持现状。代价是历史超限带键订单重放变 500；无法确认生产没有这类数据，不选。
3. HTTP 映射不变：IllegalArgumentException 目前无专门 handler，与 quantity 上限（2026-09-18--quantity-limit）一致，走默认 500。
   - 备选：给 IllegalArgumentException 加 400 handler。会同时改变 quantity 上限、负单价等已有行为的对外状态码，属于接口契约变化，本需求不做。

## 影响范围
- core/src/main/java/com/example/demo/core/OrderAmountCalculator.java：新增 MAX_TOTAL 与超限校验
- core/src/test/java/com/example/demo/core/OrderAmountCalculatorTest.java：边界用例
- app/src/main/java/com/example/demo/app/order/OrderService.java：金额计算后移
- app/src/test/java/com/example/demo/app/order/OrderServiceTest.java、OrderApiIT.java：超限拒绝与历史订单重放

## 验收标准
- [x] AC-1：计算器边界——结果 1000000.00（如 10000.00 × 100 × 1）正常返回；结果 1000000.01 抛 IllegalArgumentException；舍入边界：未舍入值 1000000.004 放行得 1000000.00，1000000.005 抛异常；原有 quantity / 单价 / 折扣校验和 HALF_UP 舍入用例全部仍通过。证据：新增边界测试的 RED/GREEN 输出。
- [x] AC-2：POST /orders 请求金额超限（如单价 1000000.01、数量 1、折扣 1）不返回 201，orders 表不新增记录；带新幂等键时同样拒绝且不落库。证据：真实 Postgres 上的 OrderApiIT，断言状态码非 2xx 且行数为 0。
- [x] AC-3：库里已有一条带幂等键、金额超过 100 万的订单（测试直接写库模拟上限生效前的数据），用同键同体重放返回 201、带 Idempotent-Replayed: true、返回原订单，且不新增记录；同键不同体仍返回 422。证据：真实 Postgres 上的 OrderApiIT。

## 实现验证
- AC-1 RED：`./mvnw -q -pl core test`，11 个测试 2 个失败（rejectsTotalAboveMaximum、comparesMaximumAfterRounding：未抛异常）。GREEN：同命令 11 passed。
- AC-2/AC-3 RED：`./mvnw -q test`，OrderServiceTest.replaysExistingOrderAboveAmountLimitWithoutRecalculating 报 IllegalArgument（重放前就算了金额）。GREEN：金额计算后移后 `./mvnw -q test` 退出码 0，core 11 + app 11 = 22 passed（新增 5）。
- `./mvnw -q verify` 退出码 0，OrderApiIT 10 passed（新增 amountAboveLimitIsRejectedAndNotPersisted、existingOrderAboveLimitStillReplaysWithSameKeyAndBody，真实 Postgres）。
- typecheck / lint 未配置，编译由 test 覆盖。

## 假设与风险
- 假设：上限值固定为 1000000.00，不需要配置化。
- 假设：超限统一用 IllegalArgumentException，消息写明上限值。
- 风险：金额计算后移后，带键重放不再校验当前入参合法性；因为 requestHash 必须与首单一致，首单当时已通过校验，可接受。

## 变更记录
