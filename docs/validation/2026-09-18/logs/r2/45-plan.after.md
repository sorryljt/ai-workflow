---
status: in-progress      # draft | confirmed | in-progress | done | archived
tier: L              # S | M | L
stage: review        # plan | code | review | check | ship | done（最近完成或停住的节点）
stage_result: error  # ok | blocked | error
review_round: 0
base_tree: 87e1228dc1d4d5ee9d1d141a59df9df89b099615
verified: {}
timing: {plan: 1m, code: 2m, review: 1m}
created: 2026-09-18
updated: 2026-09-18
---

# 折扣率最多 4 位小数

## 目标
订单金额计算的折扣率 `discountRate` 允许精确到 4 位小数，超过 4 位小数报错（core 抛 `IllegalArgumentException`，`POST /orders` 返回 400）。
不做：金额结果精度调整（仍 HALF_UP 保留 2 位）、折扣率持久化、历史数据处理。

## 现状核对（与需求描述不一致）
需求写"目前最多 2 位"，但代码中没有任何小数位限制：
- `OrderAmountCalculator.total` 只校验 [0, 1] 区间；
- `CreateOrderRequest.discountRate` 只有 `@DecimalMin("0.00") @DecimalMax("1.00")`，这两个注解只限取值，不限小数位；
- 现有单测已在使用 `0.678`、`0.3333`。

所以"允许 4 位"现状已满足，本需求的实际改动是**新增"最多 4 位小数"的上限**：5 位及以上的请求由 201 变为 400，属于对外契约收紧。

## 方案
- 小数位按**有效小数位**判断：`discountRate.stripTrailingZeros().scale() > 4` 视为超限。`0.12340`（尾零）按 4 位处理，接受；`0.12345` 拒绝。
  备选：按原始 scale 判断，`0.12340` 也拒绝。不选：数值上是 4 位小数，拒绝尾零会让 `1.00000` 这类写法意外失败，且与幂等指纹"去尾零后视为同一请求"的口径不一致。
- core：`OrderAmountCalculator` 增加常量 `DISCOUNT_RATE_MAX_SCALE = 4`，在区间校验后增加小数位校验，抛 `IllegalArgumentException("discountRate 最多 4 位小数")`；类注释补充该规则。
- app：`CreateOrderRequest` 增加 `@AssertTrue` 校验方法 `isDiscountRateScaleValid()`（去尾零后小数位 ≤ `OrderAmountCalculator.DISCOUNT_RATE_MAX_SCALE`），参数校验层返回 400，不进 service。
  原计划用 `@Digits(integer = 1, fraction = 4)`，code 阶段实测它按原始 scale 计数，会以 400 拒绝 `0.12340`，与决定 1 冲突，改为上述方式（见变更记录）。
  备选：只改 core，接口层依赖 core 的 `IllegalArgumentException`。不选：当前 controller 没有把 `IllegalArgumentException` 映射成 400，会变成 500。
- 持久化：`discountRate` 不落库（`orders` 只存 `amount numeric(12,2)`），无迁移。
- 幂等指纹：不改；超限请求在校验层即被拒，不会产生订单。

## 影响范围
- `core/src/main/java/com/example/demo/core/OrderAmountCalculator.java`：新增小数位校验、常量、注释
- `core/src/test/java/com/example/demo/core/OrderAmountCalculatorTest.java`：4 位通过 / 5 位报错 / 尾零用例
- `app/src/main/java/com/example/demo/app/order/CreateOrderRequest.java`：`@AssertTrue` 校验 `discountRate` 小数位
- `app/src/test/java/com/example/demo/app/order/OrderControllerWebMvcTest.java`：5 位返回 400、4 位 / 尾零返回 201
- `app/src/test/java/com/example/demo/app/order/OrderApiIT.java`：4 位折扣率端到端创建并落库
- 接口：`POST /orders` 请求体 `discountRate` 新增约束"最多 4 位小数"

