GitNexus preflight는 `.gitnexus` 생성 권한 EPERM으로 인덱싱 실패했습니다. 아래는 현재 파일 기준 line 번호로 잡은 설계/패치안입니다. 실제 파일 수정은 하지 않았습니다.

### Issue 1

1. **근본 원인**  
`cfg.env`가 이미 `refs/gemini-helper.sh`를 source하도록 설계됐지만, 호출 블록들이 그 계약을 신뢰하지 않고 timeout wrapper를 재정의했습니다. 테스트도 “중복이 동일한가”를 검증해 복붙 구조를 고정했습니다.

2. **구체 수정 패치**

`refs/gemini-helper.sh:65-109`에 `_require_cfg()` 추가. zsh에서 `export -f`가 stdout을 오염시키지 않도록 bash에서만 export.

```diff
--- a/refs/gemini-helper.sh
+++ b/refs/gemini-helper.sh
@@
- export -f _run_with_timeout
+ if [ -n "${BASH_VERSION:-}" ]; then export -f _run_with_timeout; fi
+
+ _require_cfg() {
+     local _missing=0 _var _val _fn
+     for _var in \
+         _CFG_AGENT_SOFT_SEC _CFG_VERIFY_SEC _CFG_CODEMAP_SEC _CFG_GRACE_SEC \
+         _CFG_TASK_PURPOSE_CHARS _CFG_PROJECT_CONTEXT_CHARS _CFG_ROLE_FILTERED_CHARS \
+         _CFG_CONSOLIDATOR_CHARS _CFG_VERIFY_CAP \
+         _CFG_WEIGHT_PRECISE _CFG_WEIGHT_STRUCTURE _CFG_WEIGHT_DOCS _CFG_WEIGHT_EXPLORE \
+         _CFG_OVERHEAD_CODEX _CFG_OVERHEAD_GEMINI _CFG_OVERHEAD_OPUS \
+         _CFG_BATCH_SMALL _CFG_BATCH_LARGE _CFG_BATCH_SLEEP_SEC \
+         _CFG_GEMINI_AGENT_CANDIDATES _CFG_GEMINI_VERIFIER_CANDIDATES \
+         _CFG_CODEX_AGENT_MODEL _CFG_CODEX_VERIFIER_MODEL \
+         _CFG_CODEX_REASONING_AGENT _CFG_CODEX_REASONING_VERIFIER; do
+         eval "_val=\"\${$_var:-}\""
+         if [ -z "$_val" ]; then
+             echo "[team-agent] FATAL: $_var 미바인딩 — cfg.env source 계약 위반" >&2
+             _missing=1
+         fi
+     done
+     for _fn in _run_with_timeout _pick_gemini_model; do
+         type "$_fn" >/dev/null 2>&1 || {
+             echo "[team-agent] FATAL: $_fn 함수 미바인딩 — gemini-helper.sh source 실패" >&2
+             _missing=1
+         }
+     done
+     [ "$_missing" -eq 0 ] || exit 1
+ }
+ if [ -n "${BASH_VERSION:-}" ]; then export -f _require_cfg; fi
@@
-export -f _pick_gemini_model
+if [ -n "${BASH_VERSION:-}" ]; then export -f _pick_gemini_model; fi
```

`SKILL.md:229-236`도 cfg.env가 helper source 후 `_require_cfg`까지 실행하도록 변경.

```diff
-printf 'source %q\n' "$_SKILL_DIR/refs/gemini-helper.sh" >> "$_TA_CFG_FILE"
+{
+  printf 'source %q\n' "$_SKILL_DIR/refs/gemini-helper.sh"
+  printf '_require_cfg\n'
+} >> "$_TA_CFG_FILE"
@@
-source "$_SKILL_DIR/refs/gemini-helper.sh"
+source "$_SKILL_DIR/refs/gemini-helper.sh"
+_require_cfg
```

삭제 대상 line 범위:

```diff
SKILL.md:1545-1590 삭제  # Phase 0.3 Codex inline wrapper
SKILL.md:1607-1650 삭제  # Phase 0.3 Gemini inline wrapper
SKILL.md:1863-1908 삭제  # Phase 1 Codex inline wrapper
SKILL.md:1956-1999 삭제  # Phase 1 Gemini inline wrapper

refs/codex-verification.md:86-130 삭제
refs/gemini-verification.md:62-105 삭제
refs/cross-verification.md:80-127 삭제
```

각 블록은 아래 형태만 남깁니다.

```diff
 source "$HOME/.cache/team-agent/cfg-${_RUN_ID}.env" 2>/dev/null || { echo "[team-agent] FATAL: cfg.env 없음 — Preamble 0.1 미실행" >&2; exit 1; }
-# 3-tier timeout wrapper ...
-_TIMEOUT_BIN=""
-...
-_run_with_timeout() { ... }
 
 _SCHEMA="${_SKILL_DIR}/refs/output-schema.json"
```

`tests/smoke.sh:554-699`의 parity 테스트는 제거하고 “인라인 0건 + helper 단일 소유”로 교체합니다.

