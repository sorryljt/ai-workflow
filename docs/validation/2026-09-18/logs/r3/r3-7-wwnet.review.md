---
run_id: 20260918221313-66981
result: pass
reviewed: 2026-09-18
round: 2
independent: true
---

# Review：折扣率精度校验

摘要：test ✅ 25 passed · BLOCKING 0 · SUGGESTED 1 · 验收覆盖 1/1 · 知识库命中 2 条，违反 0 条

## 维度结论
| 维度 | 结论 | 说明（一行） |
|------|------|-------------|
| 检查命令 | ✅ | 本轮 `./mvnw -q test` 退出码 0；core 14、app 11，失败 / 错误 / 跳过均为 0；证据为 core 和 app 的 `target/surefire-reports/*.txt:4`；计算器被 app 服务调用，故选择全量 test；未执行 verify / dev，未覆盖真实数据库及端到端行为；typecheck / lint 未配置，编译由 test 覆盖。 |
| 验收覆盖 | ✅ | AC-1 有精度拒绝、尾零接受、金额结果、HALF_UP 和范围校验回归测试，见下表。 |
| 知识库一致性 | ✅ | 指定 lookup 命中 2 条，均未违反，见知识库对照。 |
| 正确性 | ✅ | `core/src/main/java/com/example/demo/core/OrderAmountCalculator.java:20` 先判空，`:32` 保留范围检查，`:35` 去尾零后判断 scale，`:38` 保留原乘法与舍入；对应回归测试通过。 |
| 数据与契约兼容 | ⚠️ | 未改持久化结构；新建订单的折扣率接受范围按需求收紧；`app/src/main/java/com/example/demo/app/order/OrderService.java:35` 仍先回查并重放历史订单；HTTP 错误行为需 check 验证，见 S-1。 |
| 安全 | ✅ | 新增分支仅判断 BigDecimal 精度并抛固定文案（计算器 `:35`），未新增日志、敏感数据输出或权限路径。 |
| 范围 | ✅ | 指定完整 diff 仅改计算器与对应测试；旧舍入用例改用合法折扣率，仍分别覆盖第三位大于 / 小于 5，无调试代码；上一轮无 BLOCKING，Mockito 环境错误本轮未复现。 |
| 附加项 | — | diff 未涉及迁移 / 鉴权 / 重试、消息或定时任务 / 外部调用 / 查询；调用方幂等顺序按命中知识核对，未更改。 |

## 问题
| 级别 | 位置 | 问题 | 后果 | 建议 | 状态 |
|------|------|------|------|------|------|
| SUGGESTED（S-1） | `core/src/main/java/com/example/demo/core/OrderAmountCalculator.java:35`；`app/src/main/java/com/example/demo/app/order/CreateOrderRequest.java:15`；`app/src/main/java/com/example/demo/app/order/OrderController.java:45` | 新增精度异常可经 `OrderService.create:42` 传播；请求 DTO 仅限制范围，现有 Controller 异常处理不包含 IllegalArgumentException，app 主源码检索也未发现全局处理器。 | 新建订单传入 0.1230 时 HTTP 响应可能表现为服务端错误；本轮未验证运行时状态码。 | 交 check 验证超精度请求的实际状态码及错误体，并确认是否符合接口预期。 | 待 check 验证 |

## 验收覆盖
| AC | 结论 | 依据（用例名 / 位置） |
|----|------|----------------------|
| AC-1 | ✅ 有回归测试 | `core/src/test/java/com/example/demo/core/OrderAmountCalculatorTest.java:44` 的 `rejectsDiscountRatesWithMoreThanTwoSignificantDecimalPlaces` 覆盖 0.001、0.123、0.1230、0.678、0.3333；`:53` 的 `acceptsDiscountRatesWithAtMostTwoDecimalPlacesIgnoringTrailingZeros` 覆盖全部指定合法值及金额；`:24`、`:30`、`:38` 覆盖第三位等于、大于、小于 5 的舍入；`:62` 覆盖零、负数、大于 1 及 null；本轮计算器 14 个测试全通过。 |

## 知识库对照
| 知识条目 | 结论 | 说明 |
|---------|------|------|
| `glossary/2026-09/订单金额舍入口径-HALF-UP-保留-2-位-历史订单为-DOWN-截断.md` | ✅ 未违反 | 计算器 `:41` 保留 HALF_UP 两位小数；三个舍入测试通过；diff 未加入历史订单回算。 |
| `pitfalls/2026-09/OrderService-create-幂等键回查未命中后才算金额-不要挪回前面.md` | ✅ 未违反 | `OrderService.java:35` 至 `:42` 保持先回查重放、后计算；`OrderServiceTest.java:34` 的历史超限订单重放测试本轮通过，未新增超精度历史订单专用测试。 |
