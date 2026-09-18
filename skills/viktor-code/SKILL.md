---
name: viktor-code
description: 以测试驱动的方式实现需求或修复 bug，每一步都提供真实运行的测试证据。用户输入 /viktor-code 或提到 viktor-code、要求开始实现或按计划编码、修复 bug（S 档，无需计划）时使用。
---

# viktor-code：测试驱动实现

用中文回复（节点卡、需要处理卡和其他说明都用中文）。

## 输入

- **M/L 档**：`docs/changes/<…>/plan.md`，要求 `status` 为 `confirmed` 或 `in-progress`。选择规则：只有一个 `in-progress` 的计划就用它；否则列出候选让用户选；没有已确认的计划则提示先使用 /viktor-plan。开始时把 `status` 改为 `in-progress`；`base_tree` 为空则写入 `bash <workflow-dir>/scripts/viktor-spawn.sh snapshot` 的输出（当前工作区快照，含未提交的改动；之后的审查只看此后的变化，前一个需求没提交也不会混进来）。
- **S 档**：直接使用用户描述。开始前用一句话声明档位和要做的改动，并自动创建 `docs/changes/YYYY-MM-DD--<slug>/plan.md`（frontmatter：`status: in-progress`、`tier: S`、`stage: code`、`base_tree: <viktor-spawn.sh snapshot 的输出>`，字段同 viktor-plan 的模板，写入时去掉模板里的行尾注释；正文只有问题描述和一节 `## 验收标准`（一条 AC；按 viktor-plan"写作要求"里的关键 AC 规则：默认关键的写一句"证据："，标题必须是 `## 验收标准`，续接时靠它算验收输入摘要），不需要用户确认。

开始前用 `bash <workflow-dir>/scripts/knowledge.sh lookup <plan.md 影响范围里的路径>` 取相关知识（S 档用要改的文件路径）。检查命令以 AGENTS.md 的 `viktor-checks` 块为准。缺失时做**不修改项目配置的预检**：读 CI 配置、wrapper、README 推导本次可用的命令（可推导的键列全：`typecheck` / `lint` / `test` / `verify` / `e2e` / `dev`（推导不出的省略）；完整验收命令（含集成测试、需要环境的）放 `verify`，`e2e` 只放端到端测试；以 AGENTS.md 或仓库根目录为工作目录，子模块写进命令）和环境前提，写进 plan.md 的 `## 本轮运行配置` 节并注明来源；不写 AGENTS.md、不改 settings.json；卡片备注"未初始化，建议 /viktor-init"。

## 循环（每条任务或验收标准执行一次）

1. **RED**：写出描述目标行为的测试并运行。确认它失败，而且失败原因正确，不是语法或导入错误。
2. **GREEN**：写出刚好让测试通过的实现，运行测试。
3. **REFACTOR**：在测试保持通过的前提下整理代码，运行相关的 lint 和 typecheck。
4. **记录**：在 plan.md 中勾选完成的验收标准或任务。

修 bug 时，第一步必须是写出能复现问题的回归测试。

## 不走 RED/GREEN 的情况

统一规则：**无法形成有意义的行为 RED 时，提供替代验证并说明理由**。环境不可用（数据库起不来、依赖下不了）不是免测理由，那是"证据缺失"，要如实记录。常见情况：

- 纯类型 / DTO / Entity 定义：以编译或 typecheck 通过为验证。
- 纯样式或布局：说明验证方式（截图对比 / 手动步骤）并实际执行。
- 数据库迁移：在测试库上跑一遍迁移并验证结果；同时确认旧数据可读。
- 配置修改：如果改变了事务、权限、序列化等行为，必须有对应测试；只是环境参数才可免。
- 测试环境难以模拟的交互（拖拽、滚动、真实浏览器行为）：优先用 `viktor-checks` 里的 e2e；没有就写明手动验证步骤和观察到的结果，记录在 plan.md 对应条目下。

## 规则

- 无依赖标注的任务可以并行（工具支持子代理时）；标注了依赖的按顺序执行。
- 发现计划有问题：停下来说明，经用户同意后更新 plan.md 并在“变更记录”里写一行；不要自行偏离计划。
- 发现范围超出当前档位：停下来说明，建议升档并回到 /viktor-plan。

## 完成条件

所有任务或验收标准都有对应测试或验证证据，并且完整运行一遍 `viktor-checks` 中的快速检查（`typecheck` / `lint` / `test`）后全部通过。`verify` / `e2e` 留给 check，`dev` 不是检查项。

完成后：把 plan.md 的 `stage` 改为 `code`、`stage_result: ok`、更新 `updated`；S 档若排查中有符合 pitfalls 标准的踩坑（花了明显排查时间，或下一个 Agent 很可能再犯），用 `bash <workflow-dir>/scripts/knowledge.sh add --type pitfall …` 写入。然后只输出节点卡：

```
━━ ✔ CODE · <档位> · <耗时> ━━━━━━━━━━━━━━━━━━━━━━━━━
结果      AC <n>/<n> 完成
测试      <k> passed（新增 <j>）· typecheck ✅ · lint ✅
改动      <f> 文件 +<a> −<d>
下一步    → review
```

执行过程中每完成一个 AC 或任务输出一行 `· AC-n ✔ <测试名>`，不输出别的。单独运行时最后一行改为"输入 /viktor-review 继续"。

用户在本节点中途给出的补充要求或改动说明，追加到 plan.md 的“变更记录”。发现计划不成立或需升档时，`stage_result: blocked` 并输出需要处理卡（格式见 viktor-flow）。
