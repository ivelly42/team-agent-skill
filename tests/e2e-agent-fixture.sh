#!/usr/bin/env bash
# tests/e2e-agent-fixture.sh — round-10: Agent fixture harness 기반
#
# 목적:
#   Phase 1 Agent 호출이 생성한다고 "약속하는" JSON 스키마와, 실제 fixture가 일치하는지
#   기계적으로 검증. 향후 TEAM_AGENT_TEST_MODE=fixture 환경변수가 설정되면 Phase 1이
#   Agent 도구 호출 대신 refs/fixtures/agent-{role}.json을 읽도록 Mock 설계.
#   지금은 fixture 자체의 스키마 + 내용 sanity check만 수행. (Mock shim은 후속 round)
#
# 왜 필요한가:
#   기존 schema-validation.sh는 `.schema.json` 존재/구조만 확인. fixture 대비 실제
#   Agent가 뱉을 JSON이 schema와 맞는지 종단간 검증이 없었다. Agent 시뮬 fixture로
#   "schema ↔ runtime 계약"을 양쪽에서 고정.

set -u
readonly SKILL_DIR="${SKILL_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
readonly SCHEMA="$SKILL_DIR/refs/output-schema.json"
readonly FIXTURE_DIR="$SKILL_DIR/refs/fixtures"
readonly RED=$'\033[0;31m'
readonly GREEN=$'\033[0;32m'
readonly YELLOW=$'\033[0;33m'
readonly NC=$'\033[0m'

PASS=0
FAIL=0
declare -a FAIL_LOG

if ! python3 -c "import jsonschema" 2>/dev/null; then
    echo "${YELLOW}[skip] jsonschema 미설치 — brew install python + pip3 install jsonschema${NC}"
    echo "[skip] python3 -m pip install --user jsonschema 권장"
    exit 0
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  e2e-agent-fixture test (round-10)"
echo "  schema: $SCHEMA"
echo "  fixtures: $FIXTURE_DIR"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 필수 fixture 3개 — Phase 1에서 실제 호출되는 3개 역할 대표 (security/performance/testing)
FIXTURES=(
    "agent-security.json"
    "agent-performance.json"
    "agent-testing.json"
)

for fx in "${FIXTURES[@]}"; do
    fx_path="$FIXTURE_DIR/$fx"
    if [ ! -f "$fx_path" ]; then
        echo "   ${RED}[FAIL $fx]${NC} 파일 없음"
        FAIL=$((FAIL+1))
        FAIL_LOG+=("$fx: missing")
        continue
    fi

    # (1) JSON parse
    if ! python3 -c "import json; json.load(open('$fx_path'))" 2>/dev/null; then
        echo "   ${RED}[FAIL $fx]${NC} JSON parse 실패"
        FAIL=$((FAIL+1))
        FAIL_LOG+=("$fx: invalid JSON")
        continue
    fi

    # (2) schema validate
    validate_err=$(python3 - "$fx_path" "$SCHEMA" <<'PYEOF' 2>&1
import json, sys
from jsonschema import validate, ValidationError
fx_path, schema_path = sys.argv[1], sys.argv[2]
with open(fx_path) as f:
    instance = json.load(f)
with open(schema_path) as f:
    schema = json.load(f)
try:
    validate(instance=instance, schema=schema)
except ValidationError as e:
    # path/msg 함께 출력
    path = list(e.absolute_path) or ["<root>"]
    print(f"path={path} msg={e.message}", file=sys.stderr)
    sys.exit(1)
PYEOF
    )
    if [ $? -ne 0 ]; then
        echo "   ${RED}[FAIL $fx]${NC} schema validation 실패"
        echo "      $validate_err"
        FAIL=$((FAIL+1))
        FAIL_LOG+=("$fx: schema: $validate_err")
        continue
    fi

    # (3) sanity check — findings ≥1 + ideas ≥1 (empty fixture는 의미 없음)
    counts=$(python3 - "$fx_path" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
print(f"{len(d.get('findings', []))} {len(d.get('ideas', []))}")
PYEOF
    )
    nf=$(echo "$counts" | awk '{print $1}')
    ni=$(echo "$counts" | awk '{print $2}')
    if [ "$nf" -lt 1 ] || [ "$ni" -lt 1 ]; then
        echo "   ${RED}[FAIL $fx]${NC} findings=$nf ideas=$ni — 최소 1개씩 필요"
        FAIL=$((FAIL+1))
        FAIL_LOG+=("$fx: empty — findings=$nf ideas=$ni")
        continue
    fi

    # (4) secret scrubber parity — fixture에 실제 secret 패턴이 남아있지 않은지
    #     ("REDACTED_FIXTURE_ONLY" 같은 명시적 sentinel은 허용)
    if python3 -c "
import json, re, sys
d = json.load(open('$fx_path'))
patterns = [
    r'sk_live_[A-Za-z0-9]{24,}',  # 실제 Stripe live key 구조 (24+ 영숫자)
    r'ghp_[A-Za-z0-9]{36,}',      # GitHub personal access token
    r'AKIA[A-Z0-9]{16}',          # AWS access key
]
text = json.dumps(d)
for p in patterns:
    if re.search(p, text):
        print(f'leak: {p}', file=sys.stderr)
        sys.exit(1)
" 2>&1; then
        :
    else
        echo "   ${RED}[FAIL $fx]${NC} fixture에 실제 secret 패턴 leak"
        FAIL=$((FAIL+1))
        FAIL_LOG+=("$fx: real secret pattern detected")
        continue
    fi

    echo "   ${GREEN}[PASS $fx]${NC} schema + sanity (findings=$nf, ideas=$ni)"
    PASS=$((PASS+1))
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Total: $((PASS+FAIL))  |  Pass: $PASS  |  Fail: $FAIL"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "실패 상세:"
    printf '  %s\n' "${FAIL_LOG[@]}"
    echo ""
    echo "${RED}❌ 실패 있음${NC}"
    exit 1
fi

echo "${GREEN}✅ 전체 통과 (schema ↔ fixture 계약 확립)${NC}"
exit 0
