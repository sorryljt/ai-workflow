---
run_id: 20260918214110-35553
result: pass
reviewed: 2026-09-18
round: 4
independent: true
---

# Review：订单创建接口支持幂等键

摘要：test ✅ 22 passed · BLOCKING 0 · SUGGESTED 5（另 1 条已修复） · 验收覆盖 6/6 关键 AC（AC-1~5 的 IT 本轮未运行；AC-9 为人工项） · 知识库 命中 5 条，违反 0 条

## 维度结论
| 维度 | 结论 | 说明（一行） |
|------|------|-------------|
| 检查命令 | ✅ | 全量 `./mvnw -q test` 退出码 0（增量同时改了 core 和 app，所以跑全量）；surefire 21:41 报告：core OrderAmountCalculatorTest 11、app OrderControllerWebMvcTest 8、app OrderServiceTest 3，合计 22 个，0 失败 0 跳过。未跑 verify（OrderApiIT 10 个用例，含本轮新增 2 个），交给 check |
| 验收覆盖 | ⚠️ | 增量没有改变 AC-1~6 的覆盖；新增的 OrderServiceTest 和 OrderApiIT 用例覆盖“金额计算后移”：超限的已有带键订单可以重放，新的超限订单被拒绝。AC-1~5 本轮仍然没有 IT 运行证据 |
| 知识库一致性 | ✅ | knowledge.sh lookup 命中 5 条，未违反；新增的 pitfall“回查未命中后才算金额”与实现一致（OrderService.java:41-42） |
| 正确性 | ✅ | 金额计算挪到按键回查未命中之后：fingerprint 只依赖经 @NotNull 校验的字段，不需要先算金额；并发 catch 分支用的仍是已算好的 amount；同键不同体且入参违规时，由原来的 500 变成 422，符合键语义 |
| 数据与契约兼容 | ⚠️ | 本轮增量没有改持久化结构；金额上限让超限的新请求返回 500（IllegalArgumentException 没有 handler），这是 amount-upper-limit 需求有意保留的映射，不属于本需求引入 |
| 附加项 | ⚠️ | 幂等：重放不再受之后收紧的金额校验影响，上一轮的 SUGGESTED 已修复；旧表升级建约束仍待 check 验证；没有涉及鉴权、外部调用或查询 |
| 安全 | ✅ | 应用代码增量没有新增日志字段或输入面；异常消息只包含上限常量 |
| 范围 | ⚠️ | 自 fa933b3 起的增量里，OrderAmountCalculator 上限、OrderService 金额后移和对应测试来自 amount-upper-limit 需求（status: done）；skills、settings.json、.workflow 子模块、AGENTS.md 属于工作流升级，都不是本 plan 的任务。没有遗留调试代码 |

## 问题
| 级别 | 位置 | 问题 | 后果 | 建议 | 状态 |
|------|------|------|------|------|------|
| SUGGESTED | app/src/main/java/com/example/demo/app/order/OrderService.java:42 | 计算器抛出的 IllegalArgumentException（quantity > 999、金额 > 1000000.00）没有 HTTP 映射；CreateOrderRequest 也没有对应的 @Max | 不带键或带新键时，超限请求返回 500 而不是 400（OrderApiIT#amountAboveLimitIsRejectedAndNotPersisted 只断言“非 2xx”） | 单独立需求统一映射为 400；请 check 用 quantity=1000、unitPrice=1000000.01 确认实际状态码为 500 且不落库 | 待处理（跨需求口径，本轮未改动） |
| SUGGESTED | app/src/main/java/com/example/demo/app/order/OrderService.java:33 | 上一轮问题：金额计算先于按键回查，导致重放也要经过当前计算器的校验 | — | — | 已修复（计算已挪到 :42，见 OrderServiceTest#replaysExistingOrderAboveAmountLimitWithoutRecalculating） |
| SUGGESTED | app/src/test/java/com/example/demo/app/order/OrderApiIT.java:106 | AC-1~5（含 8 线程并发）和新增的 2 个金额上限用例只在 OrderApiIT 中验证，本轮 review 没有 verify 运行证据 | 并发、唯一约束兜底和超限历史订单重放都没有真实运行证据 | check 跑 `./mvnw -q verify`，确认 OrderApiIT 10 个用例全部执行（Skipped 0）且通过 | 待验证 |
| SUGGESTED | app/src/main/java/com/example/demo/app/order/Order.java:14 | 在已有的 `orders` 表上靠 `ddl-auto: update` 新增列和 `uk_orders_idempotency_key`；IT 用的是空库，覆盖不到旧表升级 | 旧库升级后如果约束没建出来，并发同键会落多条 | check 在带旧 schema 的库上启动一次，用 `\d orders` 确认两列和唯一约束都已建出 | 待验证 |
| SUGGESTED | app/src/main/java/com/example/demo/app/order/Order.java:37 | `request_hash` 映射成 varchar(64)（`length = 64`），plan 写的是 char(64) | 功能不受影响，文档和实现对不上 | 统一 plan 或实现其中一处 | 待处理（本轮未改动） |
| SUGGESTED | app/src/main/java/com/example/demo/app/order/OrderService.java:65 | `fingerprint` 的规范化（10 与 10.00 视为相同）没有 surefire 单测；新增的 OrderServiceTest 只把 fingerprint 当作工具调用，没有验证规范化本身 | 不跑 Docker 时，规范化逻辑出现回归也发现不了 | 在 OrderServiceTest 中补测试：等值写法哈希相同，quantity 不同则哈希不同 | 待处理（本轮未改动） |

