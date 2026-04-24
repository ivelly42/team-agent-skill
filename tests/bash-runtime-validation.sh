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
# R10. cfg.env가 helper source 라인 + _require_cfg 호출을 append하도록 지시하는지 (Preamble 0.1)
# round-9 C1: 인라인 `printf 'source %q'` → `{ printf 'source %q'; printf '_require_cfg\n' } >> cfg`
# 그룹 형태도 허용. _require_cfg 자체도 포함되는지 검증.
# =========================================================================
if (grep -q 'printf .source %q.*_TA_CFG_FILE' "$SKILL_DIR/SKILL.md" \
    || grep -qE "printf 'source %q" "$SKILL_DIR/SKILL.md") \
   && grep -q "_require_cfg" "$SKILL_DIR/SKILL.md"; then
    pass "R10 — Preamble 0.1이 cfg.env에 helper source + _require_cfg append"
else
    fail "R10 — Preamble 0.1에서 helper source 또는 _require_cfg append 지시 누락"
fi

# =========================================================================
# R11. round-6: refs/config.json에 codex 섹션 4개 필드 존재
# =========================================================================
if env _CFG="$CONFIG" python3 -c "
import json, os, sys
cfg = json.load(open(os.environ['_CFG']))
cx = cfg.get('codex', {})
for k in ('agent_model','verifier_model','reasoning_effort_agent','reasoning_effort_verifier'):
    if k not in cx: sys.exit(1)
sys.exit(0)
" 2>/dev/null; then
    pass "R11 — round-6: refs/config.json codex 섹션 4 필드 완비"
else
    fail "R11 — round-6: refs/config.json codex 섹션 필드 누락"
fi

# =========================================================================
# R12. round-6: Preamble 0.1이 _CFG_CODEX_* 4개 export
# =========================================================================
_R12_COUNT=$(grep -cE 'export _CFG_CODEX_(AGENT_MODEL|VERIFIER_MODEL|REASONING_AGENT|REASONING_VERIFIER)' "$SKILL_DIR/SKILL.md")
if [ "$_R12_COUNT" -ge 4 ]; then
    pass "R12 — round-6: Preamble 0.1에서 _CFG_CODEX_* 4개 export"
else
    fail "R12 — round-6: _CFG_CODEX_* export 누락 ($_R12_COUNT/4)"
fi

# =========================================================================
# R13. round-6: 모든 codex exec 호출이 -m "$_CFG_CODEX_*_MODEL" 포함
# =========================================================================
if env _SKILL_DIR_TEST="$SKILL_DIR" python3 <<'PYEOF' >/dev/null 2>&1
import re, os, glob, sys
SKILL_DIR = os.environ["_SKILL_DIR_TEST"]
missing = 0
total = 0
for p in [f"{SKILL_DIR}/SKILL.md"] + sorted(glob.glob(f"{SKILL_DIR}/refs/*.md")):
    with open(p) as f: txt = f.read()
    for m in re.finditer(r'```bash\n(.*?)\n```', txt, flags=re.DOTALL):
        body = m.group(1)
        if 'codex exec' in body and '_run_with_timeout' in body:
            total += 1
            if '-m "$_CFG_CODEX_AGENT_MODEL"' not in body and '-m "$_CFG_CODEX_VERIFIER_MODEL"' not in body:
                missing += 1
sys.exit(0 if (missing == 0 and total >= 3) else 1)
PYEOF
then
    pass "R13 — round-6: 모든 codex exec 호출에 -m \"\$_CFG_CODEX_*_MODEL\" 주입"
else
    fail "R13 — round-6: codex exec -m 명시 누락 블록 잔존"
fi

# =========================================================================
# R14. round-6: verifier codex는 VERIFIER 변수 참조 (agent vs verifier 분리)
# =========================================================================
if grep -q '_CFG_CODEX_VERIFIER_MODEL' "$SKILL_DIR/refs/codex-verification.md" \
   && grep -q '_CFG_CODEX_VERIFIER_MODEL' "$SKILL_DIR/refs/cross-verification.md" \
   && grep -q '_CFG_CODEX_REASONING_VERIFIER' "$SKILL_DIR/refs/codex-verification.md"; then
    pass "R14 — round-6: verifier codex는 _CFG_CODEX_VERIFIER_* 참조"
else
    fail "R14 — round-6: verifier/agent 변수 혼용 또는 누락"
fi

