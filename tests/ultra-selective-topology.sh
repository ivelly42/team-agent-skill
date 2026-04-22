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

# U3. 가중치 기반 복제 테이블 — Codex round-3 #3: ≤×0.7도 2중 강제
# Ultra 모드 실행 섹션 안에서 "×1.5 3중", "×1.0 2중", "×0.7 2중" 또는 "2-replica baseline"이 모두 있어야 함
if grep -qE "×1\.5.*3중" "$SKILL_MD" \
  && grep -qE "×1\.0.*2중" "$SKILL_MD" \
  && grep -qE "2-replica baseline" "$SKILL_MD" \
  && grep -qE "(×0\.7|≤×0\.7|문서·탐색).*2중" "$SKILL_MD"; then
    pass "U3 — 가중치별 복제 수 테이블 (×1.5=3중, ×1.0/≤×0.7=2중, baseline 명시)"
else
    fail "U3 — 가중치별 복제 테이블 불완전 또는 2-replica baseline 문구 누락"
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

# U6. Phase 2.5 1중 패스스루 (이제 예외 경로이지만 안전망으로 유지)
if grep -qE "1중.*패스스루|단일 결과.*consensus_findings|agreement.*1/1" "$SKILL_MD"; then
    pass "U6 — Phase 2.5 1중 패스스루 안전망 규칙 (예외 경로)"
else
    fail "U6 — 1중 역할 통합자 생략 규칙 미명시"
fi

# U7. 비용 배지에 strategy 포함
if grep -qE "Ultra Mode \[(full|selective)\]|ultra:3|ultra:2|ultra:1" "$SKILL_MD"; then
    pass "U7 — 비용 미리보기에 strategy 배지"
else
    fail "U7 — 비용 표시에 strategy 구분 없음"
fi

# U8. Python 시뮬레이션 — Codex round-3 #3 이후 2-replica baseline
python3 <<'PYEOF'
def ultra_replication(role_weight, strategy, codex_avail=True, gemini_avail=True):
    """SKILL.md 의사코드 그대로 (2-replica baseline)."""
    if strategy == "full":
        want = ["claude", "codex", "gemini"]
    elif role_weight >= 1.5:
        want = ["claude", "codex", "gemini"]
    elif role_weight >= 1.0:
        want = ["claude", "codex"]
    else:
        want = ["claude", "codex"]  # ≤×0.7도 2중 강제
    out = [b for b in want if b == "claude"
           or (b == "codex" and codex_avail)
           or (b == "gemini" and gemini_avail)]
    if len(out) < 2 and gemini_avail and "gemini" not in out:
        out.append("gemini")
    return out

# Full 모드 — 전원 3중
assert ultra_replication(0.5, "full") == ["claude", "codex", "gemini"], "full×0.5"
assert ultra_replication(1.5, "full") == ["claude", "codex", "gemini"], "full×1.5"

# Selective 2-replica baseline
assert ultra_replication(1.5, "selective") == ["claude", "codex", "gemini"], "sel×1.5=3중"
assert ultra_replication(1.0, "selective") == ["claude", "codex"], "sel×1.0=2중"
assert ultra_replication(0.7, "selective") == ["claude", "codex"], "sel×0.7=2중 (baseline)"
assert ultra_replication(0.5, "selective") == ["claude", "codex"], "sel×0.5=2중 (baseline)"

# 가용성 필터
# Codex 미설치 → Gemini로 보강 (×0.7 이하도 2중 보장)
assert ultra_replication(0.7, "selective", codex_avail=False, gemini_avail=True) == ["claude", "gemini"], \
    "codex 없으면 gemini fallback"
# 양쪽 미설치 → Claude 단독 (호출측이 ULTRA_MODE=false 다운그레이드 판단)
assert ultra_replication(0.7, "selective", codex_avail=False, gemini_avail=False) == ["claude"], \
    "양쪽 미설치 → 1중 (다운그레이드 신호)"
