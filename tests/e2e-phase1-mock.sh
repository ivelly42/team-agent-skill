#!/usr/bin/env bash
# tests/e2e-phase1-mock.sh — round-11: Agent mock shim 종단간 검증
#
# 목적:
#   TEAM_AGENT_TEST_MODE=fixture 경로가 실제로 작동하는지 zsh subprocess에서 실증.
#   Preamble 0.1 → cfg.env source → mock-shim source → _load_fixture_for_role 3회 호출
#   → 각 JSON을 refs/output-schema.json으로 validate.
#
#   이 테스트는 Phase 1의 Agent 도구 호출 분기를 실제 실행 경로에서 대체하는
#   "mock backend" 계약이 깨지지 않는지 확인한다. 향후 Mock shim 기반 종단간 테스트의 토대.

set -u
readonly SKILL_DIR="${SKILL_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
readonly RED=$'\033[0;31m'
readonly GREEN=$'\033[0;32m'
readonly YELLOW=$'\033[0;33m'
readonly NC=$'\033[0m'

PASS=0
FAIL=0
declare -a FAIL_LOG

ZSH_BIN="$(command -v zsh)"
if [ -z "$ZSH_BIN" ]; then
    echo "FATAL: zsh 미설치"
    exit 2
fi
if ! python3 -c "import jsonschema" 2>/dev/null; then
    echo "${YELLOW}[skip] jsonschema 미설치${NC}"
    exit 0
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  e2e-phase1-mock test (round-11)"
echo "  zsh: $ZSH_BIN"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 임시 cfg.env 생성 (e2e-preamble.sh와 동일 패턴 축약)
TEST_RUN_ID="mock-e2e-$$-$(date +%s)"
TEST_CACHE_DIR="$HOME/.cache/team-agent"
TEST_CFG_FILE="$TEST_CACHE_DIR/cfg-${TEST_RUN_ID}.env"

cleanup() {
    rm -f "$TEST_CFG_FILE"
}
trap cleanup EXIT

mkdir -p "$TEST_CACHE_DIR"
chmod 700 "$TEST_CACHE_DIR"

# 최소 cfg.env 생성 (Preamble 0.1 Python loader와 동일 로직)
python3 - "$SKILL_DIR" "$TEST_CFG_FILE" <<'PYEOF'
import json, shlex, sys
skill_dir, out_path = sys.argv[1], sys.argv[2]
with open(f"{skill_dir}/refs/config.json") as f:
    cfg = json.load(f)
