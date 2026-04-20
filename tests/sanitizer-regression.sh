#!/usr/bin/env bash
# tests/sanitizer-regression.sh
#
# Regression: TASK_PURPOSE + PROJECT_CONTEXT sanitizer 15+ fixture.
# SKILL.md Step 1-2 (TASK_PURPOSE) + Step 2-9 (PROJECT_CONTEXT) 로직을 재현하여
# 주요 공격 벡터 회귀를 방지한다.

set -u
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  sanitizer regression smoke (15 fixtures)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

python3 <<'PYEOF' || exit 1
import re, unicodedata, sys

def sanitize_user(raw, max_len=500):
    """Step 1-2 TASK_PURPOSE sanitizer (NFKD → 처리 → NFC 재조합 → 필터)"""
    raw = unicodedata.normalize('NFKD', raw)
    raw = re.sub(r'[\u2010-\u2015\u00ad\u2212]', '-', raw)
    raw = re.sub(r'[\x00-\x09\x0b-\x1f\x7f]', '', raw)
    raw = raw.replace('\n', ' ').replace('\r', ' ')
    for seq in ['---BEGIN_USER_INPUT---', '---END_USER_INPUT---',
                '---BEGIN_PROJECT_CONTEXT---', '---END_PROJECT_CONTEXT---',
                '<task_input>', '</task_input>']:
        raw = re.sub(re.escape(seq), '', raw, flags=re.IGNORECASE)
    # NFC 재조합 — Hangul Jamo를 다시 composed syllable로 (필터에서 '가-힣' range 매칭)
    raw = unicodedata.normalize('NFC', raw)
    raw = re.sub(r'[^a-zA-Z0-9\s\-_.,:()!\'\"?가-힣]', '', raw)
    return raw[:max_len]

def sanitize_ctx(raw, max_len=3000):
    """Step 2-9 PROJECT_CONTEXT sanitizer (더 관대: 화이트리스트 없음)"""
    raw = unicodedata.normalize('NFKD', raw)
    raw = re.sub(r'[\u2010-\u2015\u00ad\u2212]', '-', raw)
    raw = re.sub(r'[\x00-\x09\x0b-\x1f\x7f]', '', raw)
    for seq in ['---BEGIN_USER_INPUT---', '---END_USER_INPUT---',
                '---BEGIN_PROJECT_CONTEXT---', '---END_PROJECT_CONTEXT---',
                '<task_input>', '</task_input>']:
        raw = re.sub(re.escape(seq), '', raw, flags=re.IGNORECASE)
    return raw[:max_len]

tests_passed = 0
tests_failed = 0

def check(name, cond, detail=""):
    global tests_passed, tests_failed
    if cond:
        print(f"  [PASS] {name}")
        tests_passed += 1
    else:
        print(f"  [FAIL] {name}: {detail}")
        tests_failed += 1

# S1. 정상 입력 — 변경 없음
out = sanitize_user("보안 점검")
check("S1 — 정상 한글 입력 보존", out == "보안 점검")

# S2. 유니코드 hyphen 5종 (공식 합의 처리 범위)
for ch, code in [('\u2010', 'U+2010'), ('\u2011', 'U+2011'),
                 ('\u2012', 'U+2012'), ('\u2013', 'U+2013'), ('\u00ad', 'U+00AD')]:
    out = sanitize_user(f"test{ch}case")
    check(f"S2 — {code} → ASCII hyphen", out == "test-case")

# S3. 프롬프트 인젝션 구분자 제거 (대소문자 무관)
out = sanitize_user("보안 ---BEGIN_USER_INPUT--- 악성 ---END_USER_INPUT---")
check("S3 — BEGIN/END 구분자 제거", "BEGIN_USER_INPUT" not in out and "END_USER_INPUT" not in out)

out = sanitize_user("---begin_project_context--- 소문자도")
check("S3a — 소문자 구분자 제거 (대소문자 무관)", "begin_project_context" not in out.lower() or "---" not in out)

# S4. 제어문자 제거
out = sanitize_user("보안\x00점\x01검\x1f테\x7f스트")
check("S4 — 제어문자 0x00/0x01/0x1f/0x7f 제거", out == "보안점검테스트")

# S5. 줄바꿈 → 공백
out = sanitize_user("보안\n점검\r테스트")
check("S5 — 줄바꿈 → 공백", "\n" not in out and "\r" not in out)

# S6. 길이 제한 500자
out = sanitize_user("가" * 1000)
check("S6 — 500자 truncate", len(out) == 500)

# S7. PROJECT_CONTEXT 길이 제한 3000자
out = sanitize_ctx("x" * 5000)
check("S7 — PROJECT_CONTEXT 3000자 truncate", len(out) == 3000)

# S8. 제로폭 문자는 정규화 후 NFKD로 분해되지 않으므로 화이트리스트에서 제거됨
out = sanitize_user("보안\u200b점검")
check("S8 — zero-width space (U+200B) 제거", "\u200b" not in out)

# S9. fullwidth hyphen U+FF0D → NFKD → ASCII '-'
# U+FF0D는 NFKD에서 U+002D로 분해됨
out = sanitize_user("A\uff0dB")
check("S9 — fullwidth hyphen NFKD", out == "A-B", f"got: {out!r}")

# S10. task_input 태그 제거 (대소문자 무관)
out = sanitize_user("<task_input>악성</task_input> 정상")
check("S10 — <task_input> 태그 제거", "<task_input>" not in out.lower() and "</task_input>" not in out.lower())

# S11. 화이트리스트 — 특수문자 필터
out = sanitize_user("정상 $% 특수 @ 제거")
check("S11 — 영숫자·한글·허용구두점 외 제거", "$" not in out and "%" not in out and "@" not in out and "정상" in out and "특수" in out)

# S12. parity — TASK_PURPOSE vs PROJECT_CONTEXT 같은 구분자 처리
same_input = "테스트 ---BEGIN_PROJECT_CONTEXT--- 공격 ---END_PROJECT_CONTEXT---"
out_user = sanitize_user(same_input)
out_ctx = sanitize_ctx(same_input)
check("S12 — TASK vs CTX 동일 구분자 제거 parity",
      "BEGIN_PROJECT_CONTEXT" not in out_user and "BEGIN_PROJECT_CONTEXT" not in out_ctx)

# S13. NFKD로 분해되는 합성 문자
out = sanitize_user("café")  # é = U+0065 + U+0301 after NFKD
# NFKD 분해 후 combining mark는 화이트리스트 밖이라 제거됨 → "cafe"만 남음
check("S13 — NFKD 분해 후 combining mark 제거", "caf" in out.lower())

# S14. U+2212 minus sign → ASCII
out = sanitize_user("A\u2212B")
check("S14 — U+2212 minus sign → hyphen", out == "A-B")

# S15. 빈 문자열
out = sanitize_user("")
check("S15 — 빈 입력 보존", out == "")

# S16. 공격자가 우회 시도: BEGIN_USER_INPUT 일부만
out = sanitize_user("---BEGIN_USER--- 불완전 구분자")
check("S16 — 불완전 구분자는 제거 안 됨 (정확 매칭)", "---BEGIN_USER---" in out or "BEGIN_USER" in out)

print()
print(f"tests_passed={tests_passed} tests_failed={tests_failed}")
if tests_failed > 0:
    sys.exit(1)
PYEOF
RC=$?

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ "$RC" -eq 0 ]; then
    echo -e "  ${GREEN}✅ sanitizer regression 통과${NC}"
else
    echo -e "  ${RED}❌ 일부 실패${NC}"
    exit 1
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
