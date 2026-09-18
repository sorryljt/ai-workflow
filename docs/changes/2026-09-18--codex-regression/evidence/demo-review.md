---
run_id: 20260918234730-57913
result: pass
reviewed: 2026-09-18
round: 2
independent: true
---

# Review：Codex 1.1.1 S 档复测：负单价错误文案

摘要：test ✅ 27 passed · BLOCKING 0 · SUGGESTED 0 · 验收覆盖 1/1 · 知识库 命中 2 条，违反 0 条

## 维度结论
| 维度 | 结论 | 说明（一行） |
|------|------|-------------|
| 检查命令 | ✅ | 本轮原样执行 `./mvnw -q test`，退出码 0；core 16、app 8+3，失败、错误、跳过均为 0；core 被 app 的 OrderService.java:42 调用，采用允许的全量 test；未运行 verify、dev，未覆盖真实数据库与 e2e；输入未配置 typecheck / lint。 |
| 验收覆盖 | ✅ | 复审 diff 新增 2 个测试；OrderAmountCalculatorTest.java:12-29 覆盖 AC-1 的负单价异常类型及精确文案、零单价及既有正单价计算；上一轮缺回归测试 BLOCKING 已修复。 |
| 知识库一致性 | ✅ | lookup 命中 2 条，逐条核对未违反，见知识库对照。 |
| 正确性 | ✅ | 新增测试使用有效数量与折扣，直接调用真实计算器；:13-16 对 -0.01、-10.00 断言异常类型及目标消息，:21-23 对零单价断言 0.00；本轮均通过，未屏蔽或删除既有测试。 |
| 数据与契约兼容 | ✅ | 复审 diff 仅新增测试；完整需求 diff 仅变更 OrderAmountCalculator.java:24 的指定异常文案及新增测试，异常类型、校验边界、持久化结构与接口字段均未变。 |
| 安全 | ✅ | 复审 diff 仅增加固定数据的单元测试；源码 :24 仍为固定异常字符串，无输入拼接、敏感数据或鉴权变更。 |
| 范围 | ✅ | 复审 diff 仅 OrderAmountCalculatorTest.java:11-24 的两个回归测试，与 plan.md 补齐测试要求一致，无调试代码。 |
| 附加项 | — | diff 未涉及迁移 / 鉴权 / 幂等 / 外部调用 / 查询。 |

## 问题
| 级别 | 位置 | 问题 | 后果 | 建议 | 状态 |
|------|------|------|------|------|------|
| BLOCKING | core/src/main/java/com/example/demo/core/OrderAmountCalculator.java:24；core/src/test/java/com/example/demo/core/OrderAmountCalculatorTest.java:12 | 上一轮源码文案变更缺少回归测试；本轮新增 rejectsNegativeUnitPriceWithExactMessage 与 acceptsZeroUnitPrice，保留 multipliesPriceByQuantity，均运行通过。 | 原缺口会使恢复旧文案无法被测试发现；现在 :16 精确文案断言可识别该回归。 | 已补齐负值、零值覆盖，并重跑正值计算用例。 | 已修复 |

## 验收覆盖
| AC | 结论 | 依据（用例名 / 位置） |
|----|------|----------------------|
| AC-1：负单价异常类型及精确文案；零单价与正单价计算正确 | ✅ 已覆盖 | core/src/test/java/com/example/demo/core/OrderAmountCalculatorTest.java:12 rejectsNegativeUnitPriceWithExactMessage 覆盖 -0.01、-10.00 与精确消息；:21 acceptsZeroUnitPrice 断言 0.00；:27 multipliesPriceByQuantity 断言 30.00；本轮该类 16 个测试全部通过。 |

## 知识库对照
| 知识条目 | 结论 | 说明 |
|---------|------|------|
| glossary/2026-09/订单金额舍入口径-HALF-UP-保留-2-位-历史订单为-DOWN-截断.md | ✅ 未违反 | lookup 命中；OrderAmountCalculator.java:38-41 保持 HALF_UP 保留 2 位，新增零值断言为 0.00，未改历史订单处理。 |
| pitfalls/2026-09/OrderService-create-幂等键回查未命中后才算金额-不要挪回前面.md | ✅ 未违反 | lookup 命中；OrderService.java:35-42 仍先回查并重放，未命中才计算金额；复审仅新增计算器测试，不改变该顺序。 |

## 命令证据
| 命令 / 报告 | 本轮结果 |
|---------------|----------|
| `git diff 18937dfc3fa845070f4b5e600c110ac029225db0 -- . ':!docs/changes' ':!docs/knowledge'` | 退出码 0，仅 OrderAmountCalculatorTest.java 新增 15 行、2 个测试。 |
| `git diff 488993351f61ff18c35c3b766be2186a7390f568 -- . ':!docs/changes' ':!docs/knowledge'` | 退出码 0，完整需求仅计算器异常文案替换及上述测试新增，用于核对上一轮 BLOCKING。 |
| `bash .workflow/fe-ai-workflow/scripts/knowledge.sh lookup core/src/test/java/com/example/demo/core/OrderAmountCalculatorTest.java core/src/main/java/com/example/demo/core/OrderAmountCalculator.java 负单价 错误文案` | 退出码 0，返回上列 2 条知识。 |
| `./mvnw -q test` | 退出码 0。 |
| core/target/surefire-reports/com.example.demo.core.OrderAmountCalculatorTest.txt:4 | Tests run: 16, Failures: 0, Errors: 0, Skipped: 0 |
| app/target/surefire-reports/com.example.demo.app.order.OrderControllerWebMvcTest.txt:4 | Tests run: 8, Failures: 0, Errors: 0, Skipped: 0 |
| app/target/surefire-reports/com.example.demo.app.order.OrderServiceTest.txt:4 | Tests run: 3, Failures: 0, Errors: 0, Skipped: 0 |
