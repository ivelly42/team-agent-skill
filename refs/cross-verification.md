# `--cross` 3중 검증 알고리즘

`--cross` 모드에서만 활성화. Codex와 Gemini를 동시에 독립 검증자로 투입하고, Claude 원본 판정과 함께 2/3 다수결로 severity 확정.

## 활성화 조건

다음 모두:
1. `--cross` 플래그 지정됨 (`CROSS_MODE=true`)
2. `codex` CLI + `gemini` CLI 모두 설치
3. 성공 에이전트 1명 이상

미충족 시 폴백:
- codex 만 가용 → `refs/codex-verification.md` 단독 모드
- gemini 만 가용 → `refs/gemini-verification.md` 단독 모드
- 둘 다 없음 → 검증 스킵

## 검증 대상 필터 (비용 제어)

전체 finding 중 아래만 검증 대상:
- severity ∈ {Critical, High} — 전체 포함
- severity == Medium && 2명 이상 에이전트가 동일 이슈 보고 — 교차확인 항목만
- severity == Low/Info — 검증 스킵

ideas:
- impact == high — 전체
- impact == medium && 2명 이상 제안 — 교차확인

## 프롬프트 (Codex·Gemini 동일 전달)

```
## 역할
너는 독립 검증자다. 1차 분석팀이 발견한 이슈를 직접 코드를 읽어 재평가하라.

## 검증 대상
{필터된 finding 목록 — finding_id, file, line_start, line_end, title, severity, evidence}

## 검증 절차
각 finding에 대해:
1. file의 line_start-line_end 범위를 직접 읽는다 (Codex: `sed -n`, Gemini: `sed -n` 또는 `cat`)
2. evidence의 주장이 코드와 일치하는지 확인
3. severity가 정당한지 본인이 독립 판단
4. 결과 분류:
   - "confirmed": severity 동의
   - "disagree_severity": 다른 severity 제안 + 근거
   - "not_an_issue": 이슈 아님 + 근거

## 금지사항
- 새로운 이슈 발견 금지 (이 단계는 "검증"만)
- 원본 evidence를 그대로 반복 금지 — 본인이 읽은 내용으로 재작성
- 심각도 인플레이션 금지 — 확신 없으면 "confirmed"

## 출력 형식 (JSON만, 설명·마크다운 금지)

{
  "verifications": [
    {
      "finding_id": "f-001",
      "verdict": "confirmed",
      "suggested_severity": "High",
      "rationale": "src/auth.ts:42-48 읽음. req.params.id가 템플릿 리터럴로 바로 삽입되는 것을 확인.",
      "code_quote": "const q = `SELECT * FROM users WHERE id=${req.params.id}`"
    }
  ]
}

verdict: "confirmed" | "disagree_severity" | "not_an_issue"
suggested_severity: "Critical" | "High" | "Medium" | "Low" | "Info"
```

## 실행 (동시 독립 + 포터블 timeout + per-process 폴백 매트릭스)

검증 대상 JSON과 프롬프트를 Write 도구로 먼저 저장한 뒤 아래 bash 블록을 실행한다.
사전 저장 경로:
- `/tmp/ta-${_RUN_ID}-verify-input.json`
- `/tmp/ta-${_RUN_ID}-codex-verify-prompt.txt`
- `/tmp/ta-${_RUN_ID}-gemini-verify-prompt.txt`

