## Auto-Status Rule
매 작업 완료 시 이 파일 맨 아래 "## Current Status" 섹션을 1-2줄로 갱신하라. 형식: [날짜] 현재 상태 요약. 이전 상태는 지우고 최신만 유지.

# CLAUDE.md — team-agent skill

## Overview

범용 팀 에이전트 구성 스킬. 프로젝트 분석 후 최적 에이전트 팀(3~8명)을 자동 추천하고 Agent 도구로 병렬 실행. 보안 점검, 코드 리뷰, 리팩토링, 성능 최적화, 디버깅 등 다목적.

## Key Files

- `SKILL.md` — 스킬 본체 (프롬프트 + 실행 로직)
- `docs/` — 실행 결과 보고서 저장 디렉토리

## Usage

```
/team-agent 보안 점검
/team-agent --auto 코드 리팩토링
/team-agent --deep 성능 최적화
```

## Current Status
[2026-04-25] round-10 — **test self-fulfillment 탈출** 완료. 최종 **16 test suite 전체 PASS** (shell-parity + e2e-preamble + e2e-agent-fixture 3종 신규 + fixture 3개 JSON).

왜 필요했는가:
- round-8 HS8(bash-only `${!var}` → zsh bad substitution)이 **테스트 159개 PASS 상태에서 프로덕션 `/team-agent --ultra --dry-run`에서 폭발**. 기존 테스트가 전부 grep 기반 + `bash` 명시 실행이라 zsh parse 문제를 원천적으로 못 잡음. "테스트가 자기 자신만 검증하는" 구조적 결함이 round-9에서 3인 합의로 식별됨.

