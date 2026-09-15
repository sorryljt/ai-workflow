---
name: viktor-review
description: 在独立上下文中审查本次改动的 diff，输出经过核实的问题清单（BLOCKING / SUGGESTED）。用户输入 /viktor-review 或提到 viktor-review、要求做 code review，或者实现完成后准备合并之前使用。
context: fork
---

# viktor-review：独立审查

本技能在独立上下文中运行（Claude Code 通过 frontmatter `context: fork`；其他工具建议在新会话中执行，若仍在实现会话中执行，在报告里注明 `independent: false`）。审查者只依据 diff、plan.md、AGENTS.md、`docs/knowledge/` 和调用参数，看不到实现过程中的对话。

参数：`$ARGUMENTS`。S 档没有 plan.md，调用方必须把要修的问题描述作为参数传入；参数为空且找不到 `in-progress` 的 plan.md 时，先向用户询问审查目标。

## 步骤

1. **确定范围**：主干分支取 AGENTS.md 项目信息中的“主干分支”，缺失时用 `main`。范围为 `git diff $(git merge-base HEAD <主干>)` 加上未提交改动。范围内若含明显不属于本需求的提交，在报告中列出并排除。
2. **先跑检查命令**：`viktor-checks` 中的 typecheck / lint / test，任何一项失败直接记为 BLOCKING；有 e2e 且本次涉及交互时也运行。
3. **逐项审查**：
   - **验收覆盖**：M/L 档对照 plan.md 的每条验收标准；S 档对照用户描述的问题，确认存在回归测试。
   - **正确性**：边界条件、异常处理、异步和竞态、状态一致性、已有持久化数据的兼容。
   - **安全**：XSS、敏感信息泄露、鉴权绕过、不可信输入的处理。
   - **与知识库一致**：是否违反 `docs/knowledge/` 中的决策或踩坑记录。
   - **范围**：计划之外的改动、无关重构、遗留的调试代码。
   - **性能与可维护性**：只在确实相关时提出。
4. **核实每个问题**：报告之前回到代码确认问题确实存在。

## 输出

M/L 档写入 `docs/changes/<…>/review.md`；S 档直接在对话中输出。

```markdown
---
result: pass         # pass | blocked
reviewed: YYYY-MM-DD
independent: true
---

# Review：<需求名>

## 检查命令
typecheck ✅ / lint ✅ / test ✅（附关键输出）

## 问题
- [BLOCKING] path/to/file.ts:42 —— 问题；后果；建议
- [SUGGESTED] …

## 验收覆盖
AC-1 ✅ xxx.test.ts；AC-2 ❌ 缺少测试
```

不打分，不写泛泛的评价，没有问题就写“无”。

## 复审

BLOCKING 修复后只复审相关部分。就地更新 review.md：已修复的问题标记为 `[已修复]` 保留，更新 `reviewed`，全部 BLOCKING 修复后把 `result` 改为 `pass`。

## 之后

- 有 BLOCKING：回到 /viktor-code 修复。
- 通过：M/L 档提示下一步使用 /viktor-ship；S 档到此结束。
