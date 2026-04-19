#!/usr/bin/env bash
# Shared hard-timeout wrapper for external CLI backends (codex exec, gemini -p).
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
    rc = p.wait(timeout=secs)
    sys.exit(rc)
except subprocess.TimeoutExpired:
    try: os.killpg(p.pid, signal.SIGTERM)
    except ProcessLookupError: pass
    try:
        rc = p.wait(timeout=grace)
        sys.exit(124 if rc in (0, -signal.SIGTERM) else rc)
    except subprocess.TimeoutExpired:
        try: os.killpg(p.pid, signal.SIGKILL)
        except ProcessLookupError: pass
        p.wait()
        sys.exit(137)
' "$_secs" "$_grace" "$@"
    return $?
}
