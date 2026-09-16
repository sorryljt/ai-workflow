---
name: viktor-flow
description: 一个入口跑完整个开发流程（判档 → plan → code → review → check → ship），人只在 plan 确认和异常时介入；不带参数时续接自己未完成的需求。用户输入 /viktor-flow 或提到 viktor-flow、说“继续”“接着上次的”、或者给出一个完整需求希望自动做完时使用。
---

# viktor-flow：自动流水线与续接

## 两种调用

### `/viktor-flow <需求描述>`：开新需求

1. 判档并用一句话声明（S / M / L，判据见 AGENTS.md），用户可以改。
2. S 档：viktor-code → viktor-review → viktor-check → viktor-ship，中间不停。
3. M/L 档：viktor-plan → **等用户确认 plan** → viktor-code → viktor-review → viktor-check → viktor-ship。
4. 不检查旧需求，不提示旧尾巴。目录名冲突时自动加 `-2`、`-3` 后缀。

### `/viktor-flow`（无参数）或“继续”：续接

1. 扫描 `docs/changes/*/plan.md`，筛选**我的** in-progress 需求：`status` 为 `confirmed` 或 `in-progress`，并且（文件未提交或有本地修改，或最后一次提交作者是当前 git 用户），并且 `updated` 在 14 天内。别人的需求完全静默，不列出、不碰。
2. 没有候选：说明没有可续接的需求，结束。
3. 一个候选：直接续接。多个：列出（需求名 / 停在哪个节点 / 更新时间）让用户选。
4. 每个候选可选：**继续**（从 `stage` 的下一个节点开始）/ **归档**（`status: archived`，之后不再列出）/ **忽略**（这次不管）。
5. 续接时不重跑已完成的节点；后续节点都从磁盘重新取输入，用户手工的改动自然纳入。

## 节点顺序与续接位置

| stage（最近完成的节点） | stage_result | 下一步 |
|---|---|---|
| plan | ok（且 status: confirmed） | code |
| plan | 其他 | 等待确认 plan |
| code | ok | review |
| code | blocked | 需要处理（计划偏离/升档），处理后从 code 继续 |
| review | ok | check |
| review | blocked | 需要处理（复审超阈值），用户修完后从 review（复审）继续 |
| check | ok | ship |
| check | blocked | 需要处理（验收失败），用户修完后从 check 继续 |
| ship | ok | done |

## 只在这五处停下

| 停下的地方 | 触发条件 |
|---|---|
| plan 确认 | M/L 档 plan 写完 |
| 缺前置 | AGENTS.md 无 viktor-checks 块 / 无测试框架 → 建议先 viktor-init |
| 计划偏离 / 升档 | code 中发现计划不成立或范围超出档位 |
| 审查超阈值 | 2 轮复审后仍有 BLOCKING |
| 验收失败 | check 修复一次后仍 ❌，或 AC 无法验证 |

流程停下来时只有两种卡；卡里不写续接命令（续接是使用规则，README 里说明一次即可）：

**待确认卡**（plan 写完，格式见 viktor-plan）：`━━ ⏸ PLAN 待确认 · <档位> · <耗时> ━━`

**需要处理卡**（其余四种情况）：

```
━━ ⚠ <节点> 需要处理 · <档位> · <耗时> ━━━━━━━━━━━━━━
原因      <一句话>
问题      <每条一行，最多 5 条；超过的在产物文件里>
产物      docs/changes/<…>/<文件>
回复      「再修」我再处理一轮 ／「跳过」带着问题继续 ／ 自己改完后说「继续」
```

"回复"行只列当前情况真实可选的动作，每个动作写清后果；不存在的选项不列。
除这五处外不提问、不等待；review 的 SUGGESTED、check 的 👀 都不停，汇总进报告。

## 节点卡与耗时

每个节点开始时记下时间（`date +%H:%M:%S`），完成时只输出一张节点卡（各节点的"关键数字"行见对应 skill），并把耗时追加到 plan.md frontmatter 的 `timing`（例如 `timing: {plan: 4m, code: 9m, review: 3m×2, check: 3m, ship: 1m}`）：

```
━━ ✔ <节点> · <档位> · <耗时> ━━━━━━━━━━━━━━━━━━━━━━━
结果      <一句话>
<关键数字行，节点各异>
产物      docs/changes/<…>/<文件>
下一步    → <节点>（自动继续）
```

节点卡之外不输出别的内容，不复述文件。被打断后磁盘状态仍然有效，用 `/viktor-flow` 续接。

## 对话输出纪律（所有节点通用）

- 对话里只输出节点卡，不复述文件内容；细节在产物文件里，卡片给出路径。
- 卡片宽度不超过 60 列，表格不超过 5 列；数字说话，不写评价性的句子。
- 节点卡固定五行：结果 / 关键数字 / 产物 / 下一步。卡片之外只允许一行 `备注`（最多两条），不另起段落。


## 用户中途插话

用户在任何节点给出补充要求：当前节点照常处理，并把要求追加到 plan.md 的“变更记录”，之后按新要求继续。用户说“停”：更新 `stage` / `stage_result` 后停止，不做收尾动作。
