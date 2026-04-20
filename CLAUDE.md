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
[2026-04-21] Ultra 자기분석(4역할 × Claude+Codex+Gemini 3중, 107 findings) 기반 최우선 7가지 + 심화 2종 완료. **최종 60/60 PASS** (smoke 10 + schema 6 + gemini-probe 6 + flag-combos 8 + manifest-migration 19 + sanitizer-regression 21). 커밋: `73a1ca1` + 이어서 심화. 핵심 변경: (1) gemini `--json-schema` probe 일관 적용 + (2) `--ultra=selective` 플래그(44% 절감) + (3) 플래그 매트릭스 refs/flag-matrix.md 외부화 + (4) PROJECT_CONTEXT 역할별 필터링 기본값화(1,500자) + (5) refs/config.json 중앙 설정 + (6) refs/checklists.md 39개 역할 파일로 분할(~700B/파일, Ultra 조립 97% 토큰 절감) + (7) **sanitizer latent bug fix** — NFKD가 Hangul syllables를 Jamo로 분해해 `가-힣` 필터를 통과 못하던 문제를 NFC 재조합 추가로 해결(한글 입력 보존). 회귀 smoke 3종 신규 (gemini-probe, flag-combos, manifest-migration, sanitizer-regression).
