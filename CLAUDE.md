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
[2026-04-22] Codex adversarial review `needs-attention` 3개 finding을 실행 레벨까지 전부 수정. **최종 90/90 PASS** (smoke 10 + schema 6 + gemini-probe 6 + flag-combos 8 + manifest-migration 23 + sanitizer-regression 21 + ultra-selective-topology 8 + config-loading 8). 핵심 변경: (1) Finding #2 해결 — manifest schema v6로 bump + `ultra_strategy` 필드 저장 + v5→v6 migration 규칙. (2) Finding #1 해결 — Ultra spawn 경로에 `ultra_replication()` 함수 정의로 가중치별 실제 분기(×1.5=3중/×1.0=2중/≤×0.7=1중), 5역할 15→9명으로 실제 40% 절감. Phase 2.5 selective 1중 패스스루(통합자 생략, `agreement:"1/1"`). (3) Finding #3 해결 — Preamble 0.1 설정 로드 단계 신규, `refs/config.json` + `refs/config.local.json` 깊이 병합 + `_pick_gemini_model` alias fallback + 런타임 치환 규칙(`_CFG_*` 변수). config.local.json .gitignore 등록. (4) 회귀 smoke 2종 신규 (ultra-selective-topology 8 + config-loading 8), manifest-migration v6로 확장(19→23). 이전 Ultra 자기분석 개선(`73a1ca1`+`77e9833`) 누적.
