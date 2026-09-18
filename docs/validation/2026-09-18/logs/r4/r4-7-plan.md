---
status: in-progress
tier: S
stage: check
stage_result: error
review_round: 1
base_tree: ba50d3ad671b9872ee711b018e48fed8182274eb
verified: {review: 240ec1281a1a}
timing: {code: 70s, review: 122s, check: 110s}
created: 2026-09-18
updated: 2026-09-18
---

# unitPrice 负数异常文案

仅将 OrderAmountCalculator 的「unitPrice 不能为负数」改为「unitPrice 必须大于等于 0」，保持校验逻辑不变。

## 验收标准
- [x] AC-1：负数单价仍抛出 IllegalArgumentException，信息为「unitPrice 必须大于等于 0」；零和正数仍可计算，所有校验逻辑不变。证据：实际调用计算器验证负数、零、正数，检查生产 diff 仅改变字符串，并运行项目 test / verify。

## 实现证据
仅修改生产代码 1 行字符串；本次文案改动不新增持久测试，使用临时 Java 行为检查提供 RED/GREEN 证据。
- RED：java -cp core/target/classes /tmp/UnitPriceMessageCheck.java，退出 1，AssertionError: unexpected message: unitPrice 不能为负数。
- GREEN：同一命令，退出 0，PASS: 2 negative messages and zero/positive calculations（输入 -1、-0.01、0、1）。
- ./mvnw -q test，退出 0；25 tests，0 failures / errors / skipped。typecheck / lint 未配置，编译由 test 覆盖。
- git diff --stat：生产代码 1 文件 +1 −1。
