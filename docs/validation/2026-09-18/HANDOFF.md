# 交接：fe-ai-workflow 后端验证（由本地 Claude Code 接手执行）

你在 `~/personWorkSpace` 下工作，以完全自主的方式完成本文件描述的验证。原则：能自己做的全部自己做，只有需要用户本人动手的地方才停下来说清楚要做什么；不要问确认性问题；不要 push 任何仓库；提交一律用当前 git 身份。

## 一、现状（前一个会话已完成的部分）

- `~/personWorkSpace/fe-ai-workflow` HEAD 应为 `2076810`（未 push）。这是被验证对象，**不要改它**（结果文档除外）。
- `~/personWorkSpace/springboot-demo` 已建好：Maven 多模块（core 纯逻辑 + app Spring Boot），`./mvnw test` 只跑单测（surefire，5 个），`./mvnw verify` 再跑 Testcontainers 集成测试（failsafe，`OrderApiIT`，2 个）。基线已提交；工作区里有一处未提交改动：`pom.xml` 把 `testcontainers.version` 升到 1.21.4（兼容 colima / Docker 29 的 API 版本要求），先把它提交掉：`git commit -am "chore: Testcontainers 升到 1.21.4 以兼容 colima / Docker 29"`。
- `~/personWorkSpace/viktor-validation/run.sh` 是驱动脚本，分四个阶段 `a / b / c / d`，用无头 `claude -p ... --dangerously-skip-permissions --output-format stream-json` 跑真实会话，日志在 `viktor-validation/logs/`。**先通读 run.sh**，理解每个阶段做什么；你可以按需修改它（它不是被验证对象）。
- 本机环境：JDK 17（Temurin）、Docker 走 colima（socket 在 `~/.colima/default/docker.sock`，run.sh 已自动设置 `DOCKER_HOST` / `TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE`）、claude 2.1.x、codex-cli 0.155（未登录，阶段 d 才需要）。
- **当前卡点**：colima 虚拟机里拉不到镜像，`docker pull postgres:16-alpine` 报 `lookup registry-1.docker.io on [::1]:53: connection refused`，`colima start --dns 223.5.5.5` 也没用。先修这个：查 `colima ssh -- cat /etc/resolv.conf`、`colima ssh -- cat /etc/docker/daemon.json`、`~/.colima/default/colima.yaml`，把 DNS 修好；若 Docker Hub 本身不通，在 `colima.yaml` 的 `docker:` 段配 `registry-mirrors`（如 `https://docker.m.daocloud.io`、`https://docker.1ms.run`）后 `colima restart`。目标：`docker pull postgres:16-alpine` 成功，然后在 springboot-demo 里 `./mvnw -pl app -am verify` 看到 `OrderApiIT` `Tests run: 2, Failures: 0, Errors: 0`。
- 前一个会话因为没有删除权限，把 git 锁文件挪到了 `~/personWorkSpace/_to_delete/`，可以直接 `rm -rf` 掉。

## 二、原始任务说明（逐条执行，判定标准以此为准）

### 背景

- 工作流仓库：`~/personWorkSpace/fe-ai-workflow`，HEAD `2076810`。它原本只服务前端，这轮改造让它同时支持后端（Java 为主）仓库，前后端各自独立仓库、各自使用。
- 规格：`docs/2026-09-18--fullstack-and-evidence.md`（9 节，第 9 节是验证场景清单）。三轮 Codex 评审报告在 `docs/reviews/`，脚本层面的问题已全部关闭。
- 现在缺的是真实模型下的验证。以下四条完全靠提示词约束，脚本证明不了：init 的命令验证协议、plan/check 的关键 AC 判定与降级理由、check 的 blocked 不改代码、未初始化项目的预检。
- 前端回归基线：`~/personWorkSpace/todolist-demo`（Vue/React，已接入工作流 v1.0.1，跑过 F1/F2/F4/F5/F8，结果在 `docs/changes/`）。

先读：工作流仓库的 README.md、规格文档、`skills/viktor-{init,plan,code,review,check,flow}/SKILL.md`、`prompts/{review,check}.md`。读完再动手。

### 第一步：Spring Boot 多模块 demo（已建好，按上文补验 verify 后接入）

按工作流 README 的"接入"一节接入：submodule 指向本地路径 `~/personWorkSpace/fe-ai-workflow`（不是 GitHub，因为改动未 push），checkout `2076810`，执行 install.sh，提交。run.sh 阶段 a 已包含这一步。

### 第二步：init 验证协议

在 springboot-demo 里运行 `/viktor-init`。核对 AGENTS.md：

- `viktor-checks` 块：`test` 是快速子集、`verify` 是含 Testcontainers 的完整验收、没有 `dev` 或 `dev` 是启动入口。命令都能从仓库根目录直接执行，子模块写在命令里（`-pl app` 之类）。
- "命令验证"行：test 写了执行数；verify 允许写"未验证：原因"；不许把跑不通的命令换成能跑通的替代命令。
- `### 运行前提` 节写了 Docker / Postgres，没有"执行目录"字段，没有密钥。
- `.claude/settings.json` 的 `permissions.allow` 放行了这些命令。

