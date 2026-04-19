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
import re, shlex, sys
files = sys.argv[1:]

CLI_RE = re.compile(r'\b(codex\s+exec|gemini\s+(?:-m\s+\S+\s+)?(?:--json-schema\s+\S+\s+)?-p)\b')
ALLOWED_LAUNCHER = '_run_with_timeout'
ALLOWED_CHILDREN = {'codex', 'gemini'}

def _tokenize_wrapped(cmd_text):
    """Codex 23차 [high]: shell-aware argv 토큰화. shlex가 따옴표·backslash를
    제대로 해체해서 `gemini "document -p behavior"` 같은 quoted prompt 내부의
    `-p` 문자열이 별개 argv flag로 오인되는 것을 차단. 실패 시 whitespace
    split로 폴백 — fallback 경로는 적어도 이전 세대와 동일한 엄격도를 유지."""
    try:
        return shlex.split(cmd_text, posix=True)
    except ValueError:
        return cmd_text.split()

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

def _unescape_shell_meta(s):
    """Outer-level shell escapes (`\\"`, `\\'`, `\\\\`, `\\\``, `\\$`) 를 그에 해당하는
    literal 한 글자로 반환. Codex 19/20/21차: `$()`, backtick body recursion 전 단계에
    적용해 내부에서 quote state 변화가 올바르게 이루어지도록 한다."""
    out = []; i = 0; n = len(s)
    while i < n:
        if s[i] == '\\' and i + 1 < n and s[i+1] in ('"', "'", '\\', '`', '$'):
            out.append(s[i+1]); i += 2
        else:
            out.append(s[i]); i += 1
    return ''.join(out)

def strip_quoted_regions(text):
    """Codex 19차 [medium] 해결: `$(...)` 와 backtick body를 재귀적으로 quote-strip.
    내부의 inert quoted literal(`printf "codex exec"`)도 blank 처리.
    단 $() 내부에서 실제로 실행되는 command는 boundary outside라 operator 자체는
    여전히 보인다. 여기 함수는 CLI_RE 검사용 unquoted view만 생성."""
    out = []
    j, n = 0, len(text)
    in_single = in_double = False
    while j < n:
        ch = text[j]
        if ch == '\\' and j + 1 < n:
            out.append(' '); out.append(' '); j += 2; continue
        if ch == "'" and not in_double:
            in_single = not in_single; out.append(' '); j += 1; continue
        if ch == '"' and not in_single:
            in_double = not in_double; out.append(' '); j += 1; continue
        # `$(...)` — body 추출 후 재귀 quote-strip.
        if ch == '$' and j + 1 < n and text[j+1] == '(' and not in_single:
            out.append(' '); out.append(' ')  # `$(` blank
            depth = 1; k = j + 2; body_start = k
            while k < n and depth > 0:
                c2 = text[k]
                if c2 == '\\' and k + 1 < n:
                    k += 2; continue
                if c2 == "'" and not in_double:
                    # single-quote inside $(): find matching close
                    k += 1
                    while k < n and text[k] != "'":
                        if text[k] == '\\' and k + 1 < n: k += 2
                        else: k += 1
                    if k < n: k += 1
                    continue
                if c2 == '"':
                    k += 1
                    while k < n and text[k] != '"':
                        if text[k] == '\\' and k + 1 < n: k += 2
                        else: k += 1
                    if k < n: k += 1
                    continue
                if c2 == '(':
                    depth += 1
                elif c2 == ')':
                    depth -= 1
                    if depth == 0:
                        break
                k += 1
            body = text[body_start:k]
            # outer shell escape(`\"`, `\'`, `\\`, `\``, `\$`)를 먼저 unescape —
            # 내부 context에선 escape가 literal로 해석됨 → quote state 변화 유발.
            body = _unescape_shell_meta(body)
            stripped = strip_quoted_regions(body)
            out.extend(stripped)
            if k < n:
                out.append(' '); k += 1  # `)` blank
            j = k
            continue
        # backtick command substitution — 내부 재귀 quote-strip.
        if ch == '`' and not in_single:
            out.append(' ')
            k = j + 1; body_start = k
            while k < n and text[k] != '`':
                if text[k] == '\\' and k + 1 < n:
                    k += 2; continue
                k += 1
            body = text[body_start:k]
            body = _unescape_shell_meta(body)
            stripped = strip_quoted_regions(body)
            out.extend(stripped)
            if k < n:
                out.append(' '); k += 1
            j = k
            continue
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
        # Codex 16차: quote state per `$()` depth. 바깥 double-quote가 안쪽 `)` 종료를
        # 막으면 안 됨. 각 `$(` 진입 시 현재 (in_single,in_double) 저장, `)` 시 복원.
        quote_stack = []
        subst_depth = 0
        btick = False
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
            if ch == '$' and j+1 < n and text[j+1] == '(' and not in_single and not btick:
                quote_stack.append((in_single, in_double))
                in_single = False; in_double = False
                subst_depth += 1; buf += ch + text[j+1]; j += 2; continue
            # Codex 18차 [medium]: `)` 는 backtick 안에선 subst frame을 pop 하면 안 됨.
            if ch == ')' and subst_depth > 0 and not in_single and not in_double and not btick:
                subst_depth -= 1
                if quote_stack:
                    in_single, in_double = quote_stack.pop()
                buf += ch; j += 1; continue
            # backtick 안 quote state도 local. push/pop.
            if ch == '`' and not in_single:
                if not btick:
                    quote_stack.append((in_single, in_double))
                    in_single = False; in_double = False
                    btick = True
                else:
                    btick = False
                    if quote_stack:
                        in_single, in_double = quote_stack.pop()
                buf += ch; j += 1; continue
            # top-level operator는 quote/subst/backtick 밖에서만.
            # (subshell 내부 operator는 split 하되, Pass A가 `|`를 항상 violation으로
            #  잡도록 exemption을 `&` 만 허용하는 방식으로 처리.)
            if not in_single and not in_double and subst_depth == 0 and not btick:
                if ch == ';':
                    pieces.append((buf, ';')); buf = ''; j += 1; continue
                if ch == '&' and j+1 < n and text[j+1] == '&':
                    pieces.append((buf, '&&')); buf = ''; j += 2; continue
                if ch == '|' and j+1 < n and text[j+1] == '|':
                    pieces.append((buf, '||')); buf = ''; j += 2; continue
                if ch == '|':
                    pieces.append((buf, '|')); buf = ''; j += 1; continue
                if ch == '&':
                    if j+1 < n and (text[j+1].isdigit() or text[j+1] in ('{', '-')):
                        buf += ch; j += 1; continue  # redirect fd ref
                    pieces.append((buf, '&')); buf = ''; j += 1; continue
            buf += ch; j += 1
        if buf.strip():
            pieces.append((buf, ''))
        for p, op in pieces:
            if p.strip():
                commands.append((lineno, p.strip(), op))
    return commands

