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
[2026-04-20] Codex 11차 findings 2건 수정: (1) `.github/workflows/tests.yml` 추가 — push/PR마다 smoke.sh + schema-validation.sh (strict mode, jsonschema 설치) 자동 실행. CI 연결 전까지 claim만 있고 enforcement 없던 구멍을 실제 merge gate로 격상. (2) Test 10 fixture identity pin: EXPECTED_FIXTURE_SIGNATURE (FIXTURES desc|cmd|expect 튜플의 SHA256, `992739714d740e...`) + REQUIRED_BYPASS_DESCS / REQUIRED_OK_DESCS set. count 고정 외에 내용 swap (bash -lc를 weak happy-path로 교체) regression도 즉시 차단. 이중 방어. smoke 10/10 + schema 6/6 = 16 PASS. Codex 12차 대기.