```bash
source "$HOME/.cache/team-agent/cfg-${_RUN_ID}.env" 2>/dev/null || { echo "[team-agent] FATAL: cfg.env 없음 — Preamble 0.1 미실행" >&2; exit 1; }
# ───────────────────────────────────────────────────────────
# 1. 포터블 timeout 래퍼 (3단 fallback — 무한 대기 절대 금지)
# ───────────────────────────────────────────────────────────
# 우선순위: GNU timeout > gtimeout(Homebrew coreutils) > Python watchdog
# Python 3가 없는 환경은 가정하지 않는다 (skill 자체가 python3 의존).
# round-9 C1: _run_with_timeout은 cfg.env가 load한 refs/gemini-helper.sh에서 제공.

# ───────────────────────────────────────────────────────────
# 2. per-process 경로 정의
# ───────────────────────────────────────────────────────────
_CODEX_OUT="/tmp/ta-${_RUN_ID}-codex-verdicts.json"
_GEMINI_OUT="/tmp/ta-${_RUN_ID}-gemini-verdicts.json"
_CODEX_RC_FILE="/tmp/ta-${_RUN_ID}-codex.rc"
_GEMINI_RC_FILE="/tmp/ta-${_RUN_ID}-gemini.rc"
_CODEX_LOG="/tmp/ta-${_RUN_ID}-codex.log"
_GEMINI_LOG="/tmp/ta-${_RUN_ID}-gemini.log"

: > "$_CODEX_OUT"; : > "$_GEMINI_OUT"
rm -f "$_CODEX_RC_FILE" "$_GEMINI_RC_FILE"

_START_TS=$(date +%s)

# ───────────────────────────────────────────────────────────
# 3. Codex 검증자 (서브셸로 rc 캡처)
# ───────────────────────────────────────────────────────────
(
  # timeout·grace는 Preamble 0.1에서 바인딩된 fail-closed _CFG_* 사용 (폴백 문법 금지).
  # round-6: codex verifier 모델·effort 명시 주입 (user config.toml drift 차단).
  _run_with_timeout "$_CFG_VERIFY_SEC" "$_CFG_GRACE_SEC" \
    codex exec - -s read-only -C "$_EXEC_DIR" \
      -m "$_CFG_CODEX_VERIFIER_MODEL" \
      -c "model_reasoning_effort=\"$_CFG_CODEX_REASONING_VERIFIER\"" \
      --output-schema "${_SKILL_DIR}/refs/cross-verification-schema.json" \
      -o "$_CODEX_OUT" \
      --skip-git-repo-check \
      < "/tmp/ta-${_RUN_ID}-codex-verify-prompt.txt" \
      > "$_CODEX_LOG" 2>&1
  echo $? > "$_CODEX_RC_FILE"
) &
_CODEX_PID=$!

# ───────────────────────────────────────────────────────────
# 4. Gemini 검증자 (서브셸로 rc 캡처)
# GEMINI_HAS_SCHEMA 분기 (CLI 버전에 따라 --json-schema 미지원)
# 모델: _pick_gemini_model verifier → refs/config.json candidates_verifier 우선순위 배열.
# ───────────────────────────────────────────────────────────
_GEMINI_VERIFIER_MODEL="$(_pick_gemini_model verifier)"
# bug_006: 모델 탐색 실패 시 빈 문자열 + rc=1. rc 무시하면 `gemini -m ""`로 혼란스런 에러 2번 발생.
if [ -z "$_GEMINI_VERIFIER_MODEL" ]; then
  echo "[cross-verification] gemini verifier 모델 탐색 실패 — Gemini 검증 스킵 (codex 단독 진행)" >&2
  echo 127 > "$_GEMINI_RC_FILE"
  _GEMINI_PID=""
else
(
  if [ "${GEMINI_HAS_SCHEMA:-0}" -gt 0 ]; then
    _run_with_timeout "$_CFG_VERIFY_SEC" "$_CFG_GRACE_SEC" \
      gemini -m "$_GEMINI_VERIFIER_MODEL" \
        --json-schema "${_SKILL_DIR}/refs/cross-verification-schema.json" \
        -p - < "/tmp/ta-${_RUN_ID}-gemini-verify-prompt.txt" \
        > "$_GEMINI_OUT" 2> "$_GEMINI_LOG"
  else
    # --json-schema 미지원 — 프롬프트에 JSON 스키마 지시로 대체 (프롬프트 조립 시 포함되어야 함)
    _run_with_timeout "$_CFG_VERIFY_SEC" "$_CFG_GRACE_SEC" \
      gemini -m "$_GEMINI_VERIFIER_MODEL" \
        -p - < "/tmp/ta-${_RUN_ID}-gemini-verify-prompt.txt" \
        > "$_GEMINI_OUT" 2> "$_GEMINI_LOG"
  fi
  echo $? > "$_GEMINI_RC_FILE"
) &
_GEMINI_PID=$!
fi

# ───────────────────────────────────────────────────────────
# 5. 대기 — timeout은 각 서브셸이 자체 처리. wait는 blocking-safe.
# ───────────────────────────────────────────────────────────
wait "$_CODEX_PID" 2>/dev/null
wait "$_GEMINI_PID" 2>/dev/null

_END_TS=$(date +%s)
_DURATION_SEC=$((_END_TS - _START_TS))

# rc 파일 없으면 (서브셸 자체 실패) 124 간주
_CODEX_RC=$(cat "$_CODEX_RC_FILE" 2>/dev/null || echo 124)
_GEMINI_RC=$(cat "$_GEMINI_RC_FILE" 2>/dev/null || echo 124)

# ───────────────────────────────────────────────────────────
# 6. 3단계 검증 (rc == 0 && non-empty && json parseable)
# ───────────────────────────────────────────────────────────
_validate_verdict() {
  # $1=rc, $2=out_file → stdout: "ok" | "timeout" | "non_zero_rc" | "empty_output" | "invalid_json"
  local _rc="$1" _out="$2"
  if [ "$_rc" = "124" ] || [ "$_rc" = "137" ]; then
    echo "timeout"; return 1
  fi
  if [ "$_rc" != "0" ]; then
    echo "non_zero_rc"; return 1
  fi
  if [ ! -s "$_out" ]; then
    echo "empty_output"; return 1
  fi
  if ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$_out" >/dev/null 2>&1; then
    echo "invalid_json"; return 1
  fi
  echo "ok"; return 0
}

_CODEX_REASON=$(_validate_verdict "$_CODEX_RC" "$_CODEX_OUT") && _CODEX_OK=1 || _CODEX_OK=0
_GEMINI_REASON=$(_validate_verdict "$_GEMINI_RC" "$_GEMINI_OUT") && _GEMINI_OK=1 || _GEMINI_OK=0

# ok면 reason은 null로 기록
[ "$_CODEX_OK" = "1" ]  && _CODEX_FAILED_REASON="null"  || _CODEX_FAILED_REASON="\"$_CODEX_REASON\""
[ "$_GEMINI_OK" = "1" ] && _GEMINI_FAILED_REASON="null" || _GEMINI_FAILED_REASON="\"$_GEMINI_REASON\""

# ───────────────────────────────────────────────────────────
# 7. Fallback 매트릭스 (mode 결정 + WARN 로그)
# ───────────────────────────────────────────────────────────
if   [ "$_CODEX_OK" = "1" ] && [ "$_GEMINI_OK" = "1" ]; then
  _VERIFICATION_MODE="full_3way"
elif [ "$_CODEX_OK" = "1" ] && [ "$_GEMINI_OK" = "0" ]; then
  _VERIFICATION_MODE="codex_only"
  echo "[team-agent WARN] Gemini 검증 실패 (reason=$_GEMINI_REASON, rc=$_GEMINI_RC) — Codex 단독 판정으로 진행" >&2
elif [ "$_CODEX_OK" = "0" ] && [ "$_GEMINI_OK" = "1" ]; then
  _VERIFICATION_MODE="gemini_only"
  echo "[team-agent WARN] Codex 검증 실패 (reason=$_CODEX_REASON, rc=$_CODEX_RC) — Gemini 단독 판정으로 진행" >&2
else
  _VERIFICATION_MODE="skipped"
  echo "[team-agent WARN] Codex+Gemini 모두 검증 실패 (codex=$_CODEX_REASON/$_CODEX_RC, gemini=$_GEMINI_REASON/$_GEMINI_RC) — Claude 원본 채택" >&2
fi

# ───────────────────────────────────────────────────────────
# 8. manifest.verification 조각 저장 (Phase 4-A-2에서 병합)
# ───────────────────────────────────────────────────────────
cat > "/tmp/ta-${_RUN_ID}-verification-meta.json" <<EOF
{
  "mode": "$_VERIFICATION_MODE",
  "codex_rc": $_CODEX_RC,
  "gemini_rc": $_GEMINI_RC,
  "codex_failed_reason": $_CODEX_FAILED_REASON,
  "gemini_failed_reason": $_GEMINI_FAILED_REASON,
  "duration_sec": $_DURATION_SEC
}
EOF

export _VERIFICATION_MODE _CODEX_OK _GEMINI_OK _CODEX_RC _GEMINI_RC _DURATION_SEC
```

