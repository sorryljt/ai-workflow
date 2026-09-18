---
status: done
based_on: 2076810
inputs: docs/2026-09-18--backend-validation.md（两轮验证，P1～P11）
---

# 验证问题修复规格（v1.1.0 前）

> 目标：把两轮真实模型验证暴露的 11 个问题关闭，然后跑一次缩减回归，通过后发 v1.1.0。
> 原则不变：能用脚本拦的不靠提示词；允许降低执行方式，不允许降低通过标准；不引入新节点、不改状态机。

## 一、脚本硬约束（安全边界，优先级最高）

### F1 spawn 拒绝子进程提权（P6）

- `viktor-spawn.sh`：`VIKTOR_CODEX_ARGS` 含 `danger-full-access`、`VIKTOR_CLAUDE_ARGS` 含 `--dangerously-skip-permissions` / `bypassPermissions` 时，打印原因并退出 2，不派单。
- 需要更宽沙箱的项目（JVM 项目在 Codex 下 Maven 跑不起来）走**项目配置**：init 在 AGENTS.md 项目信息节可写一行 `- 子进程参数：codex --sandbox <值>`；spawn 只从这一行读取，并且仍然拒绝 `danger-full-access`。Codex 对 JVM 的可行沙箱值由 F8 的回归确定，写进 README。
- viktor-review / viktor-check SKILL 在"退出码 2"处加一句：**不得修改沙箱或权限参数后重跑**，只能输出需要处理卡。
- `spawn.test.sh` 加两条用例：两种提权参数都被拒。

### F2 未信任工作区检测（P1）

- spawn 派单后若子进程退出码非 0 且 `.<role>.log` 含 `has not been trusted`（或 Claude Code 对应的英文提示，按当前版本核对），改为退出 2，stderr 明确写"工作区未被 Claude Code 信任，子进程会忽略 .claude/settings.json 的放行规则；请在项目目录交互式启动一次 claude 并选择信任，然后说「继续」"。
- README"接入"一节和 viktor-init 步骤 6 加一句：接入后必须在项目目录交互式打开一次 Claude Code 并信任工作区；上级目录的信任不传递到独立 git 仓库。
- `spawn.test.sh` 加一条：伪造含该提示的日志 → 退出 2 且 stderr 含"未被信任"。

### F3 子进程不得替换本轮配置里的命令（P10）

- `prompts/check.md`、`prompts/review.md` 的"输入"段改为：**只执行本轮运行配置里的命令**；认为命令无法产生证据、或命令本身有问题时，写 `result: error` 并在正文说明原因，退出；不得改用 AGENTS.md、README 或自己推导的其他命令。
- spawn 侧兜底：check.md / review.md 的"验证方式 / 证据"列若引用了 `viktor-checks` 块之外的构建命令，只警告不拦（无法可靠判断），警告写进 stderr。

## 二、init 放行规则（P2、P5、P11）

### F4 放行清单补齐

viktor-init 步骤 6 改为固定清单：

- `viktor-checks` 里除 `dev` 外的每条命令，原样一条；
- 该构建工具的通配一条（`Bash(./mvnw:*)`、`Bash(npx vitest run:*)` 等）；
- `Bash(bash <workflow-dir>/scripts/knowledge.sh:*)`（review / check 提示词都要求执行它）；
- `dev`：也放行，但 check 提示词改为"只有 AC 明确需要运行中的服务时才后台启动 dev，并登记 pid"；
- 运行前提提到 Docker / 容器运行时的项目：放行 `Bash(docker ps:*)`、`Bash(docker rm:*)`、`Bash(docker run:*)`、`Bash(docker stop:*)`。
- `install.test.sh` 不涉及；这一条靠回归里的 init 场景核对 settings.json。

### F5 资源登记适配测试框架（P5）

- 规格 §7 与 `prompts/check.md` 改为：子进程**不自行创建容器**来验证；只登记自己直接创建的资源（临时目录、后台 dev 的 pid）。测试框架内部创建的容器（Testcontainers）由框架自己回收，子进程在 check.md 说明"容器由 Testcontainers/ryuk 回收"即可。
- spawn 超时清理加一条兜底：有 docker 时 `docker ps -q --filter label=org.testcontainers.sessionId` 中**创建时间晚于本轮开始**的容器一律 `rm -f`，其余只报告。`spawn.test.sh` 用假 docker 脚本验证这条路径。

