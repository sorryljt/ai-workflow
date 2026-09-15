# fe-ai-workflow 仓库（元仓库）

这是工作流本身的仓库，不是业务项目。`skills/viktor-*/SKILL.md` 是唯一真相源，`templates/AGENTS.snippet.md` 是注入业务项目的入口段，`hooks/` 是 Stop hook 门禁。

修改工作流时：
- 改 SKILL.md 或 snippet 后运行 `bash scripts/validate.sh`；改 `scripts/` 或 `hooks/` 后运行 `bash scripts/install.test.sh`。
- 节点语义变化时同步更新 `templates/AGENTS.snippet.md` 和 README。
- 发布：更新 CHANGELOG 与 README 中的版本号 → commit → 打 tag。
