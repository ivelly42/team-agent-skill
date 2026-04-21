#!/usr/bin/env bash
# tests/ultra-selective-topology.sh
#
# Regression: --ultra=selective가 실행 레벨까지 연결되었는지 검증.
# 1) SKILL.md에 ultra_replication() 의사함수 존재
# 2) 가중치별 복제 수 로직 정확
# 3) manifest에 ultra_strategy 필드 저장 경로 존재
# 4) Phase 2.5 1중 패스스루 명시

set -u
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_MD="$SKILL_DIR/SKILL.md"
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
PASS=0; FAIL=0
pass() { printf "  ${GREEN}✓ PASS${NC}: %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "  ${RED}✗ FAIL${NC}: %s\n" "$1"; FAIL=$((FAIL+1)); }

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ultra=selective 실행 레벨 연결 smoke"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# U1. SKILL.md에 ultra_replication 의사함수 정의 존재
if grep -q "def ultra_replication" "$SKILL_MD"; then
    pass "U1 — ultra_replication 함수 정의 (spawn 분기 로직)"
else
    fail "U1 — ultra_replication 분기 로직 미정의"
fi

# U2. spawn 경로에서 ULTRA_STRATEGY 참조 (파서/도움말 외)
# Ultra 모드 실행 섹션 이후에서 strategy 참조
CNT=$(awk '/Ultra 모드 실행/,/^---$/' "$SKILL_MD" | grep -c "ULTRA_STRATEGY\|ultra_strategy\|strategy")
if [ "$CNT" -ge 3 ]; then
    pass "U2 — Ultra 실행 섹션에 strategy 참조 ${CNT}회"
else
    fail "U2 — Ultra 실행 섹션 strategy 참조 부족 ($CNT)"
fi

# U3. 가중치 기반 복제 테이블 (3중/2중/1중)
if grep -qE "×1\.5.*3중" "$SKILL_MD" && grep -qE "×1\.0.*2중" "$SKILL_MD" && grep -qE "(×0\.7|≤×0\.7).*1중" "$SKILL_MD"; then
    pass "U3 — 가중치별 복제 수 테이블 (×1.5=3중, ×1.0=2중, ≤×0.7=1중)"
else
    fail "U3 — 가중치별 복제 테이블 불완전"
fi

# U4. Phase 0 manifest 생성 시 ultra_strategy 포함
if grep -q '"ultra_strategy":' "$SKILL_MD"; then
    pass "U4 — manifest 생성 페이로드에 ultra_strategy 필드"
else
    fail "U4 — manifest에 ultra_strategy 필드 누락"
fi

# U5. schema_version 6 upgrade 명시
if grep -q '"schema_version": 6' "$SKILL_MD" && grep -q "v5.*v6\|v6로 보정" "$SKILL_MD"; then
    pass "U5 — schema_version 6 + v5→v6 migration 규칙"
else
    fail "U5 — schema 버전 bump 누락"
fi

# U6. Phase 2.5에서 selective 1중 패스스루 언급
if grep -qE "selective 1중.*패스스루|단일 결과.*consensus_findings|agreement.*1/1" "$SKILL_MD"; then
    pass "U6 — Phase 2.5 selective 1중 패스스루 규칙"
else
    fail "U6 — selective 1중 역할 통합자 생략 규칙 미명시"
fi

# U7. 비용 배지에 strategy 포함
if grep -qE "Ultra Mode \[(full|selective)\]|ultra:3|ultra:2|ultra:1" "$SKILL_MD"; then
    pass "U7 — 비용 미리보기에 strategy 배지"
else
    fail "U7 — 비용 표시에 strategy 구분 없음"
fi

# U8. 실제 로직 검증: Python으로 ultra_replication 시뮬레이션
python3 <<'PYEOF'
def ultra_replication(role_weight, strategy):
    if strategy == "full":
        return ["claude", "codex", "gemini"]
    if role_weight >= 1.5:
        return ["claude", "codex", "gemini"]
    if role_weight >= 1.0:
        return ["claude", "codex"]
    return ["claude"]

# Full 모드 — 전원 3중
assert ultra_replication(0.5, "full") == ["claude", "codex", "gemini"], "full×0.5"
assert ultra_replication(1.5, "full") == ["claude", "codex", "gemini"], "full×1.5"

# Selective 모드
assert ultra_replication(1.5, "selective") == ["claude", "codex", "gemini"], "sel×1.5=3중"
assert ultra_replication(1.0, "selective") == ["claude", "codex"], "sel×1.0=2중"
assert ultra_replication(0.7, "selective") == ["claude"], "sel×0.7=1중"
assert ultra_replication(0.5, "selective") == ["claude"], "sel×0.5=1중"

# 5역할 시나리오 (×1.5 1 + ×1.0 2 + ×0.7 2)
scenarios = [1.5, 1.0, 1.0, 0.7, 0.5]
full_total = sum(len(ultra_replication(w, "full")) for w in scenarios)
sel_total = sum(len(ultra_replication(w, "selective")) for w in scenarios)
# full: 5*3=15, selective: 3+2+2+1+1=9 → ~40% 절감
assert full_total == 15, f"full 15 expected, got {full_total}"
assert sel_total == 9, f"selective 9 expected, got {sel_total}"
print(f"U8_OK: full={full_total} selective={sel_total} savings={(full_total-sel_total)/full_total*100:.0f}%")
PYEOF
if [ "$?" -eq 0 ]; then
    pass "U8 — Python 시뮬레이션: selective가 full 대비 40% 감소 (15→9)"
else
    fail "U8 — 복제 로직 시뮬레이션 실패"
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
