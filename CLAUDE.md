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
[2026-04-20] Codex 17차 findings 1건 수정: backtick 내부 quote state가 외부로 leak하여 top-level operator split 실패. `` `printf '"'`  | tee out`` 이 하나의 piece로 병합되어 wrapper pipe 감지 실패. 해결: backtick도 `$()`와 동일하게 quote_stack push/pop — backtick 진입 시 현재 quote state를 push하고 내부 reset, 종료 시 pop. Test 10 fixture 31→34 (backtick leak pipe + `;` chained + `&&` chained unwrapped codex), signature `59d07606d53d...`. REQUIRED_BYPASS 24 / REQUIRED_OK 10. smoke 10/10 + schema 6/6 = 16 PASS. Codex 18차 대기.
