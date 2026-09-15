---
name: viktor-code
description: 以测试驱动的方式实现需求或修复 bug，每一步都提供真实运行的测试证据。用户输入 /viktor-code 或提到 viktor-code、要求开始实现或按计划编码、修复 bug（S 档，无需计划）时使用。
---

# viktor-code：测试驱动实现

## 输入

- **M/L 档**：`docs/changes/<…>/plan.md`，要求 `status` 为 `confirmed` 或 `in-progress`。选择规则：只有一个 `in-progress` 的计划就用它；否则列出候选让用户选；没有已确认的计划则提示先使用 /viktor-plan。开始时把 `status` 改为 `in-progress`。
- **S 档**：直接使用用户描述。开始前用一句话声明档位和要做的改动，并自动创建 `docs/changes/YYYY-MM-DD--<slug>/plan.md`（frontmatter：`status: in-progress`、`tier: S`、`stage: code`；正文只有问题描述和一条 AC），不需要用户确认。

检查命令以 AGENTS.md 的 `viktor-checks` 块为准；缺失时提示用户运行 /viktor-init，本次先从 package.json 推断。

## 循环（每条任务或验收标准执行一次）

1. **RED**：写出描述目标行为的测试并运行。确认它失败，而且失败原因正确，不是语法或导入错误。
2. **GREEN**：写出刚好让测试通过的实现，运行测试。
3. **REFACTOR**：在测试保持通过的前提下整理代码，运行相关的 lint 和 typecheck。
4. **记录**：在 plan.md 中勾选完成的验收标准或任务。

修 bug 时，第一步必须是写出能复现问题的回归测试。

## 不走 RED/GREEN 的情况

- 纯类型定义任务：以 typecheck 通过为验证。
- 纯样式或布局、配置修改、一次性探索：说明改用哪种验证方式并实际执行。
- jsdom 中难以测试的交互（拖拽、滚动等）：优先用 `viktor-checks` 里的 e2e 命令；没有 e2e 时写明手动验证步骤和观察到的结果，作为证据记录在 plan.md 的对应条目下。

## 规则

- 无依赖标注的任务可以并行（工具支持子代理时）；标注了依赖的按顺序执行。
- 发现计划有问题：停下来说明，经用户同意后更新 plan.md 并在“变更记录”里写一行；不要自行偏离计划。
- 发现范围超出当前档位：停下来说明，建议升档并回到 /viktor-plan。

## 完成条件

所有任务或验收标准都有对应测试或验证证据，并且完整运行一遍 `viktor-checks` 中的命令后全部通过。

完成后：把 plan.md 的 `stage` 改为 `code`、`stage_result: ok`、更新 `updated`；S 档若排查中有符合 pitfalls 标准的踩坑（花了明显排查时间，或下一个 Agent 很可能再犯），追加一条到 `docs/knowledge/pitfalls.md`。在 viktor-flow 中运行时直接进入 review；单独运行时提示下一步使用 /viktor-review。

用户在本节点中途给出的补充要求或改动说明，追加到 plan.md 的“变更记录”。发现计划不成立或需升档时，`stage_result: blocked` 并输出停车卡（格式见 viktor-flow）。
