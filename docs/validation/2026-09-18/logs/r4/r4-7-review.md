---
run_id: 20260918230614-59086
result: pass
reviewed: 2026-09-18
round: 1
independent: true
---

# Review：unitPrice 负数异常文案

摘要：test ✅ 25 passed · BLOCKING 0 · SUGGESTED 1 · 验收覆盖 0/1（部分覆盖） · 知识库命中 2 条，违反 0 条

## 维度结论
| 维度 | 结论 | 说明（一行） |
|------|------|-------------|
| 检查命令 | ✅ | 本轮原样执行 `./mvnw -q test`，退出 0；surefire XML：core 14、app WebMvc 8、app Service 3，失败 / 错误 / 跳过均为 0；core 被 app 调用，选全量 test 覆盖两模块；未运行 verify / dev，未覆盖数据库集成及运行时验收；传入配置无 typecheck / lint。 |
| 验收覆盖 | ⚠️ | `OrderAmountCalculatorTest.java:11–114` 覆盖正数及其他校验，但没有负单价异常文案断言及零单价用例；本轮 25 个测试不能证明新文案的回归覆盖。 |
| 知识库一致性 | ✅ | 指定 lookup 命中 2 条，逐条核对未违反，见知识库对照。 |
| 正确性 | ✅ | `core/src/main/java/com/example/demo/core/OrderAmountCalculator.java:23–24` 保留 `signum() < 0` 与异常类型，仅替换要求的字符串；零及正数的分支、空值及其他校验均未变。 |
| 数据与契约兼容 | ✅ | 指定 diff 仅改变第 24 行异常文案，属于需求明确要求的消息变更；未改变字段、方法签名、持久化结构或状态码逻辑。 |
| 安全 | ✅ | 第 24 行仍为固定字符串，不含输入插值或敏感数据；diff 无鉴权、日志或输入处理逻辑变更。 |
| 范围 | ✅ | 指定基线 diff 仅 1 文件 1 行字符串替换，与 plan.md 问题描述一致，无调试代码。 |
| 附加项 | — | 未涉及迁移 / 鉴权 / 幂等实现 / 外部调用 / 查询。 |

## 问题
| 级别 | 位置 | 问题 | 后果 | 建议 | 状态 |
|------|------|------|------|------|------|
| SUGGESTED | core/src/test/java/com/example/demo/core/OrderAmountCalculatorTest.java:11–114 | 现有 14 个计算器测试均未断言负单价异常文案，也没有零单价用例；指定 diff 无测试变更。 | 将文案改回旧值仍不能被现有测试发现；AC-1 仅部分有测试覆盖。 | 后续补充负单价异常类型及完整文案断言、零单价计算断言；check 核验 AC-1 的负数、零与正数行为。 | 待处理 |

## 验收覆盖
| AC | 结论 | 依据（用例名 / 位置） |
|----|------|----------------------|
| AC-1 | ⚠️ 部分覆盖 | `multipliesPriceByQuantity`（core/src/test/java/com/example/demo/core/OrderAmountCalculatorTest.java:12）覆盖正数；同文件数量、折扣率、金额上限用例本轮通过；生产代码第 23–24 行满足负数判断与新文案的静态核对，但本轮测试未覆盖负数文案及零单价；plan.md 中既往临时检查记录不计为本轮命令证据。 |

## 知识库对照
| 知识条目 | 结论 | 说明 |
|---------|------|------|
| glossary/2026-09/订单金额舍入口径-HALF-UP-保留-2-位-历史订单为-DOWN-截断.md | ✅ 未违反 | `OrderAmountCalculator.java:38–41` 仍按 HALF_UP 保留 2 位；diff 无历史订单回算，舍入测试本轮通过。 |
| pitfalls/2026-09/OrderService-create-幂等键回查未命中后才算金额-不要挪回前面.md | ✅ 未违反 | 调用方 `app/src/main/java/com/example/demo/app/order/OrderService.java:35–42` 仍先回查并重放，未命中才算金额；本次 diff 未改调用顺序。 |
