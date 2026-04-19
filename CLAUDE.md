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
[2026-04-20] Codex 7차 findings 2건 수정: (1) Test 8 command-level state machine 재작성 — `FOO=1 timeout 300 codex exec` · `env timeout` prefix 포함 모든 비-`_run_with_timeout` launcher 거부, (2) SKILL.md 4곳 + codex/gemini-verification.md 인라인 watchdog body를 canonical(refs/timeout-wrapper.sh)과 byte-parity 동기화 — `if not cmd` empty guard, `cmd not found` diagnostic, `124 if rc in (0, -SIGTERM)` 정규화 추가. Test 9 parity 추가. smoke 9/9 + schema 6/6 = 15 PASS. Codex 8차 검증 대기.
