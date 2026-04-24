#!/usr/bin/env bash
# tests/shell-parity.sh — round-10: test self-fulfillment 탈출
#
# SKILL.md + refs/*.md의 모든 ```bash 블록을 **실제로** bash + zsh 양쪽에서 parse check.
# HS8(bash-only `${!var}` → zsh bad substitution) 같은 shell-dialect 버그를 CI에서 선취.
#
# 실행 의도 블록만 검증 — 마크다운 prose·pseudocode 블록은 `<!-- shell-parity: skip reason=... -->`
# 주석으로 명시 표식 필요. 자동 휴리스틱 skip 금지 (self-fulfillment 재발 방지).
#
# 기존 테스트(bash-runtime-validation R1)는 bash -n으로 refs/gemini-helper.sh만 확인.
# 이 테스트는 SKILL.md 본문의 매 bash 블록으로 커버리지 확장.

set -u

# shellcheck disable=SC2155
readonly SKILL_DIR="${SKILL_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"

readonly RED=$'\033[0;31m'
readonly GREEN=$'\033[0;32m'
readonly YELLOW=$'\033[0;33m'
readonly NC=$'\033[0m'

PASS=0
FAIL=0
SKIP=0
declare -a FAIL_LOG

# 검사 대상 파일 — 실행 블록 다수 포함하는 파일
SOURCES=(
    "$SKILL_DIR/SKILL.md"
    "$SKILL_DIR/refs/codex-verification.md"
    "$SKILL_DIR/refs/gemini-verification.md"
    "$SKILL_DIR/refs/cross-verification.md"
    "$SKILL_DIR/refs/codemap-generator.md"
)

# bash·zsh binary 경로
BASH_BIN="$(command -v bash)"
ZSH_BIN="$(command -v zsh)"

if [ -z "$BASH_BIN" ] || [ -z "$ZSH_BIN" ]; then
    echo "FATAL: bash 또는 zsh가 PATH에 없음"
    exit 2
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  shell-parity test (round-10)"
echo "  SKILL_DIR: $SKILL_DIR"
echo "  bash: $BASH_BIN ($($BASH_BIN --version | head -1 | awk '{print $4}'))"
echo "  zsh:  $ZSH_BIN (v$($ZSH_BIN --version | awk '{print $2}'))"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

for src in "${SOURCES[@]}"; do
    if [ ! -f "$src" ]; then
        echo "${YELLOW}[skip] missing:${NC} $src"
        continue
    fi

    rel=$(python3 -c "import os; print(os.path.relpath('$src', '$SKILL_DIR'))")
    echo ""
    echo "── $rel"

    # Python 헬퍼로 bash 블록 + line + skip annotation 추출
    blocks_json=$(python3 - "$src" <<'PYEOF'
import re, sys, json
path = sys.argv[1]
with open(path, encoding='utf-8') as f:
    text = f.read()

# ```bash ... ``` 블록을 match (line 번호 포함)
pattern = re.compile(r'^```bash\s*\n(.*?)^```', re.DOTALL | re.MULTILINE)
results = []
for m in pattern.finditer(text):
    start_line = text[:m.start()].count('\n') + 1
    code = m.group(1)
    # 블록 선행 500자 안에 skip annotation 검색
    preceding = text[max(0, m.start()-500):m.start()]
    skip_m = re.search(r'<!--\s*shell-parity:\s*skip(?:\s+reason=([^>]*?))?\s*-->', preceding)
    skip_reason = (skip_m.group(1) or 'no reason').strip() if skip_m else None
    results.append({
        "line": start_line,
        "code": code,
        "skip": skip_reason,
    })
print(json.dumps(results))
PYEOF
    )

    count=$(echo "$blocks_json" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")
    echo "   발견된 bash 블록: $count"

    # 각 블록 추출 후 bash -n + zsh -n 실행
    idx=0
    while [ "$idx" -lt "$count" ]; do
        block_data=$(echo "$blocks_json" | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)[$idx]))")
        line_num=$(echo "$block_data" | python3 -c "import json,sys; print(json.load(sys.stdin)['line'])")
        skip_reason=$(echo "$block_data" | python3 -c "import json,sys; r=json.load(sys.stdin)['skip']; print(r or '')")

        if [ -n "$skip_reason" ]; then
            echo "   ${YELLOW}[skip L$line_num]${NC} $skip_reason"
            SKIP=$((SKIP+1))
            idx=$((idx+1))
            continue
        fi

        tmp=$(mktemp /tmp/shell-parity-XXXXXX.sh)
        echo "$block_data" | python3 -c "import json,sys; print(json.load(sys.stdin)['code'], end='')" > "$tmp"

        bash_err=$("$BASH_BIN" -n "$tmp" 2>&1) && bash_rc=0 || bash_rc=$?
        zsh_err=$("$ZSH_BIN" -n "$tmp" 2>&1) && zsh_rc=0 || zsh_rc=$?

        if [ "$bash_rc" -eq 0 ] && [ "$zsh_rc" -eq 0 ]; then
            PASS=$((PASS+1))
        elif [ "$bash_rc" -ne 0 ] && [ "$zsh_rc" -ne 0 ]; then
            # 양쪽 실패 — 아마 markdown prose 블록이 ```bash로 잘못 태그됨
            # 실행 의도 블록은 최소한 bash에선 parse돼야 함 → FAIL
            FAIL=$((FAIL+1))
            FAIL_LOG+=("$rel:$line_num — 양쪽 fail: bash rc=$bash_rc zsh rc=$zsh_rc")
            FAIL_LOG+=("   bash: $(echo "$bash_err" | head -1)")
            FAIL_LOG+=("   zsh:  $(echo "$zsh_err" | head -1)")
            echo "   ${RED}[FAIL L$line_num]${NC} 양쪽 parse 실패"
        elif [ "$bash_rc" -eq 0 ] && [ "$zsh_rc" -ne 0 ]; then
            # HS8급 — bash는 되지만 zsh에서 실패
            FAIL=$((FAIL+1))
            FAIL_LOG+=("$rel:$line_num — HS8급 bash-only 문법 (zsh 실패)")
            FAIL_LOG+=("   zsh err: $(echo "$zsh_err" | head -1)")
            echo "   ${RED}[FAIL L$line_num]${NC} bash OK / zsh FAIL (HS8급 dialect)"
        else
            # zsh는 되지만 bash에서 실패 — 드문 경우
            FAIL=$((FAIL+1))
            FAIL_LOG+=("$rel:$line_num — zsh-only 문법 (bash 실패)")
            FAIL_LOG+=("   bash err: $(echo "$bash_err" | head -1)")
            echo "   ${RED}[FAIL L$line_num]${NC} zsh OK / bash FAIL"
        fi

        rm -f "$tmp"
        idx=$((idx+1))
    done
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Total: $((PASS+FAIL+SKIP))  |  Pass: $PASS  |  Fail: $FAIL  |  Skip: $SKIP"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "실패 상세:"
    printf '  %s\n' "${FAIL_LOG[@]}"
    echo ""
    echo "${RED}❌ 실패 있음${NC}"
    echo ""
    echo "💡 수정 옵션:"
    echo "   (a) 블록을 실제 parse 가능하게 수정"
    echo "   (b) prose/pseudocode면 블록 타입을 '\`\`\`bash' → '\`\`\`text' 로 변경"
    echo "   (c) 의도적 skip: 블록 앞에 '<!-- shell-parity: skip reason=설명 -->' 주석 추가"
    exit 1
fi

echo "${GREEN}✅ 전체 통과 (bash + zsh parity 확보)${NC}"
exit 0
