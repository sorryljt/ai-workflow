---
name: viktor-ship
description: 收尾一个需求：只沉淀代码里读不出来的知识（决策、踩坑、业务术语）到 docs/knowledge/，按需更新 CHANGELOG，并标记需求完成。用户输入 /viktor-ship 或提到 viktor-ship，或者 M/L 档 review 通过后准备收尾时使用。
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
5. **收尾**：把 plan.md 的 `status` 改为 `done`，输出小结：改了什么、如何验证的、沉淀了哪些知识、建议的 commit message。
