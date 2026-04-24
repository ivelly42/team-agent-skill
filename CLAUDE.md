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
[2026-04-25] round-7 — **schema drift 방어 + secret scrubber + HS5/6/7** 완료. 최종 **148/148 PASS** (R15-R19 신규 5개 + 기존 143).

핵심:
- **(B) Phase 2.5 schema drift 방어**: Opus 통합자 프롬프트에 "출력 키는 `consensus_findings` 등 정확히 6개. `findings`/`ideas` 키 사용 금지. schema `additionalProperties: false`" 명시. round-5 메타 실행에서 5명 중 3명이 `findings` 쓴 이슈 구조적 차단.
- **(C) secret scrubber 결정론**: `refs/secret-scrubber.py` 신규 — AWS/GitHub/OpenAI/Anthropic/Google/Slack/JWT/Bearer/password/DB conn/PEM 패턴 결정론 regex 치환. Phase 2 결과 수집 시 code_snippet·evidence에 scrub_findings 적용. 자가 테스트 8/8.
- **(HS5) PROJECT_CONTEXT sanitizer 하드코딩 제거**: Step 2-9 의사코드가 `os.environ["_CFG_PROJECT_CONTEXT_CHARS"]` 사용. 3000 하드코딩 폴백 금지.
- **(HS6) GEMINI_HAS_SCHEMA multi-line 오작동 수정**: `|| echo 0` → `|| true` + 숫자 외 값 0으로 강제. `0\n0` 정수 비교 오작동 방지.
- **(HS7) Phase 5 cfg.env 정리 강화**: Phase 5 섹션에 명시적 cleanup 블록 추가 (`rm -f "$HOME/.cache/team-agent/cfg-${_RUN_ID}.env"`). 7일 mtime 스윕 의존 제거.

이전 round 유지 (바뀌지 않음): round-4 5 bugs, round-5 gemini-helper.sh + source 가드 + bash-runtime-validation, round-6 codex `-m`/`-c` 명시.

메타 분석 산출물 (로컬): `docs/team-agent/2026-04-25-012148-meta-report.md` (25KB).
