---
name: viktor-check
description: 派发独立验收：在新进程中以用户视角逐条验证验收标准是否真的可用（e2e、浏览器实际操作或给出手动步骤），输出 check.md。用户输入 /viktor-check 或提到 viktor-check、要求验证功能是否可用，或者 review 通过后、ship 之前使用。
---

# viktor-check：独立验收（派单器）

用中文回复（节点卡、需要处理卡和其他说明都用中文）。

测试通过不等于功能可用。本节点让一个没有实现记忆的进程以用户视角逐条验证 AC，AI 先替人点一遍，人只看“待人工”的条目。验证逻辑在工作流仓库的 `prompts/check.md`。

## 输入（只从磁盘取）

- 需求目录（定位规则同 viktor-review）；plan.md 中的验收标准，S 档为问题描述。
- AGENTS.md `viktor-checks` 块中的 `e2e`、`dev` 命令（可选）。

## 步骤

1. 派单：`bash <workflow-dir>/scripts/viktor-spawn.sh check <需求目录> --agent <当前工具> [--checks <文件>]`。项目有 `viktor-checks` 块就不传 `--checks`（spawn 自己读，项目配置权威）；没有时把 plan.md `## 本轮运行配置` 整节内容（块 + 环境前提）写到临时文件传入；两者都没有 spawn 会拒绝派单（退出码 2），先做预检。退出码：
   - 0：`pass` 或 `manual`（仅非关键 AC 待人工）。`stage: check`、`stage_result: ok`，写 `verified.check`（指纹）和 `verified.inputs`（`viktor-spawn.sh inputs-digest <需求目录>` 的输出：AC 列表 + 证据要求 + 本轮运行配置的摘要）。manual 时把 check.md 的 `pending` 原样带进报告的"待人工"，不表述为全部验证完成。
   - 1：`failed`，观察到行为错误。回到 viktor-code 修复（先补能复现失败的测试），修复后先派 review 复审，再派 check；仍失败则 `stage_result: blocked`，输出需要处理卡。
   - 4：`blocked`，关键 AC 证据缺失或环境不可用。**不改业务代码**。`stage_result: blocked`，只输出下面这张需要处理卡（沿用 viktor-flow 的格式，不另造字段、不换语言）；用户处理后说"继续"，flow 会先核对代码指纹再重跑 check：

     ```
     ━━ ⚠ CHECK 需要处理 · <档位> · <耗时> ━━━━━━━━━━━━━━━━━━━━

     关键 AC 证据缺失，未改代码：
       1. AC-n  <缺什么证据 / 需要什么环境>
       2. …（最多 5 条）

     详情  docs/changes/<…>/check.md
     ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
     环境处理好后说「继续」
     ```

   - 2 / 3：同 viktor-review（进程失败 / 无 CLI）。`stage_result: error`。**不得修改沙箱或权限参数后重跑**，只能输出需要处理卡。检查命令无法执行（`result: error`）时用同一张卡，第一段改为"检查命令无法执行："，条目写 `<命令>  <被拒 / 不存在 / 报错>`，详情指向 check.md 或 `.check.log`，最后一行改为"运行 /viktor-init 补齐权限；你自己放行了就说「继续」"；spawn 报"工作区未被 Claude Code 信任"时，最后一行改为"在项目目录交互式启动一次 claude 并选择信任，然后说「继续」"。
2. **👀 项的补验（可选）**：子进程通常没有浏览器。如果你（主会话）有浏览器工具，可以对 check.md 里的 👀 项做一次浏览器验证，结果写回 check.md 对应行，验证方式标注"主会话浏览器验证"；✅ 的项不重验；没有浏览器工具就跳过，👀 留给人。
3. 只输出节点卡（有 ❌ 时在"AC"行下方缩进列出，每条一行）：

```
━━ ✔ CHECK · <档位> · <耗时> ━━━━━━━━━━━━━━━━━━━━━━━━
结果      pass ／ manual ／ failed（独立进程）
AC        ✅ <a> · 👀 <b> · ❌ <c>
产物      docs/changes/<…>/check.md
下一步    → ship
```

## 对话输出纪律

同 viktor-flow：**卡片之外不输出任何文字，包括"备注"**；需要补充的信息写进卡片条目或产物文件。

## 之后

在 viktor-flow 中运行时直接进入 ship；单独运行时提示下一步使用 /viktor-ship。
