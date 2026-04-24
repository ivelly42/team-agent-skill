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
[2026-04-25] round-9 — **Codex 5.5 xhigh 제안 적용: timeout wrapper 7곳 인라인 복제 제거 + `_require_cfg` 계약 검증 함수** 완료. 최종 **13 test suite 전체 PASS** (R31·R32 신규 2개 + smoke Test 9 재작성).

핵심 (라운드-9, 3명 합의 이슈 중 1건):
- **(C1 HIGH)** `_run_with_timeout` 40줄 함수가 SKILL.md 4곳 + refs/{codex,gemini,cross}-verification.md 3곳 = **총 7곳 인라인 복붙** 제거. `refs/gemini-helper.sh`가 이미 `export -f`하므로 `source cfg.env` 한 줄로 자동 바인딩되는 단일 진실원 구조 확립. Codex 5.5 xhigh가 round-9 제안 문서에서 패치까지 설계.
- **신규: `_require_cfg` 함수** `refs/gemini-helper.sh`에 추가 — 26개 `_CFG_*` 변수 + 3개 함수(`_run_with_timeout`/`_pick_gemini_model`/`_require_cfg`) 바인딩 일괄 검증. cfg.env 말미에 자동 호출 → 계약 위반 즉시 fail-closed.
- **`export -f` zsh 호환 가드**: `if [ -n "${BASH_VERSION:-}" ]; then export -f ...; fi` — zsh에서 `export -f`는 bash와 다른 의미라 조건부로 유지.
- **smoke Test 9 재작성**: 이전엔 "7곳 인라인이 canonical과 SHA256 일치" 검증 (증상 관리). 이제 "helper 3 함수 단일 소유 + runtime 4 파일 인라인 0건" (원인 해결 검증).
- **R10 패턴 확장**: cfg.env append가 `{printf source; printf _require_cfg}` 그룹 형태 허용.
- **신규 R31**: grep으로 _require_cfg 존재 + 7곳 인라인 잔존 0건 검증.
- **신규 R32**: zsh subprocess에서 helper.sh source 후 3 함수 전부 바인딩 실제 실행 검증 (R30 패턴 확장).

보류 (round-10 예정, 2건 3-agent 합의 남음):
- SKILL.md 2674줄 분할 (Codex가 refs/phases/*.md 16파일 분할안 제시) — 큰 리팩터, 별도 round
- 테스트 self-fulfillment 탈출 (shell-parity.sh + e2e-preamble.sh + Agent fixture mock) — 별도 round

round-9 메타 분석 산출물: `docs/team-agent/2026-04-25-040151-meta-ultra-report.md` (13KB)
round-9 Codex 제안 원본: `/tmp/ta-round9-codex-proposal.md` (285줄, ~9.5KB)

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
