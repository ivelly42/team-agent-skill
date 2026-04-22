#!/usr/bin/env bash
# tests/config-wired-in-exec.sh
#
# Codex round-2 Finding #1 regression:
# 실제 Bash 실행 블록에 하드코딩 값이 남아있지 않은지 검증.
# Preamble 0.1 선언 섹션은 예외 허용 (화살표 "→" 로 치환 규칙 설명).

set -u
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_MD="$SKILL_DIR/SKILL.md"
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
PASS=0; FAIL=0
pass() { printf "  ${GREEN}✓ PASS${NC}: %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "  ${RED}✗ FAIL${NC}: %s\n" "$1"; FAIL=$((FAIL+1)); }

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  config 치환 실제 적용 smoke (Codex round-2 #1)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# W1. Preamble 0.1 선언 섹션 외에서 `gemini -m gemini-3.1-...-preview` 직접 사용 0
# Preamble 선언은 "→" 화살표 포함 라인이므로 필터
PINNED_GEMINI=$(grep -nE 'gemini -m gemini-3\.1-(flash-lite|pro)-preview' "$SKILL_MD" \
  | grep -vE '→|config\.json|candidates_(agent|verifier)' || true)
if [ -z "$PINNED_GEMINI" ]; then
    pass "W1 — 실행 블록에 하드코딩 gemini preview 모델 0건 (Preamble 선언 제외)"
else
    fail "W1 — 하드코딩 gemini 모델 발견:"
    echo "$PINNED_GEMINI"
fi

# W2. Preamble 외에서 `_run_with_timeout <숫자> <숫자>` 하드코딩 0
PINNED_TIMEOUT=$(grep -nE '_run_with_timeout [0-9]+ [0-9]+' "$SKILL_MD" \
  | grep -vE '→|_CFG_|assert ' || true)
if [ -z "$PINNED_TIMEOUT" ]; then
    pass "W2 — 실행 블록에 하드코딩 timeout 숫자 0건"
else
    fail "W2 — 하드코딩 timeout 발견:"
    echo "$PINNED_TIMEOUT"
fi

# W3. _pick_gemini_model 헬퍼가 실제 호출되는지 (선언 외)
CALLS=$(grep -nE '_pick_gemini_model (agent|verifier)' "$SKILL_MD" | grep -vE '→|^124:|정의|함수' | wc -l | tr -d ' ')
if [ "$CALLS" -ge 2 ]; then
    pass "W3 — _pick_gemini_model 실행 호출 ${CALLS}회"
else
    fail "W3 — _pick_gemini_model 호출이 2회 미만 ($CALLS)"
fi

# W4. _CFG_* 변수가 실행 블록에서 실제 참조 (선언 외)
CFG_REFS=$(grep -nE '\$\{?_CFG_[A-Z_]+' "$SKILL_MD" | grep -vE '→|export _CFG_|refs/config\.json' | wc -l | tr -d ' ')
if [ "$CFG_REFS" -ge 4 ]; then
    pass "W4 — _CFG_* 실행 블록 참조 ${CFG_REFS}회"
else
    fail "W4 — _CFG_* 실행 참조 부족 ($CFG_REFS)"
fi

# W5. TASK_PURPOSE Python 블록에서 _CFG_TASK_PURPOSE_CHARS 사용
if grep -q "_CFG_TASK_PURPOSE_CHARS" "$SKILL_MD"; then
    pass "W5 — TASK_PURPOSE sanitizer가 _CFG_TASK_PURPOSE_CHARS 참조"
else
    fail "W5 — TASK_PURPOSE 길이 변수 참조 없음"
fi

# W6. Phase 0.5 Ultra 비용 섹션에 ULTRA_STRATEGY 참조 (Codex round-2 #2)
if awk '/^### Phase 0\.5/,/^### Phase 1:/' "$SKILL_MD" | grep -qE "ULTRA_STRATEGY|selective"; then
    pass "W6 — Phase 0.5 비용 계산에 ULTRA_STRATEGY 분기"
else
    fail "W6 — Phase 0.5가 여전히 selective 무관"
fi

# W7. Phase 0.5에 ultra_replicas_for_cost 함수 정의
if awk '/^### Phase 0\.5/,/^### Phase 1:/' "$SKILL_MD" | grep -q "ultra_replicas_for_cost"; then
    pass "W7 — Phase 0.5에 replica 계산 함수 존재"
else
    fail "W7 — Phase 0.5 replica 계산 함수 미정의"
fi

# W8. 승인 게이트가 selective와 full 차등
if awk '/^### Phase 0\.5/,/^### Phase 1:/' "$SKILL_MD" | grep -qE "ultra=full.*4명|ultra=selective.*5명|전략별 차등"; then
    pass "W8 — 승인 게이트가 strategy별 차등 규칙"
else
    fail "W8 — 승인 게이트 strategy 차등 부재"
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
