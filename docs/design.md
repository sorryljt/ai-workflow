# 工作机制

面向维护者的机制说明。使用方法见 README；规则的真相源是 `skills/viktor-*/SKILL.md`、`prompts/`、`hooks/`，本文只解释它们为什么这样设计、边界在哪。

## 门禁

`viktor-init` 在 AGENTS.md 写入：

```viktor-checks
typecheck: pnpm tsc --noEmit
test: pnpm vitest run
verify: mvn verify           # 可选，完整验收，只有 check 跑
e2e: pnpm playwright test    # 可选
dev: pnpm dev                # 可选，启动入口
```

命令一律以 AGENTS.md 所在目录为工作目录，子模块写进命令本身（`mvn -pl server test`）。块后面的 `### 运行前提` 节写外部环境（数据库、容器运行时），会一起交给独立进程。

Stop hook 只在源码改动指纹变化时运行 typecheck / lint / test；失败反馈给 Agent 修复，同一回合连续 3 次失败后放行并提示用户。支持 git worktree 和 monorepo 子包。命令必须是非 watch 模式。

## 独立审查与验收

review / check 通过 `scripts/viktor-spawn.sh` 用 `claude -p` 或 `codex exec` 起新进程，同步等待，默认 480 秒超时。审查深度按档位限制，diff 超过 800 行不自动审。子进程不继承会话授权，`viktor-init` 会把检查命令写进 `.claude/settings.json` 的 `permissions.allow`；这些规则只在已信任的工作区生效，spawn 派 Claude 子进程前读取 `~/.claude.json` 中的信任字段，候选包含 `$PWD`、解析符号链接后的物理路径、git 根目录和 worktree 对应的主仓库路径；任一为 `true` 即通过，无明确记录时只警告并继续，明确为 `false` 且没有候选为 `true` 时退出 2 并提示先信任。配置文件缺失或 node / python3 均不可用时跳过主动检测，仍保留日志关键字检测兜底。check 按每条 AC 选最小充分证据：涉及服务端数据、权限、契约、资金、幂等的 AC 默认关键，证据缺失就 `blocked`（退出码 4，不改代码，处理环境后重验）；非关键项测不到标 👀 待人工。没跑过 `/viktor-init` 的项目，plan 会先做一次不改配置的预检，逐键从 README、package.json、CI 和构建配置核对 typecheck / lint / test / verify / e2e / dev，能推导出的键一条都不能省，推导不出的键省略且注明；dev 只记录启动入口，预检时不启动服务。命令以本轮配置传给子进程。

子进程不得提权：spawn 拒绝 `--dangerously-skip-permissions`、`bypassPermissions`、`danger-full-access` 等参数（退出码 2），主会话遇到权限问题只输出需要处理卡、不改参数重跑。Codex 下 JVM 项目（Maven / Gradle）在默认 `workspace-write` 沙箱里跑不起测试（Mockito 等需要 JVM self-attach，被沙箱的网络限制拦下），需要 `--sandbox workspace-write -c sandbox_workspace_write.network_access=true`：viktor-init 探测到 Maven / Gradle 时会在 AGENTS.md 项目信息节写入 `- 子进程参数：codex --sandbox workspace-write -c sandbox_workspace_write.network_access=true`，并在节点卡上注明。**这会放开 review / check 子进程的外网访问**，不接受的话删掉这一行（Codex 下 JVM 项目的独立验收会报 error）。`read-only` 连报告都写不了；`danger-full-access` 和 `--dangerously-*` 无论写在环境变量还是这一行都会被拒绝。

验证范围：Claude Code 端的各档位、续接、blocked / manual、交付报告都做过真实模型验证；**Codex 端只验证了基本流程**（S 档派单、JVM 项目的沙箱参数、子进程不提权）。

Codex + JVM + Docker（本机 colima）已验证：保留 `workspace-write`、`network_access=true` 和 colima 目录写权限，设置 `DOCKER_HOST=unix://<socket 绝对路径>`、`TESTCONTAINERS_RYUK_DISABLED=true` 后，完整 verify 的 37 个测试通过。另加 `TESTCONTAINERS_HOST_OVERRIDE=127.0.0.1` 也通过，但本机不需要这个变量。init 会在“子进程参数”中一并写入这些配置，例如：

```text
- 子进程参数：codex --sandbox workspace-write -c sandbox_workspace_write.network_access=true --add-dir /Users/dawson/.colima/default -c 'shell_environment_policy.set.DOCKER_HOST="unix:///Users/dawson/.colima/default/docker.sock"' -c 'shell_environment_policy.set.TESTCONTAINERS_RYUK_DISABLED="true"'
```

将示例路径换成实际探测到的绝对路径。`--add-dir` 用于添加 colima 可写目录（试验中使用等效的 `sandbox_workspace_write.writable_roots`）；[Codex 的 shell_environment_policy.set](https://developers.openai.com/codex/config-reference) 向执行命令注入环境变量，其值必须为字符串，保留示例中的单双引号，不能把 `"true"` 写成 TOML 布尔值。spawn 支持这些分组引号，仍拒绝 shell 展开、运算符及提权参数。禁用 Ryuk 后不再有 Ryuk 的异常退出回收保障：正常结束由测试关闭容器，spawn 超时保留本轮 Testcontainers 容器清理兜底，其他异常退出需检查本轮残留。两次试验均无残留容器，详见 [试验记录](2026-09-19--next-backlog.md)。

实测（Vite + React + Vitest）：M 档一个需求 40 分钟左右，S 档 8 分钟；review 一轮 2～5 分钟，check 2～4 分钟。

## 硬规则（对 AI 的约束，真相源在 skills / prompts / spawn）

审查验收覆盖是硬规则：源码改动没有新增或修改测试直接 BLOCKING，S 档同样需要回归测试；仅 plan.md 对相应 AC 明确写“替代验证”并说明理由才可免测。spawn 会把缺测试提示追加到审查提示词。

Codex 的对话输出纪律与待确认卡、需要处理卡同步注入 AGENTS.md；节点卡标题仅限 INIT / PLAN / CODE / REVIEW / CHECK / SHIP，每个节点完成时只输出一张，复审通过必须输出 `✔ REVIEW` 卡。中途进度仅允许 `· AC-n ✔ <测试名>` 单行，不得制作进度、准备、收尾卡或自造标题；卡片外仅允许该进度单行及规定的未初始化备注，模板源仍保留在 skills 中。

## 设计与验证记录

设计文档：`2026-09-15--v1-redesign.md`、`2026-09-16--flow-and-independent-review.md`；审查记录：`2026-09-15--v1-review.md`；验收记录：`2026-09-16--demo-results.md`。
