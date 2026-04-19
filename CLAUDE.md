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
[2026-04-20] Codex 23차 findings 2건 수정: (1) `validate_wrapped()`의 `cmd_text.split()`이 quoted argv를 whitespace로 쪼개서 `_run_with_timeout 300 30 gemini "document -p behavior"`같은 입력이 `-p`가 argv가 아닌 prompt body의 substring인데도 contract 통과. 해결: `shlex.split(posix=True)` 기반 `_tokenize_wrapped()` helper 도입 — Test 8/Test 10 validate_wrapped 양쪽 업데이트. shlex 실패 시 whitespace fallback. Test 10 fixture 39→40 (`gemini quoted -p bypass` 신규), signature `94dae4f771a0...`. (2) `ultra-consolidation-schema.json`이 `status=ok`에도 `error` 필드를 허용해 stale failure text 누수 가능. 해결: Draft-07 allOf에 두 번째 if/then 추가 — status=ok일 때 `not: {required: [error]}`. schema-validation.sh에 negative test 1건(ok+error→reject rc=6) 추가. smoke 10/10 + schema 6/6 = 16 PASS. Codex 24차 대기.