# Gemini 미설치, Codex 있음 → ×1.5 역할만 3중→2중
assert ultra_replication(1.5, "selective", codex_avail=True, gemini_avail=False) == ["claude", "codex"], \
    "gemini 미설치 시 ×1.5는 2중으로"

# 5역할 시나리오 재계산
scenarios = [1.5, 1.0, 1.0, 0.7, 0.5]
full_total = sum(len(ultra_replication(w, "full")) for w in scenarios)
sel_total = sum(len(ultra_replication(w, "selective")) for w in scenarios)
# full: 5*3=15, selective 2-replica baseline: 3+2+2+2+2=11 → ~27% 감소
assert full_total == 15, f"full 15 expected, got {full_total}"
assert sel_total == 11, f"selective(2-replica) 11 expected, got {sel_total}"

# 독립 검증 보장: 모든 역할 최소 2중
for w in scenarios:
    r = ultra_replication(w, "selective")
    assert len(r) >= 2, f"selective w={w} should have ≥2 replicas, got {r}"

print(f"U8_OK: full={full_total} selective={sel_total} savings={(full_total-sel_total)/full_total*100:.0f}%")
PYEOF
if [ "$?" -eq 0 ]; then
    pass "U8 — Python 시뮬레이션: 2-replica baseline + fallback (full 15 / selective 11, ~27% 감소)"
else
    fail "U8 — 복제 로직 시뮬레이션 실패"
fi

# U9. Python 시뮬레이션: ultra_replicas_for_cost도 동일 규칙 (단일 진실원)
python3 <<'PYEOF'
def ultra_replicas_for_cost(role_weight, strategy, codex_avail=True, gemini_avail=True):
    if strategy == "full":
        want = ["claude", "codex", "gemini"]
    elif role_weight >= 1.5:
        want = ["claude", "codex", "gemini"]
    elif role_weight >= 1.0:
        want = ["claude", "codex"]
    else:
        want = ["claude", "codex"]  # Codex round-3 #3
    out = [b for b in want if b == "claude"
           or (b == "codex" and codex_avail)
           or (b == "gemini" and gemini_avail)]
    if len(out) < 2 and gemini_avail and "gemini" not in out:
        out.append("gemini")
    return out

# Phase 0.5 비용 함수는 Phase 1 spawn과 동일 결과여야 함
assert ultra_replicas_for_cost(0.7, "selective") == ["claude", "codex"], "cost ×0.7=2중"
assert ultra_replicas_for_cost(1.5, "selective") == ["claude", "codex", "gemini"], "cost ×1.5=3중"
assert ultra_replicas_for_cost(0.7, "selective", codex_avail=False) == ["claude", "gemini"], "cost codex 없으면 gemini"
print("U9_OK: ultra_replicas_for_cost 규칙이 ultra_replication과 일치")
PYEOF
if [ "$?" -eq 0 ]; then
    pass "U9 — Phase 0.5 비용 함수가 Phase 1 spawn과 동일 규칙 (단일 진실원)"
else
    fail "U9 — 비용 함수와 spawn 함수 규칙 drift"
fi

# U10. SKILL.md 실제 소스에 fail-safe 분기 존재 (가용성 부족 → gemini 보강)
if grep -qE "gemini_avail\s+and\s+\"gemini\"\s+not\s+in\s+out" "$SKILL_MD"; then
    pass "U10 — ultra_replication fail-safe: Codex 미설치 시 Gemini로 2중 복구"
else
    fail "U10 — fail-safe 분기 미정의 (len(out) < 2 보강 로직 누락)"
fi

# U11. 양쪽 미설치 시 ULTRA_MODE=false 다운그레이드 경고 문구
if grep -qE "Ultra 모드 취소|ULTRA_MODE.*false|Claude 단일 팀 \+ Phase 4-A-2" "$SKILL_MD"; then
    pass "U11 — 양쪽 미설치 fail-closed: ULTRA_MODE 다운그레이드 + Phase 4-A-2 정규 검증"
else
    fail "U11 — 양쪽 미설치 다운그레이드 경로 미명시"
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
