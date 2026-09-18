---
status: done
tier: S
stage: done
stage_result: ok
review_round: 2
base_tree: 031115538d764141d9b7ac40499af1914e23d5f9
verified: {review: 7de5f28104d3, check: c53e470e67f8, inputs: cb2d0db876a1, pending: []}
timing: {review: 8m, check: 10m, total: 29m}
created: 2026-09-18
updated: 2026-09-19
---
# Codex P24/P25 修复

用户已明确实现方案、分别提交、不 push；skills 原文不动。

## 验收标准
- [x] AC-1：源码缺测试时 review 硬性 BLOCKING；spawn 提示缺测试；snippet 完整注入纪律及两张卡。证据：四个脚本通过、demo 独立 Codex review 负例和完成流程。

## 本轮运行配置
```viktor-checks
test: bash scripts/spawn.test.sh
test: bash scripts/knowledge.test.sh
verify: bash scripts/install.test.sh
lint: bash scripts/validate.sh
```
来源：AGENTS.md、scripts 下测试入口；另运行 knowledge.test.sh。

## 运行记录
- RED：spawn 提示缺失、install 待确认卡缺失均退出 1；边界用例复现测试目录文档误判。
- GREEN：validate 45/45，spawn、install、knowledge 均 PASS。spawn 旧有等长 fixture 指纹用例曾偶发失败，原样重跑通过；未改该既有测试。
- 独立 review 第 1 轮发现 2 项 BLOCKING，补齐删除源码和文档误判用例后第 2 轮 pass。第一轮包装脚本因运行中被主会话编辑发生 EOF，保留独立报告后用固定脚本复审通过；未调整任何权限参数。

## 复测证据位置
- 本目录 evidence/ 包含真实 demo 负例 review、prompt、diff、主会话卡片及校验记录，四脚本输出。
- demo 完整流程：/Users/dawson/personWorkSpace/springboot-demo/docs/changes/2026-09-18--codex-111/（review pass，check pass，ship done，demo 提交 614a346；最终报告已复制到 evidence/demo-report.md）。
- 工作流源码已分两条提交 c96f97c、5bdc861；剩余为复测文档。

## check 补验
第一轮读取 demo 收尾前的状态，判 manual。现已完成 demo check/ship 并保存提交 614a346，evidence/demo-{check,report,plan}.md 均已落盘；第二轮配置明确列出全部四个脚本，补齐本轮独立证据。
