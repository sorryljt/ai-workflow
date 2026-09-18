---
name: viktor-init
description: 首次接入 viktor 工作流时初始化项目：探测技术栈和检查命令，把项目信息写入 AGENTS.md，并创建 docs/knowledge/。用户输入 /viktor-init 或提到 viktor-init、首次接入工作流，或者其他节点发现 AGENTS.md 缺少 viktor-checks 块时使用。可以重复执行。
---

# viktor-init：项目初始化

用中文回复（节点卡、需要处理卡和其他说明都用中文）。

目标是给 Agent 提供它从代码里不容易得到、却每次都需要的信息：检查命令、主干分支、非显而易见的约定、禁区。

## 步骤

1. **探测**：语言、框架、构建工具（包管理器 / wrapper）、测试框架，以及 dev / build / lint / typecheck / test 对应的命令。多模块工程注明命令在哪个目录执行、是否需要先构建依赖模块。
2. **验证命令**（不安装依赖、不起服务、不改项目配置）：把探测出的每条命令跑一遍，只有这样判定"已验证"：
   - test：看执行数 / 跳过数 / 目标模块。0 个测试执行、全部跳过或只跑了无关模块，算未验证。
   - typecheck / lint：看退出码，并确认它真的覆盖了源码目录。
   - e2e / dev：不跑，标"未验证"。
   验证不了（缺依赖、需要环境、超时）的写"未验证：<原因>"，不删这条命令，也不换成能跑通的替代命令。
3. **补齐测试能力**：没有测试框架时，推荐一个与技术栈匹配的方案并说明理由，用户同意后再安装。
4. **询问**（一次性提出）：探测不到的约定和禁区，例如生成代码的目录、禁止修改的文件、提交规范、主干分支名。
5. **写入 AGENTS.md**：在 `<!-- fe-ai-workflow-end -->` 标记之后写入或更新“项目信息”节。这一节在标记之外，重新安装工作流时不会被覆盖。

   ````markdown
   ## 项目信息（viktor-init）
   - 技术栈：<语言 / 框架 / 测试框架>
   - 构建工具：<pnpm / npm / mvn / gradle …>
   - 主干分支：main
   - 命令验证：test 已验证（xx 个执行）；typecheck 已验证；verify 未验证：<原因>

   ```viktor-checks
   typecheck: pnpm tsc --noEmit
   lint: pnpm eslint .
   test: pnpm vitest run
   verify: mvn -pl app verify
   e2e: pnpm playwright test
   dev: pnpm dev
   ```

   ### 运行前提
   - <需要什么外部环境，例如本地数据库、容器运行时，以及怎么判断就绪；没有就写"无"。不写密钥>

   ### 约定（只写不明显的）
   - …

   ### 禁区
   - …（不要写 ".claude/ 由安装脚本维护"：settings.json 的 permissions 由本节点维护，用户也可以手工改）
   ````

   `viktor-checks` 块的规则（Stop hook 会直接执行它）：
   - 每行 `key: 命令`，命令必须单行、非交互、非 watch 模式（例如用 `vitest run` 而不是 `vitest`）。
   - 项目没有的检查直接省略该行，不写占位符。
   - monorepo：AGENTS.md 放在哪个目录，命令就在哪个目录执行；会话从子包启动时优先读子包的 AGENTS.md。
   - 键按用途分：`typecheck` / `lint` / `test` 是快速检查（几分钟内跑完，hook 和 code 完成时执行）；`verify` 是完整验收入口（慢、可能需要环境，只有 check 执行，可选）；`e2e` 供 check 使用；`dev` 是启动入口，不是要等它退出的检查。项目只有一套慢测试时，想办法找出快速子集放进 `test`（例如按模块或按标签），找不到就把慢的放 `verify`、`test` 留空并注明。
   - 所有命令都以 AGENTS.md 所在目录为工作目录（hook、code、子进程一致）；子模块写进命令本身（`mvn -pl server test` 或 `cd server && npm test`），不另设执行目录。
   - `### 运行前提` 节紧跟在块后面：外部环境与就绪条件；spawn 会把块和这一节一起交给子进程。
   - 标了"未验证"的命令照写，viktor-check 首次执行时以当轮结果判定。
   - 探测到 Maven / Gradle（JVM 项目）时，在项目信息节写一行 `- 子进程参数：codex --sandbox workspace-write -c sandbox_workspace_write.network_access=true`：Codex 默认沙箱（`workspace-write`）不放网络，Mockito 等的 JVM self-attach 会失败，测试跑不起来。这一行会放开 Codex 下 review / check 子进程的外网访问，节点卡上用"子进程"一行注明（见节点卡）。其他项目不写这一行。spawn 只从这一行读取 Codex 子进程参数，只允许字母数字、空格、单双引号和 `_ . = : / , @ + -`（引号用于保留 TOML 字符串，禁止 shell 展开或运算符）；`danger-full-access`、`--dangerously-*` 会被拒绝，不要写。
   - **Codex + JVM + Docker**：在上述“子进程参数”同一行一并写入 Docker 环境。先探测实际 Docker endpoint（例如 `docker context inspect`），必须用已确认的 socket 绝对路径，不原样复制示例用户名，也不在参数中留下 `$HOME` / `~`。colima 时增加 `--add-dir <socket 所在目录绝对路径>`；再加 `-c 'shell_environment_policy.set.DOCKER_HOST="unix://<socket 绝对路径>"' -c 'shell_environment_policy.set.TESTCONTAINERS_RYUK_DISABLED="true"'`，保留 `--sandbox workspace-write -c sandbox_workspace_write.network_access=true`。环境变量通过 Codex 的 `shell_environment_policy.set` 注入，值必须是字符串，保留内层双引号与外层单引号。目录有空格时也用分组引号；路径含 spawn 不支持的字符时注明未验证，不伪造路径。
   - 该组合已在 colima 上通过完整 verify；`TESTCONTAINERS_HOST_OVERRIDE=127.0.0.1` 叠加后也通过，但不是本机必要条件，不默认写入。其他 Docker endpoint 先按项目实际环境验证，不把 colima 路径套用到其他运行时。运行前提注明禁用 Ryuk：正常结束由测试关闭容器，spawn 超时有本轮容器清理兜底，其他异常退出检查本轮残留；节点卡“子进程”行同时注明“Docker / Ryuk 禁用”。
