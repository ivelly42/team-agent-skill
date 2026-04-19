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
[2026-04-20] Codex 12차 findings 2건 수정: (1) Test 8 Pass A를 CLI_RE pre-check 없이 unconditional — `_run_with_timeout`으로 시작하는 모든 command를 child 검증. `_run_with_timeout 300 30 bash -lc "$CMD"` / `_run_with_timeout 300 30 run_backend` 같은 variable/function indirection bypass 차단. (2) CI workflow jsonschema를 `==4.24.0`으로 pin + `importlib.metadata.version()` 사용 — 비헤메틱 latest-install 경로 제거. Test 10 fixture 15→18개(`bash -c var indirection`, `function indirection`, `codex login (wrapped, CLI 없음)` 추가), signature `cb5128e7f50c...`. REQUIRED_BYPASS 12개 / REQUIRED_OK 6개. smoke 10/10 + schema 6/6 = 16 PASS. Codex 13차 대기.
