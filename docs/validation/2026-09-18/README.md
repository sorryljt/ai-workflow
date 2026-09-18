# 2026-09-18 验证资料归档

- `run.sh`：第一轮分阶段驱动脚本（含第二轮环境调整）；`run2-*.sh`：第二轮补测脚本。
- `HANDOFF.md`、`HANDOFF-2.md`、`HANDOFF-3.md`：三轮任务与交接说明，仅作为历史记录。
- `backup/`：原始备份整体保留，包含配置、场景产物和第一轮脚本。
- `logs/`：保留最终回复（`*.final.txt`）、标准错误（`*.stderr`）、`git-status.log`、`driver.log`，以及各场景 plan/check/review/report 等 Markdown 副本；不保留 JSONL、Maven 日志和其他临时日志。

## 三轮结果

1. 第一轮：[后端验证结果](../../2026-09-18--backend-validation.md)。
2. 第二轮：同一份[后端验证结果](../../2026-09-18--backend-validation.md)中的“补测（第二轮）”。
3. 第三轮：[0564e95 修复后回归](../../2026-09-18--regression-0564e95.md)。

历史文档中的 `~/personWorkSpace/viktor-validation/` 路径对应本目录；未纳入归档的临时文件已删除。

## 下次回归复用

先复制 `run.sh` 和需要的 `run2-*.sh` 到新的临时验证目录，保留本归档不变。按目标版本调整脚本中的 `WS`、`WF`、`WF_SHA`、`DEMO`、`NOINIT`、`TODO`、`V`（日志与备份会写到 `V/logs` 和 `V/backup`）；`WF_SHA` 必须匹配待测工作流 HEAD 的短哈希。

先通读对应 HANDOFF 与脚本，准备独立的测试仓库及 F5 起点分支，安装 Git、Claude Code、Codex、Python、JDK 和 Docker/colima，并检查登录和 Docker 镜像。原脚本会修改及提交 demo、重建测试分支并启停 Docker，不要直接对保留基线运行 `all`。

从新临时目录执行 `bash run.sh a`（接入/init/S/M）、`bash run.sh b`（定向场景）、`bash run.sh c`（前端 F5）、`bash run.sh d`（Codex），按需要逐阶段运行；`bash run.sh all` 顺序执行四阶段。第二轮补测参考 `HANDOFF-2.md` 和 `run2-*.sh`。每轮开始和结束核对 git status，结果另写新日期文档，不 push。
