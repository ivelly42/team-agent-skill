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
[2026-04-25] round-5 — **Ultra 메타 분석 4개 Critical 실행 레벨 수정**. 최종 **139/139 PASS** (신규 bash-runtime-validation 10개 + 기존 12종 유지). 핵심:

(C1+C4 통합) `refs/gemini-helper.sh` 신규 — `_pick_gemini_model` + `_run_with_timeout` 단일 진실원. Preamble 0.1 cfg.env 끝에 `source gemini-helper.sh` auto-append → 모든 후속 Bash 블록이 `source cfg.env` 한 줄로 **변수+함수 둘 다** 바인딩. SKILL.md 8 + refs/*.md 3 = 11 블록에 source 가드 자동 삽입 (Python regex). bug_007이 문서에만 반영되던 근본 결함 해결.

(C2) SKILL.md Phase 0.3 `_CODEMAP_RC=$?` 고아 할당 제거 — if/elif/else rc를 마지막 assignment 0이 덮어쓰던 bug_020.

(C3) `tests/bash-runtime-validation.sh` 신규 — 자기충족 grep을 넘어 실제 bash subprocess로 Preamble 0.1 cross-invocation 시뮬레이션 + 함수 바인딩 + guard 커버리지 동적 검증. Ultra 메타 분석의 핵심 발견(129 PASS 자기충족 패턴) 극복.

Ultra 메타 분석 산출물: `docs/team-agent/2026-04-25-012148-meta-report.md` (25KB, 64 findings + 41 ideas).
