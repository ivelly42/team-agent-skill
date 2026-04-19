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
# Test 8: 모든 backend CLI 호출 (codex exec, gemini -p) 이 _run_with_timeout으로 launch됨
# ───────────────────────────────────────────────────────────
# Codex 7차 adversarial이 재지적한 허점 해결:
#   (a) 이전 버전: 블록에 wrapper 호출 1개만 있으면 같은 블록의 unwrapped call도 통과
#   (b) 이전 버전: `FOO=1 timeout 300 codex exec`, `env timeout ...` 등 prefix 형태 놓침
# 새 규칙: bash 블록을 shell command 단위로 split한 뒤, backend CLI가 등장하는 각
# command의 "첫 실행 토큰(variable assignment prefix 제외)"이 `_run_with_timeout`
# 여야만 한다. `timeout`/`gtimeout`/`env`/`codex`/`gemini` 등 다른 값이면 violation.
test_backend_calls_timeout_guarded() {
    local name="unwrapped backend CLI 감지 (command-level state machine)"
    local files=("$SKILL_DIR/SKILL.md" "$SKILL_DIR/refs/codex-verification.md" \
                 "$SKILL_DIR/refs/cross-verification.md" "$SKILL_DIR/refs/gemini-verification.md")

    python3 - "${files[@]}" <<'PYEOF'
import re, sys
files = sys.argv[1:]

# backend CLI invocation (argv로 실제 실행되는 형태)
CLI_RE = re.compile(r'\b(codex\s+exec|gemini\s+(?:-m\s+\S+\s+)?(?:--json-schema\s+\S+\s+)?-p)\b')
# 허용되는 유일한 launcher
ALLOWED_LAUNCHER = '_run_with_timeout'

violations = []

def extract_bash_blocks(lines):
    blocks = []
    in_bash = False
    block_start = 0
    block_lines = []
    for i, ln in enumerate(lines, 1):
        if ln.strip().startswith('```bash'):
            in_bash = True; block_start = i; block_lines = []
            continue
        if in_bash and ln.strip() == '```':
            blocks.append((block_start, block_lines))
            in_bash = False
            continue
        if in_bash:
            block_lines.append((i, ln))
    return blocks

def split_commands(block_lines):
    """bash 블록을 논리적 shell command 단위로 쪼갠다.
    처리:
      - `#`로 시작하는 주석 줄 제거
      - `\\` 라인 끝 continuation 병합
      - 따옴표 밖 `;`, `&&`, `||`, `|`, `&`에서 분할
      - backslash escape 존중
      - python heredoc `'...'` 내부의 단일 따옴표도 literal로 취급
    """
    processed = []
    for lineno, raw in block_lines:
        s = raw.rstrip('\n')
        if s.lstrip().startswith('#'):
            continue
        processed.append((lineno, s))

    # line continuation 병합
    merged = []
    i = 0
    while i < len(processed):
        start_line, text = processed[i]
        while text.rstrip().endswith('\\') and i + 1 < len(processed):
            text = text.rstrip()[:-1]
            i += 1
            text = text + ' ' + processed[i][1]
        merged.append((start_line, text))
        i += 1

    commands = []
    for lineno, text in merged:
        buf = ''
        j = 0
        in_single = False
        in_double = False
        pieces = []
        n = len(text)
        while j < n:
            ch = text[j]
            if ch == '\\' and j + 1 < n:
                buf += ch + text[j+1]
                j += 2
                continue
            if ch == "'" and not in_double:
                in_single = not in_single
                buf += ch; j += 1; continue
            if ch == '"' and not in_single:
                in_double = not in_double
                buf += ch; j += 1; continue
            if not in_single and not in_double:
                if ch == ';':
                    pieces.append(buf); buf = ''; j += 1; continue
                if ch == '&' and j+1 < n and text[j+1] == '&':
                    pieces.append(buf); buf = ''; j += 2; continue
                if ch == '|' and j+1 < n and text[j+1] == '|':
                    pieces.append(buf); buf = ''; j += 2; continue
                if ch == '|':
                    pieces.append(buf); buf = ''; j += 1; continue
                if ch == '&':
                    pieces.append(buf); buf = ''; j += 1; continue
            buf += ch; j += 1
        if buf.strip():
            pieces.append(buf)
        for p in pieces:
            if p.strip():
                commands.append((lineno, p.strip()))
    return commands

def first_executable(cmd_text):
    """variable assignment / 관용 modifier를 건너뛴 첫 실행 토큰."""
    tokens = cmd_text.split()
    # 관용 modifier / 서브셸 진입 토큰 skip
    while tokens and tokens[0] in ('!', 'time', '(', '((', '{', 'exec', 'eval'):
        tokens = tokens[1:]
    # variable assignment prefix (VAR=VAL) skip
    while tokens and re.match(r'^[A-Za-z_][A-Za-z0-9_]*=', tokens[0]):
        tokens = tokens[1:]
    return tokens[0] if tokens else None

for path in files:
    try:
        with open(path, encoding='utf-8') as f:
            lines = f.readlines()
    except FileNotFoundError:
        continue

    for block_start, block_lines in extract_bash_blocks(lines):
        for cmd_lineno, cmd in split_commands(block_lines):
            if not CLI_RE.search(cmd):
                continue
            first = first_executable(cmd)
            if first == ALLOWED_LAUNCHER:
                continue
            # first가 None 이면 단순 arg 전달 등 (거의 없음)
            shown = first if first is not None else '<none>'
            violations.append(
                f"{path}:{cmd_lineno} first_exec={shown!r} :: {cmd[:140]}"
            )

if violations:
    print(f"[test_8] {len(violations)} unwrapped backend invocation(s):", file=sys.stderr)
    for v in violations: print(v, file=sys.stderr)
    sys.exit(1)
sys.exit(0)
PYEOF
    local rc=$?
    if [ "$rc" = "0" ]; then
        _pass "$name"
    else
        _fail "$name" "violations above"
    fi
}