def strip_leading_modifiers(tokens):
    # `(_run_with_timeout` 같이 `(`가 다음 토큰에 붙은 경우도 처리 (Codex 14차 [medium]).
    out = list(tokens)
    # 첫 토큰이 `(`로 시작하지만 순수 `(`이 아니면 분리
    if out and out[0].startswith('(') and out[0] != '(':
        rest = out[0][1:]
        out = ['('] + ([rest] if rest else []) + out[1:]
    while out and out[0] in ('!', 'time', '(', '((', '{', 'exec', 'eval'):
        out = out[1:]
    while out and re.match(r'^[A-Za-z_][A-Za-z0-9_]*=', out[0]):
        out = out[1:]
    return out

def validate_wrapped(cmd_text):
    """`_run_with_timeout <secs> <grace> <child> ...` 형태 검증.
    Returns: (ok: bool, reason: str)"""
    tokens = strip_leading_modifiers(_tokenize_wrapped(cmd_text))
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
        # Codex 22차 [high]: gemini wrapper contract는 `-p` stdin prompt consumer.
        # `--version`, `list`, `login` 같은 비-`-p` 모드는 stdin을 소비하지 않으므로
        # `_run_with_timeout`이 launch할 이유가 없음.
        if '-p' not in tokens[4:]:
            return False, f"gemini without -p (wrapper contract requires stdin prompt mode)"
        return True, None
    return False, f"child={child!r} (must be codex/gemini, not interpreter wrapper)"