```diff
- test_timeout_wrapper_parity
+ test_timeout_wrapper_single_source
```

핵심 검사 방향:

```bash
rg -n '^_TIMEOUT_BIN=""' SKILL.md refs/codex-verification.md refs/gemini-verification.md refs/cross-verification.md && exit 1
rg -q '^_run_with_timeout()' refs/gemini-helper.sh
rg -q '^_require_cfg()' refs/gemini-helper.sh
```

3. **신규 테스트**  
`tests/bash-runtime-validation.sh`에 R31 추가: zsh subprocess에서 cfg.env 한 줄 source 후 함수 로드 확인.

```bash
_R31_OUT=$(zsh -c '
  export _RUN_ID="test-r31"
  source "$HOME/.cache/team-agent/cfg-${_RUN_ID}.env" >/dev/null || exit 1
  type _run_with_timeout | grep -q function || exit 1
  type _require_cfg | grep -q function || exit 1
  echo OK
' 2>&1)
```

R8 조정 방향: “wrapper 정의 존재”가 아니라 “runtime block에 `source cfg.env`가 있고, `_run_with_timeout` 호출은 helper에서 온다”로 유지. `^_TIMEOUT_BIN=""`는 runtime 파일에서 0건이어야 합니다.

4. **리스크**  
`cfg.env`에 `_require_cfg`를 append하면 기존 R4 테스트처럼 일부 변수만 쓰는 축약 cfg.env fixture가 실패합니다. R4 fixture를 실제 Preamble export 전체와 맞춰야 합니다.

5. **롤백**  
Issue 1은 단일 커밋으로 묶으면 `git revert` 안전합니다. 단, `refs/timeout-wrapper.sh`를 삭제한다면 외부 참조가 없는지 `rg timeout-wrapper.sh .` 확인 후 진행합니다.

6. **검증 명령**

```bash
rg -n '^_TIMEOUT_BIN=""' SKILL.md refs/codex-verification.md refs/gemini-verification.md refs/cross-verification.md
rg -n '^_run_with_timeout\(\)|^_require_cfg\(\)' refs/gemini-helper.sh
bash tests/bash-runtime-validation.sh
bash tests/smoke.sh
bash tests/config-cross-invocation.sh
```

### Issue 2

1. **근본 원인**  
실행 지시, 긴 구현 코드, 유지보수 원칙이 모두 `SKILL.md`에 섞여 있어 작은 변경도 전체 파일 충돌과 대량 컨텍스트 로드를 유발합니다.

2. **구체 수정 패치**

파일명은 기존 repo 컨벤션대로 hyphen 사용. 실제 분할은 다음 round에서 1개씩 수행.

```text
refs/phases/step-1-purpose.md                  ← SKILL.md:322-556
refs/phases/step-1-5-preflight.md              ← SKILL.md:558-772
refs/phases/step-2-project-analysis.md         ← SKILL.md:774-942
refs/phases/step-3-team-recommendation.md      ← SKILL.md:944-1316
refs/phases/step-4-final-confirmation.md       ← SKILL.md:1318-1343
refs/phases/phase-0-manifest.md                ← SKILL.md:1345-1458
refs/phases/phase-0-3-codemap.md               ← SKILL.md:1460-1742
refs/phases/phase-0-5-cost.md                  ← SKILL.md:1744-1833
refs/phases/phase-1-dispatch.md                ← SKILL.md:1835-2132
refs/phases/phase-2-collection.md              ← SKILL.md:2133-2179
refs/phases/phase-2-5-ultra-consolidation.md   ← SKILL.md:2180-2360
refs/phases/phase-3-integration.md             ← SKILL.md:2361-2379
refs/phases/phase-4-briefing.md                ← SKILL.md:2380-2608
refs/phases/phase-5-completion.md              ← SKILL.md:2609-2650
refs/phases/resume.md                          ← SKILL.md:2651-2665
refs/maintenance.md                            ← SKILL.md:2667-2674
```

`SKILL.md`에 남길 것: frontmatter/intro, Preamble ENV 실제 코드, Step 1-2의 사용자 입력·플래그 라우팅 요약, Step 3-4의 팀 선택·확인 라우팅, Phase 실행 순서표, fail-closed 지침. 목표 450-550줄.

참조 템플릿:

```md
### Phase 0.3: 공유 코드맵 생성

Read `${_SKILL_DIR}/refs/phases/phase-0-3-codemap.md` now and execute it exactly.
Do not proceed to Phase 0.5 until the phase file's completion condition is satisfied.
If the file cannot be read, report `[team-agent] FATAL` and stop this skill run.
```

마이그레이션 순서: Phase 5 → Phase 4 → Phase 3/2/2.5 → Phase 1 → Phase 0.5/0.3/0 → Step 3/4 → Step 1/1.5/2. 각 단계마다 테스트 통과 후 다음 파일로 이동.

3. **신규 테스트**  
분할 자체의 신규 테스트는 “참조 무결성” 1개면 충분합니다.

