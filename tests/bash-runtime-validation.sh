#!/usr/bin/env bash
# tests/bash-runtime-validation.sh
#
# round-5 C3 대응 — 자기충족 grep 검증을 넘어서 **실제 bash 실행으로 행위 검증**.
# Ultra round-4 메타 분석에서 발견:
#   - 기존 tests/*.sh 대부분이 `grep -c` 정적 매칭으로 SKILL.md 문자열만 확인
#   - 실제 Preamble 0.1 bash가 실행되어 _CFG_* + 함수가 바인딩되는지 검증하는 테스트 부재
# 이 스위트는 해당 gap을 메운다: 임시 RUN_ID + 임시 HOME.cache로 실제 실행.

set -u
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HELPER="$SKILL_DIR/refs/gemini-helper.sh"
CONFIG="$SKILL_DIR/refs/config.json"
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
PASS=0; FAIL=0
pass() { printf "  ${GREEN}✓ PASS${NC}: %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "  ${RED}✗ FAIL${NC}: %s\n" "$1"; FAIL=$((FAIL+1)); }

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  bash runtime validation (round-5 C3)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# =========================================================================
# 테스트 환경: 임시 RUN_ID. cfg.env는 실제 $HOME/.cache/team-agent/에 생성한 뒤
# 테스트 종료 시 정리. 동일 머신의 다른 team-agent 실행과 충돌 방지용 prefix.
# =========================================================================
_TEST_RUN_ID="test-$$-$(date +%s)"
_TEST_CFG_FILE="$HOME/.cache/team-agent/cfg-${_TEST_RUN_ID}.env"
cleanup() { rm -f "$_TEST_CFG_FILE" 2>/dev/null; }
trap cleanup EXIT

# =========================================================================
# R1. gemini-helper.sh bash 문법 유효성
# =========================================================================
if [ ! -f "$HELPER" ]; then
    fail "R1 — refs/gemini-helper.sh 파일 누락"
elif bash -n "$HELPER" 2>/dev/null; then
    pass "R1 — gemini-helper.sh bash -n 문법 OK"
else
    fail "R1 — gemini-helper.sh 문법 오류"
fi

# =========================================================================
# R2. helper 소싱 후 두 함수 모두 정의됨
# =========================================================================
_R2_RESULT=$(bash -c '
source "'"$HELPER"'"
type _pick_gemini_model >/dev/null 2>&1 && type _run_with_timeout >/dev/null 2>&1 && echo OK
' 2>&1)
if [ "$_R2_RESULT" = "OK" ]; then
    pass "R2 — helper 소싱 후 _pick_gemini_model + _run_with_timeout 둘 다 바인딩"
else
    fail "R2 — helper 소싱 후 함수 바인딩 실패: $_R2_RESULT"
fi

# =========================================================================
# R3. bug_006 — _pick_gemini_model 전원 실패 시 **빈 문자열 + rc=1**
#     caller가 rc 체크하도록 loud fail 강제
# =========================================================================
_R3_OUT=$(bash -c '
export _CFG_GEMINI_AGENT_CANDIDATES="nonexistent-model-1 nonexistent-model-2"
source "'"$HELPER"'"
_result=$(_pick_gemini_model agent 2>/dev/null)
_rc=$?
echo "result=[$_result]"
echo "rc=$_rc"
')
if echo "$_R3_OUT" | grep -q "result=\[\]" && echo "$_R3_OUT" | grep -q "rc=1"; then
    pass "R3 — bug_006: 전원 실패 시 빈 문자열 + rc=1"
else
    fail "R3 — bug_006 regression: $_R3_OUT"
fi

# =========================================================================
# R4. Preamble 0.1 시뮬레이션 — config.json → cfg.env 생성 → source → 바인딩
# =========================================================================
_R4_OUT=$(bash <<PYWRAP
export _SKILL_DIR="$SKILL_DIR"
export _RUN_ID="$_TEST_RUN_ID"
mkdir -p "\$HOME/.cache/team-agent"
_CFG="\$HOME/.cache/team-agent/cfg-\${_RUN_ID}.env"
: > "\$_CFG" && chmod 600 "\$_CFG"
python3 -c "
import json, shlex
with open('$CONFIG') as f: cfg = json.load(f)
t = cfg['timeouts']; gm = cfg['gemini']
lines = [
    'export _CFG_AGENT_SOFT_SEC=' + shlex.quote(str(t['agent_soft_sec'])),
    'export _CFG_VERIFY_SEC=' + shlex.quote(str(t['verify_sec'])),
    'export _CFG_GRACE_SEC=' + shlex.quote(str(t['grace_sec'])),
    'export _CFG_GEMINI_AGENT_CANDIDATES=' + shlex.quote(' '.join(gm['candidates_agent'])),
]
with open('$_TEST_CFG_FILE','w') as f: f.write('\n'.join(lines)+'\n')
"
printf 'source %q\n' "\$_SKILL_DIR/refs/gemini-helper.sh" >> "\$_CFG"

# 별도 bash 프로세스에서 source cfg.env 한 줄만 — cross-invocation 시뮬레이션
bash -c '
source "'"\$_CFG"'"
[ -n "\$_CFG_AGENT_SOFT_SEC" ] || { echo "MISSING: _CFG_AGENT_SOFT_SEC"; exit 1; }
type _pick_gemini_model >/dev/null 2>&1 || { echo "MISSING: _pick_gemini_model"; exit 1; }
type _run_with_timeout >/dev/null 2>&1 || { echo "MISSING: _run_with_timeout"; exit 1; }
echo "ALLGOOD"
'
PYWRAP
)
if echo "$_R4_OUT" | grep -q "ALLGOOD"; then
    pass "R4 — Preamble 0.1 cross-invocation: cfg.env 한 줄로 변수+함수 로드"
else
    fail "R4 — Preamble 0.1 실행 실패: $_R4_OUT"
fi

# =========================================================================
# R5. bug_020 regression — Phase 0.3 Gemini 코드맵 블록 _CODEMAP_RC=$? 고아 할당 제거 확인
# =========================================================================
# SKILL.md에서 "fi\n_CODEMAP_RC=$?\n" 패턴 (fi 직후 compound rc overwrite) 0건이어야 함
_R5_BAD=$(python3 - "$SKILL_DIR/SKILL.md" <<'PYEOF'
import re, sys
with open(sys.argv[1]) as f: txt = f.read()
matches = re.findall(r'\nfi\n_CODEMAP_RC=\$\?\n', txt)
print(len(matches))
PYEOF
)
if [ "$_R5_BAD" = "0" ]; then
    pass "R5 — bug_020: Phase 0.3 고아 _CODEMAP_RC=\$? 제거"
else
    fail "R5 — bug_020 regression: ${_R5_BAD}개 고아 할당 잔존"
fi

# =========================================================================
# R6. bug_010 regression — manifest template ultra_strategy 따옴표 없음 (Python 리터럴)
# =========================================================================
_R6_BAD=$(grep -c '"ultra_strategy": "ULTRA_STRATEGY_VALUE"' "$SKILL_DIR/SKILL.md" || true)
if [ "$_R6_BAD" = "0" ]; then
    pass "R6 — bug_010: ultra_strategy 따옴표 드리프트 없음"
else
    fail "R6 — bug_010 regression: 따옴표 래핑 ${_R6_BAD}건"
fi

# =========================================================================
# R7. bug_011 regression — help 텍스트 selective 설명이 '2-replica baseline' 포함
# =========================================================================
if grep -q "2-replica baseline" "$SKILL_DIR/SKILL.md"; then
    pass "R7 — bug_011: selective 2-replica baseline 설명 존재"
else
    fail "R7 — bug_011 regression: 2-replica baseline 문구 누락 (help·routing drift)"
fi

# =========================================================================
# R8. round-5 C1 — SKILL.md + refs/*.md 실행 bash 블록의 source cfg.env 가드 커버리지
# python exit code 기반: 누락 0건이면 exit 0, 아니면 exit 1
# =========================================================================
if env _SKILL_DIR_TEST="$SKILL_DIR" python3 <<'PYEOF' >/dev/null 2>&1
import re, os, glob, sys
SKILL_DIR = os.environ["_SKILL_DIR_TEST"]

def is_runtime_exec(body):
    if '_TA_CFG_FILE' in body or 'mkdir -p "$_TA_CFG_DIR"' in body: return False
    if body.strip().startswith('rm -f "$HOME/.cache/team-agent') and body.count('\n') <= 2: return False
    return any(t in body for t in ['$_CFG_', '_pick_gemini_model', '_run_with_timeout', '_GEMINI_', '_CODEMAP'])

runtime_exec = 0
missing_guard = 0
for p in [f"{SKILL_DIR}/SKILL.md"] + sorted(glob.glob(f"{SKILL_DIR}/refs/*.md")):
    with open(p) as f: txt = f.read()
    for m in re.finditer(r'```bash\n(.*?)\n```', txt, flags=re.DOTALL):
        body = m.group(1)
        if is_runtime_exec(body):
            runtime_exec += 1
            if 'source "$HOME/.cache/team-agent/cfg-' not in body:
                missing_guard += 1
sys.exit(0 if (missing_guard == 0 and runtime_exec > 0) else 1)
PYEOF
then
    pass "R8 — round-5 C1: 모든 런타임 실행 블록에 source cfg.env 가드 삽입"
else
    fail "R8 — round-5 C1: 가드 누락 블록 잔존 또는 런타임 블록 0건"
fi

# =========================================================================
# R9. round-5 C4 — SKILL.md가 refs/gemini-helper.sh를 실제 참조
# =========================================================================
if grep -q "refs/gemini-helper.sh" "$SKILL_DIR/SKILL.md"; then
    pass "R9 — round-5 C4: SKILL.md가 refs/gemini-helper.sh 참조"
else
    fail "R9 — round-5 C4: SKILL.md에서 refs/gemini-helper.sh 참조 누락"
fi

# =========================================================================
# R10. cfg.env가 helper source 라인을 append하도록 지시하는지 (Preamble 0.1)
# =========================================================================
if grep -q 'printf .source %q.*>> "\$_TA_CFG_FILE"' "$SKILL_DIR/SKILL.md" \
   || grep -q 'printf .source %q.*_TA_CFG_FILE' "$SKILL_DIR/SKILL.md"; then
    pass "R10 — Preamble 0.1이 cfg.env에 helper source 라인 append"
else
    fail "R10 — Preamble 0.1에서 helper source 라인 append 지시 누락"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Total: $((PASS+FAIL))  |  Passed: $PASS  |  Failed: $FAIL"
if [ "$FAIL" -eq 0 ]; then
    echo -e "  ${GREEN}✅ 전체 통과${NC}"
else
    echo -e "  ${RED}❌ 실패 있음${NC}"
    exit 1
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
