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
[2026-04-20] Bug #2(Gemini refs 환경독립 추상화) + G-S1(TEAM_AGENT_META $HOME whitelist) 적용. refs/gemini-agent-template.md와 refs/codemap-generator.md의 Gemini 섹션을 outcome 기반 추상화로 전환해 gstack-augmented Gemini CLI(`grep_search`/`read_file`만) 환경과 표준 Gemini CLI 모두 정확히 동작. SKILL.md Step 2-10은 `TEAM_AGENT_META=true`일 때 realpath 해소 후 `$HOME` 하위 경로만 허용(임의 경로 injection 차단). smoke.sh I10을 3-case(baseline/in-home/outside) 검증으로 확장. smoke 10/10 + schema 6/6 = 16 PASS. Codex verify-fix loop는 25차로 재개하지 않음(convergence 보장 없는 loop, 실제 기능 버그 발견 시에만 단일 fix 모드 진입). C1(prompt cache)은 Claude Code Agent 도구가 skill 레벨에서 cache_control 미노출로 skip(harness 변경 영역).
