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
[2026-04-20] Codex 10차 findings 2건 수정: (1) Test 9가 Python watchdog body만 비교하던 것을 full wrapper block(`_TIMEOUT_BIN=""` 부터 `_run_with_timeout() { ... }` closing `}` 까지, preamble 선택 로직 + argument plumbing + return handling 포함) byte-exact 비교로 확장 — shell-side drift도 감지. 7 인라인 모두 canonical(refs/timeout-wrapper.sh)과 byte-identical하게 재작성, pinned hash `8c217c34c677edef9ea43cefcf89cb926cbc4afff39e0e3c20a8beebd89eaffb`. (2) Test 10 `EXPECTED_FIXTURE_COUNT = 15` assertion 추가 — 향후 fixture 축소가 CI 통과되는 shrinkage regression 방지. smoke 10/10 + schema 6/6 = 16 PASS. Codex 11차 대기.
