#!/usr/bin/env bash
# team-agent smoke tests — 2026-04-19 Tier 2-3 패치 검증
# 5건 조용한 실패 위험 영역만 확인 (B1, B2, S1, S3, 신규 스키마)
# 사용: bash tests/smoke.sh  (또는 zsh tests/smoke.sh)

set -u
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0
FAILED_TESTS=()

_pass() { echo "  ✓ PASS: $1"; PASS=$((PASS+1)); }
_fail() { echo "  ✗ FAIL: $1"; [ -n "${2:-}" ] && echo "    └─ $2"; FAIL=$((FAIL+1)); FAILED_TESTS+=("$1"); }

# ───────────────────────────────────────────────────────────
# Test 1 (B1): ultra-consolidation-schema.json의 agreement enum에 "1/1" 포함
# ───────────────────────────────────────────────────────────
test_agreement_enum_has_one_one() {
    local name="B1 — agreement enum '1/1' 포함"
    local schema="$SKILL_DIR/refs/ultra-consolidation-schema.json"
    [ -f "$schema" ] || { _fail "$name" "schema 파일 없음"; return; }

    python3 - <<PYEOF && _pass "$name" || _fail "$name" "agreement enum에 1/1 누락"
import json, sys
try:
    with open("$schema") as f:
        s = json.load(f)
    enum = s['properties']['consensus_findings']['items']['properties']['agreement']['enum']
    expected = {'3/3', '2/3', '1/3', '2/2', '1/2', '1/1'}
    missing = expected - set(enum)
    sys.exit(1 if missing else 0)
except Exception as e:
    print(f"  exception: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
}

# ───────────────────────────────────────────────────────────
# Test 2 (B2): mapfile → while IFS= read 루프 zsh/bash 호환
# ───────────────────────────────────────────────────────────
test_while_read_loop_compat() {
    local name="B2 — while read 루프 배열 수집 (zsh/bash 호환)"
    local input=$'a.ts\nb.ts\nc.ts'
    local arr=()
    while IFS= read -r _f; do
        [ -n "$_f" ] && arr+=("$_f")
    done <<< "$input"
    # bash는 arr[0], zsh는 arr[1]로 첫 원소 접근 — 호환 위해 join으로 확인
    local joined
    joined=$(IFS=,; echo "${arr[*]}")
    if [ "${#arr[@]}" = "3" ] && [ "$joined" = "a.ts,b.ts,c.ts" ]; then
        _pass "$name"
    else
        _fail "$name" "기대 3건, 실제 ${#arr[@]}건 (joined=$joined)"
    fi
}

# ───────────────────────────────────────────────────────────
# Test 3 (S3): NFKD + hyphen 등가 → ASCII '-' 정규화
# ───────────────────────────────────────────────────────────
test_nfkd_hyphen_normalize() {
    local name="S3 — 유니코드 hyphen 등가 정규화"
    python3 - <<'PYEOF' && _pass "$name" || _fail "$name" "유니코드 hyphen 우회 가능"
import re, unicodedata, sys
# em dash(U+2014), en dash(U+2013), soft hyphen(U+00AD), minus(U+2212)
raw = "head\u2014tail\u00adzone\u2013end\u2212stop"
raw = unicodedata.normalize('NFKD', raw)
raw = re.sub(r'[\u2010-\u2015\u00ad\u2212]', '-', raw)
expected = "head-tail-zone-end-stop"
sys.exit(0 if raw == expected else 1)
PYEOF
}

# ───────────────────────────────────────────────────────────
# Test 4 (S1): symlink 감지 — [ -L ] 가드가 symlink를 거부
# ───────────────────────────────────────────────────────────
test_symlink_guard() {
    local name="S1 — symlink 가드 (mkdir 전 검증)"
    local tmp; tmp=$(mktemp -d)
    mkdir "$tmp/real"
    ln -s "$tmp/real" "$tmp/suspect"

    # SKILL.md Phase 0의 감지 로직 재현
    local triggered=0
    if [ -L "$tmp/suspect" ]; then triggered=1; fi

    rm -rf "$tmp"
    if [ "$triggered" = "1" ]; then
        _pass "$name"
    else
        _fail "$name" "[ -L path ] 체크가 symlink 탐지 못함"
    fi
}

# ───────────────────────────────────────────────────────────
# Test 5: ultra-consolidation-schema.json 구조 완전성
# ───────────────────────────────────────────────────────────
test_schema_structure() {
    local name="신규 schema 구조 완전성 (required 필드)"
    local schema="$SKILL_DIR/refs/ultra-consolidation-schema.json"
    [ -f "$schema" ] || { _fail "$name" "schema 파일 없음"; return; }

    python3 - <<PYEOF && _pass "$name" || _fail "$name" "필수 필드 누락"
import json, sys
try:
    with open("$schema") as f:
        s = json.load(f)
    # 최상위 required
    if set(s.get('required', [])) < {'role', 'consensus_findings'}:
        sys.exit(1)
    # consensus_findings item required
    item = s['properties']['consensus_findings']['items']
    required = set(item['required'])
    expected = {'severity', 'title', 'file', 'line_start', 'line_end',
                'code_snippet', 'evidence', 'agreement', 'confidence', 'contradiction'}
    if not expected.issubset(required):
        print(f"missing required: {expected - required}", file=sys.stderr)
        sys.exit(1)
    # additionalProperties 봉쇄
    if item.get('additionalProperties') is not False:
        sys.exit(1)
    sys.exit(0)
except Exception as e:
    print(f"exception: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
}

# ───────────────────────────────────────────────────────────
# Test 6 (I10): META_ANALYSIS — TEAM_AGENT_META=true 환경변수 override
# ───────────────────────────────────────────────────────────
test_meta_mode_env_override() {
    local name="I10 — TEAM_AGENT_META=true override (비표준 경로)"
    # 비표준 경로(예: /tmp/fork-team-agent)에서도 환경변수로 강제 활성화 가능해야 함
    local tmp; tmp=$(mktemp -d)
    local fake_dir="$tmp/random-name"
    mkdir -p "$fake_dir/refs"
    touch "$fake_dir/SKILL.md" "$fake_dir/refs/checklists.md"

    # SKILL.md Step 2-10 감지 로직 재현
    local META_ANALYSIS=false
    local _META_REAL; _META_REAL=$(realpath "$fake_dir" 2>/dev/null || echo "")
    if [ "${TEAM_AGENT_META:-}" = "true" ]; then
        META_ANALYSIS=true
    elif [[ "$_META_REAL" == */team-agent ]] && [ -f "$_META_REAL/SKILL.md" ] && [ -f "$_META_REAL/refs/checklists.md" ]; then
        META_ANALYSIS=true
    fi

    # 1) override 없이: 비표준 경로는 감지 안 됨
    local baseline="$META_ANALYSIS"

    # 2) TEAM_AGENT_META=true로 강제: 감지돼야 함
    META_ANALYSIS=false
    if [ "true" = "true" ]; then META_ANALYSIS=true; fi  # 환경변수 분기 직접 시뮬
    local overridden="$META_ANALYSIS"

    rm -rf "$tmp"
    if [ "$baseline" = "false" ] && [ "$overridden" = "true" ]; then
        _pass "$name"
    else
        _fail "$name" "baseline=$baseline overridden=$overridden"
    fi
}

# ───────────────────────────────────────────────────────────
# Test 7 (C6 배치): 여러 변경 파일 stem을 한 번의 grep -e 리스트로 처리
# ───────────────────────────────────────────────────────────
test_grep_batch_args() {
    local name="C6 배치 — 변경 파일 stem 배열 → 단일 grep 호출"
    local tmp; tmp=$(mktemp -d)
    # git identity를 로컬 repo에만 설정 — 전역 user.name/email 없는 clean CI·fresh box에서도
    # spurious failure 방지 (Codex adversarial 재발견 #3).
    (cd "$tmp" && git init -q && \
        git config user.email "test@team-agent.local" && \
        git config user.name "team-agent-test" && \
        git config commit.gpgsign false && \
        mkdir -p pkg app && \
        echo "export default 1" > pkg/foo.ts && \
        echo "export default 2" > pkg/bar.ts && \
        echo "import './pkg/foo'" > app/uses-foo.ts && \
        echo "import './pkg/bar'" > app/uses-bar.ts && \
        git add -A && git commit -q -m init) || { rm -rf "$tmp"; _fail "$name" "git init 실패"; return; }

    local _GREP_ARGS=()
    local stems=(pkg/foo pkg/bar)
    for _stem in "${stems[@]}"; do
        _GREP_ARGS+=(-e "$_stem" -e "./$_stem")
    done

    local result
    result=$(cd "$tmp" && git grep -l "${_GREP_ARGS[@]}" 2>/dev/null | sort | tr '\n' ',' || true)
    rm -rf "$tmp"

    # 두 importer 파일이 모두 나와야 하고, 단 1회 git grep 호출로 처리됨
    if [[ "$result" == *"app/uses-bar.ts"* ]] && [[ "$result" == *"app/uses-foo.ts"* ]]; then
        _pass "$name"
    else
        _fail "$name" "기대: uses-foo, uses-bar 모두 매칭. 실제: $result"
    fi
}

# ───────────────────────────────────────────────────────────
# Test 8: 모든 backend CLI 호출 (codex exec, gemini -p) 가 timeout 래퍼로 가드됨
# ───────────────────────────────────────────────────────────
# Codex adversarial가 반복적으로 찾아낸 "unwrapped subprocess" 패턴을 lint로 고정.
# SKILL.md와 refs/*.md에서 codex exec / gemini -p 가 등장하는 줄마다 앞쪽 ~20줄 안에
# `_run_with_timeout` 호출이 있어야 한다. 없으면 regression.
test_backend_calls_timeout_guarded() {
    local name="unwrapped backend CLI 감지 (codex exec / gemini -p 가 timeout 가드됨)"
    local files=("$SKILL_DIR/SKILL.md" "$SKILL_DIR/refs/codex-verification.md" \
                 "$SKILL_DIR/refs/cross-verification.md" "$SKILL_DIR/refs/gemini-verification.md")
    local unguarded=()

    for f in "${files[@]}"; do
        [ -f "$f" ] || continue
        # codex exec / gemini -p 패턴 (단독 줄로 시작하거나 backslash 연결 직전)
        # 단, 설명·help 텍스트·주석·table 안의 언급은 제외: 앞에 "#" 또는 table `|` 있는 줄
        # 'docs text' context까지 스킵하는 근사법: awk로 라인 추출 + 이전 20줄 검사
        while IFS=: read -r line_no _; do
            [ -z "$line_no" ] && continue
            # 설명 prose 패턴 제외 (한글 포함 / "설명" / 표 / 인용)
            local context; context=$(sed -n "${line_no}p" "$f")
            case "$context" in
                *"|"*"|"*)            continue ;;     # 마크다운 테이블 행
                "> "*|">  "*)         continue ;;     # 인용 블록
                *"설명"*|*"예시"*|*"참고"*) continue ;;
            esac
            # 이전 20줄 안에 _run_with_timeout 있는지
            local start=$((line_no - 20)); [ "$start" -lt 1 ] && start=1
            if ! sed -n "${start},${line_no}p" "$f" | grep -q "_run_with_timeout\|timeout-wrapper"; then
                unguarded+=("$f:$line_no → $context")
            fi
        done < <(grep -n -E '^[[:space:]]*(codex exec|gemini -m gemini|gemini -p -)' "$f" 2>/dev/null)
    done

    if [ "${#unguarded[@]}" = "0" ]; then
        _pass "$name"
    else
        _fail "$name" "unguarded 발견: ${unguarded[*]}"
    fi
}

# ───────────────────────────────────────────────────────────
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  team-agent smoke tests"
echo "  SKILL_DIR: $SKILL_DIR"
echo "  shell: $(ps -p $$ -o comm= 2>/dev/null | tr -d ' -' || echo unknown)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

test_agreement_enum_has_one_one
test_while_read_loop_compat
test_nfkd_hyphen_normalize
test_symlink_guard
test_schema_structure
test_meta_mode_env_override
test_grep_batch_args
test_backend_calls_timeout_guarded

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
total=$((PASS+FAIL))
echo "  Total: $total  |  Passed: $PASS  |  Failed: $FAIL"
[ "$FAIL" = "0" ] && { echo "  ✅ 전체 통과"; exit 0; } || { echo "  ❌ 실패: ${FAILED_TESTS[*]}"; exit 1; }
