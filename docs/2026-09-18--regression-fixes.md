---
status: done
based_on: aac4797
inputs: docs/2026-09-18--regression-0564e95.md（P12～P21）
---

# 回归问题修复规格（v1.1.0 发版前最后一轮）

> 范围：只修会让用户踩坑的五条（P12、P13、P14、P16、P18）加 P17 的决定；P15、P19、P20、P21 写进 CHANGELOG"已知问题"，不修。每条单独提交；改完 validate / spawn.test / install.test / knowledge.test 全绿；不跑回归、不 push。

## F11 环境探测不得包 timeout、不得吞 stderr（P12）

`prompts/check.md`"先探测自己有什么"一段改为：探测命令直接执行（`docker ps`、`docker info`），**不要用 `timeout` 包裹**（macOS 没有这个命令），**不要 `2>/dev/null`**；"命令不存在"是探测方式错误而不是环境不可用，换一种直接命令再探一次；只有命令存在且报错才算环境不可用。删掉"探测本身不超过 1 分钟"（spawn 有总超时兜底）。

## F12 检查命令单独执行（P18）

`prompts/review.md` 与 `prompts/check.md` 的"输入"段加一条：检查命令**单独作为一条 Bash 执行**，不加管道、重定向、`;`、`&&`、`$?`；需要退出码看工具的返回，需要明细去读测试报告文件（surefire / failsafe / vitest 输出）。理由写一句：放行规则只匹配单条命令。

## F13 knowledge.sh 路径统一（P13）

spawn 替换 `{{WORKFLOW_DIR}}` 时改为**相对于项目根目录的路径**（`python3 -c` 或 `realpath --relative-to`，无 realpath 时退回绝对路径并同时放行）；viktor-init 步骤 6 放行 `Bash(bash <相对 workflow-dir>/scripts/knowledge.sh:*)`。`spawn.test.sh` 加一条：生成的 `.review.prompt.md` 里 knowledge.sh 路径以 `.workflow/` 开头。

## F14 升级提示补齐放行（P14）

- `upgrade.sh` 结束时检测项目 `.claude/settings.json` 缺少 `knowledge.sh` 放行规则 → 打印"本版本要求重跑 /viktor-init（重复执行模式）补齐放行规则"。
- CHANGELOG `[1.1.0]` 第一条写升级说明；README"接入"一节的升级命令后加同一句。

## F15 需要处理卡遵从度（P16）

- viktor-review、viktor-check、viktor-flow 的"对话输出纪律"加一句：**卡片之外不输出任何文字，包括"备注"**（S 档 viktor-code 的一行备注例外，仅限"未初始化"提示）。
- viktor-review：error 时标题写 `第 <review_round>/3 轮`（不加 1），第一段固定为"检查命令无法执行："。
- 所有 SKILL 顶部加一句"用中文回复"（顺带关 P19）。

## F16 Codex 沙箱配置（P17，已由用户决定）

- AGENTS.md 项目信息节的 `- 子进程参数：codex …` 一行允许完整参数串，spawn 原样切分后追加；仍拒绝含 `danger-full-access` 的值（环境变量和这一行都拒）。
- README"独立审查与验收"一节写明：JVM 项目在 Codex 下需要 `--sandbox workspace-write -c sandbox_workspace_write.network_access=true`，这会放开子进程外网访问；由 init 在探测到 Maven / Gradle 时写入这一行并在节点卡备注。
- `spawn.test.sh`：AGENTS.md 行含 `network_access=true` → 参数被追加；含 `danger-full-access` → 退出 2。

## 已知问题（写进 CHANGELOG，不修）

P15 未信任检测依赖 settings.json 有规则；P20 预检偶尔漏列 dev；P21 init 重复执行模式可能对约定 / 禁区提差异（经确认才改）。

## 复测（修完后单独跑）

| 场景 | 覆盖 | 通过标准 |
|---|---|---|
| R3-4 manual 走完 ship | F11、F12、F15 | 第一次 check 就是 manual（不再误判 blocked）；卡外无备注 |
| R3-7 Codex S 档 | F16 | init 写入子进程参数行；默认跑通，无提权；需要处理卡（如出现）用模板 |
| R3-9 todolist F5（`f5-rerun-3`） | F13、F14 | upgrade 打印重跑 init 提示；init 后 review 第一次调用 knowledge.sh 不被拒 |
| 自测 | 全部 | 四个测试脚本全绿 |

通过后：CHANGELOG 定版 1.1.0、README 接入命令的 tag 改为 v1.1.0、打 tag、push（用户执行）。
