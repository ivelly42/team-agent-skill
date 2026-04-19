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
[2026-04-20] Codex 16차 findings 1건 수정: `"$(printf x)" | tee out` 처럼 double-quoted command substitution 뒤 top-level `|`/`&`가 검사 스킵되던 구멍. 15차에서 `not in_double` 가드가 정상 `$()` 종료(`"$(..)")까지 막았음. 해결: quote_stack per `$()` depth — `$(` 진입 시 (in_single,in_double) push하고 내부 reset, `)` 로 pop. 내부 quote state와 외부가 독립. Test 10 fixture 29→31 (dquoted `$()` pipe/bg bypass 2 FAIL), signature `1d7e5b917a35...`. REQUIRED_BYPASS 21 / REQUIRED_OK 10. smoke 10/10 + schema 6/6 = 16 PASS. Codex 17차 대기.
