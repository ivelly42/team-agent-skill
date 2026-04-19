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
[2026-04-20] Codex adversarial 3 findings 전부 수정 (commit d6c26b5): #1 --cross timeout/fallback 매트릭스 구현, #2 Ultra 실패 shape-stable contract + schema 업데이트, #3 schema-validation.sh 하드게이트(TEAM_AGENT_SCHEMA_STRICT=0 opt-in SKIP). smoke 7/7 + schema 6/6. 3 Codex 경로 모두 silent failure 제거. 잔여 아키텍처 항목(C1/C10/C11/G-S1/manifest_op.py)은 별도 세션.
