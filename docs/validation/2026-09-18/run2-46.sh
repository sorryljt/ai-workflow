#!/usr/bin/env bash
# 第二轮 4.6 合成超时清理：bash run2-46.sh <标签> <literal|env> <超时秒> [manual]
set -uo pipefail
TAG="$1"; MODE="$2"; T="$3"; MAN="${4:-}"
WS="$HOME/personWorkSpace"; DEMO="$WS/springboot-demo"; L="$WS/viktor-validation/logs/r2"
MD="$DEMO/docs/changes/2026-09-18--order-idempotency-key"
export DOCKER_HOST="unix://$HOME/.colima/default/docker.sock" TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE=/var/run/docker.sock DOCKER_API_VERSION=1.44
unset JAVA_TOOL_OPTIONS
cd "$DEMO"
gs(){ { echo "== r2 $1 @ $(date '+%F %T') =="; git status --short; echo; } >> "$WS/viktor-validation/logs/git-status.log"; }
CK="$L/46-$TAG.checks.md"
if [[ "$MODE" == literal ]]; then NAME='viktor-<本轮 run_id，见上一行>-pg'; else NAME='viktor-$VIKTOR_RUN_ID-pg'; fi
cat > "$CK" <<CK
\`\`\`viktor-checks
test: ./mvnw -q test
verify: docker run -d --name $NAME -e POSTGRES_PASSWORD=x postgres:16-alpine && sleep 600
\`\`\`
- 运行前提：本机 Docker 可用（colima）；verify 会起一个 Postgres 容器，容器名按本轮 run_id 命名
CK
gs "4.6-$TAG 前"
docker ps -a --format '{{.Names}} {{.Image}} {{.Status}}' > "$L/46-$TAG.docker-before.txt"
OLD_RID=$(sed -n 's/^- 本轮 run_id：\([0-9-]*\)。.*/\1/p' "$MD/.check.prompt.md" 2>/dev/null | head -1)
export START_TS=$(date +%s)
if [[ -n "$MAN" ]]; then  # 手工证明：spawn 起来后抓 run_id，自己起容器并登记
  ( for i in $(seq 1 30); do rid=$(sed -n 's/^- 本轮 run_id：\([0-9-]*\)。.*/\1/p' "$MD/.check.prompt.md" 2>/dev/null | head -1)
      [[ -n "$rid" && "$rid" != "$OLD_RID" ]] && break; sleep 1; done
    docker run -d --name "viktor-$rid-pg" -e POSTGRES_PASSWORD=x postgres:16-alpine > "$L/46-$TAG.manual-docker.txt" 2>&1
    echo "container:viktor-$rid-pg" >> "$MD/.check.resources"
    echo "manual rid=$rid" >> "$L/46-$TAG.manual-docker.txt"
    docker ps --format '{{.Names}} {{.Status}}' >> "$L/46-$TAG.manual-docker.txt" ) &
fi
s=$(date +%s)
VIKTOR_SPAWN_TIMEOUT="$T" VIKTOR_CLAUDE_ARGS="--permission-mode acceptEdits --allowedTools 'Bash(docker:*)' 'Bash(sleep:*)' --output-format stream-json --verbose" \
  bash .workflow/fe-ai-workflow/scripts/viktor-spawn.sh check "$MD" --agent claude --checks "$CK" > "$L/46-$TAG.spawn.out" 2>&1
rc=$?; e=$(date +%s)
echo "EXIT=$rc 耗时=$((e-s))s" | tee -a "$L/46-$TAG.spawn.out"
sleep 3
docker ps -a --format '{{.Names}} {{.Image}} {{.Status}}' > "$L/46-$TAG.docker-after.txt"
cp "$MD/.check.resources" "$L/46-$TAG.check.resources"; cp "$MD/.check.log" "$L/46-$TAG.check.log"; cp "$MD/.check.prompt.md" "$L/46-$TAG.check.prompt.md"
ps -axo pid,pgid,command | grep -E 'sleep 600|claude -p|postgres|surefire|failsafe|maven' | grep -v grep > "$L/46-$TAG.ps-after.txt"
gs "4.6-$TAG 后"
echo "--- resources"; cat "$L/46-$TAG.check.resources"; echo "--- docker after"; cat "$L/46-$TAG.docker-after.txt"; echo "--- ps after"; cat "$L/46-$TAG.ps-after.txt"
