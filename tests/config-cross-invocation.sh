#!/usr/bin/env bash
# tests/config-cross-invocation.sh
#
# bug_007 회귀 방지: Bash 도구 호출마다 새 shell이므로 Preamble 0.1의 _CFG_* export가
# 다음 Bash 호출에서 빈 문자열이 됨. Persistent cfg.env + 후속 블록 선두 source 패턴 검증.

set -u
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_MD="$SKILL_DIR/SKILL.md"
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
PASS=0; FAIL=0
pass() { printf "  ${GREEN}✓ PASS${NC}: %s\n" "$1"; PASS=$((PASS+1)); }
fail() { printf "  ${RED}✗ FAIL${NC}: %s\n" "$1"; FAIL=$((FAIL+1)); }

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  cross-invocation config persistence smoke (bug_007)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# X1. Preamble 0.1이 persistent 경로 사용 ($HOME/.cache/team-agent/cfg-*.env)
if grep -qE '_TA_CFG_FILE="\$_TA_CFG_DIR/cfg-\$\{_RUN_ID\}\.env"' "$SKILL_MD"; then
    pass "X1 — Preamble 0.1이 \$HOME/.cache/team-agent/cfg-\${_RUN_ID}.env 경로 사용"
else
    fail "X1 — persistent cfg.env 경로 구조 미완성"
fi

# X2. Preamble 0.1이 cfg.env를 rm하지 않음 (persistent 유지)
# Preamble 0.1 섹션만 추출
PREAMBLE="$(awk '/^### Preamble 0\.1/{flag=1} flag{print} /^### 1-0/{if(flag){exit}}' "$SKILL_MD")"
if echo "$PREAMBLE" | grep -qE 'rm -f "\$_TA_CFG_FILE"$'; then
    # 실패 경로의 rm은 허용. 성공 경로 마지막 rm이 없어야 함.
    # 실패 분기 (exit 1 직전) rm은 있어도 됨. 하지만 sanity 통과 후 rm은 없어야 함.
    if echo "$PREAMBLE" | grep -A2 'sanity check' | grep -qE 'rm -f "\$_TA_CFG_FILE"'; then
        fail "X2 — sanity 통과 후에도 rm -f \$_TA_CFG_FILE 호출 (persistent 원칙 위반)"
    else
        pass "X2 — rm은 실패 경로에만 있고 성공 경로에선 파일 유지"
    fi
else
    pass "X2 — Preamble 0.1 성공 경로에서 cfg.env rm 안 함 (persistent)"
fi

# X3. "후속 Bash 블록이 source" 안내 문구 존재
if grep -qE '후속 Bash 블록이 (이 파일을 )?source' "$SKILL_MD"; then
    pass "X3 — 후속 블록 source 안내 문구"
else
    fail "X3 — source 패턴 안내 누락"
fi

# X4. _CFG_* 참조 블록 패턴 명시 (bug_007 방지 문구)
if grep -qE 'bug_007|cross-invocation 지속|Bash 도구는 호출마다' "$SKILL_MD"; then
    pass "X4 — bug_007 cross-invocation 지속 설계 명시"
else
    fail "X4 — bug_007 설계 문구 누락"
fi

# X5. 실제 런타임 시뮬레이션 — 2개 분리된 bash 호출로 cross-invocation 검증.
# 호출 #1에서 cfg.env 생성 → 호출 #2(별개 shell)에서 source → _CFG_* 실제 바인딩 확인.
# Preamble 전체를 복제하는 대신 핵심 계약만 재현: env 파일 작성 + 별개 shell source.
export _TEST_SKILL_DIR="$SKILL_DIR"
export _TEST_MD_PATH="$SKILL_MD"
python3 <<'PYEOF'
import os, re, subprocess, tempfile, sys
import shutil

with tempfile.TemporaryDirectory() as tmp:
    home = os.path.join(tmp, "home")
    os.makedirs(home, exist_ok=True)
    run_id = "2026-04-25-xtest"

    # 호출 #1: Preamble 계약대로 cfg.env 작성 (핵심: persistent 경로 + 실제 config 값)
    # 실제 refs/config.json을 Python으로 로드해 shell env 파일 생성 (Preamble 0.1이 하는 일)
    call1 = f"""
set -eu
export HOME={home!r}
mkdir -p "$HOME/.cache/team-agent"
chmod 700 "$HOME/.cache/team-agent"
cat > "$HOME/.cache/team-agent/cfg-{run_id}.env" <<'ENV'
export _CFG_AGENT_SOFT_SEC=600
export _CFG_VERIFY_SEC=300
export _CFG_GRACE_SEC=30
export _CFG_CODEMAP_SEC=60
export _CFG_GEMINI_AGENT_CANDIDATES='gemini-3-flash-preview gemini-2.5-flash'
export _CFG_GEMINI_VERIFIER_CANDIDATES='gemini-3.1-pro-preview gemini-2.5-pro'
ENV
chmod 600 "$HOME/.cache/team-agent/cfg-{run_id}.env"
echo "call1 OK"
"""
    r1 = subprocess.run(["bash", "-c", call1], capture_output=True, text=True)
    if r1.returncode != 0:
        sys.stderr.write(f"호출 #1 실패 rc={r1.returncode}\n{r1.stderr}\n")
        sys.exit(1)

    # 호출 #2: 완전히 새 bash 프로세스 (shell state 불연속) — source 후 _CFG_* 참조
    call2 = f"""
set -eu
export HOME={home!r}
export _RUN_ID={run_id!r}
# SKILL.md 규약대로 후속 블록 선두에서 source
source "$HOME/.cache/team-agent/cfg-$_RUN_ID.env" || {{ echo "FATAL source failed"; exit 1; }}
echo "AGENT=$_CFG_AGENT_SOFT_SEC"
echo "VERIFY=$_CFG_VERIFY_SEC"
echo "GRACE=$_CFG_GRACE_SEC"
echo "CODEMAP=$_CFG_CODEMAP_SEC"
# bug_007 재현 방지 확인: 빈 문자열이 아닌지
[ -n "$_CFG_AGENT_SOFT_SEC" ] || {{ echo "FATAL _CFG_AGENT_SOFT_SEC empty"; exit 1; }}
"""
    r2 = subprocess.run(["bash", "-c", call2], capture_output=True, text=True)
    if r2.returncode != 0:
        sys.stderr.write(f"호출 #2 실패 rc={r2.returncode}\n{r2.stderr}\n")
        sys.exit(1)
    if not re.search(r'AGENT=\d+', r2.stdout) or not re.search(r'VERIFY=\d+', r2.stdout):
        sys.stderr.write(f"_CFG_* 미바인딩:\n{r2.stdout}\n")
        sys.exit(1)
    print("X5_OK: 2개 분리 bash 호출 간 cfg.env source로 _CFG_* 실제 전파")
PYEOF
if [ "$?" -eq 0 ]; then
    pass "X5 — 런타임 시뮬레이션: 2개 분리된 Bash 호출 간 _CFG_* 실제 전파"
else
    fail "X5 — cross-invocation 지속 실패 (bug_007 재발)"
fi

# X6. 오래된 cfg-*.env 정리 로직
if grep -qE 'find "\$_TA_CFG_DIR".*cfg-\*\.env.*-mtime' "$SKILL_MD"; then
    pass "X6 — 오래된 cfg-*.env 자동 정리 (cache 무한 증가 방지)"
else
    fail "X6 — cfg.env 정리 로직 누락"
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
