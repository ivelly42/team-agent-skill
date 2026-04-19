# Gemini 독립 분석 절차 (`--gemini` 단독 모드)

`--gemini hybrid` 또는 `--gemini all` 모드에서 Phase 4-A-2의 역검증자로 사용된다.
Claude 에이전트 결과 → Gemini가 독립 분석 → 대조 검증의 2단계.
(`--cross` 모드에서는 `refs/cross-verification.md`의 3중 검증 알고리즘을 사용한다. 이 파일은 단독 `--gemini` 모드 전용.)

## 실행 조건

다음 모두 충족 시 실행:
1. `gemini` CLI가 설치되어 있음 (`command -v gemini`)
2. 성공한 에이전트가 1명 이상
3. Critical 또는 High 발견 1건 이상, 발견 0건, 또는 Medium 5건 이상

**조건 미충족**: 건너뛰고 Phase 5로 진행. "Gemini 검증: 건너뜀" 표시.

## 프롬프트 구성

Phase 4-A-2 도달 시 에이전트 보고 JSON에서 finding/idea를 추출하여 Gemini에 전달.

**보안 원칙**: 모든 동적 값은 Write 도구 → 파일 → Gemini stdin 패턴. 셸 인젝션 차단.

### 프롬프트 조립 및 실행

1. **Write 도구**로 `/tmp/ta-${_RUN_ID}-gemini-verify.txt`에 프롬프트 저장:

```
너는 독립 분석자다. 아래 프로젝트를 직접 분석하라.
다른 AI 팀이 이미 분석을 수행했으나, 그 결과는 네가 분석을 완료한 후에만 참고하라.

**1단계: 독립 분석** (먼저 수행)
프로젝트의 실제 코드를 직접 읽고 다음을 분석하라:
- 작업 목적에 해당하는 핵심 이슈 (보안, 성능, 품질 등)
- 놓치기 쉬운 엣지 케이스
- 개선 아이디어

**반증 시도 (필수)**: 각 팀 finding에 대해 먼저 반증을 시도하라. 상위/하위 컨텍스트를 읽고 이미 존재하는 방어 장치(프레임워크 자동 보호, 상위 호출자 검증)를 확인하라. 반증 실패한 것만 검증 대상으로 올려라.

프로젝트 경로: {PROJECT_DIR}
작업 목적: {TASK_PURPOSE}

**2단계: 대조 검증** (1단계 완료 후)
아래 팀 결과와 네 분석을 대조하라:

== 팀 발견 사항 ==
{FINDINGS_SUMMARY — 심각도 높은 순, 2000자 이내}

== 팀 아이디어 ==
{IDEAS_SUMMARY — 영향 높은 순, 1000자 이내}

각 항목에 대해 다음 중 하나로 판정:
- ✅ 검증됨 (Gemini도 동일 결론)
- ❗ 이의 (근거 부족, severity 부적절 등)
- 🔍 추가 발견 (팀이 놓친 이슈)

출력은 이모지 + 3-5줄 설명 형식.
```

2. **Bash 도구**로 gemini 실행 — **hard timeout 필수** (Codex adversarial finding B):

```bash
_PROMPT="/tmp/ta-${_RUN_ID}-gemini-verify.txt"
_OUTPUT=$(mktemp "/tmp/ta-${_RUN_ID}-gemini-verify-output.XXXXXX")
_RC_FILE=$(mktemp "/tmp/ta-${_RUN_ID}-gemini-verify-rc.XXXXXX")

# 포터블 timeout: GNU timeout → gtimeout → Python watchdog (bare macOS 호환)
# refs/cross-verification.md의 `_run_with_timeout`과 동일한 3-tier fallback.
# 네트워크/인증 wedge 또는 대형 repo stall 시 5분 이내 강제 종료.
_TIMEOUT_BIN=""
if command -v timeout >/dev/null 2>&1; then _TIMEOUT_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then _TIMEOUT_BIN="gtimeout"
fi

if [ -n "$_TIMEOUT_BIN" ]; then
  "$_TIMEOUT_BIN" -k 30 300 \
    gemini -m gemini-3.1-pro-preview -p - < "$_PROMPT" > "$_OUTPUT" 2>/dev/null
  _GEMINI_RC=$?
else
  # Python watchdog (stdin 보존 — `-c` argv, heredoc 절대 금지)
  python3 -c '
import os, signal, subprocess, sys
secs=int(sys.argv[1]); grace=int(sys.argv[2]); cmd=sys.argv[3:]
try:
    p = subprocess.Popen(cmd, start_new_session=True, stdin=sys.stdin)
except FileNotFoundError: sys.exit(127)
try:
    rc = p.wait(timeout=secs); sys.exit(rc)
except subprocess.TimeoutExpired:
    try: os.killpg(p.pid, signal.SIGTERM)
    except ProcessLookupError: pass
    try: p.wait(timeout=grace); sys.exit(124)
    except subprocess.TimeoutExpired:
        try: os.killpg(p.pid, signal.SIGKILL)
        except ProcessLookupError: pass
        p.wait(); sys.exit(137)
' 300 30 gemini -m gemini-3.1-pro-preview -p - < "$_PROMPT" > "$_OUTPUT" 2>/dev/null
  _GEMINI_RC=$?
fi

# 검증 3단: rc / output 비어있지 않음 / 타임아웃 아님
if [ "$_GEMINI_RC" -eq 0 ] && [ -s "$_OUTPUT" ]; then
  cat "$_OUTPUT"
else
  case "$_GEMINI_RC" in
    124) echo "[gemini-verification] 5분 타임아웃 — 검증 건너뜀" >&2 ;;
    137) echo "[gemini-verification] SIGKILL (grace 초과) — 검증 건너뜀" >&2 ;;
    127) echo "[gemini-verification] gemini CLI 미설치 — 검증 건너뜀" >&2 ;;
    *)   echo "[gemini-verification] 실패 rc=$_GEMINI_RC — 검증 건너뜀" >&2 ;;
  esac
fi
rm -f "$_PROMPT" "$_OUTPUT" "$_RC_FILE"
```

**모델**: 검증은 정밀도가 필요하므로 `gemini-3.1-pro-preview` 사용 (Flash 아님).
**타임아웃**: 5분(실제 enforced), 30초 SIGTERM grace, 이후 SIGKILL. 초과 시 Gemini 검증 실패로 기록, 에이전트 결과만 사용.

## 출력 처리

Gemini 응답은 자유 형식 텍스트 (이모지 기반). JSON 파싱 불필요.
Phase 4-A-3 채팅 출력의 "Gemini 검증 쟁점" 테이블에 반영.

## fallback

- gemini 미설치 → "Gemini 검증: 건너뜀 (gemini 미설치)" 표시
- gemini 타임아웃/에러 → 에이전트 결과만 사용 + "Gemini 검증 실패" 경고
