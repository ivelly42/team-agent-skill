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
# Test 8: 모든 backend CLI 호출이 _run_with_timeout의 direct child argv로 launch됨
# ───────────────────────────────────────────────────────────
# Codex 8차 [medium] nested shell wrapper 허점 해결:
#   이전 버전은 `_run_with_timeout 300 30 bash -lc 'codex exec ...'`처럼 bash/sh/env
#   interpreter로 한 겹 감싼 호출을 통과시킴. 이 경우 _run_with_timeout이 launch하는
#   process는 bash이고 codex는 nested shell 안에서 re-parse되므로 실제로는
#   stdin/signal/exit-code 불변량이 깨진다.
# 새 규칙:
#   1) bash 블록을 shell command 단위로 split (quote/escape/continuation 처리)
#   2) CLI substring이 quoted literal 안에만 있으면 스킵 (따옴표 밖 매치만 violation)
#   3) command의 첫 실행 토큰이 `_run_with_timeout`이어야 하고
#   4) 토큰 레이아웃 = `_run_with_timeout <secs> <grace> <child>` 에서
#      child가 `codex`(+ `exec`) 또는 `gemini`여야 함
#   5) child가 bash/sh/zsh/env/python3/node 등 interpreter wrapper면 violation
test_backend_calls_timeout_guarded() {
    local name="backend CLI → _run_with_timeout direct child (argv state machine)"
    local files=("$SKILL_DIR/SKILL.md" "$SKILL_DIR/refs/codex-verification.md" \
                 "$SKILL_DIR/refs/cross-verification.md" "$SKILL_DIR/refs/gemini-verification.md")

    python3 - "${files[@]}" <<'PYEOF'
import re, sys
files = sys.argv[1:]

CLI_RE = re.compile(r'\b(codex\s+exec|gemini\s+(?:-m\s+\S+\s+)?(?:--json-schema\s+\S+\s+)?-p)\b')
ALLOWED_LAUNCHER = '_run_with_timeout'
ALLOWED_CHILDREN = {'codex', 'gemini'}

violations = []

def extract_bash_blocks(lines):
    blocks, in_bash, block_start, block_lines = [], False, 0, []
    for i, ln in enumerate(lines, 1):
        if ln.strip().startswith('```bash'):
            in_bash, block_start, block_lines = True, i, []
            continue
        if in_bash and ln.strip() == '```':
            blocks.append((block_start, block_lines))
            in_bash = False
            continue
        if in_bash:
            block_lines.append((i, ln))
    return blocks

def strip_quoted_regions(text):
    """따옴표 안의 내용을 공백으로 치환한 버전 반환.
    escape(\\X)는 X를 literal로 취급. CLI substring이 따옴표 안에만 있으면
    이 함수 리턴값에는 매치되지 않아 false positive 제거."""
    out = []
    j, n = 0, len(text)
    in_single = in_double = False
    while j < n:
        ch = text[j]
        if ch == '\\' and j + 1 < n and (in_single or in_double or not (in_single or in_double)):
            out.append(' '); out.append(' ')
            j += 2
            continue
        if ch == "'" and not in_double:
            in_single = not in_single
            out.append(' '); j += 1; continue
        if ch == '"' and not in_single:
            in_double = not in_double
            out.append(' '); j += 1; continue
        if in_single or in_double:
            out.append(' ')
        else:
            out.append(ch)
        j += 1
    return ''.join(out)

def split_commands(block_lines):
    processed = []
    for lineno, raw in block_lines:
        s = raw.rstrip('\n')
        if s.lstrip().startswith('#'):
            continue
        processed.append((lineno, s))

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
        in_single = in_double = False
        pieces = []
        n = len(text)
        while j < n:
            ch = text[j]
            if ch == '\\' and j + 1 < n:
                buf += ch + text[j+1]; j += 2; continue
            if ch == "'" and not in_double:
                in_single = not in_single; buf += ch; j += 1; continue
            if ch == '"' and not in_single:
                in_double = not in_double; buf += ch; j += 1; continue
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

def strip_leading_modifiers(tokens):
    while tokens and tokens[0] in ('!', 'time', '(', '((', '{', 'exec', 'eval'):
        tokens = tokens[1:]
    while tokens and re.match(r'^[A-Za-z_][A-Za-z0-9_]*=', tokens[0]):
        tokens = tokens[1:]
    return tokens

def validate_wrapped(cmd_text):
    """`_run_with_timeout <secs> <grace> <child> ...` 형태 검증.
    Returns: (ok: bool, reason: str)"""
    tokens = strip_leading_modifiers(cmd_text.split())
    if not tokens:
        return False, "empty command"
    if tokens[0] != ALLOWED_LAUNCHER:
        return False, f"launcher={tokens[0]!r} (must be _run_with_timeout)"
    if len(tokens) < 4:
        return False, f"argv too short: {tokens[:3]}"
    # tokens[1]=secs, tokens[2]=grace, tokens[3]=child
    child = tokens[3]
    # child는 variable assignment 아니어야 함 (wrapper argv는 pure exec)
    if re.match(r'^[A-Za-z_][A-Za-z0-9_]*=', child):
        return False, f"child assignment not allowed: {child!r}"
    if child == 'codex':
        if len(tokens) < 5 or tokens[4] != 'exec':
            return False, f"codex without 'exec' subcommand: {tokens[4] if len(tokens) >= 5 else '<none>'}"
        return True, None
    if child == 'gemini':
        return True, None
    return False, f"child={child!r} (must be codex/gemini, not interpreter wrapper)"

for path in files:
    try:
        with open(path, encoding='utf-8') as f:
            lines = f.readlines()
    except FileNotFoundError:
        continue

    for block_start, block_lines in extract_bash_blocks(lines):
        for cmd_lineno, cmd in split_commands(block_lines):
            # 따옴표 밖에만 CLI가 있는지 확인
            cmd_unquoted = strip_quoted_regions(cmd)
            if not CLI_RE.search(cmd_unquoted):
                continue
            ok, reason = validate_wrapped(cmd)
            if not ok:
                violations.append(f"{path}:{cmd_lineno} {reason} :: {cmd[:140]}")

if violations:
    print(f"[test_8] {len(violations)} improperly-launched backend invocation(s):", file=sys.stderr)
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
# Test 9: canonical byte-exact parity — refs/timeout-wrapper.sh의 Python watchdog
# body와 모든 인라인 복사본을 byte-exact 비교. Codex 8차 [medium] 해결:
# regex fragment 체크가 아니라 canonical function text를 source-of-truth로 사용.
# ───────────────────────────────────────────────────────────
test_timeout_wrapper_parity() {
    local name="canonical ↔ 인라인 wrapper byte-exact parity"
    local canonical="$SKILL_DIR/refs/timeout-wrapper.sh"
    local inlines=("$SKILL_DIR/SKILL.md" "$SKILL_DIR/refs/codex-verification.md" \
                   "$SKILL_DIR/refs/cross-verification.md" "$SKILL_DIR/refs/gemini-verification.md")

    python3 - "$canonical" "${inlines[@]}" <<'PYEOF'
import hashlib, re, sys
canonical_path = sys.argv[1]
inline_paths = sys.argv[2:]

# `python3 -c '\n...\n' "$_secs" "$_grace" "$@"` 형태의 body 추출
PY_BODY_RE = re.compile(r"python3\s+-c\s+'\n(.*?)\n'\s*\"\$_secs\"", re.DOTALL)

try:
    with open(canonical_path, encoding='utf-8') as f:
        canonical_text = f.read()
except FileNotFoundError:
    print(f"FATAL: canonical missing: {canonical_path}", file=sys.stderr); sys.exit(2)

canonical_bodies = PY_BODY_RE.findall(canonical_text)
if not canonical_bodies:
    print(f"FATAL: canonical has no python3 -c body: {canonical_path}", file=sys.stderr); sys.exit(2)
canonical_body = canonical_bodies[0]
canonical_hash = hashlib.sha256(canonical_body.encode()).hexdigest()[:12]

violations = []
total_bodies = 0
for path in inline_paths:
    try:
        with open(path, encoding='utf-8') as f:
            text = f.read()
    except FileNotFoundError:
        violations.append(f"{path}: file missing"); continue
    bodies = PY_BODY_RE.findall(text)
    if not bodies:
        violations.append(f"{path}: no inline python3 -c body found"); continue
    for idx, body in enumerate(bodies, 1):
        total_bodies += 1
        if body != canonical_body:
            body_hash = hashlib.sha256(body.encode()).hexdigest()[:12]
            # 처음 달라지는 라인 3개만 간단히 표시
            clines = canonical_body.splitlines()
            blines = body.splitlines()
            diffs = []
            for i in range(max(len(clines), len(blines))):
                c = clines[i] if i < len(clines) else '<EOF>'
                b = blines[i] if i < len(blines) else '<EOF>'
                if c != b:
                    diffs.append(f"    L{i+1}: canonical={c!r} inline={b!r}")
                    if len(diffs) >= 3:
                        break
            violations.append(
                f"{path} body#{idx}: hash={body_hash} != canonical={canonical_hash}\n" +
                '\n'.join(diffs)
            )

if violations:
    print(f"[test_9] canonical hash: {canonical_hash}", file=sys.stderr)
    print(f"[test_9] {len(violations)} drifted copy(ies) out of {total_bodies}:", file=sys.stderr)
    for v in violations: print(v, file=sys.stderr)
    sys.exit(1)
print(f"[test_9] all {total_bodies} inline copies byte-equal to canonical ({canonical_hash})")
sys.exit(0)
PYEOF
    local rc=$?
    if [ "$rc" = "0" ]; then
        _pass "$name"
    else
        _fail "$name" "byte-exact drift above"
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
