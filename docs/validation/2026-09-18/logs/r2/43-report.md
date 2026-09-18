```
━━ ✅ 交付 · 订单创建接口支持幂等键 · L · 合计 17m ━━━━━━━━━━━
改动 10 文件 +315 −8 · 测试 25 passed · review 3 轮 · check ✅ 6 👀 1 ❌ 0 · 待人工 2 项
```

## 待人工确认
| # | 项 | 怎么验 | 期望 |
|---|----|--------|------|
| 1 | AC-9 Kibana 日志检索（非关键） | 部署到生产后用 orderNo X 创建一笔订单，在 Kibana 检索 `order created orderNo=X` | 1 条 INFO 日志，logger 为 `c.example.demo.app.order.OrderService`，带 orderNo 和 id |
| 2 | 已有数据的库升级（IT 用的是空库） | 对已有 `orders` 表的库执行 `./mvnw -pl app -am spring-boot:run`，再在 psql 里执行 `\d orders` | 出现 `idempotency_key`、`request_hash` 两列和唯一约束 `uk_orders_idempotency_key`；历史行两列都为 NULL |

## 本轮做了什么
| 项 | 做了什么 | 改动文件 | 验证 | 结果 |
|----|---------|---------|------|------|
| T1 契约 | orders 表新增 `idempotency_key`（唯一）、`request_hash` 两列；新增 `findByIdempotencyKey`、`OrderCreation`，以及 400 / 422 两个异常 | Order.java、OrderRepository.java、OrderCreation.java、*Exception.java | 编译 | ✅ |
| AC-1 | 带键首次创建时写入键和 SHA-256 指纹 | OrderService.java | OrderApiIT 1 例（真实 Postgres） | ✅ |
| AC-2 | 同键同体重放首单：201，带 `Idempotent-Replayed: true`；等值写法（10 / 10.00）视为同一请求 | OrderService.java、OrderController.java | OrderApiIT 1 例 + WebMvcTest 1 例 | ✅ |
| AC-3 | 并发时靠唯一约束兜底，冲突后按键回查 | OrderService.java | OrderApiIT 8 线程并发 1 例 | ✅ |
| AC-4 | 同键不同体返回 422 `IDEMPOTENCY_KEY_REUSED` | OrderService.java、OrderController.java | OrderApiIT 1 例 + WebMvcTest 1 例 | ✅ |
| AC-5 | 不带键行为不变；键不同但 orderNo 重复仍返回 409 | OrderController.java | OrderApiIT 4 例 + WebMvcTest 1 例 | ✅ |
| AC-6 | 键为空白或超过 64 字符时返回 400 `INVALID_IDEMPOTENCY_KEY`，不进入 service | OrderController.java | WebMvcTest 3 例（含 64 字符正例） | ✅ |
| AC-9 | 创建成功后输出 INFO 日志 `order created orderNo={} id={}`（第 1 次 check 判 ❌ 后补上） | OrderService.java、OrderServiceTest.java | OrderServiceTest 1 例 + IT 运行日志 | 👀 |

## 审查记录
| 轮 | 结果 | BLOCKING | 处理 |
|----|------|----------|------|
| 1 | pass | 0 | — |
| 2 | pass | 0 | 复审 main 上的数量上限增量 |
| 3 | pass | 0 | 复审 AC-9 日志修复 |

剩余 SUGGESTED：
- CreateOrderRequest.java:14 —— quantity 只有 `@Min(1)`，缺 `@Max(999)`，quantity=1000 会返回 500（属于 quantity-limit 需求）
- OrderService.java:29 —— 金额计算在按键回查之前，重放也会被数量上限拦下；建议挪到回查未命中之后（已记入 pitfalls）
- OrderApiIT.java:106 —— AC-1~5 需要 verify 证据（check 已补上：OrderApiIT 8/8 通过）
- Order.java:14 —— 在已有旧 schema 的库上确认 ddl-auto 能建出列和唯一约束（已列入待人工确认第 2 条）
- Order.java:37 —— `request_hash` 实际是 varchar(64)，plan 里写的是 char(64)，两边要统一
- OrderService.java:59 —— 给 `fingerprint` 补 surefire 单测，覆盖等值写法得到相同哈希、不同 quantity 得到不同哈希

## 耗时
| plan | code | review | check | ship | 合计 |
|------|------|--------|-------|------|------|
| 1m（不含等待确认） | 3m+1m | 2m×3 | 1m×3 | 1m×3 | 17m |

## 沉淀的知识
- decisions：订单幂等键存在 orders 表上，不建独立幂等记录表
- pitfalls：OrderService.create 不能加外层 @Transactional，否则并发幂等回查失效；OrderService.create 先算金额再按幂等键回查，重放也受当前金额校验约束（本轮新增）
- glossary：Idempotency-Key 语义：全局唯一、永久有效、只有创建成功才占用

## 建议的 commit message
```
feat: 订单创建接口支持 Idempotency-Key 幂等键（viktor L 档）

- orders 表新增 idempotency_key（唯一）与 request_hash 列
- 同键同体返回首单（201 + Idempotent-Replayed: true），同键不同体返回 422
- 并发由唯一约束兜底，冲突后按键回查
- 非法键返回 400；不带键时行为不变
- 创建成功输出 INFO 日志（含 orderNo、id）
```