## 验收标准
- [x] AC-1：给定单价 10.00、数量 1、折扣率 `0.1235`，`OrderAmountCalculator.total` 返回 `1.24`（10 × 0.1235 = 1.235，HALF_UP）；折扣率 `0.12340` 返回 `1.23`。　证据：core 单测，`assertEquals(new BigDecimal(...), …)` 同时校验 scale。
  实现：`OrderAmountCalculatorTest.acceptsDiscountRateWithFourDecimals`、`ignoresTrailingZerosWhenCountingDiscountRateDecimals`（现状下即通过，作为回归保护）。
- [x] AC-2：折扣率 `0.12345`（5 位）或 `0.000001` 时，`total` 抛 `IllegalArgumentException`；原有 [0, 1] 区间校验不变。　证据：core 单测。
  实现：`rejectsDiscountRateWithMoreThanFourDecimals`（RED：未抛异常；GREEN 后通过）；区间用例 `rejectsNegativeDiscountRate` / `rejectsDiscountRateAboveOne` 保持通过。
- [x] AC-3：`POST /orders` 提交 `discountRate: 0.12345`，返回 400，service 未被调用；提交 `0.1235`、`0.12340` 返回 201。　证据：WebMvc 切片测试断言状态码与 `verifyNoInteractions(service)`。
  实现：`OrderControllerWebMvcTest.rejectsDiscountRateWithMoreThanFourDecimals`（0.12345 / 0.000001；RED：校验放行后调用到 service mock）、`acceptsDiscountRateWithUpToFourDecimals`（0.1235 / 0.12340；`@Digits` 方案下 0.12340 返回 400，改方案后通过）。
- [x] AC-4：`POST /orders` 提交单价 10.00、数量 1、`discountRate: 0.1235`，返回 201，响应与数据库中 `amount` 均为 1.24。　证据：OrderApiIT 在真实 Postgres（Testcontainers）下断言响应与落库值。
  实现：`OrderApiIT.fourDecimalDiscountRateCreatesOrderAndPersistsRoundedAmount`；另加 `discountRateWithMoreThanFourDecimalsReturns400AndDoesNotInsert`。两条单独 verify 通过（Docker 可用），完整 verify 留给 check。

## 任务
- [x] T1 core 增加折扣率小数位上限常量与校验，补 4 位 / 5 位 / 尾零单测（对应 AC-1、AC-2）
- [x] T2 `CreateOrderRequest` 加 `discountRate` 小数位校验，补 WebMvc 400 / 201 用例（对应 AC-3；依赖 T1）
- [x] T3 OrderApiIT 新增 4 位折扣率创建订单并校验落库金额（对应 AC-4；依赖 T1、T2）

## 假设与风险
- 假设：需求本意是"精度上限为 4 位"，而不是"放宽某个已存在的 2 位限制"（该限制在代码中不存在）。
- 假设：有效小数位按去尾零计算。
- 风险：契约收紧后，当前传 5 位及以上小数的调用方会从 201 变为 400；仓库内无法确认线上是否存在此类调用。

## 变更记录
- 2026-09-18：用户确认需求前提与现状不符，按"新增 4 位小数上限"实施。
- 2026-09-18：接口层由 `@Digits(integer = 1, fraction = 4)` 改为 `@AssertTrue` 方法。实测 Hibernate `@Digits` 按原始 scale 计数，会拒绝 `0.12340`，与已确认的决定 1（去尾零后计数）冲突；行为口径不变，只换实现。副作用：400 时的字段错误名为 `discountRateScaleValid`，不是 `discountRate`（当前接口不返回字段级错误体）。

## 本轮运行配置
```viktor-checks
test: ./mvnw -q test
e2e: ./mvnw -q verify
```
- 环境前提 / 来源：README.md「跑测试」一节；以仓库根目录为工作目录。`test` 跑 core 单测 + app WebMvc 切片（不需要 Docker）；`e2e` 追加 app 的 `*IT`（failsafe，Testcontainers 拉起 postgres:16-alpine，需要 Docker）。无独立 typecheck / lint，编译在 test 阶段完成。
