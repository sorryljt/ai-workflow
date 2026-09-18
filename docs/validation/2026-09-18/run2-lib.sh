# 第二轮公用函数（source 使用）
WS="$HOME/personWorkSpace"; DEMO="$WS/springboot-demo"; NOINIT="$WS/springboot-demo-noinit"
V="$WS/viktor-validation"; L="$V/logs/r2"; mkdir -p "$L"
export DOCKER_HOST="unix://$HOME/.colima/default/docker.sock" TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE=/var/run/docker.sock DOCKER_API_VERSION=1.44
unset JAVA_TOOL_OPTIONS CLAUDECODE CLAUDE_PROJECT_DIR
gs(){ { echo "== r2 $2 @ $(date '+%F %T') =="; git -C "$1" status --short; echo; } >> "$V/logs/git-status.log"; }
cl(){ local name="$1" sid="$2" mode="$3" prompt="$4" s e rc
  s=$(date +%s)
  if [[ "$mode" == new ]]; then set -- --session-id "$sid"; else set -- --resume "$sid"; fi
  claude -p "$prompt" "$@" --dangerously-skip-permissions --output-format stream-json --verbose > "$L/$name.jsonl" 2> "$L/$name.stderr"; rc=$?
  e=$(date +%s); echo "$name rc=$rc 耗时=$((e-s))s" | tee -a "$V/logs/driver.log"
  python3 - "$L/$name.jsonl" > "$L/$name.final.txt" <<'PY'
import json,sys
last=""
for line in open(sys.argv[1],encoding="utf-8"):
    try: o=json.loads(line)
    except Exception: continue
    if o.get("type")=="result": last=o.get("result") or ""
print(last)
PY
  cat "$L/$name.final.txt"; }
uuid(){ uuidgen | tr 'A-Z' 'a-z'; }