## 三、提示词模板（P3、P4、P8）

### F6 viktor-check 的 blocked / error 卡模板（P3）

在 SKILL"步骤 1"退出码 4 与 2/3 处直接给出卡片（沿用 flow 的需要处理卡，不另造格式）：

```
━━ ⚠ CHECK 需要处理 · <档位> · <耗时> ━━━━━━━━━━━━━━━━━━━━

关键 AC 证据缺失，未改代码：
  1. AC-n  <缺什么证据 / 需要什么环境>
  2. …（最多 5 条）

详情  docs/changes/<…>/check.md
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
环境处理好后说「继续」
```

error 时第一段改为"检查命令无法执行："，最后一行"运行 /viktor-init 补齐权限；你自己放行了就说「继续」"。viktor-review 的 error 卡同样明示。

### F7 交付报告的"待人工"只取 check 的 pending（P4）

viktor-ship 步骤 4 改为："待人工确认"**只列 check.md `pending` 里的 AC**，逐条附 check.md 里的人工步骤；review 的 SUGGESTED 一律进"剩余 SUGGESTED"，即使审查者建议人工核实。状态条的"待人工 <n> 项"与 `pending` 条数必须一致。

### F8 预检键名与格式小偏差（P8）

- viktor-plan 步骤 0 与 viktor-code 预检段：可推导的键列全（typecheck / lint / test / verify / e2e / dev），并写明"完整验收命令放 `verify`，`e2e` 只放端到端测试"。
- viktor-code S 档 plan.md、viktor-plan 模板：写入文件时去掉模板里的行尾注释（`# draft | confirmed | …`）。
- viktor-init 节点卡"检查命令"行只允许 `✅ / — / 未验证` 三种标记，不加括号说明。

## 四、判档判据（P7，可选）

### F9 README 与 AGENTS.snippet 的 L 档判据细化

"新增或修改数据模型 / 持久化结构"后加括：**给已有表加可空列、放宽或收紧请求校验边界不算**，这两类按 M 处理；只有影响已有数据可读性、需要迁移或改主键 / 唯一约束的才算 L。规格 §8 同步。

## 五、其他

- F10（P9）：spawn 默认给 claude 子进程加 `--output-format stream-json --verbose`，`.review.log` / `.check.log` 保留完整流，便于排查被拒的命令；`verify()` 读 result 的逻辑不受影响（仍读 `.md`）。
- CHANGELOG `[Unreleased]` 记录以上各项；README"独立审查与验收"一节补一句子进程不得提权、工作区需信任。

## 六、回归清单（修完后跑，缩减版）

| 场景 | 覆盖的修复 | 通过标准 |
|---|---|---|
| springboot-demo 重跑 `/viktor-init`（重复执行模式） | F4、F8 | settings.json 含 knowledge.sh、docker、dev 放行；节点卡无自由发挥 |
| S 档一次 | F8、F10 | plan.md 无模板注释；`.review.log` 为 stream-json |
| 4.1 blocked | F6 | 卡片与模板一致 |
| 4.3 manual 走完 ship | F7 | 报告"待人工"只有 AC-9，SUGGESTED 单列 |
| 4.5 noinit（保留删掉放行规则的状态） | F2、F3、F8 | 预检 verify 写成 `verify:` 键；error 卡提示信任 / init |
| 4.6 手工登记 + Testcontainers 兜底 | F5 | 两条清理路径都命中 |
| Codex S 档 | F1 | 默认沙箱下 error → 需要处理卡，主会话不提权；配置项目级沙箱值后通过 |
| spawn.test.sh / install.test.sh / validate.sh | F1、F2、F5 | 全绿 |
| todolist-demo F5 重跑一次 | 回归 | 与第一轮"部分通过"的差异 1、2、3 消失 |

通过后：更新 CHANGELOG 版本号、打 tag v1.1.0、push（由用户执行）。
