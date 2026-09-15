---
name: viktor-ship
description: 收尾一个需求：生成交付报告 report.md（本轮做了什么、待人工确认项），沉淀非推导知识到 docs/knowledge/，按需更新 CHANGELOG，标记需求完成。用户输入 /viktor-ship 或提到 viktor-ship，或者 review / check 完成后准备收尾时使用。
---

# viktor-ship：收尾与知识沉淀

## 值得沉淀的只有三类

| 文件 | 写什么 | 判断标准 |
|------|--------|---------|
| `docs/knowledge/decisions.md` | 架构或方案决策 | 存在被否决的备选方案，而且否决理由从代码里看不出来 |
| `docs/knowledge/pitfalls.md` | 踩坑、必须确认的事项、高危约束 | 花了明显的排查时间，或者下一个 Agent 很可能再犯 |
| `docs/knowledge/glossary.md` | 业务术语、枚举语义、隐含业务规则 | 代码里只有值，没有含义 |

本次需求没有符合标准的内容就不写。不为留痕而写。

## 步骤

1. **提炼**：阅读本需求的 plan.md、review.md、diff 和对话中的关键讨论，列出候选条目。
2. **确认**：展示给用户，用户可以删改。
3. **写入**：

   ```markdown
   ## <一句话标题>
   - 日期：YYYY-MM-DD ｜ 来源：docs/changes/<…>/
   - 内容：<结论与原因，2～5 行>
   - 适用范围：<相关文件、模块或场景>
   ```

   新条目推翻或修改已有条目时，直接改原条目并注明变更原因，不让矛盾的记录并存。
4. **CHANGELOG**：项目有 CHANGELOG.md 时，在 `[Unreleased]` 下添加面向用户的变更描述。
5. **交付报告**：写入 `docs/changes/<…>/report.md`，并在对话中原样展示。只统计本需求目录的内容。

   ```markdown
   # 交付报告：<需求名>（<档位>）

   ## 待人工确认
   - 👀 AC-3：<手动验证步骤>（来自 check.md）
   - 未执行的节点：review（原因：…）        # 只有确实没做时才列

   ## 本轮做了什么
   | 项 | 做了什么 | 改动文件 | 验证方式 | 结果 |
   |----|---------|---------|---------|------|
   | AC-1 | … | src/a.ts, src/a.test.ts | vitest | ✅ |
   | 人工修改 | <根据 git 记录识别的非 AI 改动> | … | — | — |

   ## 审查记录
   review <n> 轮，发现并修复 <m> 个 BLOCKING；剩余 SUGGESTED：…

   ## 沉淀的知识
   - decisions：…

   ## 建议的 commit message
   ```

   review.md / check.md 缺失时对应章节写“未执行”，不阻塞。
6. **收尾**：把 plan.md 的 `status` 改为 `done`、`stage: done`、更新 `updated`。
