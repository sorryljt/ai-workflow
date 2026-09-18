# 交付：Codex P24/P25 修复与 1.1.1 复测

## 本轮做了什么
| 项 | 改动 | 结果 |
|---|---|---|
| P24 | review 缺测试硬规则，spawn 按实际 diff 追加提醒，新增脚本回归 | c96f97c |
| P25 | snippet 注入原文纪律及两张卡，安装完整性断言，入口长度阈值随模板调整 | 5bdc861 |
| demo 升级 | submodule 5bdc861、重新 install、AGENTS 注入 | 98a3556 |
| demo S 档 | 负单价文案，先源码负例再补测试完成 flow | 614a346 |

## 验证
- validate 45/45；spawn、install、knowledge 均通过。RED 和 GREEN 证据见 plan.md 与 evidence/。
- 真实缺测试负例：25 个原有测试全绿，review 仍 BLOCKING 1，脚本退出 1。
- 真实主会话需要处理卡：从会话 JSONL 提取完整消息，与安装后 AGENTS.md 模板替换后逐字相等，卡外无文字。
- 待确认卡仅验证注入原文，S 档未触发真实 plan 待确认输出。
- demo 补测 RED 精确文案断言失败，GREEN 27 测试通过；独立 review pass、check AC 1/1，ship done。
- demo 完整 verify 退出 1（Testcontainers 找不到 Docker socket）；本次纯计算 AC 的单元测试证据充分，独立 check pass。不声明集成测试通过。

## 审查记录
工作流 review 第 1 轮 BLOCKING 2（源码删除与测试目录文档分类），补回归并修复后第 2 轮 pass。SUGGESTED 为真实 Codex 行为复测，已通过负例报告和主会话卡片证据落实。

## 待人工确认
无。最终独立 check 为 pass，pending: []。

## 知识沉淀
无；本次为工作流自身验证，证据写入 docs/2026-09-18--regression-0564e95.md 的“Codex 复测（1.1.1）”。

## 耗时
总计约 29m（包含并行执行）。过程与环境限制见 plan.md。

## 提交与发布
按用户要求分别提交 P24、P25，demo 升级单独提交，复测记录另行提交。未 push。
