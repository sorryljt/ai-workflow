# 下一版待办（2026-09-19）

来源：[2026-09-18 修复后回归](2026-09-18--regression-0564e95.md)（P15、P20、P21 及后续 Codex 回归的验证范围）。P15、P20、P21 已在 1.1.2 完成；Codex socket 两组试验已完成，完整验收仍未通过，详见第 4 条。

1. **P15：派单前主动检测工作区信任。** **已在 1.1.2 完成。** 原因：现有检测依赖 Claude Code 忽略 allow 规则时的警告，没有 allow 规则的未信任项目不会触发该警告。建议：在 Claude 子进程派单前读取 `~/.claude.json` 的 `projects[<pwd>].hasTrustDialogAccepted`，以项目实际路径匹配，并覆盖已信任、未信任及配置缺失的情况。
2. **P20：预检补全 `dev`。** **已在 1.1.2 完成。** 原因：README 已提供启动命令，未初始化预检仍漏列 `dev`，不符合“可推导的键列全”的要求。建议：将 `dev` 纳入固定探测清单，从 README 或构建配置提取启动命令并写入本轮运行配置，标明它是启动入口，预检时不启动服务。
3. **P21：init 重复执行只对探测字段提差异。** **已在 1.1.2 完成。** 原因：重复 init 曾把用户维护的禁区纳入差异并缩小范围，约定与禁区不应随自动探测变化。建议：限定差异为“项目信息”中的可探测字段，确认后更新，约定和禁区逐字保留，并增加“不修改约定和禁区”的校验断言。
4. **验证 Codex 沙箱对 colima Docker socket 的放行方式。** **两组试验已在 1.1.2 完成，完整验收问题保留。** 原因：后续 Codex 回归中单元测试通过，但完整 `verify` 因 Testcontainers 无法发现 Docker socket 失败，集成测试仍受沙箱限制。建议：保留 `workspace-write`，尝试通过 `-c sandbox_workspace_write.writable_roots` 加入实际 socket 路径（通常为 `~/.colima/default/docker.sock`，传参时展开为绝对路径），验证 socket 连接及完整 `./mvnw -q verify`；原建议未预先认定有效，现有实测结果如下。

   **2026-09-19 实测（Codex CLI 0.155.0，springboot-demo）：完整验收仍未通过。**

   工作目录：`/Users/dawson/personWorkSpace/springboot-demo`。宿主机先执行 `docker ps`，退出 0、无运行中容器。两组均保留现有 JVM 配置 `--sandbox workspace-write -c sandbox_workspace_write.network_access=true`；未提权，未修改 demo 源码 / 配置，未提交 demo，只产生 Maven `target/` 测试产物。子进程依次执行 `docker ps` 和 `./mvnw -q -pl app -am verify`。

   ```bash
   # a) 加入 colima 目录，TOML 数组作为单个参数传入
   codex exec --ephemeral --sandbox workspace-write \
     -c sandbox_workspace_write.network_access=true \
     -c 'sandbox_workspace_write.writable_roots=["/Users/dawson/.colima/default"]' \
     '<执行上述两条命令并报告退出码，不改文件、不提权>'

   # b) 同样参数，再显式传入 DOCKER_HOST
   DOCKER_HOST=unix:///Users/dawson/.colima/default/docker.sock \
   codex exec --ephemeral --sandbox workspace-write \
     -c sandbox_workspace_write.network_access=true \
     -c 'sandbox_workspace_write.writable_roots=["/Users/dawson/.colima/default"]' \
     '<确认 DOCKER_HOST，执行上述两条命令并报告退出码，不改文件、不提权>'
   ```

   | 配置 | docker ps | Maven verify | 本轮测试报告 |
   | --- | --- | --- | --- |
   | a：writable_roots | 退出 0 | 退出 1 | 单元测试 27 个通过（core 16 + app 11），OrderApiIT 初始化错误 1 个 |
   | b：再加 DOCKER_HOST | 退出 0 | 退出 1 | 单元测试 27 个通过（core 16 + app 11），OrderApiIT 初始化错误 1 个 |

   a 的关键报错：`Could not find a valid Docker environment`；`UnixSocketClientProviderStrategy` 报 `NoSuchFileException (/var/run/docker.sock)`，DockerDesktop 策略报 `NullPointerException`。

   b 确认子进程继承 `DOCKER_HOST=unix:///Users/dawson/.colima/default/docker.sock`。关键报错：`Container startup failed for image testcontainers/ryuk:0.12.0`；Docker 返回 `Status 500`，`error while creating mount source path '/Users/dawson/.colima/default/docker.sock': mkdir /Users/dawson/.colima/default/docker.sock: operation not supported`。

   结论：两组配置下子进程均能执行 `docker ps`；b 已能连接 Docker，但卡在 Ryuk socket 挂载。不能再把本轮失败简单归因于沙箱拒绝连接，也不能把这两组配置认定为完整验收可行方案。保留 CHANGELOG 的 Codex / colima 已知问题；README 和 init 不写入未经通过验证的配置。后续仍需解决 Testcontainers / colima 的容器内 socket 路径问题。
