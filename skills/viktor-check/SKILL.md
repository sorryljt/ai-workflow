---
name: viktor-check
description: 派发独立验收：在新进程中以用户视角逐条验证验收标准是否真的可用（e2e、浏览器实际操作或给出手动步骤），输出 check.md。用户输入 /viktor-check 或提到 viktor-check、要求验证功能是否可用，或者 review 通过后、ship 之前使用。
---

# viktor-check：独立验收（派单器）

测试通过不等于功能可用。本节点让一个没有实现记忆的进程以用户视角逐条验证 AC，AI 先替人点一遍，人只看“待人工”的条目。验证逻辑在工作流仓库的 `prompts/check.md`。

## 输入（只从磁盘取）

- 需求目录（定位规则同 viktor-review）；plan.md 中的验收标准，S 档为问题描述。
- AGENTS.md `viktor-checks` 块中的 `e2e`、`dev` 命令（可选）。

## 步骤

1. 派单：`bash <workflow-dir>/scripts/viktor-spawn.sh check <需求目录>`。退出码：
   - 0：全部通过，或通过但有 👀 待人工项。`stage: check`、`stage_result: ok`。
   - 1：有 ❌。回到 viktor-code 修复一次（先补能复现失败的测试），再派单一次；仍 ❌ 则 `stage_result: blocked`，输出需要处理卡。
   - 2 / 3：同 viktor-review 的处理（进程失败 / 无 CLI，手动兜底文件为 `.check.prompt.md`）。
2. 只输出节点卡（有 ❌ 时把条目列在卡片下方，每条一行）：

```
━━ ✔ CHECK · <档位> · <耗时> ━━━━━━━━━━━━━━━━━━━━━━━━
结果      pass ／ manual ／ failed（独立进程）
AC        ✅ <a> · 👀 <b> · ❌ <c>
产物      docs/changes/<…>/check.md
下一步    → ship（自动继续） ／ → 修复后重验
```

## 之后

在 viktor-flow 中运行时直接进入 ship；单独运行时提示下一步使用 /viktor-ship。
