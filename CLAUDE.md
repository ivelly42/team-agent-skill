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
[2026-04-20] Codex 8차 findings 2건 수정: (1) Test 8에 argv child check 추가 — `_run_with_timeout <secs> <grace> <child>`의 child가 codex/gemini가 아니면 violation. `_run_with_timeout 300 30 bash -lc 'codex exec ...'` 같은 nested shell wrapper 거부. strip_quoted_regions로 따옴표 내부 CLI substring false positive 제거. (2) Test 9를 canonical byte-exact 비교로 대체 — `refs/timeout-wrapper.sh` Python body를 source-of-truth로 삼아 SKILL.md 4 + cross/codex/gemini-verification.md 3 = 총 7곳 인라인과 SHA256 대조 (현재 hash `7c923c0bc49f`로 통일). cross-verification.md body의 부가 주석 제거로 canonical parity 완성. smoke 9/9 + schema 6/6 = 15 PASS. Codex 9차 대기.
