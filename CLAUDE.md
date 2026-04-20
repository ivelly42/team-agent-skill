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
[2026-04-21] Ultra 자기분석(4역할 × Claude+Codex+Gemini 3중, 107 findings → 33 consensus) 기반 최우선 7가지 개선 적용. (1) Item 6 gemini `--json-schema` capability probe를 refs/cross-verification.md에 일관 적용(실행 중 실제 재현된 버그). (2) Item 2 `--ultra=selective` 플래그 추가 — 가중치별 선별 복제(×1.5=3중/×1.0=2중/≤×0.7=1중)로 ~44% 토큰 절감. (3) Item 3 플래그 매트릭스 45행을 refs/flag-matrix.md로 외부화. (4) Item 4 역할별 PROJECT_CONTEXT 필터링을 선택→기본 동작으로 승격(1,500자). (5) Item 5 tests/gemini-capability-probe.sh(6 cases) + tests/flag-combinations.sh(8 cases) 회귀 smoke 14개 추가. (6) Item 7 refs/config.json 중앙 설정 + `gemini.candidates.agent` alias 배열. (7) Item 1 refs/timeout-wrapper.sh에 canonical source 주석 추가(byte-parity Test 9 유지). 최종: smoke 10 + schema 6 + gemini-probe 6 + flag-combos 8 = **30/30 PASS**.
