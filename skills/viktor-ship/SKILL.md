---
name: viktor-ship
description: 收尾一个需求：生成交付报告 report.md（本轮做了什么、待人工确认项），沉淀非推导知识到 docs/knowledge/，按需更新 CHANGELOG，标记需求完成。用户输入 /viktor-ship 或提到 viktor-ship，或者 review / check 完成后准备收尾时使用。
---

# viktor-ship：收尾与知识沉淀

用中文回复（节点卡、需要处理卡和其他说明都用中文）。

## 值得沉淀的只有三类

| 类型 | 写什么 | 判断标准 |
|------|--------|---------|
| decision | 架构或方案决策 | 存在被否决的备选方案，而且否决理由从代码里看不出来 |
| pitfall | 踩坑、必须确认的事项、高危约束 | 花了明显的排查时间，或者下一个 Agent 很可能再犯 |
| glossary | 业务术语、枚举语义、隐含业务规则 | 代码里只有值，没有含义 |

本次需求没有符合标准的内容就不写。不为留痕而写。工作流工具本身的问题（权限、脚本）不属于项目知识，不写。

## 知识的存放与检索

`docs/knowledge/` 一条知识一个文件（`<类型>/YYYY-MM/<slug>.md`），`index.md` 每条一行，由脚本维护。所有读写都通过 `bash <workflow-dir>/scripts/knowledge.sh`：

- 写入：`knowledge.sh add --type decision|pitfall|glossary --title "…" --scope "src/a.ts, 模块名, 场景" --source "docs/changes/<…>/" <<'EOF'` + 正文（结论与原因，2～5 行）。scope 是检索键：只写文件路径（`src/App.tsx`）、模块名或场景关键词（`搜索`、`查重`），用逗号分隔；不要写成句子（"src/App.tsx 的 xxx" 这种会让路径检查失效），说明放正文里。
- 推翻旧条目：先 `add` 新条目（正文里一句话说明为什么改），再 `knowledge.sh supersede <旧条目路径> <新条目路径>`。不要直接改旧条目正文。
- 不要手工编辑 index.md。

## 步骤

1. **提炼**：阅读本需求的 plan.md、review.md、diff 和对话中的关键讨论，列出候选条目。
2. **写入**（不停下来确认：条目列在交付报告"沉淀的知识"里，用户看报告时可以要求删改）：每条一次 `knowledge.sh add`；有推翻的用 `supersede`。
3. **CHANGELOG**：项目有 CHANGELOG.md 时，在 `[Unreleased]` 下添加面向用户的变更描述。
4. **交付报告**：写入 `docs/changes/<…>/report.md`，并在对话中展示：顶部状态条放代码块，其余表格**不放代码块**（让终端渲染）。只统计本需求目录的内容；review.md / check.md 缺失时对应格子写"未执行"，不阻塞。"审查者核实过但未构成问题的点"不进报告。**"待人工确认"只列 check.md `pending` 里的 AC**，逐条附 check.md 该行写的人工步骤与期望；review 的 SUGGESTED 一律进"剩余 SUGGESTED"，即使审查者建议人工核实也不进待人工。状态条的"待人工 <n> 项"必须等于 `pending` 条数；`pending` 为空时这一节写"无"。

   ```markdown
   ━━ ✅ 交付 · <需求名> · <档位> · 合计 <耗时> ━━━━━━━━━━━━━━
   改动 <f> 文件 +<a> −<d> · 测试 <k> passed · review <r> 轮 · check ✅ <x> 👀 <y> ❌ <z> · 待人工 <n> 项

   ## 待人工确认
   | # | 项 | 怎么验 | 期望 |
   |---|----|--------|------|
   | 1 | AC-3 渲染层 | npm run dev → … | … |
   （只列 check.md 的 pending；review / check 未执行时在表下写一行"check 未执行（原因）"，不计入条数）

   ## 本轮做了什么
   | 项 | 做了什么 | 改动文件 | 验证 | 结果 |
   |----|---------|---------|------|------|
   | AC-1 | … | src/a.ts | vitest 3 例 | ✅ |
   | 人工修改 | <非 AI 改动> | … | — | — |

   ## 审查记录
   | 轮 | 结果 | BLOCKING | 处理 |
   |----|------|----------|------|
   | 1 | blocked | 2 | 已修复 |
   | 2 | pass | 0 | — |
   剩余 SUGGESTED：<每条一行：位置 —— 建议>

   ## 耗时
   | plan | code | review | check | ship | 合计 |
   |------|------|--------|-------|------|------|
   | 4m（含等待确认） | 9m | 3m×2 | 3m | 1m | 23m |

   ## 沉淀的知识
   - decisions：<标题>　- pitfalls：<标题>　- glossary：<标题>

   ## 建议的 commit message
   ```
5. **收尾**：把 plan.md 的 `status` 改为 `done`、`stage: done`、更新 `updated`。
