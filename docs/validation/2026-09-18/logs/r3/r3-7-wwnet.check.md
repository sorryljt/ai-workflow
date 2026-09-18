---
run_id: 20260918221621-70031
result: pass
pending: []
checked: 2026-09-18
---

# Check：折扣率精度校验

| AC | 关键 | 验证方式 | 证据 | 结果 |
|----|------|---------|------|------|
| AC-1：拒绝去尾零后超过两位小数的折扣率；接受指定合法值并正确计算金额，保留 HALF_UP 与现有范围校验 | 是（资金计算） | 真实计算器边界单元测试，由完整 verify 执行 | 本轮 `./mvnw -q verify` 退出码 0；OrderAmountCalculatorTest 14 passed，0 failures/errors/skipped；具体输入输出见下文 | ✅ |

## 本轮证据与复现

在项目根目录运行 `./mvnw -q verify`。本轮于 2026-09-18 22:17（Asia/Shanghai）执行完成，退出码 0。verify 已包含 test 阶段，无需重复执行快速子集。

核对测试输入、断言与本轮生成的报告，未检查业务实现或使用历史运行结果作为证据：

- `rejectsDiscountRatesWithMoreThanTwoSignificantDecimalPlaces`：单价 10.00、数量 1，折扣率 0.001、0.123、0.1230、0.678、0.3333 均抛 IllegalArgumentException。
- `acceptsDiscountRatesWithAtMostTwoDecimalPlacesIgnoringTrailingZeros`：同样单价与数量，0.01、0.12、0.1200、0.800、1.000 分别得到 0.10、1.20、1.20、8.00、10.00。
- `roundsHalfUpWhenThirdDecimalIsFive`、`roundsHalfUpWhenThirdDecimalIsAboveFive`、`roundsDownWhenThirdDecimalIsBelowFive`：3.33 × 1 × 0.5 得 1.67；1.356 × 1 × 0.50 得 0.68；0.01 × 7 × 0.95 得 0.07；6.666 × 1 × 0.50 得 3.33。
- `rejectsDiscountRatesOutsideExistingRange`：0.000、-0.01、1.01、null 均抛 IllegalArgumentException。其余边界测试覆盖数量 0、999、1000、Integer.MAX_VALUE，以及金额上限 1000000.00 和按舍入后金额比较上限。

本轮报告：

| 报告路径（相对项目根目录） | 执行数 | 失败 / 错误 / 跳过 |
|----|----|----|
| core/target/surefire-reports/TEST-com.example.demo.core.OrderAmountCalculatorTest.xml | 14 | 0 / 0 / 0 |
| app/target/surefire-reports/TEST-com.example.demo.app.order.OrderControllerWebMvcTest.xml | 8 | 0 / 0 / 0 |
| app/target/surefire-reports/TEST-com.example.demo.app.order.OrderServiceTest.xml | 3 | 0 / 0 / 0 |
| app/target/failsafe-reports/TEST-com.example.demo.app.order.OrderApiIT.xml | 10 | 0 / 0 / 0 |

共 35 个测试通过，其中 25 个单元测试、10 个真实 PostgreSQL 集成测试。AC-1 是计算器规则，直接调用真实计算器的单元测试提供充分证据；集成测试作为项目回归证据，不宣称覆盖全部折扣率精度输入。

## 能力与环境

- 工具清单可见浏览器控制工具 `mcp__cua_repl`；本 AC 无可见交互，无需浏览器操作。
- AC 为纯计算规则，不需要独立运行服务，未探测或启动 dev server。
- 一次 `docker ps` 探测退出码 0，仅输出表头，Docker 就绪；verify 中 Testcontainers 成功启动 postgres:16-alpine 并连接数据库。未探测不需要的本地 Postgres。
- 按指定知识入口查询 discountRate，输出“（无相关知识）”，以 plan 中 AC 为判定口径。
- 未直接创建临时目录、容器、后台 dev 进程或测试数据前缀，无需登记自建资源。容器由 Testcontainers / ryuk 回收。

## 失败详情

无。
