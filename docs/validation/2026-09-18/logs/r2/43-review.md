---
run_id: 20260918204450-20212
result: pass
reviewed: 2026-09-18
round: 3
independent: true
---

# Review：订单创建接口支持幂等键

摘要：test ✅ 17 passed · BLOCKING 0 · SUGGESTED 6 · 验收覆盖 6/6 关键 AC（AC-1~5 的 IT 本轮未运行；AC-9 为人工项） · 知识库 命中 4 条，违反 0 条

## 维度结论
| 维度 | 结论 | 说明（一行） |
|------|------|-------------|
| 检查命令 | ✅ | 全量跑 `./mvnw -q test`，退出码 0；surefire 报告：core OrderAmountCalculatorTest 8、app OrderControllerWebMvcTest 8、app OrderServiceTest 1（新增），合计 17 个，0 失败 0 跳过。增量只改了 app，本可只跑 app，但全量成本低，所以跑了全量。没跑 `verify`（OrderApiIT），交给 check |
| 验收覆盖 | ⚠️ | 自 cf67f63 之后的增量针对 AC-9：新增 OrderServiceTest#logsCreatedOrderAtInfoWithOrderNo，证明代码会输出 INFO 日志；Kibana 能否检索到仍需人工确认。AC-1~5 只在 OrderApiIT 中覆盖，本轮没有运行证据 |
| 知识库一致性 | ✅ | knowledge.sh 需要审批，没批下来；按 docs/knowledge/index.md 的 scope 对照，命中 4 条，未违反 |
| 正确性 | ✅ | `log.info` 只在 saveAndFlush 成功后执行（OrderService.java:44）；重放和并发回查路径不打这条日志，符合“创建订单”的语义；日志调用不会抛 DataIntegrityViolationException，所以不影响 catch 分支 |
| 数据与契约兼容 | ✅ | 增量没有改持久化结构和对外接口；上一轮关于 quantity ≥ 1000 返回 500 的 SUGGESTED 仍然有效 |
| 附加项 | ⚠️ | 增量没有涉及迁移、鉴权、外部调用或查询；幂等相关的 SUGGESTED 沿用上一轮（计算先于回查、旧表升级） |
| 安全 | ✅ | 日志只包含 orderNo 和 id，不打印 Idempotency-Key、request_hash 或金额，也没有敏感数据 |
| 范围 | ✅ | 增量（INFO 日志和对应单测）对应 plan 中的 AC-9，在计划范围内；没有调试代码 |

## 问题
| 级别 | 位置 | 问题 | 后果 | 建议 | 状态 |
|------|------|------|------|------|------|
| SUGGESTED | app/src/main/java/com/example/demo/app/order/CreateOrderRequest.java:14 | core 规定 `quantity > 999` 时抛 IllegalArgumentException，但请求 DTO 没有 `@Max(999)`，app 里也没有处理这个异常的处理器 | `POST /orders` 传 quantity=1000 时返回 500，不是 400 | 在 DTO 上加 `@Max(999)`，或者把这个异常映射为 400（属于 quantity-limit 需求）；请 check 用 quantity=1000 验证实际状态码 | 待处理（本轮未改动） |
| SUGGESTED | app/src/main/java/com/example/demo/app/order/OrderService.java:33 | `OrderAmountCalculator.total` 在按键回查之前执行，所以重放请求也要经过当前计算器的校验 | 如果库里有 quantity > 999 的带键历史订单，同键同体重放会得到 500，违背“永久有效”的口径；目前没有这样的数据，无法触发 | 把金额计算挪到“按键查询未命中”之后，或者在知识库记下这个依赖 | 待处理（本轮未改动） |
| SUGGESTED | app/src/test/java/com/example/demo/app/order/OrderApiIT.java:106 | AC-1~5（含 8 线程并发）只在 OrderApiIT 中验证，本轮 review 没有 verify 运行证据 | 并发和唯一约束兜底目前没有真实运行证据 | check 跑 `./mvnw -q verify`，确认 OrderApiIT 全部执行（Skipped 0）且通过 | 待验证 |
| SUGGESTED | app/src/main/java/com/example/demo/app/order/Order.java:14 | 在已有的 `orders` 表上靠 `ddl-auto: update` 新增列和 `uk_orders_idempotency_key`；IT 用的是空库，覆盖不到旧表升级 | 旧库升级后如果约束没建出来，并发同键会落多条 | check 在带旧 schema 的库上启动一次，用 `\d orders` 确认两列和唯一约束都已建出 | 待验证 |
| SUGGESTED | app/src/main/java/com/example/demo/app/order/Order.java:37 | `request_hash` 映射成 varchar(64)（`length = 64`），plan 写的是 char(64) | 功能不受影响，文档和实现对不上 | 统一 plan 或实现其中一处 | 待处理（本轮未改动） |
| SUGGESTED | app/src/main/java/com/example/demo/app/order/OrderService.java:65 | `fingerprint` 的规范化仍然没有 surefire 单测；新增的 OrderServiceTest 只覆盖日志 | 不跑 Docker 时，规范化逻辑出现回归也发现不了 | 在 OrderServiceTest 中补测试：等值写法（10 / 10.00）哈希相同，quantity 不同则哈希不同 | 待处理（本轮未改动） |