독립성 보장: 두 검증자는 서로 결과를 보지 못한다. 동일 입력, 별도 서브셸 프로세스, 각자 timeout 래퍼.

## Fallback 매트릭스 (실행 가능 구현)

| `_CODEX_OK` | `_GEMINI_OK` | `mode`         | 동작                                                     | 사용자 출력 문구                                       |
|-------------|--------------|----------------|----------------------------------------------------------|--------------------------------------------------------|
| 1           | 1            | `full_3way`    | 기존 3/3·2/3 합의 로직 (아래 Python `consensus`)         | "검증 통계" 테이블 정상 표시                           |
| 1           | 0            | `codex_only`   | Codex 단독 판정 — Python `consensus`에 `gemini=None` 주입 | `⚠️ Gemini 검증 실패 — Codex 단독 판정 ("2/3 불가")`   |
| 0           | 1            | `gemini_only`  | Gemini 단독 판정 — Python `consensus`에 `codex=None` 주입 | `⚠️ Codex 검증 실패 — Gemini 단독 판정 ("2/3 불가")`   |
| 0           | 0            | `skipped`      | 검증 전체 스킵 → Claude 원본 findings 그대로 채택        | `❌ 두 검증자 모두 실패 — Claude 원본 채택 (검증 실패)` |

`codex_failed_reason` / `gemini_failed_reason` enum:
`"timeout"` | `"non_zero_rc"` | `"empty_output"` | `"invalid_json"` | `null` (성공 시)

## 2/3 다수결 매핑 (결정론적)

