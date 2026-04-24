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
[2026-04-25] round-6 — **codex 모델·effort 명시 고정** (user config.toml drift 차단). 최종 **143/143 PASS** (bash-runtime-validation R11-R14 신규 + 기존 139 유지).

핵심: `refs/config.json`에 `codex` 섹션 추가 (`agent_model`·`verifier_model`·`reasoning_effort_agent`·`reasoning_effort_verifier` = `gpt-5.5`/`gpt-5.5`/`xhigh`/`xhigh`). Preamble 0.1 Python loader가 `_CFG_CODEX_*` 4개 env var export + sanity check 포함. 모든 `codex exec` 호출 (Phase 0.3 codemap + Phase 1 agent + refs/codex-verification + refs/cross-verification) 에 `-m "$_CFG_CODEX_AGENT_MODEL"` 또는 `_VERIFIER_MODEL` + `-c "model_reasoning_effort=\"$_CFG_CODEX_REASONING_AGENT\""` 또는 `_VERIFIER` 명시. user가 `~/.codex/config.toml`의 default를 바꿔도 스킬은 선언한 모델·effort 강제. override는 `refs/config.local.json`의 `codex` 섹션으로.

(이전 round-5 유지) `refs/gemini-helper.sh` 단일 진실원 + cfg.env 자동 소싱 + 11개 bash 블록 source 가드 + Phase 0.3 고아 rc 제거 + `bash-runtime-validation.sh` 런타임 검증.

메타 분석 산출물: `docs/team-agent/2026-04-25-012148-meta-report.md` (25KB, 64 findings + 41 ideas).