신규 테스트 3종 (runtime parity 확보):
- **`tests/shell-parity.sh`** — SKILL.md + refs/*.md의 모든 ```bash 블록을 `bash -n` + `zsh -n` 양쪽 parse check. 31/32 PASS, 1 skip (bash 3.2 Korean regex — zsh에선 OK, Claude Code가 zsh라 의도적 skip 주석). `<!-- shell-parity: skip reason=... -->` 주석으로 의도적 제외 명시.
- **`tests/e2e-preamble.sh`** — zsh subprocess에서 helper.sh + cfg.env 계약 + 5개 hostile TASK_PURPOSE(`'; rm -rf \"$HOME\"`, em dash 구분자 위장, ANSI escape, PYEOF heredoc 탈출, `$(whoami)` command substitution) **실제 실행**. 8/8 PASS. `_require_cfg` fail-closed도 subshell 래핑으로 검증.
- **`tests/e2e-agent-fixture.sh`** — `refs/fixtures/agent-{security,performance,testing}.json`을 `refs/output-schema.json`으로 jsonschema validate + secret pattern leak 검사. 3/3 PASS. 향후 TEAM_AGENT_TEST_MODE=fixture mock shim 기반 확보.

지원 파일:
- **`tests/_sanitizer_shim.py`** — Step 1-2 sanitizer Python 단일 파일 shim (stdin → sanitized stdout). e2e + regression 공용.
- **`refs/fixtures/agent-{security,performance,testing}.json`** — output-schema.json 준수 3개 대표 역할 fixture (findings 2-3건 + ideas 2건씩).

보류 (round-11 예정, 더 큰 리팩터):
- SKILL.md 2674줄 분할 (Codex가 refs/phases/*.md 16파일 분할안 제시) — 큰 리팩터, 별도 round
- Agent 실제 Mock shim 구현 (지금은 fixture 자체 validate만, Phase 1 실제 Agent 호출 대체는 후속)

round-9 산출물 유지: `docs/team-agent/2026-04-25-040151-meta-ultra-report.md` (13KB), `docs/team-agent/adversarial-reviews/2026-04-25-codex-round-9-proposal.md` (285줄)

핵심 (라운드-8, 공격 벡터 15개 중 수정 완료 9개):
- **(C1 CRITICAL)** Ultra consolidator schema 삼위일체 drift 해소 — prompt에서 `replicas` 금지, example에 `status` 필수 추가, schema·prompt·example 3곳 동기화.
- **(C2 LOW→실행)** Contradiction threshold 숫자 rank 결정론화 — Critical=4/High=3/Medium=2/Low=1/Info=0, `max-min >= 2` 규칙 명시 (prompt + schema description 동기화).
- **(C3 HIGH)** TASK_PURPOSE sanitizer fail-closed — `os.environ.get(..., "500")` 폴백 제거 → `os.environ["..."]` 직접 참조 + 블록 선두 `source cfg.env` 삽입.
- **(C4 HIGH)** Gemini probe 행 방지 — `_pick_gemini_model` 각 후보 probe를 `_run_with_timeout 15초`로 래핑. 토큰 만료·keychain·네트워크 wedge에서 스킬 전체 stall 차단.
- **(C5 HIGH)** Secret scrubber 필드 재귀 — `scrub_finding`이 code_snippet·evidence만 처리 → 모든 string 필드(title·action·ideas.detail·nested) 재귀 스크러빙.
- **(C6 MED)** Scrubber 신규 패턴 6종 — Stripe `sk_live_`/`rk_live_`/`pk_live_`, Twilio AC/SK, npm_, Azure AccountKey=, GitLab glpat-. Assignment 패턴은 quoted literal만 매치해 `password = options.get("password")` false-positive 차단.
- **(C7 MED)** Codex `-c` TOML 인젝션 방어 — Preamble 0.1 Python loader가 `codex.agent_model`/`verifier_model`/`reasoning_effort_*` 값에 `^[A-Za-z0-9_.\-]{1,64}$` 화이트리스트 강제. `refs/config.local.json` 악성 값이 TOML로 재주입되기 전에 fail-closed.
- **(C8 MED)** Phase 5 cleanup best-effort — `source cfg.env || exit 1` → `source ... || true` + `rm -f` 이어서 실행. 앞 Phase 조기 abort 시에도 cleanup이 자가-차단되지 않음. +24h mtime 스윕 추가.
- **(C9 MED)** Bash `exit 1` vs LLM 세션 갭 명시화 — Preamble 0.1에 "LLM(skill runner) 차원 fail-closed 지침" 블록 추가: FATAL/exit 1 관찰 시 후속 Phase 실행 금지, 사용자 보고 후 종료 의무.
- **(HS8 프로덕션 차단 버그)** Preamble 0.1 sanity check가 bash-전용 indirect expansion(느낌표 접두어 파라미터 확장) 사용. Claude Code Bash 도구는 zsh로 실행되므로 `bad substitution`으로 **모든 스킬 실행이 여기서 abort**. 테스트는 `bash tests/...` 로 명시 실행되어 PASS하던 test self-fulfillment의 정확한 실증. `/team-agent --ultra --dry-run` 실전 실행 중 발견. eval 기반 간접 참조로 교체 → bash/zsh 양쪽 동작. R29(grep) + R30(zsh 실제 subprocess 실행) 회귀 테스트 추가.

보류 (라운드-9 예정, 큰 리팩터): mktemp -d로 `/tmp/ta-*`·cfg.env 예측 경로 전환, scope TOCTOU 재검증, Opus 출력 jsonschema validation loop, PROJECT_CONTEXT sanitizer `refs/sanitize_context.py` 외부화, test gate 우회 클래스 (R8/R13/X5 확장).

Codex adversarial findings 아카이브: `docs/team-agent/adversarial-reviews/2026-04-25-codex-round-8.md` (9.5KB, 15개 finding 원문).

이전 round 유지 (바뀌지 않음): round-4 5 bugs, round-5 gemini-helper.sh + source 가드, round-6 codex `-m`/`-c` 명시, round-7 scrubber + HS5/6/7.
