---
run_id: 20260918234953-60584
result: pass
pending: []
checked: 2026-09-18
---

# Check：Codex 1.1.1 S 档复测：负单价错误文案

| AC | 关键 | 验证方式 | 证据 | 结果 |
|----|------|---------|------|------|
| AC-1：负单价抛出 IllegalArgumentException，文案精确为“unitPrice 不能为负数”；零单价和正单价计算仍正确 | 是（金额计算） | 本轮 verify 实际执行的纯计算单元测试 | OrderAmountCalculatorTest 共 16 项通过，0 失败、0 错误、0 跳过；其中 rejectsNegativeUnitPriceWithExactMessage、acceptsZeroUnitPrice、multipliesPriceByQuantity 三项直接覆盖 AC | ✅ |

## 可复现证据

在项目根目录原样执行 `./mvnw -q verify`。本轮该命令执行了单元测试，再在集成测试环境初始化时报错，退出码为 1；不宣称完整 verify 通过。

直接覆盖 AC 的断言位于 `core/src/test/java/com/example/demo/core/OrderAmountCalculatorTest.java`：

1. 单价 -0.01、-10.00，数量 1、折扣 1：分别断言 IllegalArgumentException 及完整错误文案“unitPrice 不能为负数”。
2. 单价 0、数量 3、折扣 1：断言结果为 0.00。
3. 单价 10.00、数量 3、折扣 1：断言结果为 30.00。

本轮报告 `core/target/surefire-reports/TEST-com.example.demo.core.OrderAmountCalculatorTest.xml` 中上述三个 testcase 均无 failure/error/skipped；对应文本报告原始统计：

```text
Tests run: 16, Failures: 0, Errors: 0, Skipped: 0, Time elapsed: 0.021 s -- in com.example.demo.core.OrderAmountCalculatorTest
```

app 单元测试另有 11 项通过（WebMvc 8、Service 3）；本轮单元测试总计 27 项通过。AC 仅要求 core 计算规则和异常文案，不涉及数据库行为；已执行单元测试为充分证据，因此集成环境缺失不造成此 AC 证据缺口。

## 能力与环境

1. 工具清单提供 mcp__cua_repl 浏览器控制入口；本 AC 无可见交互，不启动浏览器。
2. 本 AC 不需要运行中的服务，未探测端口或启动 dev，未连接本地 Postgres。
3. `docker ps` 探测退出 0，仅输出表头，无运行中容器；但测试框架实际无法发现 Docker socket。未重试、未切换连接方案。
4. `bash .workflow/fe-ai-workflow/scripts/knowledge.sh lookup unitPrice` 返回“（无相关知识）”。

## 失败详情

未观察到 AC 行为错误。完整 verify 的集成环境错误如下（原始输出节选）：

```text
UnixSocketClientProviderStrategy: failed with exception InvalidConfigurationException (Could not find unix domain socket). Root cause NoSuchFileException (/var/run/docker.sock)
DockerDesktopClientProviderStrategy: failed with exception NullPointerException (Cannot invoke "java.nio.file.Path.toString()" because the return value of "org.testcontainers.dockerclient.DockerDesktopClientProviderStrategy.getSocketPath()" is null)As no valid configuration was found, execution cannot continue.
[ERROR]   OrderApiIT » IllegalState Could not find a valid Docker environment. Please see logs and check configuration
[ERROR] Tests run: 1, Failures: 0, Errors: 1, Skipped: 0
```

详细报告：`app/target/failsafe-reports/com.example.demo.app.order.OrderApiIT.txt`。这是测试环境初始化错误，命令本身已执行且本 AC 用例已完成，并非命令不存在、被拒绝或进程崩溃。

## 资源清理

未直接创建临时目录、后台服务或容器，无需登记或清理自建资源。容器由 Testcontainers / ryuk 回收；本轮框架在容器启动前即报环境错误。
