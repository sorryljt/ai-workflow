# 交接 2：补测三项（在 HANDOFF.md 那轮的基础上继续）

前置：先读 `~/personWorkSpace/fe-ai-workflow/docs/2026-09-18--backend-validation.md` 和 `viktor-validation/run.sh`，沿用同样的方式（无头 `claude -p`、日志写 `logs/`、每个场景前后记 `git status`）。fe-ai-workflow 仍然不改（结果文档除外），不 push。原则同上：能自己做的都自己做，只在需要用户动手时停下。

## 0. 收尾上一轮

1. 在 fe-ai-workflow 里单独提交结果文档：`git add docs/2026-09-18--backend-validation.md && git commit -m "docs: 后端验证结果（2076810）"`。
2. 如果用户已经把 localhost 加进系统代理例外（问一句就行，不用等），把 run.sh 里的 `JAVA_TOOL_OPTIONS` 去掉后重跑一次 `./mvnw -pl app -am verify` 确认仍然通过；没加就保留。

## 1. 补测 4.6：超时清理路径（合成场景，不依赖 Testcontainers）

目的：验证 spawn 的 `cleanup_resources` 真的会按 `.check.resources` 清理容器和进程。

做法：在 springboot-demo 的 M 档需求目录上，把 plan 退回 `stage: review`、`stage_result: ok`，然后用 `--checks` 传一份**临时运行配置**，让 check 子进程必然创建可登记的资源，例如把 `verify` 写成：
`verify: docker run -d --name viktor-$VIKTOR_RUN_ID-pg -e POSTGRES_PASSWORD=x postgres:16-alpine && sleep 600`
（子进程拿到的提示词里 run_id 是明文，`VIKTOR_RUN_ID` 也在环境变量里；两种写法都试，看它会不会按提示词要求"创建即登记"到 `.check.resources`。）
`VIKTOR_SPAWN_TIMEOUT=90` 直接调 `bash .workflow/fe-ai-workflow/scripts/viktor-spawn.sh check <目录> --agent claude --checks <临时文件>`，不经过主会话。
期望：退出码 2；`.check.resources` 里至少一行 `container:viktor-<run_id>-pg`；超时后 `docker ps -a` 没有这个容器；`ps` 里没有残留 `sleep 600`。
如果子进程 90 秒内没登记资源，加到 180 秒再试一次；仍然没有，就记"子进程不遵守创建即登记"，这是提示词问题，不算清理逻辑的问题——但要再用手工写入 `.check.resources` 的方式（先起一个名字含 run_id 的容器并写进文件，再让它超时）单独证明清理逻辑本身能工作。

## 2. 补测 4.3：manual 结果在交付报告里单列

上一轮 4.3 是单独跑 /viktor-check，没进 ship。这次让它走完：plan 保留 AC-9（非关键人工项），退回 `stage: review`、`stage_result: ok`，跑 `/viktor-flow`（无参数续接）。
期望：check `manual`、`pending: [AC-9]`；随后自动 ship；report.md 里"待人工"**只有** AC-9，review 的 SUGGESTED 不混进来（这正是 P4 要验的边界）；交付卡不把它表述为全部验证完成。做完把 plan 还原并提交。

## 3. 补测 4.5：真正未初始化状态下的权限

上一轮 noinit 的 settings.json 里还留着 init 写入的放行规则。这次在 `springboot-demo-noinit` 里把 `permissions.allow` 中 `./mvnw` 相关的规则删掉（只保留 install.sh 写入的 hook），提交，再跑一个 S 档需求（例如"discountRate 允许精确到 4 位小数"）。
期望之一（记录实际是哪种）：
- 子进程被权限拦住 → review 报 `error`、退出码 2，主会话输出需要处理卡并提示运行 /viktor-init 补齐权限，**不自行改 settings.json**；或
- 子进程能跑（说明 `--checks` 传入的命令被某种方式放行了）→ 记录是怎么放行的。
无论哪种，AGENTS.md 和 settings.json 的 sha 前后必须一致。

## 4. 交付

结果追加到 `docs/2026-09-18--backend-validation.md` 末尾新增一节 `## 补测（第二轮）`，同样的表格格式；更新"结论速览"里对应的行；有新问题继续编号 P10…。提交为一个 docs commit，不 push。最后告诉用户每项的结论。
