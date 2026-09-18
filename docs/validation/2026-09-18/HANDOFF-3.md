# 交接 3：修复后回归（fe-ai-workflow @ 0564e95）

前置：读 `docs/2026-09-18--validation-fixes.md`（第六节是回归清单）、`docs/2026-09-18--backend-validation.md`（两轮基线，对照用）、`viktor-validation/run.sh` 与 `run2-*.sh`（沿用它们的方式：无头 `claude -p`、日志写 `logs/r3/`、场景前后记 `git status`）。原则同前：能自己做的都自己做，只在需要用户动手时停下；fe-ai-workflow 除结果文档外不改——**回归里发现的 bug 记下来，不顺手修**；不 push。

## 0. 升级三个验证仓库到 0564e95

springboot-demo、springboot-demo-noinit、todolist-demo（在 `f5-rerun` 分支上）各自：`git -C .workflow/fe-ai-workflow fetch ~/personWorkSpace/fe-ai-workflow HEAD && git -C .workflow/fe-ai-workflow checkout 0564e95`，重新 `install.sh`，提交 `chore: upgrade fe-ai-workflow to 0564e95`。装完核对 `.claude/skills/` 里的 SKILL 是新版（例如 viktor-check 含"需要处理"卡模板）。三个仓库都已被 Claude Code 信任（第一轮做过），noinit 保持第二轮删掉放行规则的状态。

## 1. 场景（按第六节清单，逐条给期望 / 实际 / 结论 / 证据）

| # | 场景 | 通过标准 |
|---|---|---|
| R3-1 | springboot-demo 重跑 `/viktor-init`（重复执行模式，差异提出后由你回复"按探测结果更新"） | settings.json 含 `knowledge.sh`、`docker ps/rm/run/stop`、`dev` 放行；节点卡"检查命令"行只用 ✅ / — / 未验证；AGENTS.md 其他内容未被改坏 |
| R3-2 | S 档一次（例如 core：金额上限 100 万，超过抛异常） | plan.md frontmatter 无模板注释；`.review.log`、`.check.log` 为 stream-json；review / check 自动跑完 |
| R3-3 | 4.1 blocked（停 Docker，plan 退回 review，`/viktor-check`） | 退出码 4、不改代码（同前），**卡片与 F6 模板逐字一致**（标题行、"关键 AC 证据缺失，未改代码："、最后一行"环境处理好后说「继续」"） |
| R3-4 | 4.3 manual 走完 ship（AC-9 已在 plan 里；plan 退回 review，`/viktor-flow` 续接） | check `manual`、`pending: [AC-9]`；report.md "待人工确认"**只有** AC-9；review 的 SUGGESTED 全在"剩余 SUGGESTED"；状态条"待人工 1 项" |
| R3-5 | 4.5 noinit S 档（例如 discountRate 允许 4 位小数；若判 L 就回 OK） | 预检块里完整验收在 **`verify:`** 键、无 `e2e:` 误用；子进程被权限拦住 → review `error`、退出 2，卡片为 F6 的 error 卡，最后一行含"/viktor-init"；AGENTS.md / settings.json sha 不变。**另加**：临时把 noinit 目录的信任撤掉（`~/.claude.json` 里删该目录的 `hasTrustDialogAccepted`，备份原文件，做完还原）再派一次 review，期望 spawn 退出 2 且 stderr 含"未被信任" |
| R3-6 | 4.6 两条清理路径（直接调 spawn，`VIKTOR_SPAWN_TIMEOUT=40`） | a) 手工登记含 run_id 的容器 → 超时后被删；b) 不登记，让 IT 起 Testcontainers 容器，超时时容器仍在 → 被 F5 兜底删掉，派单前已存在的容器（先手动起一个 postgres 留着）不被动；`docker ps -a` 无残留、无残留 java 进程 |
| R3-7 | Codex S 档（例如 core：折扣率精度校验；`codex exec`，需要 codex 已登录） | 默认沙箱下 review 报 error → 主会话输出需要处理卡，**不改 VIKTOR_CODEX_ARGS、不提权**（查 `d*-codex.jsonl` 里没有 danger-full-access）。然后试 AGENTS.md 加 `- 子进程参数：codex --sandbox <值>`：先试 `workspace-write` 之外 codex 支持的值（`codex exec --help` 看清单），找出能跑 Maven 的最小值；写 `danger-full-access` 必须被拒（退出 2）。把可行值记下来，**不要改 README**，写进结果文档"需要用户决定" |
| R3-8 | 工作流自测 | `validate.sh`、`spawn.test.sh`、`install.test.sh`、`knowledge.test.sh` 全绿（在 fe-ai-workflow 里跑） |
| R3-9 | todolist-demo F5 重跑（在 `f5-rerun` 分支上再建 `f5-rerun-2`，从 `f129c8c` 起，升级到 0564e95 后 `/viktor-flow` 同一需求，回 OK） | 第一轮"第五步差异"1（report 待人工与 check 不一致）、2（尝试启动 dev 被拒）、3（knowledge.sh 被拒）消失；"关键"列全部为"否"；附加项"未涉及" |

## 2. 交付

结果写到 `fe-ai-workflow/docs/2026-09-18--regression-0564e95.md`：表格同前（期望 / 实际 / 结论 / 证据），第二节"未关闭或新发现的问题"（编号接 P12…，附原因判断），第三节"需要用户决定"（至少包含：Codex + JVM 的沙箱值、是否发 v1.1.0 并 push）。提交一个 docs commit，不 push。最后在对话里给每个场景一行结论。
