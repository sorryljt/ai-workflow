---
name: viktor-flow
description: 一个入口跑完整个开发流程（判档 → plan → code → review → check → ship），人只在 plan 确认和异常时介入；不带参数时续接自己未完成的需求。用户输入 /viktor-flow 或提到 viktor-flow、说“继续”“接着上次的”、或者给出一个完整需求希望自动做完时使用。
---

# viktor-flow：自动流水线与续接

## 两种调用

### `/viktor-flow <需求描述>`：开新需求

1. 判档并只输出一行声明（不写理由；用户可以直接说"按 L 走"改档）：

   ```
   ▶ M 档  plan（等你确认）→ code → review → check → ship
   ▶ S 档  code → review → check → ship（全程自动）
   ▶ L 档  plan（含任务清单，等你确认）→ code → review → check → ship
   ```
2. S 档：viktor-code → viktor-review → viktor-check → viktor-ship，中间不停。
3. M/L 档：viktor-plan → **等用户确认 plan** → viktor-code → viktor-review → viktor-check → viktor-ship。
4. 不检查旧需求，不提示旧尾巴。目录名冲突时自动加 `-2`、`-3` 后缀。

### `/viktor-flow`（无参数）或“继续”：续接

1. 扫描 `docs/changes/*/plan.md`，筛选**我的**未完成需求：`status` 为 `draft`、`confirmed` 或 `in-progress`，并且（文件未提交或有本地修改，或最后一次提交作者是当前 git 用户），并且 `updated` 在 14 天内。别人的需求完全静默，不列出、不碰。
2. 没有候选：说明没有可续接的需求，结束。
3. 一个候选：直接续接。多个：列出（需求名 / 停在哪个节点 / 更新时间）让用户选。
4. 每个候选可选：**继续**（从 `stage` 的下一个节点开始）/ **归档**（`status: archived`，之后不再列出）/ **忽略**（这次不管）。
5. 续接时先算当前代码指纹（`viktor-spawn.sh fingerprint <需求目录>`），与 plan.md 的 `verified` 比较：
   - 指纹与 `verified.review` / `verified.check` 一致：不重跑，从 `stage` 的下一步继续。
   - 指纹变了（用户手工改过代码）：已通过的 review / check 作废，从 review 重新开始（复审模式，只审变化部分）。
   后续节点都从磁盘重新取输入。

## 节点顺序与续接位置

| stage（最近完成的节点） | stage_result | 下一步 |
|---|---|---|
| plan | ok（且 status: confirmed） | code |
| plan | 其他（含 status: draft） | 输出待确认卡，等待确认 |
| code | ok | review |
| code | blocked | 需要处理（计划偏离/升档），处理后从 code 继续 |
| review | ok | check（指纹变了则回 review） |
| review | blocked | 需要处理（复审超阈值），用户修完后从 review（复审）继续 |
| check | ok | ship（指纹变了则回 review） |
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

**待确认卡**（plan 写完，格式见 viktor-plan）。

**需要处理卡**（其余四种情况）：

```
━━ ⚠ <节点> 需要处理 · <档位或轮次> · <耗时> ━━━━━━━━━━━━━

<一两句话说明卡在哪、你的判断>：
  1. <位置>  <问题>
  2. …（最多 5 条）

详情  docs/changes/<…>/<文件>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
回「再修」我再来一轮，回「跳过」先往下走；你自己改完了就说「继续」
```

最后一行只列当前真实可选的动作；例如缺前置时写 `补好后说「继续」`。

除这五处外不提问、不等待；review 的 SUGGESTED、check 的 👀 都不停，汇总进报告。

## 节点卡与耗时

每个节点开始时记下时间（`date +%H:%M:%S`），完成时只输出一张节点完成卡，并把耗时追加到 plan.md frontmatter 的 `timing`（例如 `timing: {plan: 4m, code: 9m, review: 3m×2, check: 3m, ship: 1m}`）：

```
━━ ✔ <节点> · <档位或轮次> · <耗时> ━━━━━━━━━━━━━━━━━━━━━━
结果      <一句话>
<关键数字行，节点各异>
产物      docs/changes/<…>/<文件>
下一步    → <节点>
```

卡片之外不输出别的内容，不复述文件。被打断后磁盘状态仍然有效，用 `/viktor-flow` 续接。

## 对话输出纪律（所有节点通用）

- 对话里只输出卡片，不复述文件内容；细节在产物文件里，卡片给出路径。卡片之外只允许一行 `备注`（最多两条）。
- 卡片放在代码块里输出，**卡内不使用任何 Markdown 语法**（不出现 `|` 表格、`#`、`**`、`-` 列表），层级靠两个空格缩进和数字编号；宽度不超过 60 列。
- 数字说话，不写评价性的句子；最后一行是固定措辞，不举例、不解释。
- 交付报告是唯一例外：顶部状态条放代码块，其余表格不放代码块，让终端渲染。
