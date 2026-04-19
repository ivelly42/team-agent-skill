#!/usr/bin/env bash
# Schema validation test — 5개 refs/*.json이 Draft-07 유효 + valid/invalid 샘플 검증
# 각 스키마에 대해 (1) meta-schema 적합성, (2) valid 문서 통과, (3) invalid 문서 거부를 확인한다.
set -u

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0
SKIPPED=0
FAILED=()

_pass() {
    echo "  ✓ PASS: $1"
    PASS=$((PASS+1))
}
_fail() {
    echo "  ✗ FAIL: $1${2:+ — $2}"
    FAIL=$((FAIL+1))
    FAILED+=("$1")
}
_skip() {
    echo "  ⊘ SKIP: $1 (degraded mode — semantic validation disabled)"
    SKIPPED=$((SKIPPED+1))
}

# 의존성 체크 (jsonschema 파이썬 모듈) — HARD REQUIREMENT by default.
# "degraded mode"에서 json.load만으로 PASS 기록하면 필수 필드/enum/거부 검증이 모두 우회되어
# "false green light"가 됨 (Codex adversarial #3). 기본은 fail-fast, 명시적 opt-in만 허용.
#
# 사용법:
#   TEAM_AGENT_SCHEMA_STRICT=0 bash tests/schema-validation.sh
#     → jsonschema 부재 시 각 테스트를 SKIP으로 기록 (PASS 아님), 종료 코드는 여전히 FAIL>0 기준.
USE_JSONSCHEMA=1
STRICT="${TEAM_AGENT_SCHEMA_STRICT:-1}"
if ! python3 -c "import jsonschema" 2>/dev/null; then
    echo "jsonschema 모듈을 찾을 수 없음 — 설치 시도 중..."
    pip install --user jsonschema >/dev/null 2>&1 || pip3 install --user jsonschema >/dev/null 2>&1 || true
fi

if ! python3 -c "import jsonschema" 2>/dev/null; then
    if [ "$STRICT" = "0" ]; then
        echo "⚠️  jsonschema 미설치 + TEAM_AGENT_SCHEMA_STRICT=0 → degraded mode"
        echo "    각 테스트는 PASS가 아닌 SKIP으로 기록됨 (false green light 방지)"
        USE_JSONSCHEMA=0
    else
        cat <<'ERR' >&2
❌ jsonschema 모듈 필요 — semantic validation 없이는 테스트 의미 없음

설치:
  pip install --user jsonschema

또는 degraded mode 명시 활성화 (SKIP으로만 기록, PASS 없음):
  TEAM_AGENT_SCHEMA_STRICT=0 bash tests/schema-validation.sh

(이 gate는 Codex adversarial #3을 막기 위한 것 — "json.load만 통과"가
"schema validation 통과"로 위장되던 이전 동작을 fail-fast로 교체)
ERR
        exit 2
    fi
fi

