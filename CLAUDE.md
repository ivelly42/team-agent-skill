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
[2026-04-20] Codex adversarial finding #1 수정: `refs/cross-verification.md` 실행 블록에 포터블 timeout 래퍼 + per-process rc 캡처 + 3단계 검증(rc/empty/json) + 4-way fallback 매트릭스(full_3way/codex_only/gemini_only/skipped) 구현. `manifest.verification`에 mode·rc·failed_reason·duration_sec 필드 추가. 스키마에 verification_mode enum 추가, SKILL.md Phase 4-A-2 폴백 서술 동기화.