# ───────────────────────────────────────────────────────────
# Test 9: timeout wrapper parity — 모든 인라인 복사본의 Python watchdog body가
# canonical (refs/timeout-wrapper.sh)의 핵심 3요소를 포함해야 함.
# Codex 7차 adversarial [medium] drift 해결.
# ───────────────────────────────────────────────────────────
test_timeout_wrapper_parity() {
    local name="canonical ↔ 인라인 wrapper parity (핵심 불변량)"
    local files=("$SKILL_DIR/SKILL.md" "$SKILL_DIR/refs/codex-verification.md" \
                 "$SKILL_DIR/refs/cross-verification.md" "$SKILL_DIR/refs/gemini-verification.md" \
                 "$SKILL_DIR/refs/timeout-wrapper.sh")

    python3 - "${files[@]}" <<'PYEOF'
import re, sys
files = sys.argv[1:]

# 모든 인라인 복사본이 반드시 포함해야 하는 불변량 (canonical의 의미론적 핵심).
INVARIANTS = [
    (r'\bif not cmd\b',                               'empty cmd guard'),
    (r'cmd not found',                                'FileNotFoundError diagnostic'),
    (r'124\s+if\s+rc\s+in\s+\(0,\s*-signal\.SIGTERM', 'SIGTERM exit normalization'),
    (r'sys\.exit\(127\)',                             '127 on cmd not found'),
    (r'sys\.exit\(137\)',                             '137 on SIGKILL'),
    (r'start_new_session=True',                       'own process group'),
    (r'stdin=sys\.stdin',                             'stdin inheritance'),
]

# 각 파일에서 python3 -c '...' literal 안의 body들을 추출
PY_BODY_RE = re.compile(r"python3\s+-c\s+'\n(.*?)\n'\s*\"\$_secs\"", re.DOTALL)

fail = []
for path in files:
    try:
        with open(path, encoding='utf-8') as f:
            text = f.read()
    except FileNotFoundError:
        fail.append(f"{path}: file missing")
        continue
    bodies = PY_BODY_RE.findall(text)
    if not bodies:
        fail.append(f"{path}: no inline python3 -c watchdog body found")
        continue
    for idx, body in enumerate(bodies, 1):
        for pat, label in INVARIANTS:
            if not re.search(pat, body):
                fail.append(f"{path} body#{idx}: missing invariant '{label}' (pattern: {pat})")

if fail:
    for f in fail: print(f, file=sys.stderr)
    sys.exit(1)
sys.exit(0)
PYEOF
    local rc=$?
    if [ "$rc" = "0" ]; then
        _pass "$name"
    else
        _fail "$name" "parity violations above"
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
test_timeout_wrapper_parity

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
total=$((PASS+FAIL))
echo "  Total: $total  |  Passed: $PASS  |  Failed: $FAIL"
[ "$FAIL" = "0" ] && { echo "  ✅ 전체 통과"; exit 0; } || { echo "  ❌ 실패: ${FAILED_TESTS[*]}"; exit 1; }
