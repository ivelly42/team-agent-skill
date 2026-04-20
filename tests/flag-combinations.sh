#!/usr/bin/env bash
# tests/flag-combinations.sh
#
# Regression: 플래그 조합 매트릭스 계약 smoke.
# refs/flag-matrix.md의 충돌/다운그레이드 규칙이 존재하고 SKILL.md 파싱
# 섹션에 누락된 플래그가 없는지 정적으로 검증한다.

set -u
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_MD="$SKILL_DIR/SKILL.md"
MATRIX_MD="$SKILL_DIR/refs/flag-matrix.md"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
PASS=0; FAIL=0
pass() { printf "  ${GREEN}✓ PASS${NC}: %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "  ${RED}✗ FAIL${NC}: %s\n" "$1"; FAIL=$((FAIL+1)); }

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  flag-combinations smoke"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# F1. refs/flag-matrix.md 파일 존재
if [ -f "$MATRIX_MD" ]; then
    pass "F1 — refs/flag-matrix.md 외부화 존재"
else
    fail "F1 — refs/flag-matrix.md 없음"
    exit 1
fi

# F2. SKILL.md가 flag-matrix.md를 참조
if grep -q "refs/flag-matrix.md" "$SKILL_MD"; then
    pass "F2 — SKILL.md가 flag-matrix.md 참조"
else
    fail "F2 — SKILL.md Step 1-1.5 flag-matrix 참조 누락"
fi

# F3. 핵심 충돌 규칙 존재 (충돌 12건 중 주요)
declare -a CONFLICTS=(
    "dry-run.*resume.*충돌"
    "diff.*resume.*충돌"
    "codex.*gemini.*충돌"
    "ultra.*codex.*충돌"
    "ultra.*gemini.*충돌"
    "ultra.*cross.*충돌"
    "auto.*빈 TASK_PURPOSE"
)
CONFLICT_MISS=0
for pat in "${CONFLICTS[@]}"; do
    if ! grep -qE "$pat" "$MATRIX_MD"; then
        fail "F3 — 충돌 규칙 누락: $pat"
        CONFLICT_MISS=$((CONFLICT_MISS+1))
    fi
done
if [ "$CONFLICT_MISS" -eq 0 ]; then
    pass "F3 — 7개 핵심 충돌 규칙 전부 매트릭스에 존재"
fi

# F4. 다운그레이드 규칙 (CLI 미설치 4종)
declare -a DOWNGRADES=(
    "codex.*미설치"
    "gemini.*미설치"
    "ultra.*양쪽 미설치"
)
DOWN_MISS=0
for pat in "${DOWNGRADES[@]}"; do
    if ! grep -qE "$pat" "$MATRIX_MD"; then
        fail "F4 — 다운그레이드 규칙 누락: $pat"
        DOWN_MISS=$((DOWN_MISS+1))
    fi
done
if [ "$DOWN_MISS" -eq 0 ]; then
    pass "F4 — CLI 미설치 다운그레이드 3종 존재"
fi

# F5. SKILL.md 플래그 파싱 섹션에 모든 플래그 선언 존재
declare -a FLAGS=(
    "auto.*AUTO_MODE"
    "deep.*DEEP_MODE"
    "dry-run.*DRY_RUN"
    "scope.*SCOPE_PATH"
    "resume.*RESUME_RUN_ID"
    "codex.*CODEX_MODE"
    "gemini.*GEMINI_MODE"
    "cross.*CROSS_MODE"
    "ultra.*ULTRA_MODE"
    "codemap-skip.*CODEMAP_SKIP"
    "diff.*DIFF_BASE"
    "notify.*NOTIFY_TELEGRAM"
)
FLAG_MISS=0
for pat in "${FLAGS[@]}"; do
    if ! grep -qE "^- \`--$pat" "$SKILL_MD"; then
        fail "F5 — 플래그 파싱 누락: $pat"
        FLAG_MISS=$((FLAG_MISS+1))
    fi
done
if [ "$FLAG_MISS" -eq 0 ]; then
    pass "F5 — 12개 플래그 파싱 섹션 전부 선언 (--auto/--deep/--dry-run/--scope/--resume/--codex/--gemini/--cross/--ultra/--codemap-skip/--diff/--notify)"
fi

# F6. --ultra=selective 파싱 지원
if grep -q "ULTRA_STRATEGY" "$SKILL_MD" && grep -q "selective" "$SKILL_MD"; then
    pass "F6 — --ultra=selective 파싱 + ULTRA_STRATEGY 변수"
else
    fail "F6 — --ultra=selective (Item 2) 미적용"
fi

# F7. Ultra selective 라우팅 테이블 (가중치별 복제 수)
if grep -q "ULTRA_STRATEGY=selective" "$SKILL_MD" && grep -q "3중\|2중\|1중" "$SKILL_MD"; then
    pass "F7 — selective 가중치별 복제 테이블 존재"
else
    fail "F7 — selective 라우팅 규칙 미기재"
fi

# F8. 권한 A + 외부 CLI 충돌 규칙
if grep -q "권한 A.*격리.*읽기 전용" "$MATRIX_MD" || grep -qE "권한 A\(bypassPermissions\)" "$MATRIX_MD"; then
    pass "F8 — 권한 A + 외부 CLI 격리 불가 강제 규칙"
else
    fail "F8 — 권한 A 격리 충돌 규칙 부재"
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