# =========================================================================
# R15. round-7 HS5: PROJECT_CONTEXT sanitizer가 _CFG_PROJECT_CONTEXT_CHARS 참조
# =========================================================================
if grep -qE '_CFG_PROJECT_CONTEXT_CHARS' "$SKILL_DIR/SKILL.md" \
   && grep -qE 'os\.environ\["_CFG_PROJECT_CONTEXT_CHARS"\]' "$SKILL_DIR/SKILL.md"; then
    pass "R15 — round-7 HS5: PROJECT_CONTEXT sanitizer가 _CFG_ 참조 (3000 하드코딩 제거)"
else
    fail "R15 — round-7 HS5: PROJECT_CONTEXT sanitizer _CFG_ 미참조 or os.environ 누락"
fi

# =========================================================================
# R16. round-7 HS6: GEMINI_HAS_SCHEMA 실행 라인이 `|| echo 0` 대신 `|| true` 사용
# (주석/설명 문구는 제외 — `GEMINI_HAS_SCHEMA=$(...)` 실제 할당만 검사)
# =========================================================================
_R16_BAD=$(grep -cE '^[[:space:]]*GEMINI_HAS_SCHEMA=.*\|\| echo 0' "$SKILL_DIR/SKILL.md" || true)
case "$_R16_BAD" in ''|*[!0-9]*) _R16_BAD=0 ;; esac
if [ "$_R16_BAD" = "0" ] && grep -qE '^[[:space:]]*GEMINI_HAS_SCHEMA=.*\|\| true' "$SKILL_DIR/SKILL.md"; then
    pass "R16 — round-7 HS6: GEMINI_HAS_SCHEMA 할당이 \`|| true\` 사용 (multi-line int 비교 오작동 방지)"
else
    fail "R16 — round-7 HS6: GEMINI_HAS_SCHEMA 할당에 \`|| echo 0\` 잔존(${_R16_BAD}건) 또는 \`|| true\` 미사용"
fi

# =========================================================================
# R17. round-7 HS7: Phase 5 cleanup 블록에 rm -f cfg-${_RUN_ID} 명시
# =========================================================================
if env _SKILL="$SKILL_DIR/SKILL.md" python3 <<'PYEOF' >/dev/null 2>&1
import re, os, sys
with open(os.environ["_SKILL"]) as f: txt = f.read()
# Phase 5 섹션 이후에 rm -f cfg-${_RUN_ID} + echo 정리 완료 패턴이 있어야 함
m = re.search(r'### Phase 5:.*?(?=###|\Z)', txt, re.DOTALL)
if not m: sys.exit(1)
body = m.group(0)
if 'rm -f "$HOME/.cache/team-agent/cfg-${_RUN_ID}.env"' not in body: sys.exit(1)
if 'cfg.env 정리 완료' not in body and 'cfg.env 정리' not in body: sys.exit(1)
sys.exit(0)
PYEOF
then
    pass "R17 — round-7 HS7: Phase 5 cleanup 블록 rm -f cfg-\${_RUN_ID} + 완료 로그"
else
    fail "R17 — round-7 HS7: Phase 5 cleanup 블록 누락 또는 불완전"
fi

# =========================================================================
# R18. round-7: refs/secret-scrubber.py 존재 + 자가 테스트 통과
# =========================================================================
SCRUBBER="$SKILL_DIR/refs/secret-scrubber.py"
if [ -f "$SCRUBBER" ] && python3 "$SCRUBBER" >/dev/null 2>&1; then
    pass "R18 — round-7: secret-scrubber.py 존재 + 자가 테스트 8/8 통과"
else
    fail "R18 — round-7: secret-scrubber.py 누락 또는 자가 테스트 실패"
fi

# =========================================================================
# R19. round-7: Phase 2.5 프롬프트가 schema key 강제 (findings 사용 금지 명시)
# =========================================================================
if grep -qE '`findings`[^.]*키 사용 금지|findings` 키 사용 금지' "$SKILL_DIR/SKILL.md"; then
    pass "R19 — round-7+8: Phase 2.5 프롬프트가 findings 키 사용 금지 명시 (schema drift 방어)"
else
    fail "R19 — round-7+8: Phase 2.5 프롬프트 schema drift 방어 문구 누락"
fi

# =========================================================================
# R20. round-8 C1: CRITICAL schema drift 삼위일체 — replicas 허용 안 하고 example에 status
# =========================================================================
if grep -q 'replicas`/`notes`/`summary` 등 다른 키 사용 금지' "$SKILL_DIR/SKILL.md" \
   && grep -qE '"status":\s*"ok"' "$SKILL_DIR/SKILL.md"; then
    pass "R20 — round-8 C1: Ultra schema 삼위일체 sync (prompt 금지 키·example에 status 포함)"
else
    fail "R20 — round-8 C1: replicas 금지 또는 example status 필드 누락"
fi