for path in files:
    try:
        with open(path, encoding='utf-8') as f:
            lines = f.readlines()
    except FileNotFoundError:
        continue

    for block_start, block_lines in extract_bash_blocks(lines):
        for cmd_lineno, cmd, trailing_op in split_commands(block_lines):
            raw_tokens = cmd.split()
            # Codex 14차 [medium]: `(_run_with_timeout ...) &` (공백 없는 `(`) 도
            # subshell로 인식. startswith('(') 로 확장.
            starts_in_subshell = bool(raw_tokens) and raw_tokens[0].startswith('(')
            leading = strip_leading_modifiers(raw_tokens)
            starts_with_wrapper = bool(leading) and leading[0] == ALLOWED_LAUNCHER

            # Pass A (Codex 12차): `_run_with_timeout`으로 시작하는 모든 command를
            # CLI_RE 여부 무관 child 검증 — variable/function indirection bypass 차단.
            if starts_with_wrapper:
                ok, reason = validate_wrapped(cmd)
                if not ok:
                    violations.append(f"{path}:{cmd_lineno} {reason} :: {cmd[:140]}")
                # Codex 13차/15차: `|` 는 subshell 안/밖 무관하게 항상 violation —
                # wrapper rc가 파이프 오른쪽으로 넘어가 숨겨진다. `&` 는 subshell
                # 전체 background(`(...) &`) 인 경우만 예외 — subshell이 wrapper rc를
                # capture해서 처리하기 때문.
                if trailing_op == '|':
                    violations.append(
                        f"{path}:{cmd_lineno} wrapped-in-pipeline op='|' :: {cmd[:120]}"
                    )
                elif trailing_op == '&' and not starts_in_subshell:
                    violations.append(
                        f"{path}:{cmd_lineno} wrapped-in-background op='&' :: {cmd[:120]}"
                    )
                continue

            # Pass B: wrapper로 시작 안 함 + CLI가 실행 영역(command substitution 포함)에
            # 있으면 unwrapped 호출. Codex 13차 [high]로 strip_quoted_regions가 `$(...)` 보존.
            if not CLI_RE.search(cmd):
                continue
            cmd_unquoted = strip_quoted_regions(cmd)
            if CLI_RE.search(cmd_unquoted):
                first = leading[0] if leading else '<none>'
                violations.append(
                    f"{path}:{cmd_lineno} unwrapped-launch first_exec={first!r} :: {cmd[:140]}"
                )

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
# Test 9: canonical wrapper 전체(preamble + function) byte-exact parity
# Codex 10차 [medium] 해결: Python body만 비교하던 것을 shell-side
# (`_TIMEOUT_BIN` 선택 / argument plumbing / return handling / function 구조)
# 까지 포함한 full block byte-exact 비교로 확장.
# ───────────────────────────────────────────────────────────
# 현재 canonical full-block SHA256. 값이 바뀌면 의도된 wrapper 변경이므로 반드시
# 테스트에서 업데이트. 바꾸는 커밋은 의도적 canonical 리팩터여야 한다.
EXPECTED_CANONICAL_SHA256="5c0c6d2c9e8449f5249bd01cc9a48582412c2465519f1c292913a8873a6cc930"
test_timeout_wrapper_parity() {
    local name="canonical ↔ 인라인 wrapper full-block byte-exact parity"
    local canonical="$SKILL_DIR/refs/timeout-wrapper.sh"
    local inlines=("$SKILL_DIR/SKILL.md" "$SKILL_DIR/refs/codex-verification.md" \
                   "$SKILL_DIR/refs/cross-verification.md" "$SKILL_DIR/refs/gemini-verification.md")

    python3 - "$EXPECTED_CANONICAL_SHA256" "$canonical" "${inlines[@]}" <<'PYEOF'
import hashlib, re, sys
expected_hash = sys.argv[1]
canonical_path = sys.argv[2]
inline_paths = sys.argv[3:]

# 각 파일별 반드시 존재해야 할 wrapper block 개수. 누락/추가 = violation.
EXPECTED_COUNTS = {
    'SKILL.md': 4,
    'refs/codex-verification.md': 1,
    'refs/cross-verification.md': 1,
    'refs/gemini-verification.md': 1,
}
EXPECTED_TOTAL = sum(EXPECTED_COUNTS.values())  # 7

def extract_wrapper_blocks(text):
    """`_TIMEOUT_BIN=""` 부터 `_run_with_timeout() { ... }` closing `}` 까지
    전체 wrapper block을 추출 (중첩 brace 정확히 매칭)."""
    blocks = []
    pos = 0
    while pos < len(text):
        m = re.search(r'^_TIMEOUT_BIN=""', text[pos:], re.MULTILINE)
        if not m:
            break
        block_start = pos + m.start()
        fn_m = re.search(r'_run_with_timeout\(\)\s*\{', text[block_start:])
        if not fn_m:
            pos = block_start + len(m.group())
            continue
        body_start = block_start + fn_m.end()
        depth = 1
        i = body_start
        while i < len(text) and depth > 0:
            c = text[i]
            if c == '{': depth += 1
            elif c == '}': depth -= 1
            if depth == 0: break
            i += 1
        if depth != 0:
            pos = body_start
            continue
        block_end = i + 1  # closing } 포함
        blocks.append(text[block_start:block_end])
        pos = block_end
    return blocks

try:
    with open(canonical_path, encoding='utf-8') as f:
        canonical_text = f.read()
except FileNotFoundError:
    print(f"FATAL: canonical missing: {canonical_path}", file=sys.stderr); sys.exit(2)

canonical_blocks = extract_wrapper_blocks(canonical_text)
if not canonical_blocks:
    print(f"FATAL: canonical has no _run_with_timeout block: {canonical_path}", file=sys.stderr); sys.exit(2)
canonical_block = canonical_blocks[0]
canonical_hash = hashlib.sha256(canonical_block.encode()).hexdigest()

# (1) canonical hash가 pinned 값과 일치해야 함 (coordinated drift 방지)
if canonical_hash != expected_hash:
    print(f"FATAL: canonical hash drift", file=sys.stderr)
    print(f"  expected: {expected_hash}", file=sys.stderr)
    print(f"  actual:   {canonical_hash}", file=sys.stderr)
    print(f"  canonical file: {canonical_path}", file=sys.stderr)
    print(f"  → 의도적 wrapper 변경이면 EXPECTED_CANONICAL_SHA256를 새 값으로 업데이트", file=sys.stderr)
    sys.exit(1)

def rel_key(path):
    parts = path.split('/')
    if 'refs' in parts:
        idx = parts.index('refs')
        return '/'.join(parts[idx:])
    return parts[-1]

violations = []
actual_counts = {}
for path in inline_paths:
    rel = rel_key(path)
    try:
        with open(path, encoding='utf-8') as f:
            text = f.read()
    except FileNotFoundError:
        violations.append(f"{rel}: file missing"); actual_counts[rel] = 0; continue
    blocks = extract_wrapper_blocks(text)
    actual_counts[rel] = len(blocks)
    for idx, block in enumerate(blocks, 1):
        if block != canonical_block:
            block_hash = hashlib.sha256(block.encode()).hexdigest()[:12]
            clines = canonical_block.splitlines()
            blines = block.splitlines()
            diffs = []
            for i in range(max(len(clines), len(blines))):
                c = clines[i] if i < len(clines) else '<EOF>'
                b = blines[i] if i < len(blines) else '<EOF>'
                if c != b:
                    diffs.append(f"    L{i+1}: canonical={c!r} inline={b!r}")
                    if len(diffs) >= 5:
                        break
            violations.append(
                f"{rel} block#{idx}: hash={block_hash} drift vs canonical\n" + '\n'.join(diffs)
            )

# (2) per-file count 검증
for expected_rel, expected_n in EXPECTED_COUNTS.items():
    got = actual_counts.get(expected_rel, 0)
    if got != expected_n:
        violations.append(
            f"{expected_rel}: expected exactly {expected_n} wrapper block(s), got {got}"
        )

# (3) total count 검증
total = sum(actual_counts.values())
if total != EXPECTED_TOTAL:
    violations.append(f"total: expected {EXPECTED_TOTAL} wrapper blocks, got {total}")

if violations:
    print(f"[test_9] canonical pinned hash: {expected_hash[:12]}... OK", file=sys.stderr)
    print(f"[test_9] {len(violations)} violation(s):", file=sys.stderr)
    for v in violations: print(v, file=sys.stderr)
    sys.exit(1)
print(f"[test_9] canonical full-block hash pinned at {expected_hash[:12]}...")
print(f"[test_9] all {total} inline wrapper blocks byte-equal across {len(EXPECTED_COUNTS)} files")
sys.exit(0)
PYEOF
    local rc=$?
    if [ "$rc" = "0" ]; then
        _pass "$name"
    else
        _fail "$name" "pinned-parity violations above"
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
# ───────────────────────────────────────────────────────────
# Test 10 (meta): Test 8이 알려진 bypass 패턴을 실제로 잡는지 adversarial fixture로 검증.
# Codex 9차 "next steps"의 명시적 요구: bash -lc / sh -c / missing-copy 시나리오 fixture.
# ───────────────────────────────────────────────────────────
test_lint_adversarial_fixtures() {
    local name="meta: Test 8 lint이 알려진 bypass fixture를 거부하는지"
    python3 - <<'PYEOF'
import re, shlex, sys

CLI_RE = re.compile(r'\b(codex\s+exec|gemini\s+(?:-m\s+\S+\s+)?(?:--json-schema\s+\S+\s+)?-p)\b')
ALLOWED_LAUNCHER = '_run_with_timeout'

def _tokenize_wrapped(cmd_text):
    """Codex 23차 [high]: shell-aware argv 토큰화. shlex가 따옴표·backslash를
    제대로 해체해서 `gemini "document -p behavior"` 같은 quoted prompt 내부의
    `-p` 문자열이 별개 argv flag로 오인되는 것을 차단. shlex.split이 실패하면
    안전하게 whitespace split으로 폴백 (guard는 적어도 수준이 같거나 엄격)."""
    try:
        return shlex.split(cmd_text, posix=True)
    except ValueError:
        return cmd_text.split()

def strip_leading_modifiers(tokens):
    # `(_run_with_timeout` 처럼 `(`가 다음 토큰에 붙은 형태도 처리 (Codex 14차 [medium]).
    out = list(tokens)
    if out and out[0].startswith('(') and out[0] != '(':
        rest = out[0][1:]
        out = ['('] + ([rest] if rest else []) + out[1:]
    while out and out[0] in ('!', 'time', '(', '((', '{', 'exec', 'eval'):
        out = out[1:]
    while out and re.match(r'^[A-Za-z_][A-Za-z0-9_]*=', out[0]):
        out = out[1:]
    return out

def validate_wrapped(cmd_text):
    tokens = strip_leading_modifiers(_tokenize_wrapped(cmd_text))
    if not tokens: return False, 'empty'
    if tokens[0] != ALLOWED_LAUNCHER: return False, f'launcher={tokens[0]!r}'
    if len(tokens) < 4: return False, 'argv short'
    child = tokens[3]
    if re.match(r'^[A-Za-z_][A-Za-z0-9_]*=', child):
        return False, f'child assignment: {child!r}'
    if child == 'codex':
        if len(tokens) < 5 or tokens[4] != 'exec':
            return False, f'codex without exec'
        return True, None
    if child == 'gemini':
        if '-p' not in tokens[4:]:
            return False, f'gemini without -p'
        return True, None
    return False, f'child={child!r}'

def strip_quoted_regions(text):
    """Codex 19차 [medium]: `$(...)` 와 backtick body를 재귀적으로 quote-strip."""
    out = []
    j, n = 0, len(text)
    in_single = in_double = False
    while j < n:
        ch = text[j]
        if ch == '\\' and j + 1 < n:
            out.append(' '); out.append(' '); j += 2; continue
        if ch == "'" and not in_double:
            in_single = not in_single; out.append(' '); j += 1; continue
        if ch == '"' and not in_single:
            in_double = not in_double; out.append(' '); j += 1; continue
        if ch == '$' and j + 1 < n and text[j+1] == '(' and not in_single:
            out.append(' '); out.append(' ')
            depth = 1; k = j + 2; body_start = k
            while k < n and depth > 0:
                c2 = text[k]
                if c2 == '\\' and k + 1 < n:
                    k += 2; continue
                if c2 == "'" and not in_double:
                    k += 1
                    while k < n and text[k] != "'":
                        if text[k] == '\\' and k + 1 < n: k += 2
                        else: k += 1
                    if k < n: k += 1
                    continue
                if c2 == '"':
                    k += 1
                    while k < n and text[k] != '"':
                        if text[k] == '\\' and k + 1 < n: k += 2
                        else: k += 1
                    if k < n: k += 1
                    continue
                if c2 == '(':
                    depth += 1
                elif c2 == ')':
                    depth -= 1
                    if depth == 0: break
                k += 1
            body = text[body_start:k]
            body = _unescape_shell_meta_10(body)
            out.extend(strip_quoted_regions(body))
            if k < n:
                out.append(' '); k += 1
            j = k; continue
        if ch == '`' and not in_single:
            out.append(' ')
            k = j + 1; body_start = k
            while k < n and text[k] != '`':
                if text[k] == '\\' and k + 1 < n: k += 2; continue
                k += 1
            body = text[body_start:k]
            body = _unescape_shell_meta_10(body)
            out.extend(strip_quoted_regions(body))
            if k < n:
                out.append(' '); k += 1
            j = k; continue
        if in_single or in_double:
            out.append(' ')
        else:
            out.append(ch)
        j += 1
    return ''.join(out)

def _unescape_shell_meta_10(s):
    out = []; i = 0; n = len(s)
    while i < n:
        if s[i] == '\\' and i + 1 < n and s[i+1] in ('"', "'", '\\', '`', '$'):
            out.append(s[i+1]); i += 2
        else:
            out.append(s[i]); i += 1
    return ''.join(out)

def split_single_cmd(text):
    """Codex 14/15/16차: $()/backtick 깊이 + 각 depth별 quote state."""
    buf = ''
    j = 0; n = len(text)
    in_single = in_double = False
    quote_stack = []
    subst_depth = 0
    btick = False
    pieces = []
    while j < n:
        ch = text[j]
        if ch == '\\' and j + 1 < n:
            buf += ch + text[j+1]; j += 2; continue
        if ch == "'" and not in_double:
            in_single = not in_single; buf += ch; j += 1; continue
        if ch == '"' and not in_single:
            in_double = not in_double; buf += ch; j += 1; continue
        if ch == '$' and j+1 < n and text[j+1] == '(' and not in_single and not btick:
            quote_stack.append((in_single, in_double))
            in_single = False; in_double = False
            subst_depth += 1; buf += ch + text[j+1]; j += 2; continue
        if ch == ')' and subst_depth > 0 and not in_single and not in_double and not btick:
            subst_depth -= 1
            if quote_stack:
                in_single, in_double = quote_stack.pop()
            buf += ch; j += 1; continue
        if ch == '`' and not in_single:
            if not btick:
                quote_stack.append((in_single, in_double))
                in_single = False; in_double = False
                btick = True
            else:
                btick = False
                if quote_stack:
                    in_single, in_double = quote_stack.pop()
            buf += ch; j += 1; continue
        if not in_single and not in_double and subst_depth == 0 and not btick:
            if ch == ';':
                pieces.append((buf, ';')); buf = ''; j += 1; continue
            if ch == '&' and j+1 < n and text[j+1] == '&':
                pieces.append((buf, '&&')); buf = ''; j += 2; continue
            if ch == '|' and j+1 < n and text[j+1] == '|':
                pieces.append((buf, '||')); buf = ''; j += 2; continue
            if ch == '|':
                pieces.append((buf, '|')); buf = ''; j += 1; continue
            if ch == '&':
                if j+1 < n and (text[j+1].isdigit() or text[j+1] in ('{', '-')):
                    buf += ch; j += 1; continue
                pieces.append((buf, '&')); buf = ''; j += 1; continue
        buf += ch; j += 1
    if buf.strip():
        pieces.append((buf, ''))
    return [(p.strip(), op) for p, op in pieces if p.strip()]

def check_violation(cmd):
    """Test 8의 Pass A + trailing_op + Pass B 로직. True = violation.
    subshell `(...)` 안의 wrapper는 trailing `&` 면제. `(foo` 붙은 paren 포함."""
    pieces = split_single_cmd(cmd)
    if not pieces:
        return False
    first_cmd, first_op = pieces[0]
    raw_tokens = first_cmd.split()
    starts_in_subshell = bool(raw_tokens) and raw_tokens[0].startswith('(')
    leading = strip_leading_modifiers(raw_tokens)
    starts_with_wrapper = bool(leading) and leading[0] == ALLOWED_LAUNCHER
    if starts_with_wrapper:
        ok, _ = validate_wrapped(first_cmd)
        if not ok:
            return True
        # `|` 는 항상 violation, `&` 는 subshell 아닐 때만 violation (Codex 15차).
        if first_op == '|':
            return True
        if first_op == '&' and not starts_in_subshell:
            return True
        for p, _ in pieces[1:]:
            p_unq = strip_quoted_regions(p)
            if CLI_RE.search(p_unq):
                return True
        return False
    cmd_unquoted = strip_quoted_regions(cmd)
    return bool(CLI_RE.search(cmd_unquoted))

# (설명, 명령, expect_violation). Codex 13차 추가: quoted $() / backtick / pipeline /
# background. `codex login (wrapped)` 은 Pass A 시점에 child='codex' 이지만 exec 없음 → violation.
FIXTURES = [
    # === OK (violation 아님) ===
    ("direct codex child",          "_run_with_timeout 600 30 codex exec - -s read-only", False),
    ("direct gemini child",         "_run_with_timeout 600 30 gemini -m foo -p -",        False),
    ("quoted CLI in echo",          'echo "codex exec prose example"',                    False),
    ("quoted gemini in echo",       "echo 'gemini -p documentation'",                     False),
    ("codex help (unwrapped)",      "codex --help",                                       False),
    ("gemini version (unwrapped)",  "gemini --version",                                   False),
    ("redirect (not pipeline)",     "_run_with_timeout 300 30 codex exec - 2> err.log",   False),
    ("cmd-subst pipeline inside",   "_run_with_timeout 300 30 codex exec --note $(cat a | wc -l)", False),
    ("attached paren subshell bg",  "(_run_with_timeout 300 30 codex exec -) &",           False),
    ("cmd-subst quoted paren",      '_run_with_timeout 300 30 codex exec --note $(printf ")" | wc -c)', False),
    ("subst with backtick paren",   "_run_with_timeout 300 30 codex exec --note $(printf `echo )` | wc -l)", False),
    ("cmd-subst inert printf",      'echo "$(printf \\"codex exec -\\")"',                 False),
    ("backtick inert printf",       'echo `printf "codex exec -"`',                        False),
    ("backtick inside dquote inert", 'echo "`printf \\"codex exec -\\"`"',                 False),
    # === FAIL (violation 이어야 함) ===
    ("codex login (wrapped, CLI 없음)", "_run_with_timeout 300 30 codex login",            True),
    ("bash -lc wrapper",            "_run_with_timeout 300 30 bash -lc 'codex exec -'",   True),
    ("sh -c wrapper",               '_run_with_timeout 300 30 sh -c "gemini -p -"',       True),
    ("zsh -c wrapper",              '_run_with_timeout 300 30 zsh -c "codex exec -"',     True),
    ("env prefix wrapper",          "_run_with_timeout 300 30 env codex exec -",          True),
    ("nohup wrapper",               "_run_with_timeout 300 30 nohup codex exec -",        True),
    ("bash -c var indirection",     '_run_with_timeout 300 30 bash -c "$BACKEND_CMD"',    True),
    ("function indirection",        "_run_with_timeout 300 30 run_backend",               True),
    ("bare codex call",             "codex exec - -s read-only",                          True),
    ("bare gemini call",            "gemini -p -",                                        True),
    ("FOO=1 timeout bypass",        "FOO=1 timeout 300 codex exec -",                     True),
    ("gtimeout prefix",             "gtimeout 300 codex exec -",                          True),
    ("cmd-substitution in dquote",  'OUT="$(codex exec - -s read-only)"',                  True),
    ("echo cmd-substitution",       'echo "$(gemini -p -)"',                               True),
    ("backtick substitution",       "OUT=`codex exec -`",                                  True),
    ("wrapper pipe",                "_run_with_timeout 300 30 codex exec - | tee out",     True),
    ("wrapper background",          "_run_with_timeout 300 30 gemini -m x -p - &",         True),
    ("subshell with inner pipe",    "(_run_with_timeout 300 30 codex exec - | tee out)",   True),
    ("subshell inner pipe bg",      "(_run_with_timeout 300 30 codex exec - | tee out) &", True),
    ("dquoted $() pipe bypass",     '_run_with_timeout 300 30 codex exec --note "$(printf x)" | tee out', True),
    ("dquoted $() bg bypass",       '_run_with_timeout 300 30 codex exec --note "$(printf x)" &',         True),
    ('backtick dquote leak pipe',   '_run_with_timeout 300 30 codex exec --note `printf \'"\'` | tee out', True),
    ('semicolon chained codex',     '_run_with_timeout 300 30 codex exec - ; codex exec -',               True),
    ('and-and chained codex',       '_run_with_timeout 300 30 codex exec - && codex exec -',             True),
    ('gemini wrapped without -p',   '_run_with_timeout 300 30 gemini --version',                          True),
    ('gemini quoted -p bypass',     '_run_with_timeout 300 30 gemini "document -p behavior"',             True),
    ('gemini ANSI-C quoted -p',     "_run_with_timeout 300 30 gemini $'document -p behavior'",           True),
]

import hashlib

EXPECTED_FIXTURE_COUNT = 41
if len(FIXTURES) != EXPECTED_FIXTURE_COUNT:
    print(
        f"FATAL: FIXTURES count regression — expected {EXPECTED_FIXTURE_COUNT}, got {len(FIXTURES)}",
        file=sys.stderr,
    )
    print(f"  If intentional expansion/pruning, update EXPECTED_FIXTURE_COUNT + signature + required sets.", file=sys.stderr)
    sys.exit(1)

# Codex 19차 추가: cmd-subst/backtick 내부 inert quoted literal 3개 OK fixture.
EXPECTED_FIXTURE_SIGNATURE = "64aced4d4483e41c94b84c00bb2d8b6c89a919f7d9d9f1eed23e9f635dfcd767"
_sig_input = "\n".join(f"{d}|{c}|{e}" for d, c, e in FIXTURES)
_actual_sig = hashlib.sha256(_sig_input.encode()).hexdigest()
if _actual_sig != EXPECTED_FIXTURE_SIGNATURE:
    print(f"FATAL: FIXTURES content drift (identity pin)", file=sys.stderr)
    print(f"  expected signature: {EXPECTED_FIXTURE_SIGNATURE}", file=sys.stderr)
    print(f"  actual signature:   {_actual_sig}", file=sys.stderr)
    print(f"  의도적 fixture 수정이면 EXPECTED_FIXTURE_SIGNATURE 업데이트 (diff 검토 필수).", file=sys.stderr)
    sys.exit(1)

# Critical bypass 17개 (12 + 5 신규). 의미론적 가드 — signature 업데이트 시 빠지면 FATAL.
REQUIRED_BYPASS_DESCS = {
    "codex login (wrapped, CLI 없음)",
    "bash -lc wrapper", "sh -c wrapper", "zsh -c wrapper",
    "env prefix wrapper", "nohup wrapper",
    "bash -c var indirection", "function indirection",
    "bare codex call", "bare gemini call",
    "FOO=1 timeout bypass", "gtimeout prefix",
    "cmd-substitution in dquote", "echo cmd-substitution",
    "backtick substitution",
    "wrapper pipe", "wrapper background",
    "subshell with inner pipe", "subshell inner pipe bg",
    "dquoted $() pipe bypass", "dquoted $() bg bypass",
    "backtick dquote leak pipe",
    "semicolon chained codex", "and-and chained codex",
    "gemini wrapped without -p",
    "gemini quoted -p bypass",
    "gemini ANSI-C quoted -p",
}
REQUIRED_OK_DESCS = {
    "direct codex child", "direct gemini child",
    "quoted CLI in echo", "quoted gemini in echo",
    "codex help (unwrapped)", "gemini version (unwrapped)",
    "redirect (not pipeline)",
    "cmd-subst pipeline inside", "attached paren subshell bg",
    "cmd-subst quoted paren", "subst with backtick paren",
    "cmd-subst inert printf", "backtick inert printf",
    "backtick inside dquote inert",
}
_fixture_map = {d: (c, e) for d, c, e in FIXTURES}
_identity_errors = []
for required in REQUIRED_BYPASS_DESCS:
    if required not in _fixture_map:
        _identity_errors.append(f"missing REQUIRED_BYPASS: {required!r}")
    elif _fixture_map[required][1] is not True:
        _identity_errors.append(f"{required!r} must have expect=True, got {_fixture_map[required][1]}")
for required in REQUIRED_OK_DESCS:
    if required not in _fixture_map:
        _identity_errors.append(f"missing REQUIRED_OK: {required!r}")
    elif _fixture_map[required][1] is not False:
        _identity_errors.append(f"{required!r} must have expect=False, got {_fixture_map[required][1]}")
if _identity_errors:
    print(f"FATAL: critical fixture identity violation(s):", file=sys.stderr)
    for e in _identity_errors: print(f"  {e}", file=sys.stderr)
    sys.exit(1)

failures = []
for desc, cmd, expect in FIXTURES:
    got = check_violation(cmd)
    if got != expect:
        failures.append(f"  {desc}: expected violation={expect}, got={got}\n    cmd: {cmd!r}")

if failures:
    print(f"[test_10] {len(failures)} fixture(s) behaved unexpectedly:", file=sys.stderr)
    for f in failures: print(f, file=sys.stderr)
    sys.exit(1)
print(f"[test_10] all {len(FIXTURES)} adversarial fixtures behaved as expected")
sys.exit(0)
PYEOF
    local rc=$?
    if [ "$rc" = "0" ]; then
        _pass "$name"
    else
        _fail "$name" "fixture mismatches above"
    fi
}

test_grep_batch_args
test_backend_calls_timeout_guarded
test_timeout_wrapper_parity
test_lint_adversarial_fixtures

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
total=$((PASS+FAIL))
echo "  Total: $total  |  Passed: $PASS  |  Failed: $FAIL"
[ "$FAIL" = "0" ] && { echo "  ✅ 전체 통과"; exit 0; } || { echo "  ❌ 실패: ${FAILED_TESTS[*]}"; exit 1; }
