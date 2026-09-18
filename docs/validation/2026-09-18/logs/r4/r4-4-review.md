---
run_id: 20260918225919-49690
result: pass
reviewed: 2026-09-18
round: 5
independent: true
---

# Review：订单创建接口支持幂等键

摘要：test ✅ 25 passed · BLOCKING 0 · SUGGESTED 6（另 1 条已修复） · 验收覆盖 6/6 关键 AC（AC-1~5 的 IT 本轮未运行；AC-9 为人工项） · 知识库 命中 5 条，违反 0 条

## 维度结论
| 维度 | 结论 | 说明（一行） |
|------|------|-------------|
| 检查命令 | ✅ | 增量改了 core，app 依赖 core，所以跑全量 `./mvnw -q test`，退出码 0；surefire 23:00 的报告显示 core OrderAmountCalculatorTest 14 个、app OrderControllerWebMvcTest 8 个、OrderServiceTest 3 个，合计 25 个，0 失败 0 跳过。verify 未跑（OrderApiIT 10 个），交给 check |
| 验收覆盖 | ⚠️ | 自 e46e958 起的增量没有改 app 代码和测试，AC-1~6 的覆盖和上一轮一致；AC-1~5 本轮仍没有 IT 运行证据 |
| 知识库一致性 | ✅ | knowledge.sh lookup 命中 5 条，未违反；新增的 discountRate 精度校验在计算器里，OrderService 仍然是回查未命中之后才算金额（OrderService.java:36-42），重放不受影响 |
| 正确性 | ✅ | 计算器增量：`stripTrailingZeros().scale() > 2` 放在范围校验之后，1.000、0.800 能通过，0.1230、0.678 会被拒绝；quantity 只改了文案。fingerprint 仍对 discountRate 去尾零，与新校验口径一致 |
| 数据与契约兼容 | ⚠️ | 持久化结构没变；但 POST /orders 在 discountRate 超过 2 位有效小数时，由原来的 201 变成 500（CreateOrderRequest.java:15 只有 DecimalMin/DecimalMax 校验，IllegalArgumentException 没有 handler），详见问题表 |
| 附加项 | ⚠️ | 幂等：历史上 3 位小数折扣率的带键订单仍可重放（回查在计算之前）；新键遇到被拒请求时抛异常、不落库，也不占用键。旧表升级建约束仍待 check 验证。没有涉及鉴权、外部调用或查询 |
| 安全 | ✅ | 增量没有新增日志、输入面或敏感字段；异常消息只包含常量文案 |
| 范围 | ⚠️ | 增量中的 discountRate 精度校验来自 discount-rate-precision 需求（status: archived，stage_result: review error，从未通过独立审查）；quantity 文案来自 quantity-error-message（done）；skills、.workflow 子模块、AGENTS.md 属于工作流升级。这些都不是本 plan 的任务，没有遗留调试代码 |

## 问题
| 级别 | 位置 | 问题 | 后果 | 建议 | 状态 |
|------|------|------|------|------|------|
| SUGGESTED | core/src/main/java/com/example/demo/core/OrderAmountCalculator.java:35 | 本轮新增的 discountRate 精度校验来自已归档、未通过审查的需求（discount-rate-precision，review error）；请求层没有对应的 `@Digits(fraction=2)`，异常也没有 HTTP 映射 | discountRate=0.678 这类请求以前返回 201，现在返回 500，破坏了现有调用方，而且这段改动没有经过独立审查和 check | 由人决定保留（重新走该需求的 review/check，并补 400 映射）还是回退；请 check 用 discountRate=0.678、不带键发起请求，确认实际状态码和是否落库 | 待处理（跨需求，需人拍板） |
| SUGGESTED | app/src/main/java/com/example/demo/app/order/OrderService.java:42 | 计算器抛出的 IllegalArgumentException（quantity > 999、金额 > 1000000.00）没有 HTTP 映射；CreateOrderRequest 也没有对应的 @Max | 不带键或带新键时，超限请求返回 500 而不是 400（OrderApiIT#amountAboveLimitIsRejectedAndNotPersisted 只断言“非 2xx”） | 另开需求统一映射为 400；请 check 用 quantity=1000、unitPrice=1000000.01 确认实际状态码为 500 且不落库 | 待处理（跨需求口径，本轮未改动） |
| SUGGESTED | app/src/main/java/com/example/demo/app/order/OrderService.java:33 | 更早一轮的问题：金额计算在按键回查之前，重放也要经过当前计算器的校验 | — | — | 已修复（计算已挪到 :42，见 OrderServiceTest#replaysExistingOrderAboveAmountLimitWithoutRecalculating） |
| SUGGESTED | app/src/test/java/com/example/demo/app/order/OrderApiIT.java:106 | AC-1~5（含 8 线程并发）和 2 个金额上限用例只在 OrderApiIT 里验证，本轮 review 没有 verify 运行证据 | 并发、唯一约束兜底、超限历史订单重放都缺真实运行证据 | check 跑 `./mvnw -q verify`，确认 OrderApiIT 10 个用例全部执行（Skipped 0）并通过 | 待验证 |
| SUGGESTED | app/src/main/java/com/example/demo/app/order/Order.java:14 | 在已有的 `orders` 表上靠 `ddl-auto: update` 新增列和 `uk_orders_idempotency_key`，而 IT 用的是空库，覆盖不到旧表升级 | 旧库升级后如果约束没建出来，并发同键会落多条 | check 在带旧 schema 的库上启动一次，用 `\d orders` 确认两列和唯一约束都已建出 | 待验证 |
| SUGGESTED | app/src/main/java/com/example/demo/app/order/Order.java:37 | `request_hash` 映射为 varchar(64)（`length = 64`），plan 写的是 char(64) | 功能不受影响，但文档和实现不一致 | 统一 plan 和实现中的一处 | 待处理（本轮未改动） |
| SUGGESTED | app/src/main/java/com/example/demo/app/order/OrderService.java:65 | `fingerprint` 的规范化（10 与 10.00 视为相同）没有 surefire 单测 | 不跑 Docker 时，规范化逻辑回归了也发现不了 | 在 OrderServiceTest 补测试：等值写法哈希相同，quantity 不同则哈希不同 | 待处理（本轮未改动） |