# =========================================================================
# R21. round-8 C2: contradiction threshold 숫자 rank 명시
# =========================================================================
if grep -q 'Critical=4, High=3, Medium=2, Low=1, Info=0' "$SKILL_DIR/SKILL.md" \
   && grep -q 'Critical=4/High=3/Medium=2/Low=1/Info=0' "$SKILL_DIR/refs/ultra-consolidation-schema.json"; then
    pass "R21 — round-8 C2: contradiction severity rank 매핑 명시 (prompt + schema 양쪽)"
else
    fail "R21 — round-8 C2: severity rank 숫자 매핑 누락 (prompt 또는 schema)"
fi

# =========================================================================
# R22. round-8 C3: TASK_PURPOSE sanitizer fail-closed (os.environ[] + source cfg.env)
# =========================================================================
if grep -q 'os.environ\["_CFG_TASK_PURPOSE_CHARS"\]' "$SKILL_DIR/SKILL.md" \
   && ! grep -q 'os.environ.get("_CFG_TASK_PURPOSE_CHARS"' "$SKILL_DIR/SKILL.md"; then
    pass "R22 — round-8 C3: TASK_PURPOSE sanitizer가 직접 참조 (폴백 없음, fail-closed)"
else
    fail "R22 — round-8 C3: TASK_PURPOSE sanitizer에 .get(..., '500') 폴백 잔존"
fi

# =========================================================================
# R23. round-8 C4: _pick_gemini_model probe가 _run_with_timeout 래핑
# =========================================================================
if grep -qE '_run_with_timeout "\$_probe_sec".*gemini -m' "$SKILL_DIR/refs/gemini-helper.sh"; then
    pass "R23 — round-8 C4: Gemini probe가 _run_with_timeout 래핑 (무한 wedge 방지)"
else
    fail "R23 — round-8 C4: _pick_gemini_model probe가 타임아웃 래퍼 없이 직접 호출"
fi

# =========================================================================
# R24. round-8 C7: Codex -c 값 enum 화이트리스트 검증 (TOML 인젝션 방어)
# =========================================================================
if grep -q '_ALLOWED = re.compile' "$SKILL_DIR/SKILL.md" \
   && grep -q '화이트리스트 위반' "$SKILL_DIR/SKILL.md"; then
    pass "R24 — round-8 C7: Codex codex.* 값 enum 화이트리스트 강제 (TOML 인젝션 방어)"
else
    fail "R24 — round-8 C7: codex 값 화이트리스트 검증 누락 — TOML 인젝션 가능"
fi

# =========================================================================
# R25. round-8 C8: Phase 5 cleanup best-effort (cfg.env source 실패해도 진행)
# =========================================================================
# Phase 5 cleanup 블록이 `|| true` 사용하는지 검사 (`|| exit 1` 아니어야).
if awk '/Phase 5: 완료/,/cfg.env 정리 완료/' "$SKILL_DIR/SKILL.md" | grep -q 'cfg-\${_RUN_ID}.env" 2>/dev/null || true'; then
    pass "R25 — round-8 C8: Phase 5 cleanup best-effort (source 실패해도 rm 계속)"
else
    fail "R25 — round-8 C8: Phase 5 cleanup이 fail-closed source로 자가 abort 가능"
fi

# =========================================================================
# R26. round-8 C5: secret scrubber 재귀 스크러빙 (scrub_finding이 모든 string 필드 재귀)
# =========================================================================
if grep -q '_scrub_recursive' "$SKILL_DIR/refs/secret-scrubber.py"; then
    pass "R26 — round-8 C5: secret scrubber 재귀 (code_snippet·evidence 외 필드도 커버)"
else
    fail "R26 — round-8 C5: scrub_finding이 여전히 2개 필드만 처리 (title/action 미커버)"
fi

# =========================================================================
# R27. round-8 C6: secret scrubber 신규 패턴 (Stripe/Twilio/npm/Azure/GitLab)
# =========================================================================
if grep -q 'REDACTED_STRIPE' "$SKILL_DIR/refs/secret-scrubber.py" \
   && grep -q 'REDACTED_TWILIO' "$SKILL_DIR/refs/secret-scrubber.py" \
   && grep -q 'REDACTED_NPM_TOKEN' "$SKILL_DIR/refs/secret-scrubber.py" \
   && grep -q 'REDACTED_AZURE_KEY' "$SKILL_DIR/refs/secret-scrubber.py"; then
    pass "R27 — round-8 C6: secret scrubber 신규 프로바이더 패턴 (Stripe·Twilio·npm·Azure)"
else
    fail "R27 — round-8 C6: Stripe/Twilio/npm/Azure 중 일부 패턴 누락"
