---
status: done
tier: S
stage: done
stage_result: ok
review_round: 1
base_tree: 5b43cb347c4e604400b07e02d3752c59c97cd707
verified: {review: 42bd8c0552d1, check: 42bd8c0552d1, inputs: c05b16673773}
timing: {code: 1m, review: 1m, check: 1m, ship: 1m}
created: 2026-09-18
updated: 2026-09-18
---

OrderAmountCalculator 中 quantity 非正数校验失败时的异常信息从「quantity 必须大于 0」改为「quantity 必须在 1 到 999 之间」，与现有上限 999 一致；只改文案，不改校验逻辑（超过 999 的「quantity 不能超过 999」不在本次范围内）。

## 验收标准

- [x] AC-1（非关键，理由：只改异常文案，不涉及数据写入、接口契约或金额计算结果；接口层 @Min(1) 先于计算器拦截）：quantity 为 0 或负数时抛 IllegalArgumentException，信息为「quantity 必须在 1 到 999 之间」；quantity 为 1 与 999 仍正常计算，1000 仍抛出原有异常。
