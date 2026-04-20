# 플래그 조합 규칙 매트릭스

SKILL.md Step 1-1.5에서 Read로 로드. 신규 플래그 추가 시 이 파일만 수정.

## 분류 체계

- **허용**: 두 플래그 공존 OK. 부가 효과 설명
- **충돌**: 동시 사용 불가. 경고 메시지 + 종료
- **다운그레이드**: 누락된 요건 자동 보정. 경고 메시지 + 진행
- **오버라이드**: 한쪽이 다른쪽을 무시. 경고 메시지 + 진행

## 매트릭스

| 조합 | 동작 |
|------|------|
| `--help` + 모든 플래그 | 허용 (우선). 도움말만 출력하고 즉시 종료 |
| `--dry-run` + `--auto` | 허용. AI 추천 팀 구성 + 프롬프트 미리보기만 (파일 생성 없음) |
| `--dry-run` + `--deep` | 허용. 프롬프트에 통합 에이전트 포함하여 미리보기 |
| `--dry-run` + `--resume` | **충돌**. "dry-run과 resume는 함께 사용할 수 없습니다" 경고 후 종료 |
| `--diff` + `--auto` | 허용. 변경 파일 집합만 대상으로 자동 실행 |
| `--diff` + `--scope` | 허용. diff 결과를 scope 하위 파일로 한 번 더 제한 |
| `--diff` + `--resume` | **충돌**. resume는 이전 실행 대상을 복원하므로 새 diff 기준을 받을 수 없음 |
| `--diff` + `--deep` | 허용. 변경 범위 기준 분석 후 통합 라운드까지 실행 |
| `--resume` + `--scope` | **충돌**. 원래 실행의 scope를 따름. 새 scope 무시 + 경고 |
| `--resume` + `--auto` | 오버라이드. 원래 실행 설정 유지. --auto 무시 + 경고 |
| `--resume` + `--deep` | 허용. 원래 실행에 --deep이 없었어도 이번에 추가 가능 |
| `--resume` + `--notify` | 허용. 이번 실행에서 알림 추가 |
| `--scope` + `--auto` | 허용. 해당 scope 내에서 자동 실행 |
| `--notify` + 모든 플래그 | 허용. 다른 플래그에 영향 없음 |
| `--auto` + 빈 TASK_PURPOSE | **충돌/오류**. "--auto 모드에서는 작업 목적이 필수입니다" 경고 후 종료 |
| `--codex` + `--deep` | 허용. 통합 에이전트는 Claude Agent로 실행 |
| `--codex` + 권한 A(bypassPermissions) | **충돌**. codex exec에 worktree 격리 없음. 읽기 전용 강제 + 경고 |
| `--codex` + `--resume` | 허용. manifest의 `agent_backends` 딕셔너리로 원래 백엔드 복원 |
| `--codex` 미설치 | **다운그레이드**. 경고 "codex CLI 미설치 — Claude Agent로 폴백" 후 정상 진행 |
| `--codex` + `--gemini` | **충돌**. "두 플래그 동시 사용 불가. 3개 모두 원하면 `--cross`" 경고 후 종료 |
| `--cross` + `--codex` | **충돌**. `--cross`가 이미 Codex 포함 |
| `--cross` + `--gemini` | **충돌**. `--cross`가 이미 Gemini 포함 |
| `--gemini` 미설치 | **다운그레이드**. 경고 "gemini CLI 미설치 — Claude로 폴백" 후 진행. `--cross`는 Codex 전용 2중 검증으로 다운그레이드 |
| `--gemini` + 권한 A (bypassPermissions) | **충돌**. gemini에 worktree 격리 없음. 읽기 전용 강제 + 경고 |
| `--cross` + 권한 A | **충돌**. 동일 사유 (Codex·Gemini 모두 격리 없음). 읽기 전용 강제 + 경고 |
| `--gemini` + `--resume` | 허용. manifest의 `agent_backends` 딕셔너리로 원래 백엔드 복원 |
| `--cross` + `--resume` | 허용. manifest의 `cross_mode`·`agent_backends`·`codemap_backend` 복원 |
| `--cross` + `--auto` | 허용. 권한 B(읽기 전용) 강제 |
| `--gemini`/`--cross` + `--scope`·`--diff`·`--dry-run`·`--deep`·`--notify` | 허용. 각 플래그 원래 의미 유지 |
| `--ultra` + `--codex` | **충돌**. `--ultra`가 이미 Codex 포함 |
| `--ultra` + `--gemini` | **충돌**. `--ultra`가 이미 Gemini 포함 |
| `--ultra` + `--cross` | **충돌**. 설계 모델이 다름 (`--cross`=분산, `--ultra`=복제). 양자택일 |
| `--ultra` + 권한 A(bypassPermissions) | **충돌**. Codex·Gemini 격리 불가 → 읽기 전용 강제 + 경고 |
| `--ultra` + codex 미설치 | **다운그레이드**. 경고 "codex CLI 미설치 — Ultra를 Claude+Gemini 2중으로 다운그레이드" |
| `--ultra` + gemini 미설치 | **다운그레이드**. 경고 "gemini CLI 미설치 — Ultra를 Claude+Codex 2중으로 다운그레이드" |
| `--ultra` + 양쪽 미설치 | **다운그레이드**. 경고 "외부 CLI 양쪽 미설치 — Ultra 무효, Claude 단독으로 진행" |
| `--ultra` + `--deep` | 허용. `--ultra`=역할 내 통합(Phase 2.5), `--deep`=역할 간 통합(Phase 3) — 계층 다름 |
| `--ultra` + `--resume` | 허용. manifest의 `agent_groups`·`ultra_mode`·`ultra_strategy` 복원 |
| `--ultra` + `--auto`/`--diff`/`--scope`/`--dry-run`/`--notify` | 허용. 각 플래그 원래 의미 유지 |
| `--ultra=selective` + 모든 Ultra 허용 조합 | 허용. 가중치별 선별 복제 로직만 다름 (SKILL.md `--ultra 라우팅` 섹션 참조) |
| `--codemap-skip` + 모든 플래그 | 허용. Phase 0.3만 스킵. 나머지 경로는 영향 없음 |

## 새 플래그 추가 체크리스트

1. 이 매트릭스에 기존 플래그와의 조합 행 추가
2. SKILL.md Step 1-1 파싱 섹션에 플래그 추출 규칙 추가
3. SKILL.md `## 옵션` 섹션 도움말에 설명 추가
4. `tests/flag-combinations.sh`에 smoke fixture 추가
5. manifest schema_version 증가 필요 시 `refs/migrate.py` 체인에 함수 추가
