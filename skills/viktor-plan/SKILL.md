---
name: viktor-plan
description: 把需求变成一份经用户确认的轻量计划（docs/changes/<日期>--<slug>/plan.md），包含方案、影响范围和可验证的验收标准。用户输入 /viktor-plan 或提到 viktor-plan、提出新需求或功能想法、给出 PRD，或者 M/L 档任务开始编码之前使用。S 档的小改动和 bug 修复不使用。
---

# viktor-plan：需求到计划

一个节点完成需求澄清和任务拆分。计划只写对齐所必需的内容，其余交给 Agent 在编码时自行判断。

## 档位差异

- S 档：本节点不需要人工确认，由 viktor-code 自动生成 5 行的 plan.md（问题描述、tier、一条 AC）。

- M 档：写目标、方案、影响范围、验收标准、假设；不拆任务清单，验收标准即进度清单。
- L 档：在 M 档基础上增加任务清单。

## 与工具原生 plan 能力的关系

在 Claude Code 中，可以先进入 plan mode 完成调研和方案思考。用户批准退出 plan mode 即视为对计划的确认：随后把内容写入 `docs/changes/…/plan.md`，`status` 直接设为 `confirmed`，不再二次确认。其他工具按下面的步骤执行。

## 步骤

1. **收集上下文**：读取 AGENTS.md 的项目信息；用 `bash <workflow-dir>/scripts/knowledge.sh lookup <可能涉及的文件路径> <需求关键词>` 取相关知识（不要直接读 `docs/knowledge/` 下的文件）。需要了解代码时直接读代码。
2. **只问会改变方案的问题**：能从代码或上下文推断的，直接作为假设写进计划。确实需要用户决定的，一次性提出，最多 3 个。
3. **写 plan.md**：路径 `docs/changes/YYYY-MM-DD--<slug>/plan.md`，slug 用英文 kebab-case（例如 `filter-by-status`）。该需求已有目录时在原文件上更新。
4. **确认**：这一步的输出只有下面这张卡，卡外不写任何段落。用户确认后把 `status` 改为 `confirmed`，`stage: plan`，`stage_result: ok`。

```
━━ ⏸ PLAN 待确认 · <档位> · <耗时> ━━━━━━━━━━━━━━━━━━━━━━━━

目标
  <一两句话，含明确不做什么>

我替你做的决定
  1. <选了什么>
       备选：<另一种做法>          ← 只在真有备选时写
  2. …
  n. <没有备选的假设也放这里，一行>

需要你选                              ← 整段只在拿不准时出现
  第 n 条：A 还是 B？我倾向 A。

验收标准（<n> 条）
  1. <可测试的行为>
  2. <…>                              👀 需人工   ← 只标不能自动测的

任务（<m> 条）                        ← 仅 L 档
  1. <行为>  2. <行为>（依赖 1）  …

完整计划  docs/changes/<…>/plan.md
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
没问题回 OK，有要改的直接告诉我
```

"为什么"不进卡片，写在 plan.md 里。卡内不用 Markdown 语法，靠缩进和编号。



## plan.md 模板

```markdown
---
status: draft        # draft | confirmed | in-progress | done | archived
tier: M              # S | M | L
stage: plan          # plan | code | review | check | ship | done（最近完成或停住的节点）
stage_result: ok     # ok | blocked | error
review_round: 0
base_sha:             # code 开始时写入 git rev-parse HEAD，作为本需求的审查基线
verified: {}          # review / check 通过时写入被验证代码的指纹，例如 {review: a1b2c3, check: a1b2c3}
timing: {}            # 各节点耗时，由 flow 追加
created: YYYY-MM-DD
updated: YYYY-MM-DD
---

# <需求名>

## 目标
一两句话说明要解决什么问题，以及明确不做什么。

## 方案
关键设计和取舍。只有存在真实的备选方案时才写对比，并说明为什么不选。
涉及已有持久化数据的，写明兼容或迁移方式。

## 影响范围
将新增或修改的文件、模块、接口。

## 验收标准
- [ ] AC-1：<可测试的行为：给定…，当…，则…>
- [ ] AC-2：…

## 任务（仅 L 档）
- [ ] T1 接口与类型定义，直接写进 src；以 typecheck 验证
- [ ] T2 <一个可独立验证的行为>（对应 AC-1）
- [ ] T3 <…>（对应 AC-2；依赖 T2）

## 假设与风险
- 假设：…
- 风险：…

## 变更记录
- YYYY-MM-DD：<实现中调整了什么、为什么>
```

## 写作要求

- 每条验收标准都必须能对应到一个测试或一个明确的验证动作；难以自动化的交互（例如拖拽）写明用 e2e 还是手动验证。
- 任务按“可独立验证的行为”拆分，粒度以一个 TDD 循环能完成为准；有依赖的任务用 `（依赖 Tn）` 标注，未标注的视为可并行。
- 涉及接口、Store、Hook 的需求，把类型定义作为第一个任务直接写进 `src`，不另存副本。

## 节点卡（确认之后）

```
━━ ✔ PLAN · <档位> · <耗时> ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
结果      已确认
范围      验收 <n> 条 · 任务 <m> 条 · 决定 <k> 条
产物      docs/changes/<…>/plan.md
下一步    → code
```

单独运行时最后一行改为"输入 /viktor-code 继续"。