## 验收覆盖
| AC | 结论 | 依据（用例名 / 位置） |
|----|------|----------------------|
| AC-1 | ⚠️ 有用例，本轮未运行 | OrderApiIT#firstRequestWithIdempotencyKeyPersistsKeyAndHash |
| AC-2 | ⚠️ 有用例，本轮未运行 | OrderApiIT#repeatedKeyWithSameBodyReplaysFirstResultWithoutInsert；WebMvcTest#passesValidIdempotencyKeyToServiceAndMarksReplay ✅ |
| AC-3 | ⚠️ 有用例，本轮未运行 | OrderApiIT#concurrentRequestsWithSameKeyInsertOnce |
| AC-4 | ⚠️ 有用例，本轮未运行 | OrderApiIT#sameKeyWithDifferentBodyReturns422AndKeepsFirstOrder；WebMvcTest#mapsReusedIdempotencyKeyTo422 ✅ |
| AC-5 | ⚠️ 有用例，本轮未运行 | OrderApiIT 原有用例 + #differentKeysWithSameOrderNoReturn409；WebMvcTest#createsWithoutIdempotencyKey、#mapsDuplicateOrderTo409 ✅ |
| AC-6 | ✅ | WebMvcTest#rejectsBlankIdempotencyKey、#rejectsIdempotencyKeyLongerThan64、64 字符正例，本轮通过 |
| AC-9 | ⚠️ 代码侧有单测，平台侧需人工确认 | OrderServiceTest#logsCreatedOrderAtInfoWithOrderNo ✅（本轮输出 `INFO ... OrderService : order created orderNo=NO-LOG-1 id=null`）；Kibana 能否检索到需要在生产环境人工确认，属非关键项 |

## 知识库对照
| 知识条目 | 结论 | 说明 |
|---------|------|------|
| glossary/2026-09/订单金额舍入口径-HALF-UP-保留-2-位-历史订单为-DOWN-截断.md | ✅ 未违反 | 增量没有改金额计算，日志也不输出金额 |
| decisions/2026-09/订单幂等键存在-orders-表上-不建独立幂等记录表.md | ✅ 未违反 | 存储结构没变，仍然是 orders 表上的两列加唯一约束 |
| pitfalls/2026-09/OrderService-create-不能加外层-Transactional-否则并发幂等回查失效.md | ✅ 未违反 | OrderService.create 仍然没有 @Transactional，增量只加了日志 |
| glossary/2026-09/Idempotency-Key-语义-全局唯一-永久有效-只有创建成功才占用.md | ✅ 未违反（有潜在风险） | 增量没有改变键的占用语义；金额计算先于回查的潜在冲突见 SUGGESTED OrderService.java:33 |