## 验收覆盖
| AC | 结论 | 依据（用例名 / 位置） |
|----|------|----------------------|
| AC-1 | ⚠️ 有用例，本轮未运行 | OrderApiIT#firstRequestWithIdempotencyKeyPersistsKeyAndHash |
| AC-2 | ⚠️ 有用例，本轮未运行 | OrderApiIT#repeatedKeyWithSameBodyReplaysFirstResultWithoutInsert；WebMvcTest#passesValidIdempotencyKeyToServiceAndMarksReplay ✅；OrderServiceTest#replaysExistingOrderAboveAmountLimitWithoutRecalculating ✅（重放不落库） |
| AC-3 | ⚠️ 有用例，本轮未运行 | OrderApiIT#concurrentRequestsWithSameKeyInsertOnce |
| AC-4 | ⚠️ 有用例，本轮未运行 | OrderApiIT#sameKeyWithDifferentBodyReturns422AndKeepsFirstOrder；WebMvcTest#mapsReusedIdempotencyKeyTo422 ✅ |
| AC-5 | ⚠️ 有用例，本轮未运行 | OrderApiIT 原有用例 + #differentKeysWithSameOrderNoReturn409；WebMvcTest#createsWithoutIdempotencyKey、#mapsDuplicateOrderTo409 ✅ |
| AC-6 | ✅ | WebMvcTest#rejectsBlankIdempotencyKey、#rejectsIdempotencyKeyLongerThan64、64 字符正例，本轮通过 |
| AC-9 | ⚠️ 代码侧有单测，平台侧需人工确认 | OrderServiceTest#logsCreatedOrderAtInfoWithOrderNo ✅（本轮输出 `INFO ... OrderService : order created orderNo=NO-LOG-1 id=null`）；Kibana 能否检索到需要在生产环境人工确认，属非关键项 |

## 知识库对照
| 知识条目 | 结论 | 说明 |
|---------|------|------|
| decisions/2026-09/订单幂等键存在-orders-表上-不建独立幂等记录表.md | ✅ 未违反 | 存储结构没变 |
| glossary/2026-09/Idempotency-Key-语义-全局唯一-永久有效-只有创建成功才占用.md | ✅ 未违反 | 金额后移之后，超限历史带键订单也能重放，符合“永久有效”；超限的新请求抛异常且不落库，不占用键 |
| glossary/2026-09/订单金额舍入口径-HALF-UP-保留-2-位-历史订单为-DOWN-截断.md | ✅ 未违反 | 仍然是 HALF_UP，上限比较在舍入之后（OrderAmountCalculatorTest#comparesMaximumAfterRounding）；重放不回算历史订单金额 |
| pitfalls/2026-09/OrderService-create-不能加外层-Transactional-否则并发幂等回查失效.md | ✅ 未违反 | OrderService.create 仍然没有 @Transactional |
| pitfalls/2026-09/OrderService-create-幂等键回查未命中后才算金额-不要挪回前面.md | ✅ 未违反 | 金额计算位于回查之后（OrderService.java:41-42） |
