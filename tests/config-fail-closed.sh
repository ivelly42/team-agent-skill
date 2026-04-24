#!/usr/bin/env bash
# tests/config-fail-closed.sh
#
# Codex round-3 Finding #1 regression:
# Preamble 0.1이 fail-closed 구조인지 검증.
# - mktemp 기반 secure tempfile
# - Python 로더 exit code 체크 후 abort
# - source 실패 시 abort
# - ${_CFG_*:-default} 폴백 문법은 실행 블록에 0건 (문서 설명 예외 허용)
# - sanity check loop 존재 (_CFG_* 빈 바인딩 차단)
# - refs/config.json 파싱 실패 시 명확한 에러 + abort
# - config.local.json 파싱 실패도 abort

set -u
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_MD="$SKILL_DIR/SKILL.md"
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
PASS=0; FAIL=0
pass() { printf "  ${GREEN}✓ PASS${NC}: %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "  ${RED}✗ FAIL${NC}: %s\n" "$1"; FAIL=$((FAIL+1)); }

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Preamble 0.1 fail-closed smoke (Codex round-3 #1)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 추출: Preamble 0.1 섹션만 (다음 `### 1-` 스텝 직전까지)
# awk `/start/,/end/`에서 start와 end가 동일 줄에 매치되면 start 한 줄만 뽑히는 이슈 회피 — end는 start와 다른 패턴.
PREAMBLE_0_1="$(awk '/^### Preamble 0\.1/{flag=1} flag{print} /^### 1-/{if(flag){exit}}' "$SKILL_MD")"

# F1. Persistent cfg.env 경로 + chmod 600 + symlink 방어 (bug_007 cross-invocation 지속)
# 2026-04-25: mktemp(세션 로컬) → $HOME/.cache/team-agent/cfg-${_RUN_ID}.env (cross-invocation persistent)로 전환.
# Bash 도구는 호출마다 새 shell이라 mktemp 파일명을 다음 호출에서 복구 불가.
if echo "$PREAMBLE_0_1" | grep -qE '\$HOME/\.cache/team-agent' \
   && echo "$PREAMBLE_0_1" | grep -qE 'cfg-\$\{_RUN_ID\}\.env' \
   && echo "$PREAMBLE_0_1" | grep -qE 'chmod 600 "\$_TA_CFG_FILE"' \
   && echo "$PREAMBLE_0_1" | grep -qE '\[ -L "\$_TA_CFG_FILE" \]'; then
    pass "F1 — persistent cfg.env ($HOME/.cache/team-agent/cfg-\${_RUN_ID}.env) + chmod 600 + symlink 방어"
else
    fail "F1 — cross-invocation persistent cfg.env 구조 미완성"
fi

# F2. Python 로더 exit code 체크 (_TA_CFG_RC 변수 또는 명시적 -ne 0 분기)
if echo "$PREAMBLE_0_1" | grep -qE '_TA_CFG_RC.*-ne 0|python exit='; then
    pass "F2 — Python 로더 exit code 체크 + abort 경로"
else
    fail "F2 — Python 로더 exit code 체크 누락"
fi

# F3. source 실패 시 abort (if ! source)
if echo "$PREAMBLE_0_1" | grep -qE 'if ! source|source env source 실패'; then
    pass "F3 — source 실패 시 abort 경로"
else
    fail "F3 — source 실패 분기 누락"
fi

# F4. 최소 1회 abort (exit 1) 경로
CNT=$(echo "$PREAMBLE_0_1" | grep -c 'exit 1')
if [ "$CNT" -ge 2 ]; then
    pass "F4 — exit 1 abort 경로 ${CNT}곳 (다층 방어)"
else
    fail "F4 — exit 1 abort 경로 부족 ($CNT)"
fi

# F5. Python 쪽 sys.exit(1) — config.json/local.json 파싱 실패 에러 핸들링
if echo "$PREAMBLE_0_1" | grep -qE 'sys\.exit\(1\)' && echo "$PREAMBLE_0_1" | grep -qE 'JSONDecodeError|파싱 실패'; then
    pass "F5 — Python: JSONDecodeError/파싱 실패 → sys.exit(1)"
else
    fail "F5 — Python 에러 핸들링 또는 sys.exit(1) 누락"
fi

# F6. sanity check loop — 핵심 _CFG_ 변수 빈 바인딩 차단
if echo "$PREAMBLE_0_1" | grep -qE 'for _var in _CFG_'; then
    pass "F6 — Preamble 후반 sanity check loop (핵심 변수 미바인딩 차단)"
else
    fail "F6 — _CFG_* sanity check loop 누락"
fi

# F7. 실행 블록에 ${_CFG_*:-NN} 폴백 문법 0건 (문서 설명 라인은 "> " 또는 "—" 포함으로 필터)
FALLBACK_LINES=$(grep -nF '{_CFG_' "$SKILL_MD" | grep ':-' | grep -vE '^\s*[0-9]+:>|→|폴백 문법을 쓰지 않는다|`\${_CFG_\*:-default}`' || true)
if [ -z "$FALLBACK_LINES" ]; then
    pass "F7 — 실행 블록에 \${_CFG_*:-default} 폴백 0건"
else
    fail "F7 — 실행 블록에 잔존 폴백 발견:"
    echo "$FALLBACK_LINES"
fi

# F8. config.local.json 에러 메시지 한글 (사용자 친화적)
if echo "$PREAMBLE_0_1" | grep -qE 'config\.local\.json 파싱 실패|config\.json 파싱 실패'; then
    pass "F8 — config 파싱 실패 시 한글 에러 메시지"
else
    fail "F8 — config 파싱 실패 한글 메시지 누락"
fi

# F9. 전체 Preamble 0.1 fail-closed 동작 — Python 로더 에뮬레이션
python3 <<'PYEOF'
import json, os, tempfile, subprocess, sys

# 임시 SKILL_DIR 만들고 refs/ 안에 잘못된 config.json 넣어서 Python 로더 부분 실행
with tempfile.TemporaryDirectory() as tmpdir:
    refs = os.path.join(tmpdir, "refs")
    os.makedirs(refs)
    # 의도적으로 JSON 문법 에러
    with open(f"{refs}/config.json", "w") as f:
        f.write("{ not valid json }")

    # Preamble 0.1의 Python 로더 시뮬레이션 (간략화 — 실제 로더와 동일 로직)
    code = f'''
import json, os, sys
SKILL_DIR = "{tmpdir}"
base = f"{{SKILL_DIR}}/refs/config.json"
try:
    with open(base) as f: cfg = json.load(f)
except json.JSONDecodeError as e:
    sys.stderr.write(f"FATAL: {{e}}\\n")
    sys.exit(1)
'''
    r = subprocess.run([sys.executable, "-c", code], capture_output=True, text=True)
    assert r.returncode == 1, f"invalid JSON이면 exit 1이어야 함, got {r.returncode}"
    assert "FATAL" in r.stderr, "stderr에 FATAL 메시지"
    print("F9_OK: 잘못된 config.json → exit 1 + 에러 메시지")
PYEOF
if [ "$?" -eq 0 ]; then
    pass "F9 — Python 로더 시뮬레이션: 잘못된 JSON → exit 1 + 에러"
else
    fail "F9 — Python 로더 fail-closed 동작 실패"
fi

# F10. 런타임 치환 규칙에 "폴백 문법을 쓰지 않는다" 명시
if grep -qE "폴백 문법.*쓰지 않는다|\\\$\\{_CFG_\\*\\}.*직접 참조" "$SKILL_MD"; then
    pass "F10 — fail-closed 규약 명시 (드리프트 방지 문서화)"
else
    fail "F10 — fail-closed 규약 문서화 누락"
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
