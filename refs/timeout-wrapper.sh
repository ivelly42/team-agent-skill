#!/usr/bin/env bash
# Shared hard-timeout wrapper for external CLI backends (codex exec, gemini -p).
#
# CANONICAL SOURCE OF TRUTH. SKILL.md와 refs/{codex,gemini,cross}-verification.md의
# `_run_with_timeout` 인라인 복사본은 이 파일과 byte-exact parity를 유지해야 한다.
# tests/smoke.sh Test 9가 SHA256으로 pin하여 drift를 감지한다.
#
# 수정 절차:
#   1. 이 파일(refs/timeout-wrapper.sh)을 먼저 수정
#   2. SKILL.md 3곳 + refs/ 3곳의 인라인 블록을 이 파일과 동일하게 복붙
#   3. tests/smoke.sh의 EXPECTED_CANONICAL_SHA256을 새 해시로 업데이트
#   4. bash tests/smoke.sh로 Test 9·10 PASS 확인
#
# 향후 개선(계획): Phase 1 런타임에서 이 파일을 런타임에 source하도록 전환하면
# 복붙 제거 가능. 현재는 "source 환경 불확실"을 이유로 self-contained 유지.
# 전환 시 smoke Test 9를 "source 성공 + 함수 existence"로 재작성.
#
# Usage (sourced or inlined):
#   source "${_SKILL_DIR}/refs/timeout-wrapper.sh"
#   _run_with_timeout <secs> <grace> cmd [args...]
#
# Returns:
#   child's exit code on normal completion
#   124 on SIGTERM timeout (GNU timeout convention)
#   137 on SIGKILL after grace period (SIGKILL convention)
#   127 if cmd not found
#
# 3-tier fallback (all paths ensure hard timeout — never hang):
#   1. GNU `timeout`  (Linux distributions, Homebrew coreutils)
#   2. `gtimeout`     (macOS with coreutils via brew)
#   3. Python watchdog — skill already depends on python3, so always available.
#      Uses `python3 -c` (NOT heredoc) to preserve child stdin: critical because
#      `codex exec -` and `gemini -p -` read prompt from fd 0.
#
# 사용처:
#   - Phase 1 codex/gemini backend exec (SKILL.md)
#   - Phase 4-A-2 cross verification (refs/cross-verification.md)
#   - Phase 4-A-2 gemini single verification (refs/gemini-verification.md)
#
# 이 파일은 LLM이 위치만 참조한다. 실제로는 각 사용처의 bash 블록에 함수 정의를
# 인라인 복사한다 (skill은 bash 실행 환경이 sourcing 가능한지 보장하지 않음).

_TIMEOUT_BIN=""
if command -v timeout >/dev/null 2>&1; then
    _TIMEOUT_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
    _TIMEOUT_BIN="gtimeout"
fi

_run_with_timeout() {
    # $1=secs, $2=grace_secs, $@=cmd...
    local _secs="$1"; shift
    local _grace="$1"; shift
    if [ -n "$_TIMEOUT_BIN" ]; then
        "$_TIMEOUT_BIN" -k "$_grace" "$_secs" "$@"
        return $?
    fi
    # Python watchdog fallback — `python3 -c` with argv preserves child stdin.
    # heredoc은 절대 사용하지 말 것: fd 0을 heredoc 바이트로 대체하여 child가
    # prompt 대신 EOF를 받는 silent failure 발생.
    python3 -c '
import os, signal, subprocess, sys
secs = int(sys.argv[1]); grace = int(sys.argv[2]); cmd = sys.argv[3:]
if not cmd:
    print("[team-agent] _run_with_timeout: empty cmd", file=sys.stderr); sys.exit(2)
try:
    p = subprocess.Popen(cmd, start_new_session=True, stdin=sys.stdin)
except FileNotFoundError as e:
    print(f"[team-agent] cmd not found: {e}", file=sys.stderr); sys.exit(127)
try:
    sys.exit(p.wait(timeout=secs))
except subprocess.TimeoutExpired:
    try: os.killpg(p.pid, signal.SIGTERM)
    except ProcessLookupError: pass
    try:
        p.wait(timeout=grace)
    except subprocess.TimeoutExpired:
        try: os.killpg(p.pid, signal.SIGKILL)
        except ProcessLookupError: pass
        p.wait()
        sys.exit(137)
    sys.exit(124)
' "$_secs" "$_grace" "$@"
    return $?
}
