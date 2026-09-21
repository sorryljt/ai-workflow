# fe-ai-workflow 仓库（元仓库）

这是工作流本身的仓库，不是业务项目。`skills/viktor-*/SKILL.md` 是唯一真相源，`templates/AGENTS.snippet.md` 是注入业务项目的入口段，`hooks/` 是 Stop hook 门禁。

修改工作流时：
- 改 SKILL.md 或 snippet 后运行 `bash scripts/validate.sh`；改 `scripts/` 或 `hooks/` 后运行 `bash scripts/install.test.sh`。
- 节点语义变化时同步更新 `templates/AGENTS.snippet.md` 和 README。
- 分支：在各自分支开发，合到 main 前四套测试与 validate 必须通过。

## 发布（每次合到 main 的功能改动都要走完）

业务项目通过 `bootstrap.sh` 安装，**只认 `vX.Y.Z` 形式的 tag**，不认 main。合到 main 但没打 tag 的改动，团队里没有任何人装得到，等于没发。所以合并不是终点，打 tag 才是：

1. CHANGELOG：把 `[Unreleased]` 改成 `[X.Y.Z] - 日期`（需要用户重跑 /viktor-init 的改动要在条目里写明）。
2. README 接入一节里的示例版本号改成新版本。
3. `bash scripts/validate.sh` 通过（它会检查 CHANGELOG 最新版本是否已有对应 tag）。
4. `git commit -m "chore(release): vX.Y.Z"` → `git tag vX.Y.Z` → `git push && git push --tags`。

版本号：改 SKILL.md / prompts / hooks 语义或要求重跑 init 的升 minor；只修脚本、文案、测试的升 patch。预发布用 `vX.Y.Z-rc.N`，bootstrap 默认不会装到它，只能显式指定。
