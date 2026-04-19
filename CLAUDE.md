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
[2026-04-20] Codex 15차 findings 2건 수정: (1) subshell exemption을 `&` 에만 한정 — `|`는 subshell 내부/외부 무관하게 항상 violation (wrapper rc가 파이프 오른쪽으로 숨겨짐). `(_run_with_timeout ... | tee)` 이제 detect. (2) `$()` depth tracker가 double-quote 내부 `)`를 무시하도록 수정 — `$(printf ")" | wc -c)` 같은 정상 command false positive 제거. Test 10 fixture 26→29 (subshell inner pipe × 2 FAIL + quoted paren OK), signature `a7341f9b4390...`. REQUIRED_BYPASS 19 / REQUIRED_OK 10. smoke 10/10 + schema 6/6 = 16 PASS. Codex 16차 대기.
