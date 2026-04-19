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
[2026-04-20] Codex 19차 findings 2건 수정: (1) Python watchdog이 SIGTERM 이후 child의 arbitrary rc를 그대로 반환하는 문제 — child가 SIGTERM 잡고 `exit(1)` 하면 timeout이 `1`로 보임. 해결: SIGTERM path로 들어왔으면 child rc 무시, 항상 `124` 반환. canonical + 7 inline copies 모두 동기화, new pinned hash `5c0c6d2c9e84...`. (2) `strip_quoted_regions`가 `$()` / backtick body 재귀 처리 + `\"`, `\'`, `\`` outer escape unescape — `echo "$(printf \"codex exec -\")"` 같은 inert printf 인자는 이제 false positive 아님. Test 10 fixture 35→38 (cmd-subst/backtick inert printf 3건 OK), signature `130802992ce6...`. REQUIRED_OK 14. smoke 10/10 + schema 6/6 = 16 PASS. Codex 20차 대기.
