#!/usr/bin/env bash
# Schema validation test — 5개 refs/*.json이 Draft-07 유효 + valid/invalid 샘플 검증
# 각 스키마에 대해 (1) meta-schema 적합성, (2) valid 문서 통과, (3) invalid 문서 거부를 확인한다.
set -u

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0
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

# 의존성 체크 (jsonschema 파이썬 모듈)
USE_JSONSCHEMA=1
if ! python3 -c "import jsonschema" 2>/dev/null; then
    echo "INSTALL: pip install --user jsonschema"
    if pip install --user jsonschema >/dev/null 2>&1 || pip3 install --user jsonschema >/dev/null 2>&1; then
        if ! python3 -c "import jsonschema" 2>/dev/null; then
            echo "⚠️  jsonschema 미설치 — 기본 python json.load 검증만 수행 (degraded mode)"
            USE_JSONSCHEMA=0
        fi
    else
        echo "⚠️  jsonschema 설치 실패 — degraded mode (json.load만)"
        USE_JSONSCHEMA=0
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
        # Degraded mode: 스키마 파일 자체가 JSON 파싱 되는지만 확인
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
            _pass "$name (degraded: json.load only)"
        else
            _fail "$name" "json.load rc=$rc"
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
    # valid: agreement '1/1' (단독 입력 케이스), 최소 required 필드만
    local valid='{"role": "보안 감사관", "consensus_findings": [{"severity":"High","title":"t","file":"f","line_start":1,"line_end":1,"code_snippet":"x","evidence":"e","agreement":"1/1","confidence":"high","contradiction":False}]}'
    # invalid: required role 누락
    local invalid='{"consensus_findings": []}'
    _run_test "ultra-consolidation-schema: role+consensus_findings required, agreement 1/1 허용" "$schema" "$valid" "$invalid"
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

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Total: $((PASS+FAIL)) | Passed: $PASS | Failed: $FAIL"
if [ "$FAIL" != "0" ]; then
    echo "  Failed tests:"
    for t in "${FAILED[@]}"; do echo "    - $t"; done
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

[ "$FAIL" = "0" ] && exit 0 || exit 1
