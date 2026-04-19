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
[2026-04-19] 품질 분석 19건 픽스 + plan-eng-review + 스모크 테스트 완료. SKILL.md 1194→1933줄, refs/ultra-consolidation-schema.json 신설, tests/smoke.sh(5건 bash+zsh 통과). 엔지니어링 리뷰 1 Medium(schema drift)/3 Low. 커밋 전 남은 작업: schema drift 해결(선택), X1 manifest append-only·C1 prompt cache·C3 Phase 3 Python 대체는 별도 세션.
