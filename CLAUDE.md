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
[2026-04-20] Codex 9차 findings 2건 + 자발적 방어 추가: (1) Test 8 dual-pass + CLI pre-check: 원본(quoted 포함)에서 CLI 언급 있을 때만 감사 → `bash -lc 'codex exec'` nested wrapper도 Pass A로 캐치 (CLI가 quoted 안에만 있어도). (2) Test 9 pinned hash + exact counts: canonical SHA256 `7c923c0bc49f95deaee8d51931905dac8bc095cba5aad7ffbecf7bf45f9b80a1` 고정값 enforcement + per-file body count (SKILL.md=4, verification 3종=각1, total=7). coordinated drift / missing-copy 모두 실패. (3) 신규 Test 10: 15개 adversarial fixture (bash/sh/zsh/env/nohup wrapper, bare call, FOO= 우회, gtimeout prefix vs. direct children vs. quoted prose vs. codex login) 기대 결과 자동 검증 — 향후 Codex 공격 패턴 사전 차단. smoke 10/10 + schema 6/6 = 16 PASS. Codex 10차 대기.