fi

# =========================================================================
# R28. round-8 C9: Bash exit 1 뒤 LLM 세션 stop 지침 문서화
# =========================================================================
if grep -q 'LLM 세션 차원 fail-closed 지침' "$SKILL_DIR/SKILL.md"; then
    pass "R28 — round-8 C9: Bash exit 1이 LLM을 막지 못함 — skill-level stop 지침 명시"
else
    fail "R28 — round-8 C9: LLM 세션 stop 지침 누락 — fail-closed가 bash-only로 한정"
fi

# =========================================================================
# R29. round-8 HS8: Preamble 0.1 sanity check가 zsh 호환 (bash `${!var}` 금지)
# Claude Code Bash 도구가 zsh로 실행 — dry-run 실전에서 "bad substitution" 발견.
# 전까지 bash 명시 테스트로만 PASS하던 self-fulfillment 패턴 파괴.
# =========================================================================
# Preamble 0.1 구역 안에 bash-only indirect expansion `${!_var...}` 잔존 금지
if awk '/^### Preamble 0.1/,/^---$/' "$SKILL_DIR/SKILL.md" | grep -qE '\$\{!_[A-Za-z_]+'; then
    fail "R29 — round-8 HS8: Preamble 0.1에 bash-only \${!var} 잔존 — zsh에서 abort"
else
    pass "R29 — round-8 HS8: Preamble 0.1에 bash-only indirect expansion 없음 (zsh 호환)"
fi

# =========================================================================
# R30. round-8 HS8 (실제 실행): sanity check loop를 zsh -c로 실제 돌려 PASS 확인
# self-fulfilling test 안티패턴 탈출: 단순 grep이 아니라 zsh subprocess에서 실행.
# =========================================================================
_R30_OUT=$(zsh -c '
  _CFG_A=hello _CFG_B=world
  for _var in _CFG_A _CFG_B; do
    eval "_val=\"\${$_var:-}\""
    [ -z "$_val" ] && echo "FAIL: $_var" && exit 1
  done
  echo OK
' 2>&1)
if [ "$_R30_OUT" = "OK" ]; then
    pass "R30 — round-8 HS8 (zsh 실제 실행): eval indirect expansion 패턴 zsh 호환"
else
    fail "R30 — round-8 HS8: zsh 실행 실패 — eval indirect 패턴이 zsh 호환되지 않음: $_R30_OUT"
fi

# =========================================================================
# R31. round-9 C1: gemini-helper.sh가 _require_cfg 함수 제공 + SKILL.md 인라인 제거
# =========================================================================
if grep -q '^_require_cfg()' "$SKILL_DIR/refs/gemini-helper.sh" \
   && ! grep -qE '^_TIMEOUT_BIN=""$' "$SKILL_DIR/SKILL.md" \
   && ! grep -qE '^_TIMEOUT_BIN=""$' "$SKILL_DIR/refs/codex-verification.md" \
   && ! grep -qE '^_TIMEOUT_BIN=""$' "$SKILL_DIR/refs/gemini-verification.md" \
   && ! grep -qE '^_TIMEOUT_BIN=""$' "$SKILL_DIR/refs/cross-verification.md"; then
    pass "R31 — round-9 C1: gemini-helper.sh에 _require_cfg 추가 + SKILL.md·refs 4곳 인라인 제거"
else
    fail "R31 — round-9 C1: _require_cfg 누락 또는 7곳 인라인 timeout wrapper 잔존"
fi

# =========================================================================
# R32. round-9 C1 (zsh 실제 실행): cfg.env source → _run_with_timeout + _require_cfg 함수 바인딩
# 실제 zsh subprocess에서 helper.sh만 source해서 함수가 type으로 보이는지 검증.
# =========================================================================
_R32_OUT=$(zsh -c "
  source \"$SKILL_DIR/refs/gemini-helper.sh\" 2>/dev/null
  type _run_with_timeout >/dev/null 2>&1 || { echo 'FAIL: _run_with_timeout missing'; exit 1; }
  type _pick_gemini_model >/dev/null 2>&1 || { echo 'FAIL: _pick_gemini_model missing'; exit 1; }
  type _require_cfg >/dev/null 2>&1 || { echo 'FAIL: _require_cfg missing'; exit 1; }
  echo OK
" 2>&1)
if [ "$_R32_OUT" = "OK" ]; then
    pass "R32 — round-9 C1 (zsh 실제 실행): helper.sh source 후 3 함수 전부 바인딩"
else
    fail "R32 — round-9 C1: zsh에서 helper 함수 바인딩 실패: $_R32_OUT"
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