6. **放行检查命令**：review / check 在独立进程（`claude -p` / `codex exec`）中运行，不继承当前会话的授权。按下面的固定清单写进 `.claude/settings.json` 的 `permissions.allow`，不增不减：
   - `viktor-checks` 里除 `dev` 外的每条命令，原样一条，形如 `Bash(npm test)`、`Bash(./mvnw -q verify)`；
   - 该构建工具 / 测试框架的通配一条，形如 `Bash(./mvnw:*)`、`Bash(npx vitest run:*)`；
   - `Bash(bash <workflow-dir>/scripts/knowledge.sh:*)`，`<workflow-dir>` 写**相对项目根目录的路径**（通常是 `.workflow/fe-ai-workflow`，不写绝对路径；spawn 交给子进程的提示词用的也是这个相对路径）。review / check 的提示词都要求执行 lookup；
   - `dev` 也放行一条（check 只在 AC 明确需要运行中的服务时才后台启动它，并登记 pid）；
   - 运行前提提到 Docker / 容器运行时的：`Bash(docker ps:*)`、`Bash(docker rm:*)`、`Bash(docker run:*)`、`Bash(docker stop:*)`。
   已有的规则保留，不重复添加。`install.sh` / `upgrade.sh` 合并 settings.json 时只替换 viktor-gate 的 hook 条目，`permissions` 原样保留。放行规则只在**已信任的工作区**生效：接入后必须在项目目录交互式打开一次 Claude Code 并选择信任，上级目录的信任不传递到独立 git 仓库；当前会话不是在项目目录交互式启动的，就在节点卡后提醒用户这一步。
7. **确保有基线 commit**：`git rev-parse HEAD` 失败（仓库还没有任何提交）时，提示用户先提交一次，否则独立审查拿不到 diff。
8. **创建知识目录**：运行 `bash <workflow-dir>/scripts/knowledge.sh rebuild` 生成 `docs/knowledge/index.md`（目录不存在会创建）。若发现旧格式的 `docs/knowledge/decisions.md` / `pitfalls.md` / `glossary.md`，先运行 `knowledge.sh migrate` 拆成条目文件。

## 节点卡（完成后只输出这个）

```
━━ ✔ INIT ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
技术栈    <框架 / 测试框架 / 包管理器>
检查命令  typecheck ✅ lint ✅ test ✅ verify 未验证 e2e — dev ✅
放行      <n> 条
子进程    codex 放开网络（JVM 测试需要）
产物      AGENTS.md 项目信息 · docs/knowledge/ · .claude/settings.json
下一步    /viktor-flow <需求>
```

"子进程"一行只在写了 `- 子进程参数` 时出现，否则省略。"检查命令"一行每个键后只允许 `✅`（已验证）、`—`（项目没有）、`未验证` 三种标记，不加括号说明；原因写在 AGENTS.md 的"命令验证"行里。

## 重复执行

已有“项目信息”节时，只对该节里探测得到的字段（技术栈、构建工具、主干分支、命令验证、`viktor-checks` 块、运行前提、子进程参数）提出与探测结果的差异，用户确认后再更新。“约定”和“禁区”是用户内容，无论位于何处，一律不提差异、不修改约定和禁区，逐字保留；不修改用户在其他位置写的内容。