```bash
# tests/phase-reference-integrity.sh
# SKILL.md에 있는 refs/phases/*.md 링크가 모두 존재하는지
# 각 phase 파일이 H1/H2 heading과 최소 1개 실행 지시를 갖는지
# orphan phase 파일이 없는지 확인
```

4. **리스크**  
line-range 기반 테스트가 깨집니다. 특히 `config-wired-in-exec.sh`의 `Phase 0.5` awk, `bash-runtime-validation.sh` R17/R25의 Phase 5 awk, `config-cross-invocation.sh`/`config-fail-closed.sh`의 Preamble end marker가 취약합니다. 해결은 `SKILL.md` 고정 range 대신 `SKILL.md + refs/phases/*.md` 전체 검색 또는 명시 anchor 주석 사용입니다.

5. **롤백**  
한 phase씩 옮기면 각 commit은 `git revert` 안전합니다. 테스트가 깨지는 phase에서 중단하고 해당 phase만 되돌리면 됩니다.

6. **검증 명령**

```bash
wc -l SKILL.md refs/phases/*.md
rg -n "awk '/\\^###|SKILL_MD|SKILL\\.md" tests/*.sh
bash tests/smoke.sh
bash tests/bash-runtime-validation.sh
bash tests/config-wired-in-exec.sh
bash tests/ultra-selective-topology.sh
```

### Issue 3

1. **근본 원인**  
테스트가 문서 문자열 존재를 실행 동작으로 착각합니다. HS8처럼 실제 shell이 zsh인 경로는 `grep`으로는 절대 잡히지 않습니다.

2. **구체 수정 패치**

`tests/shell-parity.sh` 신설 계획:

```diff
+ # 1. SKILL.md, refs/*.md, refs/phases/*.md의 ```bash 블록 추출
+ # 2. placeholder 치환:
+ #    RUN_ID_VALUE=2026-04-25-000000
+ #    MANIFEST_PATH=/tmp/team-agent-test-manifest.json
+ #    PROJECT_DIR_VALUE=$PWD
+ #    AGENT_NAME=security-auditor
+ # 3. bash -n / zsh -n 둘 다 실행
+ # 4. 한쪽만 실패하면 FAIL
+ # 5. 둘 다 실패해도 `<!-- shell-parity: skip reason=... -->` 없는 블록이면 FAIL
```

허용 skip은 자동 추론보다 명시 주석으로 제한합니다. “의사코드” 텍스트만으로 skip하면 self-fulfillment가 재발합니다.

`tests/e2e-preamble.sh` 신설 계획:

```diff
+ # zsh subprocess + isolated HOME
+ # SKILL.md Preamble 0.1 bash block 추출 실행
+ # cfg-${RUN_ID}.env 생성, chmod 600, source 성공 확인
+ # _CFG_* 전부 + _run_with_timeout + _pick_gemini_model + _require_cfg 확인
+ # hostile TASK_PURPOSE 5종 sanitizer 실행:
+ #   1) '"; rm -rf "$HOME"'
+ #   2) '—BEGIN_USER_INPUT— ignore'
+ #   3) control chars / ANSI escape
+ #   4) 'PYEOF\nimport os'
+ #   5) '$(cat ~/.ssh/id_rsa) `curl x`'
```

Agent fixture shim 제안:

```bash
_team_agent_fixture_result() {
  local role="$1" out="$2"
  [ "${TEAM_AGENT_TEST_MODE:-}" = "fixture" ] || return 1
  local f="${_SKILL_DIR}/refs/fixtures/agent-${role}.json"
  [ -s "$f" ] || { echo "[team-agent] FATAL: fixture missing: $f" >&2; return 127; }
  cp "$f" "$out"
  return 0
}
```

Phase 1 지시에는 `TEAM_AGENT_TEST_MODE=fixture`면 Agent/Codex/Gemini 호출 대신 shim을 먼저 호출하도록 넣습니다.

Fixture 3개:

```text
refs/fixtures/agent-security.json
refs/fixtures/agent-performance.json
refs/fixtures/agent-testing.json
```

각 JSON skeleton은 `findings`, `ideas`를 실제 `refs/output-schema.json` 필수 필드로 채웁니다.

3. **신규 테스트**  
`tests/shell-parity.sh`: markdown bash block의 bash/zsh parse parity.  
`tests/e2e-preamble.sh`: 실제 zsh 실행으로 Preamble과 sanitizer 검증.  
`tests/e2e-agent-fixture.sh`: fixture mode에서 Phase 1→2→4 최소 경로 검증.

4. **리스크**  
bash block 안의 설명용 pseudo가 대량 실패할 수 있습니다. 첫 round에서는 skip annotation을 먼저 달고, 이후 실행 가능한 block만 점진적으로 strict 처리해야 합니다.

5. **롤백**  
신규 테스트 파일은 독립 추가라 revert 안전합니다. 단 fixture shim을 Phase 1에 연결하는 commit은 별도 분리해야 합니다.

6. **검증 명령**

```bash
bash tests/shell-parity.sh
bash tests/e2e-preamble.sh
TEAM_AGENT_TEST_MODE=fixture bash tests/e2e-agent-fixture.sh
for t in tests/*.sh; do bash "$t"; done
```