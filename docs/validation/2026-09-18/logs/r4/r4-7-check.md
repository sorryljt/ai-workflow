---
run_id: 20260918230832-61474
result: error
pending: []
checked: 2026-09-18
---

# Check：unitPrice 负数异常文案

| AC | 关键 | 验证方式 | 证据 | 结果 |
|----|------|---------|------|------|
| AC-1：负数单价仍抛出 IllegalArgumentException，信息为「unitPrice 必须大于等于 0」；零和正数仍可计算，所有校验逻辑不变 | 是（金额计算规则） | 配置中的 verify、测试报告与生产 diff 核对 | 本轮 verify 退出 0，35 tests，0 failures/errors/skipped；正数计算及已有边界测试通过，生产 diff 仅改异常字符串；但现有测试没有调用负数单价和零单价，也没有断言目标异常信息，不能完整证明 AC-1 | ⛔ |

## 执行与证据

- 能力探测：本会话提供浏览器控制工具 mcp__cua_repl；本 AC 无可见交互或独立运行服务要求，因此不启动 dev、不探测监听端口。
- 环境探测：`docker ps` 退出 0，列表为空；Docker 就绪。verify 日志显示 Testcontainers 启动 `postgres:16-alpine` 并运行真实数据库集成测试。
- 业务口径：`bash .workflow/fe-ai-workflow/scripts/knowledge.sh lookup unitPrice` 退出 0，输出「（无相关知识）」。
- 实际检查命令：`./mvnw -q verify`，退出 0。包含 core 单测 14、app 单测 11、app 集成测试 10。报告分别位于 `core/target/surefire-reports/`、`app/target/surefire-reports/` 和 `app/target/failsafe-reports/`。
- 正数证据：`OrderAmountCalculatorTest.multipliesPriceByQuantity` 本轮通过，输入单价 10.00、数量 3、折扣 1，期望总额 30.00；其余测试覆盖舍入、折扣、数量与金额上限。
- `git diff -- core/src/main app/src/main` 显示生产代码仅将「unitPrice 不能为负数」替换为「unitPrice 必须大于等于 0」。静态字符串核对不能替代要求的实际负数与零单价调用。

## 检查入口问题

本轮配置中的 verify 未产生负数异常类型及精确文案、零单价计算的运行证据。读取 `core/src/test/java/com/example/demo/core/OrderAmountCalculatorTest.java` 及本轮 XML testcase 列表可复核：14 个测试均没有这些输入或消息断言。test 是该入口的快速子集，不能补齐此缺口。

按本轮明确要求「认为某条命令无法产生证据……写 result: error……然后退出」，本次标记 error；未观察到功能行为错误，也不能放行。未执行配置外的临时 Java 检查，未采用 plan 中上轮 RED/GREEN 记录作为本轮证据，未改测试或实现。需要主会话补齐配置入口所执行的相关行为检查后重新验收。

## 资源清理

未直接创建临时目录、后台 dev 进程或测试数据前缀。容器由 Testcontainers / ryuk 回收。
