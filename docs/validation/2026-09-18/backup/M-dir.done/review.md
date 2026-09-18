---
run_id: 20260918195621-73499
result: pass
reviewed: 2026-09-18
round: 1
independent: true
---

# Review：订单创建接口支持幂等键

摘要：test ✅ 14 passed · BLOCKING 0 · SUGGESTED 4 · 验收覆盖 6/6（AC-1~5 的 IT 本轮未运行） · 知识库 命中 1 条，违反 0 条

## 维度结论
| 维度 | 结论 | 说明（一行） |
|------|------|-------------|
| 检查命令 | ✅ | `./mvnw -q test` 全量：core OrderAmountCalculatorTest 6 + app OrderControllerWebMvcTest 8，0 失败；按依赖范围选了全量（app 依赖 core）；`verify`（OrderApiIT）执行需审批未获批，本轮没跑，交给 check |
| 验收覆盖 | ⚠️ | 6 条 AC 都有对应用例；AC-1~5 只在 OrderApiIT 中，本轮没有运行证据 |
| 知识库一致性 | ✅ | 命中 1 条（金额舍入口径），未违反；knowledge.sh 需审批未获批，直接读的 docs/knowledge |
| 正确性 | ✅ | 先查键再插入、唯一约束冲突后回查、指纹比对 3 条路径核对无误；无外层事务，open-in-view=false，回查在新事务中执行 |
| 数据与契约兼容 | ✅ | 新列可空、历史行为 NULL；请求头可选，不带头时 201 / 409 语义不变；新增 400 / 422 错误码 |
| 附加项 | ⚠️ | 幂等：已按并发路径核对；迁移：依赖 ddl-auto update 给已有表加唯一约束，没有测试覆盖；未涉及鉴权 / 外部调用 / 分页查询 |
| 安全 | ✅ | 键长度在 Controller 层限制；422 message 回显键，但只出现在 JSON 响应里，无日志泄露 |
| 范围 | ✅ | 改动与 plan 影响范围一致，无调试代码；request_hash 列类型与 plan 略有出入（见问题） |

## 问题
| 级别 | 位置 | 问题 | 后果 | 建议 | 状态 |
|------|------|------|------|------|------|
| SUGGESTED | app/src/test/java/com/example/demo/app/order/OrderApiIT.java:106 | AC-1~5（含 8 线程并发）只在 OrderApiIT 中验证，本轮 review 没拿到 verify 运行证据 | 并发与唯一约束兜底的正确性，本轮还没有真实运行证据 | check 节点跑 `./mvnw -q verify`，确认 OrderApiIT 全部用例通过 | 待验证 |
| SUGGESTED | app/src/main/java/com/example/demo/app/order/Order.java:14 | 在已有 `orders` 表上，依赖 `ddl-auto: update` 新增列和 `uk_orders_idempotency_key`；IT 用的是空库，覆盖不到旧表升级 | 旧库升级后若约束没建出来，并发同键会落多条 | check 在已有旧 schema 的库上启动一次，用 `\d orders` 确认两列和唯一约束都存在 | 待验证 |
| SUGGESTED | app/src/main/java/com/example/demo/app/order/Order.java:37 | `request_hash` 映射为 `length = 64`，生成 varchar(64)；plan 写的是 char(64) | 功能无影响，文档与实现不一致 | 统一 plan 或实现其中一处 | 待处理 |
| SUGGESTED | app/src/main/java/com/example/demo/app/order/OrderService.java:59 | `fingerprint` 的规范化（去尾零、`10` 与 `10.00` 等值）没有 surefire 单测，只在 IT 中间接覆盖 | 不跑 Docker 时，规范化逻辑回归没有防护 | 补一个 `OrderServiceTest` / fingerprint 单测：等值写法哈希相同、quantity 不同则哈希不同 | 待处理 |

## 验收覆盖
| AC | 结论 | 依据（用例名 / 位置） |
|----|------|----------------------|
| AC-1 | ⚠️ 有用例，本轮未运行 | OrderApiIT#firstRequestWithIdempotencyKeyPersistsKeyAndHash |
| AC-2 | ⚠️ 有用例，本轮未运行 | OrderApiIT#repeatedKeyWithSameBodyReplaysFirstResultWithoutInsert（10 与 "10.00"、1 与 "1.0"）；WebMvcTest#passesValidIdempotencyKeyToServiceAndMarksReplay ✅ |
| AC-3 | ⚠️ 有用例，本轮未运行 | OrderApiIT#concurrentRequestsWithSameKeyInsertOnce（8 线程，全部 201，id 相同，count=1） |
| AC-4 | ⚠️ 有用例，本轮未运行 | OrderApiIT#sameKeyWithDifferentBodyReturns422AndKeepsFirstOrder；WebMvcTest#mapsReusedIdempotencyKeyTo422 ✅ |
| AC-5 | ⚠️ 有用例，本轮未运行 | OrderApiIT 原有 3 个用例 + #differentKeysWithSameOrderNoReturn409；WebMvcTest#createsWithoutIdempotencyKey、#mapsDuplicateOrderTo409 ✅ |
| AC-6 | ✅ | WebMvcTest#rejectsBlankIdempotencyKey（""、"   "）、#rejectsIdempotencyKeyLongerThan64（65）、正例 64 字符放行；都用 verifyNoInteractions(service) 断言没调用创建逻辑 |

## 知识库对照
| 知识条目 | 结论 | 说明 |
|---------|------|------|
| glossary/2026-09/订单金额舍入口径-HALF-UP-保留-2-位-历史订单为-DOWN-截断.md | ✅ 未违反 | 重放返回库中已落订单的 amount，不按当前计算器回算；指纹只基于入参，不含金额 |
