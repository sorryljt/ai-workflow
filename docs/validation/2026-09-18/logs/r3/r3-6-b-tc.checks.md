```viktor-checks
verify: ./mvnw -q -pl app -am verify
```
- 运行前提：需要 Docker（colima）；verify 通过 Testcontainers 拉起 postgres:16-alpine