def q(v): return shlex.quote(str(v))
t = cfg["timeouts"]; lim = cfg["limits"]; w = cfg["weights"]
oh = cfg["cost_overhead_k_tokens"]; b = cfg["batch"]; gm = cfg["gemini"]; cx = cfg["codex"]
lines = [
    f"export _CFG_AGENT_SOFT_SEC={q(t['agent_soft_sec'])}",
    f"export _CFG_VERIFY_SEC={q(t['verify_sec'])}",
    f"export _CFG_CODEMAP_SEC={q(t['codemap_sec'])}",
    f"export _CFG_GRACE_SEC={q(t['grace_sec'])}",
    f"export _CFG_TASK_PURPOSE_CHARS={q(lim['task_purpose_chars'])}",
    f"export _CFG_PROJECT_CONTEXT_CHARS={q(lim['project_context_chars'])}",
    f"export _CFG_ROLE_FILTERED_CHARS={q(lim['role_filtered_context_chars'])}",
    f"export _CFG_CONSOLIDATOR_CHARS={q(lim['consolidator_input_chars'])}",
    f"export _CFG_VERIFY_CAP={q(lim['verify_target_cap'])}",
    f"export _CFG_WEIGHT_PRECISE={q(w['precise'])}",
    f"export _CFG_WEIGHT_STRUCTURE={q(w['structure'])}",
    f"export _CFG_WEIGHT_DOCS={q(w['docs'])}",
    f"export _CFG_WEIGHT_EXPLORE={q(w['explore'])}",
    f"export _CFG_OVERHEAD_CODEX={q(oh['codex'])}",
    f"export _CFG_OVERHEAD_GEMINI={q(oh['gemini'])}",
    f"export _CFG_OVERHEAD_OPUS={q(oh['opus_consolidator'])}",
    f"export _CFG_BATCH_SMALL={q(b['size_small'])}",
    f"export _CFG_BATCH_LARGE={q(b['size_large'])}",
    f"export _CFG_BATCH_SLEEP_SEC={q(b['sleep_between_sec'])}",
    f"export _CFG_GEMINI_AGENT_CANDIDATES={q(' '.join(gm['candidates_agent']))}",
    f"export _CFG_GEMINI_VERIFIER_CANDIDATES={q(' '.join(gm['candidates_verifier']))}",
    f"export _CFG_CODEX_AGENT_MODEL={q(cx['agent_model'])}",
    f"export _CFG_CODEX_VERIFIER_MODEL={q(cx['verifier_model'])}",
    f"export _CFG_CODEX_REASONING_AGENT={q(cx['reasoning_effort_agent'])}",
    f"export _CFG_CODEX_REASONING_VERIFIER={q(cx['reasoning_effort_verifier'])}",
    f"export _SKILL_DIR={shlex.quote(skill_dir)}",
    f"source {shlex.quote(skill_dir + '/refs/gemini-helper.sh')}",
    f"source {shlex.quote(skill_dir + '/refs/mock-shim.sh')}",
]
with open(out_path, 'w') as f:
    f.write("\n".join(lines) + "\n")
PYEOF

