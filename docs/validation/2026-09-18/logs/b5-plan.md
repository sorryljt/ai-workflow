---
status: draft        # draft | confirmed | in-progress | done | archived
tier: L              # S | M | L
stage: plan          # plan | code | review | check | ship | done（最近完成或停住的节点）
stage_result: ok     # ok | blocked | error
review_round: 0
base_tree:
verified: {}
timing: {}
created: 2026-09-18
updated: 2026-09-18
---

# 折扣率允许为 0（免单）

## 目标
订单金额计算的折扣率允许取 0，表示免单，金额为 0.00；折扣率合法区间由 (0, 1] 放宽为 [0, 1]。
负数、大于 1、null 仍然报错。不做：免单的审批 / 权限控制、免单订单的单独标识或统计、历史数据处理。

## 方案
- core：`OrderAmountCalculator.total` 的折扣率校验由 `signum() <= 0` 改为 `signum() < 0`，异常文案改为 `[0, 1]`。计算公式不变，0 × 任意数 按 HALF_UP 保留 2 位得 `0.00`（scale 为 2，不是 `0`）。
- app：`CreateOrderRequest.discountRate` 的 `@DecimalMin(value = "0.00", inclusive = false)` 改为 `@DecimalMin("0.00")`（含 0）。只改 core 的话 `POST /orders` 在参数校验层仍以 400 拒绝 0，需求对外不可用，所以两层一起放宽。
  备选：只改 core、接口层继续拒绝 0。不选：需求的使用入口只有 `POST /orders`。
- 持久化：`amount` 列为 `numeric(12,2) not null`，无 `> 0` 的检查约束，0.00 可直接落库，不需要迁移。
- 对外契约变化：`discountRate = 0` 的请求由 400 变为 201。调用方如果依赖"0 被拒绝"做前置拦截，会失去这层保护（见风险）。
- 幂等指纹：`fingerprint` 对 discountRate 做 `stripTrailingZeros().toPlainString()`，`0`、`0.0`、`0.00` 均归一为 `"0"`，同键重放不会误判为不同请求体，无需改动。

## 影响范围
- `core/src/main/java/com/example/demo/core/OrderAmountCalculator.java`：校验与类注释 / 异常文案
- `core/src/test/java/com/example/demo/core/OrderAmountCalculatorTest.java`：新增 0 / 负数 / 大于 1 用例
- `app/src/main/java/com/example/demo/app/order/CreateOrderRequest.java`：`discountRate` 下界含 0
- `app/src/test/java/com/example/demo/app/order/OrderControllerWebMvcTest.java`：负数 / 大于 1 返回 400
- `app/src/test/java/com/example/demo/app/order/OrderApiIT.java`：折扣率 0 创建成功并落库 0.00
- 接口：`POST /orders` 请求体 `discountRate` 取值范围 (0, 1] → [0, 1]

## 验收标准
- [ ] AC-1：给定单价 10.00、数量 3、折扣率 0（含 `0`、`0.00` 两种写法），调用 `OrderAmountCalculator.total`，则返回 `0.00`（数值与 scale 均等于 `new BigDecimal("0.00")`）。　证据：core 单测，断言用 `assertEquals(new BigDecimal("0.00"), …)` 同时校验 scale。
- [ ] AC-2：折扣率为负数（-0.01）或大于 1（1.01）时，`total` 抛 `IllegalArgumentException`；折扣率 1 仍返回原价。　证据：core 单测覆盖两侧边界。
- [ ] AC-3：`POST /orders` 提交 `discountRate: 0`，返回 201，响应 `amount` 为 0.00，数据库中该订单 `amount` 为 0.00。　证据：OrderApiIT 在真实 Postgres（Testcontainers）下断言响应与落库值。
- [ ] AC-4：`POST /orders` 提交 `discountRate: -0.01` 或 `1.01`，返回 400，不落库。　证据：WebMvc 切片测试断言 400 且 service 未被调用。

## 任务
- [ ] T1 放宽 core 折扣率下界为含 0，补 0 / 负数 / 大于 1 单测（对应 AC-1、AC-2）
- [ ] T2 放宽 `CreateOrderRequest.discountRate` 下界为含 0，补 WebMvc 负数 / 大于 1 返回 400 用例（对应 AC-4；依赖 T1）
- [ ] T3 OrderApiIT 新增折扣率 0 创建订单并校验落库 0.00（对应 AC-3；依赖 T1、T2）

## 假设与风险
- 假设：折扣率 0 对任何单价、数量都合法，不需要额外开关或权限。
- 假设：免单订单与普通订单共用 `orderNo` 唯一约束和幂等语义，不做区分。
- 风险：接口放宽后，误传 0 的请求将成功创建 0 元订单而不是 400；如需防误用，应另开需求做权限或审批。
- 风险：下游若有"金额必须大于 0"的对账 / 支付逻辑，会首次遇到 0.00 订单；本仓库内无此类逻辑。

## 变更记录

## 本轮运行配置
```viktor-checks
test: ./mvnw -q test
e2e: ./mvnw -q verify
```
- 环境前提 / 来源：README.md「跑测试」一节；以仓库根目录为工作目录。`test` 跑 core 单测 + app WebMvc 切片（不需要 Docker）；`e2e` 追加 app 的 `*IT`（failsafe，Testcontainers 拉起 postgres:16-alpine，需要 Docker）。无独立 typecheck / lint，编译在 test 阶段完成。