```
case (Claude, Codex, Gemini) =>

  (X, X, X)           → 확정 X (만장일치, 합의 3/3)
  (X, X, Y) X≠Y       → 확정 X (2/3, Gemini 이견 기록)
  (X, Y, X) X≠Y       → 확정 X (2/3, Codex 이견 기록)
  (X, Y, Y) X≠Y       → 다운그레이드 Y (2/3 반대, 쟁점 기록)
  (X, Y, Z) 모두 다름  → 보수적 선택 (가장 낮은 severity, 쟁점 기록)
  (X, not_an_issue, not_an_issue) → 삭제 후보 (쟁점 테이블 기록)
  (X, confirmed, confirmed) → 확정 X (3/3)
  (X, not_an_issue, confirmed)    → 확정 X (2/3)
  (X, confirmed, not_an_issue)    → 확정 X (2/3)
```

Severity 순서: Critical > High > Medium > Low > Info.

Python 구현 (Phase 4-A-2에서 호출):

```python
SEVERITY_RANK = {"Critical": 5, "High": 4, "Medium": 3, "Low": 2, "Info": 1}
from collections import Counter

def consensus(claude_sev, codex_verdict, gemini_verdict):
    # verdict: {"verdict": str, "suggested_severity": str | None} | None

    # "이슈 아님" 조기 종료 — 2명 이상 verdict=not_an_issue면 삭제 후보
    verifier_verdicts = [
        v["verdict"] for v in (codex_verdict, gemini_verdict) if v is not None
    ]
    if len(verifier_verdicts) >= 2 and all(x == "not_an_issue" for x in verifier_verdicts):
        return {
            "final_severity": None,
            "verdict": "deleted",
            "severity_dispute": False,
            "verifier_missing": False,
        }

    votes = [claude_sev]
    for v in (codex_verdict, gemini_verdict):
        if v is None or v["verdict"] == "not_an_issue":
            votes.append(None)  # 검증 불가 또는 이슈 아님
        elif v["verdict"] == "confirmed":
            votes.append(claude_sev)
        else:  # disagree_severity
            votes.append(v["suggested_severity"])

    # 다수결: 가장 많이 나온 값 선택. 동점이면 보수적(낮은 severity) 선택.
    non_null = [v for v in votes if v is not None]
    if not non_null:
        return {
            "final_severity": None,
            "verdict": "deleted",
            "severity_dispute": False,
            "verifier_missing": True,
        }
    cnt = Counter(non_null)
    most_common = cnt.most_common()
    top_count = most_common[0][1]
    tied = [sev for sev, c in most_common if c == top_count]
    # 동점이면 SEVERITY_RANK가 낮은 쪽 선택
    final = min(tied, key=lambda s: SEVERITY_RANK.get(s, 0))

    # 두 플래그를 분리:
    # - severity_dispute: 심각도 판정이 실제로 갈렸는가
    # - verifier_missing: 검증자 중 하나가 불가/이슈아님으로 자리를 비웠는가
    severity_dispute = len(set(non_null)) > 1
    verifier_missing = any(v is None for v in votes[1:])  # Claude 원본 제외, 검증자 2명만 체크
    return {
        "final_severity": final,
        "verdict": "kept",
        "severity_dispute": severity_dispute,
        "verifier_missing": verifier_missing,
    }
```

## 검증 실패 폴백

상세 실행 매트릭스는 위 "Fallback 매트릭스 (실행 가능 구현)" 섹션 참조.
실패 분류는 `_validate_verdict` 함수의 3단계 검증(rc == 0 / non-empty / json parseable)에서 나온 enum을 그대로 `manifest.verification.{codex,gemini}_failed_reason`에 기록한다.

## manifest 기록

```json
{
  "verification": {
    "mode": "full_3way",
    "codex_rc": 0,
    "gemini_rc": 0,
    "codex_failed_reason": null,
    "gemini_failed_reason": null,
    "duration_sec": 187,
    "codex_verdicts": [
      {"finding_id": "f-001", "verdict": "confirmed"}
    ],
    "gemini_verdicts": [
      {"finding_id": "f-001", "verdict": "disagree_severity", "suggested_severity": "Medium"}
    ],
    "consensus": [
      {"finding_id": "f-001", "final_severity": "High", "severity_dispute": true, "verifier_missing": false}
    ]
  }
}
```

폴백 모드 예시 (`codex_only` — Gemini 타임아웃):

```json
{
  "verification": {
    "mode": "codex_only",
    "codex_rc": 0,
    "gemini_rc": 124,
    "codex_failed_reason": null,
    "gemini_failed_reason": "timeout",
    "duration_sec": 330,
    "codex_verdicts": [...],
    "gemini_verdicts": [],
    "consensus": [...]
  }
}
```

`mode` enum: `"full_3way"` | `"codex_only"` | `"gemini_only"` | `"skipped"`.
