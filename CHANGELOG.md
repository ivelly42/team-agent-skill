# Changelog

team-agent 스킬의 주요 변경 이력. [Keep a Changelog](https://keepachangelog.com/ko/1.1.0/) 형식, [Semantic Versioning](https://semver.org/).

## [Unreleased] — 2026-04-20 환경독립 + 보안 하드닝

### 🛡️ Security
- **G-S1 TEAM_AGENT_META $HOME whitelist** — `TEAM_AGENT_META=true` override 사용 시 realpath 해소 후 `$HOME` 하위 경로만 허용. `/etc`, `/tmp/malicious`, `/root/...` 같은 임의 경로를 스킬 로직에 편입하려던 injection 경로 차단. 2026-04-19 Ultra 분석 Gemini 단독 finding(1/2 unique). smoke.sh I10을 3-case 검증(baseline/in-home/outside)으로 확장.

### 🟠 Fixed (High)
- **Bug #2 Gemini refs 환경독립 추상화** — `refs/gemini-agent-template.md`·`refs/codemap-generator.md`의 Gemini 섹션이 `find`/`grep`/`cat`/`head`/`sed` POSIX 셸 명령을 직접 지시하던 문제. gstack-augmented Gemini CLI(`grep_search`/`read_file`만 보유)에서 의미적 오지시. outcome 기반 추상화로 전환 — 도구명 대신 목표(구조 파악/정독/패턴 검색/LOC 계산) 명시, 도구 선택은 에이전트에 위임. 표준 Gemini CLI / gstack-augmented / 기타 환경 모두 동일 프롬프트로 동작.

### 🔬 Adversarial Hardening (22-round Codex verify-fix loop)
4~24차까지 Codex adversarial-review 22라운드 + 52커밋으로 다음 보안·정확성 개선:
- `validate_wrapped()` shlex `posix=True` 기반 재작성 — quoted `-p` bypass 차단 (`gemini "document -p behavior"` 같은 탈출 패턴).
- Gemini backend child contract 강화: `-p` flag 필수 검증 (stdin prompt 모드 강제, watchdog timeout hang 방지).
- ultra-consolidation-schema Draft-07 `allOf+if/then`: failure status면 `error` 필드 required + `minLength:1`, ok status면 `error` 금지.
- canonical timeout-wrapper hash `5c0c6d2c9e84` 고정 — SKILL.md 4곳 + refs 3종 총 7 inline copy가 byte-exact parity. SHA256 mismatch → FAIL-fast.
- 41개 adversarial fixture + `EXPECTED_FIXTURE_SIGNATURE` SHA256 pin. fixture 의도적 변경 시 상수도 함께 업데이트 강제.
- 3-tier timeout wrapper(`GNU timeout` → `gtimeout` → Python watchdog): fail-closed, 무한 대기 없음, deterministic rc (124 timeout / 137 SIGKILL / 127 not-found).

24차 Codex finding은 `posix=False` 결과 오인으로 밝혀진 false positive. 실측(`posix=True`)으로 반박 후 regression fixture를 명시 추가해 방어 증명.

### ✅ Verified
- `tests/smoke.sh`: **10/10 PASS**
- `tests/schema-validation.sh`: **6/6 PASS**
- canonical wrapper parity + 41 fixture signature pin + JSON schema Draft-07 조건부 required

---

## [2026-04-19 Ultra 품질 분석 후속 패치] — 이전 패치 계속

### 🔴 Fixed (Critical)
- **C1**: `gemini-3.1-flash-lite` → `gemini-3.1-flash-lite-preview` 6곳 수정 (SKILL.md line 1063/1066/1156/1245/1248/1254). 실제 Gemini API가 `-preview` 없는 alias를 404로 거부함을 실측 확인. 이 버그로 `--ultra`/`--gemini`/`--cross` 모드의 Gemini 경로 전체가 작동 불능 상태였음.

### 🟠 Fixed (High)
- **H4 부분**: Phase 0.3 codemap 생성과 Phase 1 Gemini 에이전트 실행의 `2>/dev/null` 제거, `/tmp/ta-${RUN_ID}-*-stderr.log`로 stderr 보존 + 실패 시 tail 출력 추가. 404·quota·network 에러 진단 가능.
- **H6**: `refs/output-schema.json`의 category enum(`ai-data`, `api-contract` 포함 9종)과 SKILL.md:806 프롬프트 예시(7종) drift 해소. 에이전트 JSON 출력이 RAG/API 카테고리를 표기하지 못하던 문제 수정.
- **H11**: `.history.json` → `.history.jsonl` 마이그레이션 one-liner를 `TypeError` 방어 + `ensure_ascii=False` + `encoding='utf-8'` + 원본 보존 패턴으로 재작성. list/dict 양쪽 입력 허용.
- **H15**: 업데이트 수동 안내의 `rm -rf ~/.claude/skills/team-agent` 파괴적 명령을 `mv ... .backup-$(date +%Y%m%d-%H%M%S)` 비파괴 백업 패턴으로 변경. 로컬 패치/커스텀 체크리스트 보존.

### 📘 Documentation
- README Workflow 표에 `--ultra` 행 추가, `cross` vs `ultra` 차이 설명(분산 vs 복제) 삽입.
- README Usage 섹션에 Ultra 예시 추가.
- README File Structure의 `schema v3` → `schema v4` 갱신 (2곳).
- CLAUDE.md Current Status 갱신.
- 메모리 `project_team_agent_v3_pending_bugs.md`에 Ultra 분석 세션 결과 추가.
- SKILL.md line 1254에 `-preview` 접미사 필수 경고 주석 삽입.
- SKILL.md line 1156 가격표 `gemini-3.1-flash-lite` → `-preview` 갱신.

### 📋 Reports
- `docs/team-agent/2026-04-19-212548-skill-improve-report.md` — 5 에이전트 교차 분석 상세 보고서 (69 findings, 46 ideas)
- `docs/team-agent/2026-04-19-212548-skill-improve-handoff.md` — 다른 AI 전달용 요약
- `docs/team-agent/.runs/2026-04-19-212548.json` — 실행 manifest (status=completed)

### ⚠️ Pending (이 세션에서 미적용, 보고서에 상세 기록)

다음 항목은 분석·진단은 완료됐으나 구현은 별도 세션 권장. 모두 `report.md` 섹션 3~5에 구체적 라인번호와 수정안 포함.

**Critical 미적용**
- **C2**: `mapfile` → POSIX `while IFS= read -r` 루프 (SKILL.md:353,381). macOS 기본 bash 3.2에서 `--diff` 실패.

**High 미적용** (15건)
- H1: `${SKILL_DIR}` vs `${_SKILL_DIR}` 변수 혼용 9곳 통일
- H2/H10: manifest `.gitignore` 자동 추가 + `agent_prompts` 참조 스키마로 경량화
- H3/H17: Python heredoc 7회 반복을 `refs/scripts/manifest_op.py` CLI로 추출
- H4 남은: 모든 외부 CLI 호출의 stderr 보존 정책 일괄 적용 (현재는 Phase 0.3 + Gemini 에이전트만)
- H7/H8/H9: sanitizer 지시 패턴 감지 + 시크릿 엔트로피 패턴(gitleaks 수준)
- H12: Phase 2.5 폴백 스키마 어댑터 (raw findings → consensus_findings)
- H13: `grep -rl` stem 휴리스틱 오탐 방어 (단어경계 + 길이 ≥5 + 상한 200)
- H14: `rg --files` 미설치 폴백 (find + grep -E)
- H16: Ultra 통합자 `model:"opus"` Sonnet 폴백 로직
- H18: Bash 24개 블록 `set -euo pipefail` 도입 (critical 블록부터)
- H19: Python `open()` 전부 `encoding='utf-8'` 명시
- H20: `json.dump(open(...))` → `with open(...) as f: json.dump(f)` context manager

**Medium/Low 미적용** (37건)
- DIFF_BASE `git rev-parse --` 구분자, SCOPE_PATH resolved 사용, TOCTOU 완화
- `/tmp` trap cleanup, manifest status 전이 기록, JSONL flock
- refs/ JSON 스키마 메타 표준화 (`$schema`/`title`/`description`/`version`)
- SRC_BYTES 타임아웃, TASK_PURPOSE 경계, Ultra 인식 삽입 위치 명시
- 42역할 풀 표 카테고리 구분선, AskUserQuestion 스키마 명시
- 용어 정의(정밀 분석 vs ×1.5 가중치), 어조 일관성 가이드, 번호체계 통일

### 🗂️ Schema Migration History
- v1 → v2: `diff_base`, `diff_target_files` 추가 (--diff 플래그 도입)
- v2 → v3: `gemini_mode`, `cross_mode`, `codemap_backend`, `codemap_path`, `verification` 추가
- v3 → v4: `ultra_mode`, `ultra_codex_avail`, `ultra_gemini_avail`, `agent_groups`, `per_role_integration` 추가
- 하위 호환: resume 시 이전 버전 manifest에 누락 필드 자동 주입

## [v3] — 2026-04-19 Triple-Check + Shared Codemap (25 commits)

### Added
- `--gemini [all|hybrid]`, `--cross`, `--ultra` 플래그
- 42개 역할 풀 (AI/데이터 5개, API/계약 4개 추가)
- Phase 0.3 공유 코드맵 생성 (Claude/Codex/Gemini 3 백엔드)
- Phase 2.5 Ultra 역할별 Opus 통합자
- Phase 4-A-2 분기 3: 3-way 합의 검증 (Cross)
- `refs/codemap-schema.json`, `refs/codemap-generator.md`, `refs/gemini-*.md`, `refs/cross-verification.md`, `refs/cross-verification-schema.json`
- manifest v4 (ultra_mode, agent_groups, per_role_integration)

### Changed
- schema_version 2 → 3 → 4 (하위 호환 마이그레이션 포함)
- 라우팅 표에 `--codex all|hybrid`, `--gemini all|hybrid`, `--cross` 열 추가

## [v2] — 2026-04 Incremental Analysis

### Added
- `--diff [base]` 플래그 (PR 리뷰용 변경 파일 bounded 분석)
- `--notify telegram` (실행 통계 요약 전송)
- import 1-hop + 계약 파일 자동 확장

## [v1] — 2026-03 Initial Release

- 17개 기본 역할 풀
- `--auto`, `--deep`, `--dry-run`, `--scope`, `--resume`, `--codex` 플래그
- Claude Agent 병렬 spawn (최대 3명 배치)
- Phase 0~5 워크플로
- manifest/history 기록
