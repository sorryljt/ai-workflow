```viktor-checks
test: ./mvnw -q test
verify: docker run -d --name viktor-<本轮 run_id，见上一行>-pg -e POSTGRES_PASSWORD=x postgres:16-alpine && sleep 600
```
- 运行前提：本机 Docker 可用（colima）；verify 会起一个 Postgres 容器，容器名按本轮 run_id 命名
