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
[2026-04-20] Codex 24차 finding 1건(ANSI-C quoting) 검증 + regression fixture 추가. Codex는 `shlex.split`이 bash `$'...'`(ANSI-C quoting)을 `$'document, -p, behavior'` 3토큰으로 쪼개서 bypass된다고 주장했으나, `posix=True`(우리 기본값) 실측은 `['$document -p behavior']` 한 토큰 → `-p` 별개 토큰 아님 → violation 정확 탐지. 즉 finding은 **false positive (posix=False 결과 오인)**. Guard는 이미 올바르게 동작하나, regression fixture를 명시 추가해 방어 증명: Test 10 fixture 40→41 (`gemini ANSI-C quoted -p` 신규, expect=True), signature `64aced4d4483...`. smoke 10/10 + schema 6/6 = 16 PASS. Codex 25차 대기 또는 convergence.
