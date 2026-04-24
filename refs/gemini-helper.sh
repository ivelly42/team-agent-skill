# shellcheck shell=bash
# refs/gemini-helper.sh — round-5 C4 대응
#
# 이 파일은 Preamble 0.1에서 생성된 cfg.env가 `source`로 읽을 때 함께 로드된다.
# cfg.env 마지막 줄은 `source "$_SKILL_DIR/refs/gemini-helper.sh"`. 따라서
# 모든 실행 Bash 블록이 선두에서 `source "$HOME/.cache/team-agent/cfg-${_RUN_ID}.env"`
# 한 줄만 호출하면:
#   (1) _CFG_* 변수 바인딩 (bug_007)
#   (2) _pick_gemini_model 함수 바인딩 (round-5 C4)
#   (3) _run_with_timeout 함수 바인딩 (DRY — 기존엔 refs 3개 파일에 중복 인라인)
# 모두 한 번에 해결된다.
#
# 과거 설계: SKILL.md Preamble prose 블록에 `_pick_gemini_model() {...}`를 정의했지만,
# Claude Code의 Bash 도구가 새 shell을 띄우므로 다음 Bash 호출에서 함수가 소실.
# Ultra round-4 메타 분석에서 실제 실증 (C1+C4).

# ==========================================================================
# _run_with_timeout — 3-tier 타임아웃 래퍼 (GNU timeout → gtimeout → Python watchdog)
# 기존엔 SKILL.md Phase 0.3 3개 블록 + refs/codex/gemini/cross-verification.md에 인라인 중복.
# round-5부터 여기 단일 정의. fail-closed 하지 않는 경우(fail-safe)는 호출측에서 rc 체크.
# ==========================================================================
_TIMEOUT_BIN=""
if command -v timeout >/dev/null 2>&1; then
    _TIMEOUT_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
    _TIMEOUT_BIN="gtimeout"
fi
export _TIMEOUT_BIN

_run_with_timeout() {
    # usage: _run_with_timeout <secs> <grace_secs> <cmd...>
    local _secs="$1"; shift
    local _grace="$1"; shift
    if [ -n "$_TIMEOUT_BIN" ]; then
        "$_TIMEOUT_BIN" -k "$_grace" "$_secs" "$@"
        return $?
    fi
    # Python watchdog fallback — `python3 -c` + argv preserves child stdin.
    # heredoc 금지: fd 0이 heredoc 바이트로 대체되어 child가 prompt 대신 EOF를 받음.
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
export -f _run_with_timeout

# ==========================================================================
# _pick_gemini_model — gemini candidates 배열에서 가용한 첫 모델 선택
# bug_006: 전 후보 실패 시 **빈 문자열 + rc=1** 반환 (caller는 반드시 rc 체크).
# zsh/bash 공통 — `while IFS= read -r < <(tr ' ' '\n')` 패턴.
# ==========================================================================
_pick_gemini_model() {
    local _role="${1:-agent}"
    local _cands_str
    if [ "$_role" = "verifier" ]; then
        _cands_str="$_CFG_GEMINI_VERIFIER_CANDIDATES"
    else
        _cands_str="$_CFG_GEMINI_AGENT_CANDIDATES"
    fi
    # Probe timeout (round-8): gemini CLI가 만료 토큰·keychain·네트워크 wedge로 무한 대기
    # 할 수 있으므로 각 probe를 _run_with_timeout 15초로 감싼다. 3-tier 래퍼 재사용.
    local _probe_sec=15 _probe_grace=5
    local _m _err _rc
    while IFS= read -r _m; do
        [ -z "$_m" ] && continue
        _err=$(_run_with_timeout "$_probe_sec" "$_probe_grace" gemini -m "$_m" -p "ping" </dev/null 2>&1 >/dev/null)
        _rc=$?
        if [ "$_rc" -eq 0 ]; then
            printf '%s' "$_m"; return 0
        fi
        # rc=124/137 → probe 자체가 timeout/killed. 다음 후보로.
        if [ "$_rc" -eq 124 ] || [ "$_rc" -eq 137 ]; then
            echo "[_pick_gemini_model] skip $_m (probe timeout rc=$_rc)" >&2
            continue
        fi
        # 429 capacity exhaust → 10초 대기 후 재시도 1회 (재시도도 timeout 래핑)
        if echo "$_err" | grep -q 'RESOURCE_EXHAUSTED\|rateLimitExceeded\|capacity'; then
            sleep 10
            if _run_with_timeout "$_probe_sec" "$_probe_grace" gemini -m "$_m" -p "ping" </dev/null >/dev/null 2>&1; then
                printf '%s' "$_m"; return 0
            fi
        fi
        echo "[_pick_gemini_model] skip $_m (rc=$_rc)" >&2
    done < <(printf '%s\n' "$_cands_str" | tr ' ' '\n')
    # 전부 실패 — bug_006: loud fail (빈 문자열 + rc=1). caller는 반드시 확인.
    printf ''
    return 1
}
export -f _pick_gemini_model
