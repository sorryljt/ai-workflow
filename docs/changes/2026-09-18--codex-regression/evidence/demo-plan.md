---
status: done
tier: S
stage: done
stage_result: ok
review_round: 2
base_tree: 488993351f61ff18c35c3b766be2186a7390f568
verified: {review: 03d7ace8a488, check: 03d7ace8a488, inputs: 76d975cbf106, pending: []}
timing: {code: 1m, review: 5m, check: 2m, ship: 1m}
created: 2026-09-18
updated: 2026-09-18
---
# Codex 1.1.1 S 档复测：负单价错误文案

按用户授权运行 viktor-flow。选择 core 负单价文案从“unitPrice 必须大于等于 0”改为“unitPrice 不能为负数”，无需口径选择，数量上限不变。选择此用例是为了让既有测试全绿，从而单独验证缺回归测试硬门禁，而非靠原有测试失败拦截。

## 验收标准
- [x] AC-1：负单价抛出 IllegalArgumentException，文案精确为“unitPrice 不能为负数”；零单价和正单价计算仍正确。证据：新增单元测试覆盖负数、零及正值。

## 复测步骤
用户明确要求先只改源码派一次 review（本次有意负例，非免测）；记录缺测试 BLOCKING 后补测试，恢复正常 code → review → check → ship。无替代验证豁免。
主会话卡片以当前 AGENTS.md 的纪律和模板为准；记录实际输出，区分安装验证与真实输出。

## 测试证据
- 负例：源码单独改动，既有 25 测试通过；独立 review result: blocked，1 项缺回归测试 BLOCKING，spawn 退出 1。
- RED：临时恢复旧文案，新测试运行 core 16，1 failure；expected unitPrice 不能为负数，actual unitPrice 必须大于等于 0。
- GREEN：恢复目标文案，./mvnw -q test 退出 0，core 16 + app 11 = 27，0 失败/错误/跳过。
- 卡片：从主会话 JSONL 提取真实需要处理卡，整条消息与 AGENTS.md 模板替换后完全相等；详见 card-verification.md。
