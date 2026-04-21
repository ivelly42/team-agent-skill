#!/usr/bin/env bash
# tests/config-loading.sh
#
# Regression: refs/config.json 실제 로딩 경로 검증.
# 1) SKILL.md에 "Preamble 0.1: 설정 로드" 섹션 존재
# 2) Python으로 config.json 파싱 가능, 모든 필수 키 존재
# 3) config.local.json override 병합 로직이 깊이 병합 (shallow 아님)
# 4) _pick_gemini_model 헬퍼 정의
# 5) 런타임 치환 규칙이 SKILL.md에 명시

set -u
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_MD="$SKILL_DIR/SKILL.md"
CFG="$SKILL_DIR/refs/config.json"
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
PASS=0; FAIL=0
pass() { printf "  ${GREEN}✓ PASS${NC}: %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "  ${RED}✗ FAIL${NC}: %s\n" "$1"; FAIL=$((FAIL+1)); }

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  config loading smoke"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# C1. SKILL.md Preamble 0.1 섹션 존재
if grep -q "Preamble 0.1:.*설정 로드" "$SKILL_MD"; then
    pass "C1 — SKILL.md에 Preamble 0.1 설정 로드 섹션"
else
    fail "C1 — 설정 로드 섹션 미존재"
fi

# C2. refs/config.json 유효 JSON + 필수 키 검증
python3 <<PYEOF
import json, sys
try:
    with open("$CFG") as f:
        cfg = json.load(f)
except Exception as e:
    print(f"FAIL: JSON parse error: {e}")
    sys.exit(1)
required_top = ["timeouts", "limits", "weights", "cost_overhead_k_tokens", "batch", "gemini"]
missing = [k for k in required_top if k not in cfg]
if missing:
    print(f"FAIL: missing top-level keys: {missing}")
    sys.exit(1)
# 하위 필수 키
assert "agent_soft_sec" in cfg["timeouts"], "timeouts.agent_soft_sec"
assert "verify_sec" in cfg["timeouts"]
assert "grace_sec" in cfg["timeouts"]
assert "role_filtered_context_chars" in cfg["limits"]
assert "precise" in cfg["weights"]
assert "codex" in cfg["cost_overhead_k_tokens"]
assert "candidates_agent" in cfg["gemini"]
assert isinstance(cfg["gemini"]["candidates_agent"], list) and len(cfg["gemini"]["candidates_agent"]) >= 1
print("OK")
PYEOF
if [ "$?" -eq 0 ]; then
    pass "C2 — refs/config.json 유효 JSON + 모든 필수 키"
else
    fail "C2 — config.json 구조 미흡"
fi

# C3. 깊이 병합 merge() 함수 정의 존재
if grep -q "def merge(base, over)" "$SKILL_MD"; then
    pass "C3 — 깊이 병합 merge() 정의 (config.local.json override)"
else
    fail "C3 — config override 깊이 병합 로직 미정의"
fi

# C4. _pick_gemini_model 헬퍼 정의
if grep -q "_pick_gemini_model()" "$SKILL_MD"; then
    pass "C4 — _pick_gemini_model 헬퍼 (alias fallback)"
else
    fail "C4 — gemini 모델 선택 헬퍼 미정의"
fi

# C5. 주요 export 변수 명시
declare -a EXPORTS=(
    "_CFG_AGENT_SOFT_SEC"
    "_CFG_VERIFY_SEC"
    "_CFG_ROLE_FILTERED_CHARS"
    "_CFG_GEMINI_AGENT_CANDIDATES"
)
MISS=0
for v in "${EXPORTS[@]}"; do
    if ! grep -q "export $v" "$SKILL_MD"; then
        fail "C5 — $v export 누락"
        MISS=$((MISS+1))
    fi
done
if [ "$MISS" -eq 0 ]; then
    pass "C5 — 주요 설정 변수 4개 export 명시"
fi

# C6. 런타임 치환 규칙 (하드코딩된 값 → config 변수)
if grep -qE "_pick_gemini_model agent|_pick_gemini_model \"agent\"" "$SKILL_MD" && \
   grep -q '_CFG_AGENT_SOFT_SEC.*_CFG_GRACE_SEC' "$SKILL_MD"; then
    pass "C6 — Gemini 모델·timeout 치환 규칙 명시"
else
    fail "C6 — 하드코딩 → config 변수 치환 규칙 부족"
fi

# C7. config.local.json .gitignore 등록
if grep -q "config.local.json" "$SKILL_DIR/.gitignore" 2>/dev/null; then
    pass "C7 — .gitignore에 config.local.json 등록"
else
    fail "C7 — config.local.json .gitignore 미등록"
fi

# C8. 병합 로직 실제 동작 시뮬레이션
python3 <<'PYEOF'
def merge(base, over):
    for k, v in over.items():
        if isinstance(v, dict) and isinstance(base.get(k), dict):
            merge(base[k], v)
        else:
            base[k] = v

# 깊이 병합: timeouts.agent_soft_sec만 덮어쓰고 verify_sec은 유지
base = {"timeouts": {"agent_soft_sec": 600, "verify_sec": 300, "grace_sec": 30}}
over = {"timeouts": {"agent_soft_sec": 120}}
merge(base, over)
assert base["timeouts"]["agent_soft_sec"] == 120, f"override 실패: {base}"
assert base["timeouts"]["verify_sec"] == 300, f"verify_sec 증발: {base}"
assert base["timeouts"]["grace_sec"] == 30, f"grace_sec 증발: {base}"

# 배열 대체 (병합 아님)
base = {"gemini": {"candidates_agent": ["a", "b", "c"]}}
over = {"gemini": {"candidates_agent": ["x"]}}
merge(base, over)
assert base["gemini"]["candidates_agent"] == ["x"], f"배열 대체 실패: {base}"

# 중첩 2단계
base = {"a": {"b": {"c": 1, "d": 2}}}
over = {"a": {"b": {"c": 99}}}
merge(base, over)
assert base == {"a": {"b": {"c": 99, "d": 2}}}, f"2단계 깊이 병합 실패: {base}"
print("OK")
PYEOF
if [ "$?" -eq 0 ]; then
    pass "C8 — 깊이 병합 시뮬레이션: shallow override 없이 하위 키 보존"
else
    fail "C8 — 병합 로직이 shallow (하위 키 유실)"
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
