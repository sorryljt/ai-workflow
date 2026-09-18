```
━━ ✅ 交付 · 订单创建接口支持幂等键 · L · 合计 12m ━━━━━━━━━━━
改动 29 文件 +616 −39（业务 12 文件） · 测试 35 passed · review 5 轮 · check ✅ 6 👀 1 ❌ 0 · 待人工 1 项
```

## 待人工确认
| # | 项 | 怎么验 | 期望 |
|---|----|--------|------|
| 1 | AC-9 Kibana 日志检索（非关键） | 1. 上线后调用 `POST /orders` 创建订单，记下 orderNo；2. 在生产 Kibana 按该 orderNo 检索 | 能看到 `order created orderNo=<该值>` 的 INFO 日志 |

## 本轮做了什么
| 项 | 做了什么 | 改动文件 | 验证 | 结果 |
|----|---------|---------|------|------|
| T1 契约 | orders 表新增 `idempotency_key`（唯一）、`request_hash` 两列；新增 `findByIdempotencyKey`、`OrderCreation`，以及 400 / 422 两个异常 | Order.java、OrderRepository.java、OrderCreation.java、*Exception.java | 编译 | ✅ |
| AC-1 | 带键首次创建时写入键和 SHA-256 指纹 | OrderService.java | OrderApiIT（真实 Postgres） | ✅ |
| AC-2 | 同键同体重放首单：201，带 `Idempotent-Replayed: true`；10 / 10.00 视为同一请求 | OrderService.java、OrderController.java | OrderApiIT + WebMvcTest | ✅ |
| AC-3 | 并发靠唯一约束兜底，冲突后按键回查 | OrderService.java | OrderApiIT 8 线程并发 | ✅ |
| AC-4 | 同键不同体返回 422 `IDEMPOTENCY_KEY_REUSED`，不落库 | OrderService.java、OrderController.java | OrderApiIT + WebMvcTest | ✅ |
| AC-5 | 不带键行为不变；键不同但 orderNo 重复仍 409 | OrderController.java | OrderApiIT + WebMvcTest | ✅ |
| AC-6 | 空白或超 64 字符返回 400 `INVALID_IDEMPOTENCY_KEY`，不进入 service | OrderController.java | WebMvcTest 3 例（含 64 字符正例） | ✅ |
| AC-9 | 创建成功输出 INFO 日志 `order created orderNo={} id={}` | OrderService.java、OrderServiceTest.java | OrderServiceTest 1 例 | 👀 |
| 金额计算后移 | 按键回查未命中后才计算金额，超限历史带键订单也能重放 | OrderService.java、OrderServiceTest.java | OrderServiceTest#replaysExistingOrderAboveAmountLimitWithoutRecalculating | ✅ |
| 并入 main 增量 | 数量上限、金额上限、quantity 文案、discountRate 精度校验（其他需求）进入本需求基线之后的范围 | OrderAmountCalculator.java、OrderAmountCalculatorTest.java、OrderApiIT.java | verify：surefire 25 + OrderApiIT 10 全部通过 | ✅ |
| 工作流升级 | fe-ai-workflow 升到 1a0af51、viktor-init 重跑（非业务改动，触发本轮复审） | .claude/skills、.agents/skills、.workflow、AGENTS.md、.claude/settings.json | — | — |

## 审查记录
| 轮 | 结果 | BLOCKING | 处理 |
|----|------|----------|------|
| 1 | pass | 0 | — |
| 2 | pass | 0 | 复审 main 上的数量上限增量 |
| 3 | pass | 0 | 复审 AC-9 日志修复 |
| 4 | pass | 0 | 复审金额上限增量与金额计算后移；上一轮“计算先于回查”已修复 |
| 5 | pass | 0 | 续接复审：代码指纹变化（工作流升级、quantity 文案、discountRate 精度校验增量） |

check 共 4 次：第 1 次 AC-9 ❌（补日志后通过）；第 2 次因 check 子进程 `docker ps` 失败 blocked，未改代码，重跑后通过；本轮续接复审后重跑，`./mvnw -q verify` 退出码 0，结果 manual（仅 AC-9 待人工）。

剩余 SUGGESTED：
- OrderAmountCalculator.java:35 —— discountRate 精度校验来自已归档、未通过审查的需求 discount-rate-precision，请求层无 `@Digits(fraction=2)`、异常无 HTTP 映射，discountRate=0.678 由 201 变为 500；需人决定保留（重走该需求 review/check 并补 400 映射）还是回退
- OrderService.java:42 —— 计算器的 IllegalArgumentException（quantity > 999、金额 > 1000000.00）没有 HTTP 映射，超限请求返回 500；建议单独立需求统一映射为 400
- Order.java:14 —— IT 用的是空库，旧 schema 上 `ddl-auto: update` 能否建出两列和 `uk_orders_idempotency_key` 未验证；建议在带旧表的库上启动后 `\d orders` 确认
- Order.java:37 —— `request_hash` 实际是 varchar(64)，plan 写的是 char(64)，统一其中一处
- OrderService.java:65 —— 给 `fingerprint` 规范化补 surefire 单测（等值写法哈希相同、quantity 不同哈希不同）
- OrderApiIT.java:106 —— AC-1~5 需 verify 证据（本轮 check 已补：OrderApiIT 10/10 通过，Skipped 0）

## 耗时
| plan | code | review | check | ship | 合计 |
|------|------|--------|-------|------|------|
| 1m（不含等待确认） | 3m | 2m×2 | 1m×2 | 1m×2 | 12m |

## 沉淀的知识
- 本轮无新增（已有条目仍有效）
- decisions：订单幂等键存在 orders 表上，不建独立幂等记录表
- pitfalls：OrderService.create 不能加外层 @Transactional，否则并发幂等回查失效；OrderService.create 幂等键回查未命中后才算金额，不要挪回前面
- glossary：Idempotency-Key 语义：全局唯一、永久有效、只有创建成功才占用

## 建议的 commit message
```
feat: 订单创建接口支持 Idempotency-Key 幂等键（viktor L 档）

- orders 表新增 idempotency_key（唯一）与 request_hash 列
- 同键同体返回首单（201 + Idempotent-Replayed: true），同键不同体返回 422
- 并发由唯一约束兜底，冲突后按键回查；回查未命中才计算金额
- 非法键返回 400；不带键时行为不变
- 创建成功输出 INFO 日志（含 orderNo、id）
```
