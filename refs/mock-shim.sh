# shellcheck shell=bash
# refs/mock-shim.sh — round-11: Agent 도구 mock shim
#
# 목적:
#   Phase 1이 실제 Agent 도구 호출 대신 refs/fixtures/agent-{role}.json을
#   읽도록 대체. 종단간 테스트 + LLM 없이 스킬 플로우 검증 가능.
#
# 활성화 조건:
#   환경변수 TEAM_AGENT_TEST_MODE=fixture
#
# 공개 함수:
#   _load_fixture_for_role <role>
#     - stdin: 없음
#     - stdout: fixture JSON 전문 (refs/fixtures/agent-{role}.json)
#     - stderr: fixture 미존재 또는 schema 위반 시 에러 메시지
#     - rc 0: 성공 (JSON 출력)
#     - rc 1: fixture 없음 or 파싱 실패 or schema 위반
#
# 정합성:
#   - 출력 JSON은 refs/output-schema.json을 반드시 통과 (이미 fixture가 validate됨)
#   - 실제 Agent 호출과 동일 shape (findings + ideas)
#   - Claude Code Bash 도구(zsh) 환경에서 sourcing 가능

# ==========================================================================
# _load_fixture_for_role — 역할명으로 fixture JSON 반환
# 보안: role 인자에 경로 순회(..) 차단. 영숫자+하이픈만 허용.
# ==========================================================================
_load_fixture_for_role() {
    # round-11-a Codex review: mock 경로는 TEAM_AGENT_TEST_MODE=fixture에서만 활성화돼야 함.
    # 이 가드가 없으면 프로덕션에서 실수로 호출 시 fixture가 실제 에이전트 결과처럼 주입되어
    # 사용자가 fixture 데이터를 진짜 분석 결과로 오인할 위험. fail-closed로 원천 차단.
    if [ "${TEAM_AGENT_TEST_MODE:-}" != "fixture" ]; then
        echo "[mock-shim] FATAL: TEAM_AGENT_TEST_MODE=fixture 미설정 — mock 경로 차단 (프로덕션에서 실수 호출 방지)" >&2
        return 1
    fi

    local _role="${1:-}"
    if [ -z "$_role" ]; then
        echo "[mock-shim] FATAL: role 인자 누락" >&2
        return 1
    fi
    # 경로 순회 방어 — 영숫자/하이픈/언더스코어만 허용
    case "$_role" in
        *[^a-zA-Z0-9_-]*|""|.*)
            echo "[mock-shim] FATAL: role 인자 형식 위반: $_role (영숫자·-·_ 만 허용)" >&2
            return 1
            ;;
    esac

    # _SKILL_DIR은 Preamble 0.1에서 export됨. cfg.env가 source된 환경에서 호출한다고 가정.
    if [ -z "${_SKILL_DIR:-}" ]; then
        echo "[mock-shim] FATAL: _SKILL_DIR 미설정 — Preamble 0.1 + cfg.env source 선행 필요" >&2
        return 1
    fi
    local _fx="$_SKILL_DIR/refs/fixtures/agent-${_role}.json"
    if [ ! -f "$_fx" ]; then
        echo "[mock-shim] FATAL: fixture 없음: $_fx" >&2
        echo "[mock-shim]         사용 가능한 role: $(find "$_SKILL_DIR/refs/fixtures" -maxdepth 1 -name 'agent-*.json' 2>/dev/null | sed 's|.*/agent-||;s|\.json||' | tr '\n' ' ')" >&2
        return 1
    fi

    # JSON 파싱 가능 여부만 선검증 (schema 전체 validate는 호출측에서 선택)
    if ! python3 -c "import json, sys; json.load(open('$_fx'))" 2>/dev/null; then
        echo "[mock-shim] FATAL: fixture JSON 파싱 실패: $_fx" >&2
        return 1
    fi

    cat "$_fx"
    return 0
}
if [ -n "${BASH_VERSION:-}" ]; then export -f _load_fixture_for_role; fi

# ==========================================================================
# _is_mock_mode — 편의 predicate (Phase 1 LLM 지시에서 참조)
# ==========================================================================
_is_mock_mode() {
    [ "${TEAM_AGENT_TEST_MODE:-}" = "fixture" ]
}
if [ -n "${BASH_VERSION:-}" ]; then export -f _is_mock_mode; fi
