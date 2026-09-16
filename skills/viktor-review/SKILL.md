---
name: viktor-review
description: 派发独立审查：在新进程中审查本次改动的 diff，输出问题清单（BLOCKING / SUGGESTED）到 review.md，并驱动修复与复审循环。用户输入 /viktor-review 或提到 viktor-review、要求做 code review，或者实现完成后准备合并之前使用。
---

# viktor-review：独立审查（派单器）

审查在一个全新的进程里进行（同一个工具，新会话），审查者没有实现过程的记忆，只看 diff。本技能负责派单、读结果、驱动修复循环；审查逻辑在工作流仓库的 `prompts/review.md`。

## 输入（只从磁盘取）

- 需求目录：优先当前对话中的需求；否则取 `docs/changes/` 下 `status: in-progress` 且属于当前用户的目录（未提交，或最后提交作者是当前 git 用户）；多个则让用户选；一个都没有就按 S 档处理当前 diff，并让 viktor-code 的规则先建一个 plan.md。
- `$ARGUMENTS`：可选的补充说明（S 档的问题描述、要求重点关注的点），追加到需求目录 `.review.prompt.md` 之后的调用参数里。

## 步骤

1. 确认有 diff（`git status`）；没有改动则说明并结束。
2. diff 超过 800 行：不派单，输出需要处理卡建议分批（按任务提交一部分再审）。
3. 派单：`bash <workflow-dir>/scripts/viktor-spawn.sh review <需求目录>`（workflow-dir 通常为 `.workflow/fe-ai-workflow`）。同步等待，退出码含义：
   - 0：通过。`stage: review`、`stage_result: ok`。
   - 1：有 BLOCKING。进入修复循环（下一节）。
   - 2：审查进程失败（超时、崩溃、无产物，或审查者报告检查命令无法执行）。不计入复审轮次。输出需要处理卡，附 `.review.log` 路径；若是权限问题，回复行给出「运行 /viktor-init 补齐权限」的选项。
   - 3：没有可用的 CLI。输出需要处理卡：让用户开一个新窗口，把 `.review.prompt.md` 的内容作为第一条消息发送，完成后回来说「继续」。
4. 读取 review.md，`review_round` 加 1，只输出节点卡（有 BLOCKING 时把条目列在卡片下方，每条一行：`[BLOCKING] 位置 —— 问题`）：

```
━━ ✔ REVIEW · 第 <r>/3 轮 · <耗时> ━━━━━━━━━━━━━━━━━━━
结果      pass ／ blocked（独立进程）
问题      BLOCKING <b> · SUGGESTED <s> · 已修复 <f>
验收覆盖  <n>/<m> 有测试
产物      docs/changes/<…>/review.md
下一步    → check（自动继续） ／ → 修复后复审
```

## 修复循环

- 有 BLOCKING 时，按 review.md 逐条修复（沿用 viktor-code 的 TDD 规则：先补测试再改），然后再次派单复审（审查者会读到已有的 review.md，进入复审模式，只审修复部分）。
- 最多 2 轮复审（`review_round` ≤ 3）。仍有 BLOCKING：`stage_result: blocked`，输出需要处理卡，列出剩余问题和你的判断（实现问题还是计划问题）。
- SUGGESTED 不修，留在 review.md，由 ship 汇总进报告。

## 不在独立进程中审查的情况

用户明确要求在当前会话审（例如说“就在这里看一下”）：按 `prompts/review.md` 的审查项自己审，review.md 标 `independent: false`。

## 之后

在 viktor-flow 中运行时直接进入 check；单独运行时提示下一步使用 /viktor-check。