# ---------------------------------------------------------
# M1. _is_mock_mode 토글 — TEAM_AGENT_TEST_MODE 미설정 → false
# ---------------------------------------------------------
echo ""
echo "── M1. _is_mock_mode predicate — off by default"
m1_out=$("$ZSH_BIN" -c "
source '$TEST_CFG_FILE' 2>&1 >/dev/null
_is_mock_mode && echo 'on' || echo 'off'
")
if [ "$m1_out" = "off" ]; then
    echo "   ${GREEN}[PASS M1]${NC} 미설정 시 off"
    PASS=$((PASS+1))
else
    echo "   ${RED}[FAIL M1]${NC} 기대 'off', 실제 '$m1_out'"
    FAIL=$((FAIL+1))
    FAIL_LOG+=("M1: $m1_out")
fi

# ---------------------------------------------------------
# M2. TEAM_AGENT_TEST_MODE=fixture → on
# ---------------------------------------------------------
echo ""
echo "── M2. _is_mock_mode predicate — on with env var"
m2_out=$("$ZSH_BIN" -c "
export TEAM_AGENT_TEST_MODE=fixture
source '$TEST_CFG_FILE' 2>&1 >/dev/null
_is_mock_mode && echo 'on' || echo 'off'
")
if [ "$m2_out" = "on" ]; then
    echo "   ${GREEN}[PASS M2]${NC} fixture 모드 활성화 감지"
    PASS=$((PASS+1))
else
    echo "   ${RED}[FAIL M2]${NC} 기대 'on', 실제 '$m2_out'"
    FAIL=$((FAIL+1))
    FAIL_LOG+=("M2: $m2_out")
fi

# ---------------------------------------------------------
# M3~M5. 3개 역할 fixture 로드 + schema validate (zsh 실전)
# ---------------------------------------------------------
for role in security performance testing; do
    label="M${role}"
    # JSON을 파일로 저장 (heredoc 보간 대신) — 특수문자 내부 해석 차단
    tmp_json="/tmp/e2e-phase1-mock-$$-${role}.json"
    "$ZSH_BIN" -c "
source '$TEST_CFG_FILE' 2>&1 >/dev/null
_load_fixture_for_role '$role'
" > "$tmp_json" 2>/dev/null
    rc=$?
    if [ "$rc" -ne 0 ] || [ ! -s "$tmp_json" ]; then
        echo "   ${RED}[FAIL $label]${NC} _load_fixture_for_role 실패 (rc=$rc)"
        FAIL=$((FAIL+1))
        FAIL_LOG+=("$label: rc=$rc, out empty")
        rm -f "$tmp_json"
        continue
    fi

    # schema validate — 파일 경로를 argv로 넘김
    validate_err=$(python3 - "$SKILL_DIR" "$tmp_json" <<'PYEOF' 2>&1
import json, sys
from jsonschema import validate, ValidationError
skill_dir, instance_path = sys.argv[1], sys.argv[2]
with open(skill_dir + "/refs/output-schema.json") as f:
    schema = json.load(f)
try:
    with open(instance_path) as f:
        instance = json.load(f)
except json.JSONDecodeError as e:
    print(f"parse: {e}", file=sys.stderr); sys.exit(2)
try:
    validate(instance=instance, schema=schema)
except ValidationError as e:
    print(f"schema: {e.message}", file=sys.stderr); sys.exit(1)
n_findings = len(instance.get('findings', []))
n_ideas = len(instance.get('ideas', []))
print(f"findings={n_findings} ideas={n_ideas}")
PYEOF
)
    rc2=$?
    rm -f "$tmp_json"
    if [ "$rc2" -eq 0 ]; then
        echo "   ${GREEN}[PASS $label]${NC} fixture 로드 + schema 통과 ($validate_err)"
        PASS=$((PASS+1))
    else
        echo "   ${RED}[FAIL $label]${NC} schema/parse 실패: $validate_err"
        FAIL=$((FAIL+1))
        FAIL_LOG+=("$label: $validate_err")
    fi
done

# ---------------------------------------------------------
# M6. 경로 순회 방어 — role에 '..' 주입 시 거부
# ---------------------------------------------------------
echo ""
echo "── M6. 경로 순회 방어 (role='../../../etc/passwd')"
m6_out=$("$ZSH_BIN" -c "
source '$TEST_CFG_FILE' 2>&1 >/dev/null
_load_fixture_for_role '../../etc/passwd' 2>&1
echo 'rc='\$?
")
if echo "$m6_out" | grep -q 'FATAL.*형식 위반' && echo "$m6_out" | grep -q 'rc=1'; then
    echo "   ${GREEN}[PASS M6]${NC} 경로 순회 차단 — fail-closed"
    PASS=$((PASS+1))
else
    echo "   ${RED}[FAIL M6]${NC} 경로 순회 방어 실패"
    FAIL=$((FAIL+1))
    FAIL_LOG+=("M6: $m6_out")
fi

# ---------------------------------------------------------
# M7. 존재하지 않는 role → rc=1 + 가용 role 목록 힌트
# ---------------------------------------------------------
echo ""
echo "── M7. 존재하지 않는 role → fail-closed"
m7_out=$("$ZSH_BIN" -c "
source '$TEST_CFG_FILE' 2>&1 >/dev/null
_load_fixture_for_role 'nonexistent-role' 2>&1
echo 'rc='\$?
")
if echo "$m7_out" | grep -q 'fixture 없음' && echo "$m7_out" | grep -q 'rc=1'; then
    echo "   ${GREEN}[PASS M7]${NC} 미존재 role 차단"
    PASS=$((PASS+1))
else
    echo "   ${RED}[FAIL M7]${NC} 미존재 role 처리 실패"
    FAIL=$((FAIL+1))
    FAIL_LOG+=("M7: $m7_out")
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Total: $((PASS+FAIL))  |  Pass: $PASS  |  Fail: $FAIL"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "실패 상세:"
    printf '  %s\n' "${FAIL_LOG[@]}"
    exit 1
fi

echo "${GREEN}✅ 전체 통과 (mock shim 종단간 계약)${NC}"
exit 0
