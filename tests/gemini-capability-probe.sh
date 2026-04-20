#!/usr/bin/env bash
# tests/gemini-capability-probe.sh
#
# Regression: GEMINI_HAS_SCHEMA probe + 분기 일관성 smoke.
# 실제 gemini CLI는 호출하지 않고, SKILL.md 및 refs/*-verification.md의
# 분기 패턴만 grep으로 검증한다 (정적 계약 회귀).

set -u
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_MD="$SKILL_DIR/SKILL.md"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
PASS=0; FAIL=0

pass() { printf "  ${GREEN}✓ PASS${NC}: %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "  ${RED}✗ FAIL${NC}: %s\n" "$1"; FAIL=$((FAIL+1)); }
note() { printf "  ${YELLOW}note${NC}: %s\n" "$1"; }

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  gemini --json-schema capability probe smoke"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# G1. SKILL.md에 GEMINI_HAS_SCHEMA 선언 존재
if grep -q "^GEMINI_HAS_SCHEMA=0" "$SKILL_MD"; then
    pass "G1 — GEMINI_HAS_SCHEMA 기본값 0 선언"
else
    fail "G1 — GEMINI_HAS_SCHEMA=0 기본 선언 누락"
fi

# G2. 가용성 탐지 코드 (gemini --help | grep --json-schema)
if grep -q "gemini --help.*grep -c.*--json-schema" "$SKILL_MD"; then
    pass "G2 — --json-schema 지원 여부 probe 코드"
else
    fail "G2 — probe 명령(gemini --help | grep -c -- --json-schema) 부재"
fi

# G3. Phase 0.3 gemini 호출에 GEMINI_HAS_SCHEMA 분기 존재 (2곳)
CNT=$(grep -c 'if \[ "\$GEMINI_HAS_SCHEMA" -gt 0 \]; then' "$SKILL_MD")
if [ "$CNT" -ge 2 ]; then
    pass "G3 — SKILL.md 내 GEMINI_HAS_SCHEMA 분기 ${CNT}곳 (Phase 0.3 + Phase 1)"
else
    fail "G3 — GEMINI_HAS_SCHEMA 분기가 2곳 미만 ($CNT)"
fi

# G4. refs/cross-verification.md에도 분기 존재 (Item 6 수정 검증)
CROSS_MD="$SKILL_DIR/refs/cross-verification.md"
if grep -q 'GEMINI_HAS_SCHEMA.*gt 0' "$CROSS_MD"; then
    pass "G4 — refs/cross-verification.md에 GEMINI_HAS_SCHEMA 분기"
else
    fail "G4 — cross-verification.md가 여전히 --json-schema 하드 의존 (Item 6 미적용)"
fi

# G5. 모든 `gemini -m` 호출이 분기 근처(±10줄)에 있거나 verifier 경로인지 체크
# verifier 경로(pro-preview)는 --json-schema 없이 호출되는 경우가 있어 허용
TMP_UNGUARDED=$(mktemp)
awk '
  /GEMINI_HAS_SCHEMA/ { guard=1; guardline=NR }
  /gemini -m.*--json-schema/ {
    if (!guard || NR - guardline > 20) print FILENAME ":" NR ": " $0
  }
' "$SKILL_MD" "$CROSS_MD" "$SKILL_DIR/refs/gemini-verification.md" > "$TMP_UNGUARDED"

if [ ! -s "$TMP_UNGUARDED" ]; then
    pass "G5 — 모든 --json-schema 사용이 GEMINI_HAS_SCHEMA guard 내 (정적 검사)"
else
    fail "G5 — guard 없는 --json-schema 호출 발견:"
    cat "$TMP_UNGUARDED"
fi
rm -f "$TMP_UNGUARDED"

# G6. 미지원 시 INFO 메시지 존재
if grep -q 'gemini --json-schema 미지원 — 프롬프트 JSON' "$SKILL_MD"; then
    pass "G6 — 미지원 폴백 INFO 메시지"
else
    fail "G6 — 폴백 경로 사용자 안내 메시지 부재"
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
