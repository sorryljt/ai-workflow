---
run_id: 20260918234341-53963
result: blocked
reviewed: 2026-09-18
round: 1
independent: true
---

# Review：Codex 1.1.1 S 档复测：负单价错误文案

摘要：test ✅ 25 passed · BLOCKING 1 · SUGGESTED 0 · 验收覆盖 0/1 · 知识库 命中 2 条，违反 0 条

## 维度结论
| 维度 | 结论 | 说明（一行） |
|------|------|-------------|
| 检查命令 | ✅ | 本轮原样执行 `./mvnw -q test`，退出码 0；surefire 报告 core 14、app 8+3，失败、错误、跳过均为 0；core 被 app 调用，采用允许的全量 test；未运行 verify、dev，未覆盖真实数据库与 e2e；输入未配置 typecheck / lint。 |
| 验收覆盖 | ⚠️ | 指定基线 diff 仅修改 OrderAmountCalculator.java:24，无测试文件变更；AC-1 无替代验证豁免，缺少本次回归测试。 |
| 知识库一致性 | ✅ | lookup 命中 2 条，逐条核对未违反，见知识库对照。 |
| 正确性 | ✅ | OrderAmountCalculator.java:23-25 仍仅在 signum() < 0 时抛 IllegalArgumentException，文案与 AC-1 一致；零值不进入该分支，计算和其他校验未改。 |
| 数据与契约兼容 | ✅ | diff 仅将负单价异常文案改为计划指定值，异常类型与校验边界未变，无持久化结构、对外接口字段或状态码变更。 |
| 安全 | ✅ | OrderAmountCalculator.java:24 为固定字符串替换，不插入输入或敏感数据，无鉴权或输入处理逻辑变更。 |
| 范围 | ✅ | 指定基线 diff 仅一行文案替换，与 plan.md 目标一致，无调试代码；计划明确有意缺测试且非免测。 |
| 附加项 | — | diff 未涉及迁移 / 鉴权 / 幂等 / 外部调用 / 查询。 |

## 问题
| 级别 | 位置 | 问题 | 后果 | 建议 | 状态 |
|------|------|------|------|------|------|
| BLOCKING | core/src/main/java/com/example/demo/core/OrderAmountCalculator.java:24；core/src/test/java/com/example/demo/core/OrderAmountCalculatorTest.java:9 | 源码错误文案发生变化，指定基线 diff 无任何测试变更；现有 14 个计算器测试均使用正单价，没有负单价异常类型及精确文案断言，也没有零单价用例；plan.md AC-1 明确要求新增覆盖且无豁免。 | 即使恢复旧文案，现有测试仍不能发现该回归；不满足本次回归测试硬规则和 AC-1。 | 新增或修改单元测试，断言负单价抛 IllegalArgumentException 且消息精确为“unitPrice 不能为负数”，并覆盖零单价与正单价计算。 | 待修复 |

## 验收覆盖
| AC | 结论 | 依据（用例名 / 位置） |
|----|------|----------------------|
| AC-1：负单价异常类型及精确文案；零单价与正单价计算正确 | ❌ 未完整覆盖 | OrderAmountCalculator.java:23-25 实现目标文案；OrderAmountCalculatorTest.java:12 的 multipliesPriceByQuantity 已有正单价断言，本轮运行通过；该测试文件无变更，全部 14 个用例未覆盖负单价或零单价，缺少本次新增回归证据。 |

## 知识库对照
| 知识条目 | 结论 | 说明 |
|---------|------|------|
| glossary/2026-09/订单金额舍入口径-HALF-UP-保留-2-位-历史订单为-DOWN-截断.md | ✅ 未违反 | lookup 命中；OrderAmountCalculator.java:38-41 保持乘积按 HALF_UP 保留 2 位，diff 未改舍入或历史数据处理。 |
| pitfalls/2026-09/OrderService-create-幂等键回查未命中后才算金额-不要挪回前面.md | ✅ 未违反 | lookup 命中；调用方 OrderService.java:35-42 仍先回查并重放，未命中才计算金额，diff 未改变该顺序。 |

## 命令证据
| 命令 / 报告 | 本轮结果 |
|---------------|----------|
| `git diff 488993351f61ff18c35c3b766be2186a7390f568 -- . ':!docs/changes' ':!docs/knowledge'` | 退出码 0，仅 OrderAmountCalculator.java:24 的异常文案替换，无测试文件变更。 |
| `bash .workflow/fe-ai-workflow/scripts/knowledge.sh lookup core/src/main/java/com/example/demo/core/OrderAmountCalculator.java 负单价 错误文案` | 退出码 0，返回上列 2 条知识。 |
| `./mvnw -q test` | 退出码 0。 |
| core/target/surefire-reports/com.example.demo.core.OrderAmountCalculatorTest.txt:4 | Tests run: 14, Failures: 0, Errors: 0, Skipped: 0 |
| app/target/surefire-reports/com.example.demo.app.order.OrderControllerWebMvcTest.txt:4 | Tests run: 8, Failures: 0, Errors: 0, Skipped: 0 |
| app/target/surefire-reports/com.example.demo.app.order.OrderServiceTest.txt:4 | Tests run: 3, Failures: 0, Errors: 0, Skipped: 0 |
