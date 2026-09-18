---
title: 订单金额舍入改为四舍五入
status: in-progress
tier: S
stage: code
stage_result: ok
base_tree: f8ebd3182611695fb5f2d5d54801ad31dc491f2a
created: 2026-09-18
updated: 2026-09-18
timing: {code: 1m}
---

## 问题描述

订单金额（单价 × 数量 × 折扣率）目前用 `RoundingMode.DOWN` 截断到 2 位小数，改为 `RoundingMode.HALF_UP` 四舍五入，仍保留 2 位小数。唯一计算点：`core/.../OrderAmountCalculator.total`，由 `app/.../OrderService` 调用后落库并返回。已落库的历史订单金额不回算。

## 验收标准

- [x] AC-1：给定下单请求，当金额第 3 位小数及之后 ≥ 0.005 时进位、< 0.005 时舍去，结果保留 2 位小数（例：1.25 × 1 × 0.5 = 0.625 → 0.63；9.99 × 1 × 0.333 = 3.32667 → 3.33；10.00 × 1 × 0.3333 = 3.333 → 3.33），接口返回与落库的 amount 一致。　证据：core 单测覆盖进位 / 舍去边界；真实 Postgres 上下单接口返回值与库中 amount 均为四舍五入结果（OrderApiIT）。
  - 验证：RED 时 roundsHalfUpWhenThirdDecimalIsFive（0.62≠0.63）、roundsUpWhenRemainderAboveHalf（3.32≠3.33）按预期失败；改为 HALF_UP 后 `./mvnw test` 8 个全部通过。OrderApiIT.roundsAmountHalfUpInResponseAndDatabase 已新增，由 check 的 verify 执行。

## 变更记录