# === 공통 테스트 러너 ===
# $1 = 테스트 이름
# $2 = 스키마 파일 경로
# $3 = valid 샘플 (python dict literal 문자열)
# $4 = invalid 샘플 (python dict literal 문자열)
_run_test() {
    local name="$1"
    local schema_path="$2"
    local valid_doc="$3"
    local invalid_doc="$4"

    if [ "$USE_JSONSCHEMA" = "1" ]; then
        python3 - "$schema_path" "$valid_doc" "$invalid_doc" <<'PYEOF' 2>&1
import json, sys
try:
    import jsonschema
    schema_path = sys.argv[1]
    valid_src = sys.argv[2]
    invalid_src = sys.argv[3]

    with open(schema_path, encoding='utf-8') as f:
        schema = json.load(f)

    # (1) meta-schema 적합성
    jsonschema.Draft7Validator.check_schema(schema)

    # (2) valid 샘플 통과
    valid_doc = eval(valid_src, {"__builtins__": {}}, {"null": None, "true": True, "false": False})
    jsonschema.validate(valid_doc, schema)

    # (3) invalid 샘플 거부
    invalid_doc = eval(invalid_src, {"__builtins__": {}}, {"null": None, "true": True, "false": False})
    rejected = False
    try:
        jsonschema.validate(invalid_doc, schema)
    except jsonschema.ValidationError:
        rejected = True
    if not rejected:
        print("invalid sample was accepted (should have been rejected)", file=sys.stderr)
        sys.exit(2)

    sys.exit(0)
except SystemExit:
    raise
except Exception as e:
    print(f"exception: {type(e).__name__}: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
        local rc=$?
        if [ $rc -eq 0 ]; then
            _pass "$name"
        else
            _fail "$name" "rc=$rc"
        fi
    else
        # Degraded mode (TEAM_AGENT_SCHEMA_STRICT=0): JSON 문법만 확인하고 SKIP 기록.
        # PASS로 올리지 않는다 — semantic validation(required·enum·invalid 거부) 미수행이므로
        # "green light 위장"을 방지. 파싱도 실패하면 FAIL로 격상.
        python3 - "$schema_path" <<'PYEOF' 2>&1
import json, sys
try:
    with open(sys.argv[1], encoding='utf-8') as f:
        json.load(f)
    sys.exit(0)
except Exception as e:
    print(f"json.load failed: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
        local rc=$?
        if [ $rc -eq 0 ]; then
            _skip "$name"
        else
            _fail "$name" "json.load failed rc=$rc (degraded mode — schema file unparseable)"
        fi
    fi
}

# === Test 1: output-schema.json ===
test_output_schema() {
    local schema="$SKILL_DIR/refs/output-schema.json"
    local valid='{"findings": [{"severity":"High","title":"SQL injection","file":"app.py","line_start":42,"line_end":45,"code_snippet":"cursor.execute(q)","evidence":"user input concat","confidence":"high","action":"use parameterized query","category":"security"}], "ideas": [{"title":"add linter","difficulty":"low","impact":"medium","detail":"set up ruff"}]}'
    # invalid: severity가 enum 위반
    local invalid='{"findings": [{"severity":"SUPERBAD","title":"x","file":"f","line_start":1,"line_end":1,"code_snippet":"x","evidence":"e","confidence":"high","action":"a","category":"security"}], "ideas": []}'
    _run_test "output-schema: 구조+valid+invalid severity" "$schema" "$valid" "$invalid"
}

# === Test 2: ultra-consolidation-schema.json ===
test_ultra_consolidation_schema() {
    local schema="$SKILL_DIR/refs/ultra-consolidation-schema.json"
    # valid: agreement '1/1' (단독 입력 케이스), status=ok
    local valid='{"role": "보안 감사관", "status": "ok", "consensus_findings": [{"severity":"High","title":"t","file":"f","line_start":1,"line_end":1,"code_snippet":"x","evidence":"e","agreement":"1/1","confidence":"high","contradiction":False}], "consensus_ideas": [], "contradictions": []}'
    # invalid: required role 누락
    local invalid='{"status":"ok","consensus_findings": [], "consensus_ideas": [], "contradictions": []}'
    _run_test "ultra-consolidation-schema: role+consensus_findings required, agreement 1/1 허용" "$schema" "$valid" "$invalid"
}

# === Test 6: Ultra failure shape schema-valid ===
# Phase 2.5 실패 경로 3종(all_agents_failed / consolidator_failed / downgraded)이 모두
# shape-stable contract + schema 유효성을 만족하는지 확인.
test_ultra_failure_shapes() {
    local schema="$SKILL_DIR/refs/ultra-consolidation-schema.json"

    if [ "$USE_JSONSCHEMA" != "1" ]; then
        # degraded mode에서 PASS로 올리면 "false green light" — Codex adversarial verification
        # 재발견(#3 regression). _skip으로 전환해 summary·exit semantics 일관성 유지.
        _skip "Ultra failure shape schema-valid"
        return
    fi

    python3 - "$schema" <<'PYEOF'
import json, sys
import jsonschema

with open(sys.argv[1], encoding='utf-8') as f:
    schema = json.load(f)

# 샘플 1: all_agents_failed — 모든 배열 빈 상태
all_failed = {
    "role": "보안 감사관",
    "status": "all_agents_failed",
    "error": "all agents failed: claude=timeout, codex=cli missing, gemini=rate limit",
    "consensus_findings": [],
    "consensus_ideas": [],
    "contradictions": []
}

# 샘플 2: consolidator_failed — raw passthrough (1/3 단독 findings 여러 건)
consolidator_failed = {
    "role": "백엔드 아키텍트",
    "status": "consolidator_failed",
    "error": "consolidator retry exhausted after 2 attempts",
    "consensus_findings": [
        {
            "severity": "High",
            "title": "SQL injection in /users",
            "file": "app.py",
            "line_start": 42,
            "line_end": 45,
            "code_snippet": "cursor.execute(q)",
            "evidence": "user input concat",
            "agreement": "1/3",
            "confidence": "medium",
            "unique_source": "claude",
            "contradiction": False,
            "severity_votes": {"claude": "High"}
        },
        {
            "severity": "High",
            "title": "SQL injection in /users",
            "file": "app.py",
            "line_start": 42,
            "line_end": 45,
            "code_snippet": "cursor.execute(q)",
            "evidence": "same spot flagged independently",
            "agreement": "1/3",
            "confidence": "medium",
            "unique_source": "codex",
            "contradiction": False,
            "severity_votes": {"codex": "High"}
        }
    ],
    "consensus_ideas": [
        {
            "title": "Add parameterized query linter",
            "difficulty": "low",
            "impact": "medium",
            "detail": "catch string-concat SQL",
            "proposers": ["gemini"]
        }
    ],
    "contradictions": []
}

# 샘플 3: downgraded — 2중 모드, 2/2 agreement
downgraded = {
    "role": "성능 엔지니어",
    "status": "downgraded",
    "error": "codex unavailable",
    "consensus_findings": [
        {
            "severity": "Medium",
            "title": "N+1 in list endpoint",
            "file": "views.py",
            "line_start": 10,
            "line_end": 18,
            "code_snippet": "for u in users: u.profile",
            "evidence": "ORM lazy load per row",
            "agreement": "2/2",
            "confidence": "high",
            "contradiction": False,
            "severity_votes": {"claude": "Medium", "gemini": "Medium"}
        }
    ],
    "consensus_ideas": [],
    "contradictions": []
}

for name, doc in [("all_agents_failed", all_failed),
                  ("consolidator_failed", consolidator_failed),
                  ("downgraded", downgraded)]:
    try:
        jsonschema.validate(doc, schema)
    except jsonschema.ValidationError as e:
        print(f"shape {name} rejected: {e.message}", file=sys.stderr)
        sys.exit(1)

# 또한 필수 shape 위반(consensus_ideas 누락) 샘플이 거부되는지 확인
broken = {
    "role": "x",
    "status": "all_agents_failed",
    "consensus_findings": [],
    "contradictions": []
}
try:
    jsonschema.validate(broken, schema)
    print("broken shape (missing consensus_ideas) was accepted", file=sys.stderr)
    sys.exit(2)
except jsonschema.ValidationError:
    pass

# status enum 위반도 거부되는지 확인
bad_status = {
    "role": "x",
    "status": "partial_success",
    "consensus_findings": [],
    "consensus_ideas": [],
    "contradictions": []
}
try:
    jsonschema.validate(bad_status, schema)
    print("bad status enum was accepted", file=sys.stderr)
    sys.exit(3)
except jsonschema.ValidationError:
    pass

# Codex 22차: failure status인데 error 필드 누락 → 거부되어야 함 (conditional required)
failure_no_error = {
    "role": "x",
    "status": "all_agents_failed",
    "consensus_findings": [],
    "consensus_ideas": [],
    "contradictions": []
}
try:
    jsonschema.validate(failure_no_error, schema)
    print("failure status without error was accepted (conditional required broken)", file=sys.stderr)
    sys.exit(4)
except jsonschema.ValidationError:
    pass

# Codex 22차: consolidator_failed + error 빈 문자열 → 거부 (minLength: 1)
failure_empty_error = {
    "role": "x",
    "status": "consolidator_failed",
    "error": "",
    "consensus_findings": [],
    "consensus_ideas": [],
    "contradictions": []
}
try:
    jsonschema.validate(failure_empty_error, schema)
    print("failure status with empty error was accepted (minLength broken)", file=sys.stderr)
    sys.exit(5)
except jsonschema.ValidationError:
    pass

sys.exit(0)
PYEOF
    local rc=$?
    if [ $rc -eq 0 ]; then
        _pass "Ultra failure shape schema-valid"
    else
        _fail "Ultra failure shape schema-valid" "rc=$rc"
    fi
}

# === Test 3: cross-verification-schema.json ===
test_cross_verification_schema() {
    local schema="$SKILL_DIR/refs/cross-verification-schema.json"
    local valid='{"verifications":[{"finding_id":"f1","verdict":"confirmed","rationale":"confirmed by code inspection"}]}'
    # invalid: verdict enum 위반
    local invalid='{"verifications":[{"finding_id":"f1","verdict":"maybe","rationale":"unclear"}]}'
    _run_test "cross-verification-schema: verifications 배열+verdict enum" "$schema" "$valid" "$invalid"
}

# === Test 4: codemap-schema.json ===
test_codemap_schema() {
    local schema="$SKILL_DIR/refs/codemap-schema.json"
    local valid='{"version":1,"generated_at":"2026-04-20T00:00:00Z","project":{"name":"x","root":"/p","stack":["python"],"src_count":10,"test_count":5},"entrypoints":[{"kind":"cli","path":"bin/x"}],"files":[{"path":"a.py","lang":"python","loc":100,"role":"core"}],"symbols":[{"name":"f","kind":"function","file":"a.py","line":1}],"dependencies":[{"from":"a.py","to":"b.py"}]}'
    # invalid: version != 1 (const 위반)
    local invalid='{"version":2,"generated_at":"2026-04-20T00:00:00Z","project":{"name":"x","root":"/p","stack":[],"src_count":0,"test_count":0},"entrypoints":[],"files":[],"symbols":[],"dependencies":[]}'
    _run_test "codemap-schema: version=1 const+entrypoints/files required" "$schema" "$valid" "$invalid"
}

# === Test 5: verification-schema.json ===
test_verification_schema() {
    local schema="$SKILL_DIR/refs/verification-schema.json"
    local valid='{"confirmed":[{"finding_title":"t","evidence":"e","confidence":"high"}],"disputed":[],"rejected":[],"additions":[]}'
    # invalid: required "additions" 누락
    local invalid='{"confirmed":[],"disputed":[],"rejected":[]}'
    _run_test "verification-schema: confirmed/disputed/rejected/additions required" "$schema" "$valid" "$invalid"
}

# === 실행부 ===
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  team-agent schema validation tests"
echo "  skill dir:  $SKILL_DIR"
if [ "$USE_JSONSCHEMA" = "1" ]; then
    echo "  jsonschema: enabled (full validation)"
else
    echo "  jsonschema: disabled (json.load degraded mode)"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

test_output_schema
test_ultra_consolidation_schema
test_cross_verification_schema
test_codemap_schema
test_verification_schema
test_ultra_failure_shapes

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Total: $((PASS+FAIL+SKIPPED)) | Passed: $PASS | Failed: $FAIL | Skipped: $SKIPPED"
if [ "$FAIL" != "0" ]; then
    echo "  Failed tests:"
    for t in "${FAILED[@]}"; do echo "    - $t"; done
fi
if [ "$SKIPPED" != "0" ]; then
    echo "  ⚠️  ${SKIPPED}건 SKIP (degraded mode) — semantic validation 미수행."
    echo "     strict mode 재실행: pip install --user jsonschema && bash $0"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 종료 코드:
#   0 = 전원 PASS (또는 PASS + 일부 SKIP, 0 FAIL)
#   1 = 1건 이상 FAIL
# SKIP만으로는 exit 0 허용 (opt-in 상태이므로) — 단, 상단 경고 출력됨
[ "$FAIL" = "0" ] && exit 0 || exit 1
