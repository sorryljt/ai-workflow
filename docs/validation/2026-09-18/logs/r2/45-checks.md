```viktor-checks
test: ./mvnw -q test
e2e: ./mvnw -q verify
```
- 环境前提 / 来源：README.md「跑测试」一节；以仓库根目录为工作目录。`test` 跑 core 单测 + app WebMvc 切片（不需要 Docker）；`e2e` 追加 app 的 `*IT`（failsafe，Testcontainers 拉起 postgres:16-alpine，需要 Docker）。无独立 typecheck / lint，编译在 test 阶段完成。