不符合就记下来，不要自己改 AGENTS.md，这是要评估的对象。

### 第三步：S 档一次、M 档一次

1. S 档：`/viktor-flow` 喂一个纯 core 模块的小改动（run.sh 用的是"舍入规则从 DOWN 改为 HALF_UP"）。看 plan.md 是否自动创建且正文有 `## 验收标准` 节；review、check 是否自动跑完；check.md 的表格是否有"关键"列。
2. M 档：`/viktor-flow` 喂"订单创建接口增加幂等键：同一幂等键重复提交返回首次结果，不重复落库"。看：
   - plan 待确认卡里，涉及落库和幂等的 AC 是否默认关键并写了"证据："；是否有 AC 被标非关键且附了理由。确认计划后让它跑完。
   - review.md 是否出现了按 diff 触发的后端附加项（幂等、数据兼容）。
   - check.md：关键 AC 是否用真实库（Testcontainers）验证，而不是 mock；`result` 五态取值是否正确。

### 第四步：定向场景（在 M 档需求上做；run.sh 阶段 b 已编好，Docker 启停用 colima stop/start）

1. **关键 AC 缺库 → blocked、不改代码**：停掉 Docker，把 plan.md 的 `stage` 改回 `review`、`stage_result: ok`（模拟 check 未跑），运行 `/viktor-check`。期望：退出码 4、`result: blocked`、`pending` 列出缺证据的关键 AC、工作区代码零改动（`git status` 只有 docs/changes 变化）、需要处理卡说明缺什么环境。
2. **环境恢复后先 review 再 check**：Docker 开回来后运行 `/viktor-flow` 续接。期望：先核对代码指纹，指纹没变就直接重跑 check（不重跑 review），通过后 `verified.inputs` 写入。然后手改一条 AC 的证据要求，再续接，期望只重跑 check。
3. **非关键人工项 → manual**：在 plan 里加一条明确标非关键且只能人工验证的 AC（例如日志格式），跑 check。期望 `result: manual`、`pending` 里列出它、报告"待人工"单列、退出码 0。
4. **测试全部跳过不得通过**：临时给 app 模块的集成测试加 `@Disabled`，跑 check。期望不 pass（blocked 或 failed 均可，但不能 pass）。做完还原。
5. **未初始化预检**：复制 springboot-demo 为 `springboot-demo-noinit`，删掉 AGENTS.md 里 viktor-init 写的"项目信息"节，跑一个 S 档需求。期望：plan.md 出现 `## 本轮运行配置`（命令 + 来源 + 环境前提），卡片备注"未初始化"，review/check 派单用 `--checks` 传入（看 `.check.prompt.md` 里有命令），不写 AGENTS.md、不改 settings.json。
6. **超时清理**：把 `VIKTOR_SPAWN_TIMEOUT=30` 传给一次 check（环境变量），期望超时后退出 2、`.check.resources` 里登记的容器/进程被清掉、无残留 `docker ps`。30 秒内子进程可能来不及登记资源，那样标"未触发"，不算通过。

### 第五步：前端回归（run.sh 阶段 c）

在 todolist-demo 里把 submodule 更新到 `2076810`，重新 install，用 `/viktor-flow` 重跑 F5 搜索过滤（先 `git checkout` 回 F5 之前的提交 `f129c8c` 建分支 `f5-rerun`）。对比新旧 `docs/changes/*search-filter*/` 下的 plan/review/check：卡片文案和节点行为应与 v1.0.1 一致，check.md 多一列"关键"且全部为"否"，review.md 不出现后端附加项。有差异逐条列出。

### 第六步：Codex 端（run.sh 阶段 d）

同样的 springboot-demo，在 Codex 里跑一遍 S 档（`codex exec`，`$viktor-flow …`）。核对 spawn 派的是 `codex exec` 不是 claude，其余产物与 Claude 端结构一致。codex 未登录时停下来让用户登录（`codex login`），登录后继续。

### 交付

结果写到 `~/personWorkSpace/fe-ai-workflow/docs/2026-09-18--backend-validation.md`：每个场景一行——期望、实际、通过/不通过、证据文件路径（日志在 `viktor-validation/logs/`，产物在各仓库 `docs/changes/`）。不通过的场景附你判断的原因（是提示词约束不够、还是脚本问题），但不要顺手改工作流仓库；改动留给下一轮。最后列出需要用户决定的事项（例如是否发 v1.1.0、是否 push、是否提交结果文档）。

### 注意

- 判档不要解释理由，卡片格式按 SKILL.md，不要自己发明。
- 提交用当前 git 身份；不要 push 任何仓库。
- 每个场景开始前 `git status` 确认工作区干净或只有预期的脏文件，结束后记录 `git status` 结果作为"不改代码"的证据（run.sh 会写到 `logs/git-status.log`）。
- 主会话免审批（`--dangerously-skip-permissions`），但 review / check 子进程仍走 spawn 默认的 `acceptEdits` + init 写入的放行规则，权限这一项照常验。
- 阶段 b 的 4.2 后半段：续接通过 check 后会自动 ship，所以 run.sh 先把 plan 状态退回"check 完成、未 ship"再改证据要求续接，这属于对场景的改编，结果文档里注明。
