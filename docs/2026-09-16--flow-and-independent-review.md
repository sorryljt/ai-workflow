---
status: confirmed
confirmed_at: 2026-09-16
---

# viktor-flow 自动流水线 + 独立审查/验证 —— 实现方案

> 方案讨论已定稿，本文是实现层面的设计，作为拆任务的依据。

## 1. 目标

1. 一个入口跑完整流程，人只在 plan 确认和异常时介入。
2. review 与 check 在独立进程中执行，避免"自己审自己"，同时把成本控制在可推广的范围。
3. 每个节点可独立运行；人随时可以停、插话、不回来，续接不依赖会话记忆。
4. 交付报告让人一眼看到本轮做了什么、哪些已自动验证、哪些待人工。

## 2. 节点与状态

节点：init / plan / code / review / check / ship，调度器 flow。共 7 个技能，用户侧命令 `/viktor-<name>`。

状态只存在 `docs/changes/<日期>--<slug>/plan.md` 的 frontmatter：

```yaml
status: in-progress     # draft | confirmed | in-progress | done | archived
tier: S                  # S | M | L
stage: review            # plan | code | review | check | ship | done
stage_result: blocked    # ok | blocked | error
review_round: 1
updated: 2026-09-16
```

- S 档也建目录和 plan.md（AI 自动填：问题描述、tier、一条 AC），不需要确认。
- 每个节点开始时读 frontmatter，结束时更新 `stage` / `stage_result` / `updated`；只从磁盘取输入。
- 人在会话中给的补充信息，由当前节点追加到 plan.md 的“变更记录”。

## 3. flow 调度器（skills/viktor-flow）

```
/viktor-flow <需求>   新需求：判档 → S 档直接 code；M/L 档 plan → 停（确认）→ code → review ⇄ 修复 → check → ship
/viktor-flow          续接：列出“我的” in-progress 需求（未提交的，或最后提交作者是我；14 天内有更新），从 stage 的下一步继续
```

- 续接时多个候选让选；每个候选给三个动作：继续 / 归档（status: archived）/ 忽略。带参数启动时不检查旧需求。
- 别人的 in-progress 需求完全静默。
- 停车点统一格式（停车卡）：

  ```
  ⏸ 停在 <节点>：<一句话原因>
  你可以：① <动作>  ② <动作>
  继续：/viktor-flow
  ```

  停车点只有五处：plan 确认、缺前置（无 viktor-checks / 无测试框架）、计划偏离或需升档、复审超阈值仍有 BLOCKING、check 失败且修不好。
- 每个节点完成时输出一行进度，便于人随时打断。
- 目录名冲突自动加 `-2`、`-3` 后缀。

## 4. 独立进程：review 与 check

### 4.1 脚本 `scripts/viktor-spawn.sh <role> <changes-dir> [extra-args]`

- 检测当前工具：`claude` → `claude -p`；`codex` → `codex exec`；都没有 → 退出码 3，并把提示词打印出来，让用户手动开新窗口粘贴。
- 提示词来源：`prompts/review.md`、`prompts/check.md`（固化本次三轮审查用的提示词，含复审模式）。变量：changes 目录、档位、diff 范围、主干分支、上一轮 review.md 是否存在。
- 同步执行，外套 `timeout`（默认 480s，可用 `VIKTOR_SPAWN_TIMEOUT` 调整）。
- 退出后校验产物（review.md / check.md）存在且 frontmatter 可解析。退出码：0 通过，1 有 BLOCKING/失败项，2 进程失败（超时、崩溃、无产物），3 无可用 CLI。
- 权限参数按工具分别配置（待实测）：需要读仓库、执行 viktor-checks 中的命令、写 changes 目录下的一个文件。
- 后台模式（`--background`）：写 `.done` 标记，主会话轮询；默认不启用，只在实测超时后打开。

### 4.2 review 的成本控制

| 档位 | 输入 | 动作 |
|---|---|---|
| S | diff + 问题描述 | 只审 diff；重跑 test |
| M | diff + plan.md | 对照 AC；重跑 test；只对 diff 触及的边界做实验 |
| L | 同 M + knowledge 相关条目 | 允许对持久化/并发/安全改动做隔离实验 |

- typecheck / lint 采信 hook 结果，不重跑。
- diff 超过 800 行：不自动审，停车提示分批。
- 提示词硬约束：只审 diff 范围、不重构、不提建议性重写、不读无关文件；输出只有问题清单。
- 复审：最多 2 轮；只审修复部分的 diff 和处理记录；就地更新 review.md。

### 4.3 check（skills/viktor-check，独立进程）

- 输入：plan.md 的 AC（S 档为问题描述）、viktor-checks 中的 e2e 命令、dev 命令。
- 逐条 AC 验证，优先级：e2e 命令 → 启动 dev server 后用浏览器工具实际操作 → 都不可用则标“待人工”并写出验证步骤。
- 输出 `check.md`：每条 AC 一行：验证方式 / 证据（测试名、命令输出摘要、截图路径）/ 结果（✅ / 👀 待人工 / ❌）。
- ❌ 的项：flow 回到 code 修复一次，再 check 一次；仍 ❌ 则停车。

## 5. ship 与交付报告

ship 保留知识沉淀，新增 `report.md`（同时在对话中展示）：

1. 待人工确认（放最前，只列 👀 和跳过的节点）
2. 本轮做了什么：表格，每行一个 AC/任务：做了什么 / 改动文件 / 验证方式 / 结果；人工修改的部分单独一行
3. 审查记录：轮数、发现并修复的问题数、剩余 SUGGESTED
4. 沉淀的知识
5. 建议的 commit message

## 6. 节点独立性与续接

- 任何节点单独调用时，前置只看磁盘：缺什么就在输出里标出（例如 review 发现没有 plan.md，就按 S 档只审 diff）。
- 没有 skip 命令。人停在哪，磁盘就是什么状态；`/viktor-flow` 或一句“继续”从 stage 续接。
- review / check / ship 都重新从磁盘和 git 取输入，人工改动自然纳入。

## 7. hook 与 flow 的关系

Stop hook 保持不变，仍在每个回合结束时把关。flow 单会话内连续执行时，hook 只在最终回合结束触发一次；中途各节点自己跑 viktor-checks。

## 8. 任务拆分

- [ ] T1 plan.md frontmatter 扩展（stage / stage_result / review_round / updated）；plan、code 两个技能读写它；S 档自动建 plan.md
- [ ] T2 `prompts/review.md`、`prompts/check.md`（固化提示词，含档位约束、复审模式）
- [ ] T3 `scripts/viktor-spawn.sh` + 测试（用假的 `claude`/`codex` 可执行文件模拟：正常、超时、无产物、无 CLI）
- [ ] T4 review 技能改为派单器；新增 check 技能；ship 增加 report.md
- [ ] T5 flow 技能：判档、停车卡、续接（含归属判断与 14 天规则）、目录名冲突
- [ ] T6 snippet / README / CHANGELOG / validate.sh 更新（7 个技能）
- [ ] T7 todolist demo：S/M/L 各跑一遍，记录每个节点耗时与审查进程的 token 用量，写入 README；据此决定 spawn 的权限参数和是否启用后台模式

## 9. 待实测项

`claude -p` / `codex exec` 的权限参数与工具超时上限；一次 review / check 的真实耗时和 token；Cursor 下 CLI 是否可用（预计不可用，走手动兜底）。