## 验收覆盖
| AC | 结论 | 依据（用例名 / 位置） |
|----|------|----------------------|
| AC-1 | ⚠️ 有用例，本轮未运行 | OrderApiIT#firstRequestWithIdempotencyKeyPersistsKeyAndHash |
| AC-2 | ⚠️ 有用例，本轮未运行 | OrderApiIT#repeatedKeyWithSameBodyReplaysFirstResultWithoutInsert；WebMvcTest#passesValidIdempotencyKeyToServiceAndMarksReplay ✅；OrderServiceTest#replaysExistingOrderAboveAmountLimitWithoutRecalculating ✅ |
| AC-3 | ⚠️ 有用例，本轮未运行 | OrderApiIT#concurrentRequestsWithSameKeyInsertOnce |
| AC-4 | ⚠️ 有用例，本轮未运行 | OrderApiIT#sameKeyWithDifferentBodyReturns422AndKeepsFirstOrder；WebMvcTest#mapsReusedIdempotencyKeyTo422 ✅ |
| AC-5 | ⚠️ 有用例，本轮未运行 | OrderApiIT 原有用例 + #differentKeysWithSameOrderNoReturn409（IT 中的 discountRate 取 1 / 0.5 / 1.0，不受新精度校验影响）；WebMvcTest#createsWithoutIdempotencyKey、#mapsDuplicateOrderTo409 ✅ |
| AC-6 | ✅ | WebMvcTest#rejectsBlankIdempotencyKey、#rejectsIdempotencyKeyLongerThan64、64 字符正例，本轮通过 |
| AC-9 | ⚠️ 代码侧有单测，平台侧需人工确认 | OrderServiceTest#logsCreatedOrderAtInfoWithOrderNo ✅（本轮输出 `INFO ... OrderService : order created orderNo=NO-LOG-1 id=null`）；Kibana 检索需在生产人工确认，属非关键项 |

## 知识库对照
| 知识条目 | 结论 | 说明 |
|---------|------|------|
| decisions/2026-09/订单幂等键存在-orders-表上-不建独立幂等记录表.md | ✅ 未违反 | 存储结构没变 |
| glossary/2026-09/Idempotency-Key-语义-全局唯一-永久有效-只有创建成功才占用.md | ✅ 未违反 | 精度校验只作用于新计算：历史带键订单仍可重放；被拒请求不落库，不占用键 |
| glossary/2026-09/订单金额舍入口径-HALF-UP-保留-2-位-历史订单为-DOWN-截断.md | ✅ 未违反 | 仍用 HALF_UP；两个舍入用例只把入参改成合法精度（1.356×0.50→0.68，6.666×0.50→3.33），断言值没变 |
| pitfalls/2026-09/OrderService-create-不能加外层-Transactional-否则并发幂等回查失效.md | ✅ 未违反 | OrderService.create 仍然没有 @Transactional |
| pitfalls/2026-09/OrderService-create-幂等键回查未命中后才算金额-不要挪回前面.md | ✅ 未违反 | 金额计算仍在回查之后（OrderService.java:41-42）；这次收紧计算器没有改 OrderService，与条目预期一致 |
