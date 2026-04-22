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
[2026-04-23] Codex round-3 adversarial review 3개 finding을 실행 레벨까지 전부 수정. **최종 121/121 PASS** (smoke 10 + schema 6 + gemini-probe 6 + flag-combos 8 + manifest-migration 23 + sanitizer-regression 21 + ultra-selective-topology 11 + config-loading 8 + config-wired-in-exec 8 + config-fail-closed 10 + verification-wired 10). 핵심 변경: (1) Finding #1 해결 — Preamble 0.1 fail-closed 전환. mktemp 기반 secure tempfile + Python 로더 exit code 체크 + source 실패 시 abort + `_CFG_*` sanity check loop + JSON 파싱 실패 시 한글 에러. 실행 블록의 `${_CFG_*:-default}` 폴백 8곳 전부 `${_CFG_*}`로 교체. (2) Finding #2 해결 — `refs/cross-verification.md` + `refs/gemini-verification.md` 두 파일의 pinned `gemini-3.1-pro-preview` → `_pick_gemini_model verifier`, `_run_with_timeout 300 30` → `$_CFG_VERIFY_SEC`/`$_CFG_GRACE_SEC`. Gemini 모델 할당이 `_run_with_timeout` 래퍼 호출 전에 위치. (3) Finding #3 해결 — `ultra_replication()` + `ultra_replicas_for_cost()` 2-replica baseline 강제 (≤×0.7도 `["claude","codex"]`). Codex 미설치 fail-safe로 Gemini 보강. 양쪽 미설치 시 ULTRA_MODE=false 다운그레이드 + Phase 4-A-2 정규 검증. selective 5역할 9→11명 (~40% → ~25% 절감), 독립 검증 보장. (4) 회귀 smoke 2종 신규 (config-fail-closed 10 + verification-wired 10) + ultra-selective-topology 8→11 확장 (2-replica + fail-safe + 다운그레이드 분기 검증). 이전 Codex round-2 (`bb48631`+`acf6b08`) 누적.
