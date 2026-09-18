---
run_id: 20260918213909-32297
result: blocked
pending:
  - "AC-2（关键：服务端写入、对外接口）：verify 前提不满足，docker ps 失败（colima socket ~/.colima/default/docker.sock 不存在），真实 Postgres 上的 OrderApiIT 无法运行；本轮只有 mock 仓储的 OrderServiceTest，证明不了不落库"
  - "AC-3（关键：幂等、数据写入）：原因同上。历史超限订单直接写库后的重放（201 + Idempotent-Replayed、不新增行）和同键不同体返回 422，都需要在真实 Postgres 上验证"
checked: 2026-09-18
---

# Check：订单金额上限 100 万

环境探测：本需求没有浏览器类 AC，也不需要 dev server，所以没有启动 dev server。运行前提检查时，`docker ps` 失败，报错为 `failed to connect to the docker API at unix:///Users/dawson/.colima/default/docker.sock ... no such file or directory`。verify 依赖 Docker 和 Testcontainers，前提不满足，按规则放弃这条路径，本轮没有执行 `./mvnw -q verify`。

本轮执行了 `./mvnw -q test`，退出码 0，输出 `TEST_OK`。surefire 报告：core OrderAmountCalculatorTest 11/11 通过；app OrderServiceTest 3/3、OrderControllerWebMvcTest 8/8 通过，失败 0，错误 0。

本轮没有创建临时目录、后台进程或容器，`.check.resources` 无需登记。

| AC | 关键 | 验证方式 | 证据 | 结果 |
|----|------|---------|------|------|
| AC-1 计算器边界：1000000.00 放行、1000000.01 拒绝、1000000.004 → 1000000.00 放行、1000000.005 拒绝，原有用例仍通过 | 是（资金计算） | 单元测试（纯计算） | 本轮 `./mvnw -q test` 结果：OrderAmountCalculatorTest 11 个全部通过。<br>- acceptsTotalEqualToMaximum：10000.00×100×1 返回 1000000.00<br>- rejectsTotalAboveMaximum：1000000.01×1×1 抛 IAE<br>- comparesMaximumAfterRounding：1000000.004 返回 1000000.00；1000000.005 抛 IAE<br>- 原有 quantity、HALF_UP 舍入、折扣等 8 个用例全部通过 | ✅ |
| AC-2 POST /orders 超限（1000000.01×1×1）不返回 201；不带键和带新键都不落库 | 是（服务端写入、对外接口） | 证据缺失 | Docker 未就绪，verify（OrderApiIT，真实 Postgres）无法运行。本轮只有 OrderServiceTest.rejectsNewOrderAboveAmountLimitWithoutSaving 通过，它用的是 mock 仓储，不等价于真实库，无法证明 HTTP 状态码和行数为 0 | ⛔ |
| AC-3 已有带键超限历史订单：同键同体重放返回 201 + Idempotent-Replayed: true + 原订单，且不新增行；同键不同体返回 422 | 是（幂等、数据写入） | 证据缺失 | 原因同上，OrderApiIT 未运行。本轮只有 OrderServiceTest.replaysExistingOrderAboveAmountLimitWithoutRecalculating 通过（mock 仓储），只能说明重放路径不再计算金额，证明不了真实库上的重放、422 和行数 | ⛔ |

## 失败详情
- 无观察到的失败。AC-2、AC-3 需要先启动 Docker（例如 `colima start`，确认 `docker ps` 成功），再重跑 check 执行 `./mvnw -q verify`。
