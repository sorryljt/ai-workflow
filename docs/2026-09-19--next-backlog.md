# 下一版待办（2026-09-19）

来源：[2026-09-18 修复后回归](2026-09-18--regression-0564e95.md)（P15、P20、P21 及后续 Codex 回归的验证范围）。以下均为待办，尚未实施或验证。

1. **P15：派单前主动检测工作区信任。** 原因：现有检测依赖 Claude Code 忽略 allow 规则时的警告，没有 allow 规则的未信任项目不会触发该警告。建议：在 Claude 子进程派单前读取 `~/.claude.json` 的 `projects[<pwd>].hasTrustDialogAccepted`，以项目实际路径匹配，并覆盖已信任、未信任及配置缺失的情况。
2. **P20：预检补全 `dev`。** 原因：README 已提供启动命令，未初始化预检仍漏列 `dev`，不符合“可推导的键列全”的要求。建议：将 `dev` 纳入固定探测清单，从 README 或构建配置提取启动命令并写入本轮运行配置，标明它是启动入口，预检时不启动服务。
3. **P21：init 重复执行只对探测字段提差异。** 原因：重复 init 曾把用户维护的禁区纳入差异并缩小范围，约定与禁区不应随自动探测变化。建议：限定差异为“项目信息”中的可探测字段及对应 permissions 补齐，确认后更新，约定和禁区逐字保留，并增加重复执行前后不变的回归检查。
4. **验证 Codex 沙箱对 colima Docker socket 的放行方式。** 原因：后续 Codex 回归中单元测试通过，但完整 `verify` 因 Testcontainers 无法发现 Docker socket 失败，集成测试仍受沙箱限制。建议：保留 `workspace-write`，尝试通过 `-c sandbox_workspace_write.writable_roots` 加入实际 socket 路径（通常为 `~/.colima/default/docker.sock`，传参时展开为绝对路径），验证 socket 连接及完整 `./mvnw -q verify`；此方案尚未验证，不预先认定有效。
