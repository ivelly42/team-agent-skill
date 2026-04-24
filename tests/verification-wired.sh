#!/usr/bin/env bash
# tests/verification-wired.sh
#
# Codex round-3 Finding #2 regression:
# refs/cross-verification.md + refs/gemini-verification.md가
# _pick_gemini_model verifier + _CFG_VERIFY_SEC/_CFG_GRACE_SEC로 완전히 연결됐는지.

set -u
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CROSS_MD="$SKILL_DIR/refs/cross-verification.md"
GEMINI_MD="$SKILL_DIR/refs/gemini-verification.md"
# bug_018 대응: 3번째 verifier 경로 (단독 --codex 모드 + cross fallback)도 감사
CODEX_MD="$SKILL_DIR/refs/codex-verification.md"
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
PASS=0; FAIL=0
pass() { printf "  ${GREEN}✓ PASS${NC}: %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "  ${RED}✗ FAIL${NC}: %s\n" "$1"; FAIL=$((FAIL+1)); }

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  verifier refs config 연결 smoke (Codex round-3 #2)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# V1. cross-verification.md에 gemini-3.1-pro-preview 하드코딩 0건
CROSS_PINNED=$(grep -cE 'gemini -m gemini-3\.1-pro-preview' "$CROSS_MD" || true)
if [ "$CROSS_PINNED" -eq 0 ]; then
    pass "V1 — cross-verification.md에 하드코딩 gemini-3.1-pro-preview 0건"
else
    fail "V1 — cross-verification.md 하드코딩 ${CROSS_PINNED}건 잔존"
fi

# V2. gemini-verification.md에 gemini-3.1-pro-preview 하드코딩 0건
GEMINI_PINNED=$(grep -cE 'gemini -m gemini-3\.1-pro-preview' "$GEMINI_MD" || true)
if [ "$GEMINI_PINNED" -eq 0 ]; then
    pass "V2 — gemini-verification.md에 하드코딩 gemini-3.1-pro-preview 0건"
else
    fail "V2 — gemini-verification.md 하드코딩 ${GEMINI_PINNED}건 잔존"
fi

# V3. cross-verification.md에 _run_with_timeout 300 30 하드코딩 0건
CROSS_TIMEOUT=$(grep -cE '_run_with_timeout 300 30' "$CROSS_MD" || true)
if [ "$CROSS_TIMEOUT" -eq 0 ]; then
    pass "V3 — cross-verification.md에 하드코딩 timeout 300/30 0건"
else
    fail "V3 — cross-verification.md timeout 하드코딩 ${CROSS_TIMEOUT}건 잔존"
fi

# V4. gemini-verification.md에 _run_with_timeout 300 30 하드코딩 0건
GEMINI_TIMEOUT=$(grep -cE '_run_with_timeout 300 30' "$GEMINI_MD" || true)
if [ "$GEMINI_TIMEOUT" -eq 0 ]; then
    pass "V4 — gemini-verification.md에 하드코딩 timeout 300/30 0건"
else
    fail "V4 — gemini-verification.md timeout 하드코딩 ${GEMINI_TIMEOUT}건 잔존"
fi

# V5. cross-verification.md에 _pick_gemini_model verifier 호출 1회 이상
CROSS_PICK=$(grep -cE '_pick_gemini_model verifier' "$CROSS_MD" || true)
if [ "$CROSS_PICK" -ge 1 ]; then
    pass "V5 — cross-verification.md _pick_gemini_model verifier 호출 ${CROSS_PICK}회"
else
    fail "V5 — cross-verification.md에서 _pick_gemini_model verifier 호출 누락"
fi

# V6. gemini-verification.md에 _pick_gemini_model verifier 호출 1회 이상
GEMINI_PICK=$(grep -cE '_pick_gemini_model verifier' "$GEMINI_MD" || true)
if [ "$GEMINI_PICK" -ge 1 ]; then
    pass "V6 — gemini-verification.md _pick_gemini_model verifier 호출 ${GEMINI_PICK}회"
else
    fail "V6 — gemini-verification.md에서 _pick_gemini_model verifier 호출 누락"
fi

# V7. cross-verification.md에 $_CFG_VERIFY_SEC + $_CFG_GRACE_SEC 사용
if grep -qE '\$_CFG_VERIFY_SEC' "$CROSS_MD" && grep -qE '\$_CFG_GRACE_SEC' "$CROSS_MD"; then
    pass "V7 — cross-verification.md \$_CFG_VERIFY_SEC + \$_CFG_GRACE_SEC 참조"
else
    fail "V7 — cross-verification.md에 _CFG_ 타임아웃 변수 참조 누락"
fi

# V8. gemini-verification.md에 $_CFG_VERIFY_SEC + $_CFG_GRACE_SEC 사용
if grep -qE '\$_CFG_VERIFY_SEC' "$GEMINI_MD" && grep -qE '\$_CFG_GRACE_SEC' "$GEMINI_MD"; then
    pass "V8 — gemini-verification.md \$_CFG_VERIFY_SEC + \$_CFG_GRACE_SEC 참조"
else
    fail "V8 — gemini-verification.md에 _CFG_ 타임아웃 변수 참조 누락"
fi

# V9. Gemini 검증자 블록 안에서 모델 해석 순서 검증 —
# `_GEMINI_VERIFIER_MODEL=$(_pick_gemini_model verifier)` 할당이 실제 `gemini -m "$_GEMINI_VERIFIER_MODEL"`
# 사용 **전**에 와야 한다 (모델 해석 후 타임아웃 래퍼 안에서 CLI 호출).
export _V9_CROSS="$CROSS_MD" _V9_GEMINI="$GEMINI_MD"
python3 <<'PYEOF'
import re, sys, os
for path in [os.environ["_V9_CROSS"], os.environ["_V9_GEMINI"]]:
    with open(path, encoding='utf-8') as f:
        txt = f.read()
    assign = [m.start() for m in re.finditer(r'_GEMINI_VERIFIER_MODEL=.*_pick_gemini_model verifier', txt)]
    use = [m.start() for m in re.finditer(r'gemini -m "\$_GEMINI_VERIFIER_MODEL"', txt)]
    if not assign or not use:
        sys.stderr.write(f"{path}: assign={len(assign)} use={len(use)} — Gemini 검증자 블록 구조 누락\n")
        sys.exit(1)
    if min(assign) > min(use):
        sys.stderr.write(f"{path}: _GEMINI_VERIFIER_MODEL 사용이 할당보다 앞섬 (순서 오류)\n")
        sys.exit(1)
print("V9_OK: 양쪽 파일 모두 Gemini 모델 할당이 사용 이전")
PYEOF
if [ "$?" -eq 0 ]; then
    pass "V9 — _pick_gemini_model verifier가 _run_with_timeout 호출 이전에 해석"
else
    fail "V9 — 모델 해석 순서 오류 (타임아웃 안에서 해석 시도 가능성)"
fi

# V10. config.json candidates_verifier 배열 존재
CONFIG_JSON="$SKILL_DIR/refs/config.json"
if python3 -c "import json; c=json.load(open('$CONFIG_JSON')); assert c['gemini']['candidates_verifier']"; then
    pass "V10 — refs/config.json candidates_verifier 배열 정의 존재"
else
    fail "V10 — refs/config.json candidates_verifier 누락"
fi

# ===== bug_018 대응 — codex-verification.md 감사 =====
# 단독 --codex 모드 (SKILL.md:2304) + --cross fallback (gemini 없음 시 codex-only)
# 두 경로 모두 codex-verification.md를 Read해서 실행하므로 동일 config wiring 필요.

# V11. codex-verification.md에 _run_with_timeout 300 30 하드코딩 0건
CODEX_TIMEOUT=$(grep -cE '_run_with_timeout 300 30' "$CODEX_MD" || true)
if [ "$CODEX_TIMEOUT" -eq 0 ]; then
    pass "V11 — codex-verification.md에 하드코딩 timeout 300/30 0건 (bug_018)"
else
    fail "V11 — codex-verification.md timeout 하드코딩 ${CODEX_TIMEOUT}건 잔존"
fi

# V12. codex-verification.md에 $_CFG_VERIFY_SEC + $_CFG_GRACE_SEC 사용
if grep -qE '\$_CFG_VERIFY_SEC' "$CODEX_MD" && grep -qE '\$_CFG_GRACE_SEC' "$CODEX_MD"; then
    pass "V12 — codex-verification.md \$_CFG_VERIFY_SEC + \$_CFG_GRACE_SEC 참조"
else
    fail "V12 — codex-verification.md에 _CFG_ 타임아웃 변수 참조 누락 (bug_018)"
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
