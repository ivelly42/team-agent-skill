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
[2026-04-20] Codex 14차 findings 2건 수정: (1) split_commands / split_single_cmd에 `$(...)` + backtick nesting 깊이 추적 — 내부 `|`/`&`는 top-level operator 아님. `_run_with_timeout ... $(cat a | wc -l)` 더 이상 false positive 아님. (2) `strip_leading_modifiers` / `starts_in_subshell`이 `(foo` 붙은 paren도 인식 — `(_run_with_timeout ...) &` 공백 유무와 무관하게 subshell 면제 적용. Test 10 fixture 24→26 (cmd-subst pipeline inside, attached paren subshell), signature `6771d62ca941...`. REQUIRED_BYPASS 17 / REQUIRED_OK 9. smoke 10/10 + schema 6/6 = 16 PASS. Codex 15차 대기.
