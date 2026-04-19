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

## 실행 (동시 독립)

```bash
# 검증 대상 JSON을 Write 도구로 먼저 저장
# /tmp/ta-${_RUN_ID}-verify-input.json 및 codex/gemini 프롬프트 각각 저장

# Codex 검증자 (run_in_background)
codex exec - -s read-only -C "$_EXEC_DIR" \
  --output-schema "${SKILL_DIR}/refs/cross-verification-schema.json" \
  -o "/tmp/ta-${_RUN_ID}-codex-verdicts.json" \
  --skip-git-repo-check < "/tmp/ta-${_RUN_ID}-codex-verify-prompt.txt" &
CODEX_PID=$!

# Gemini 검증자 (run_in_background)
gemini -m gemini-3.1-pro-preview --json-schema "${SKILL_DIR}/refs/cross-verification-schema.json" \
  -p - < "/tmp/ta-${_RUN_ID}-gemini-verify-prompt.txt" \
  > "/tmp/ta-${_RUN_ID}-gemini-verdicts.json" 2>/dev/null &
GEMINI_PID=$!

# 타임아웃 5분
wait $CODEX_PID $GEMINI_PID
```

독립성 보장: 두 검증자는 서로 결과를 보지 못한다. 동일 입력, 별도 프로세스.

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
    # verdict: {"verdict": str, "suggested_severity": str | None}

    # 특례: 검증자 둘 다 "not_an_issue" → 삭제 후보
    verifier_verdicts = [
        v["verdict"] for v in (codex_verdict, gemini_verdict) if v is not None
    ]
    if len(verifier_verdicts) >= 2 and all(x == "not_an_issue" for x in verifier_verdicts):
        return {"final_severity": None, "verdict": "deleted", "dispute": True}

    votes = [claude_sev]
    for v in (codex_verdict, gemini_verdict):
        if v is None or v["verdict"] == "not_an_issue":
            votes.append(None)  # "이슈 아님" 표 1표
        elif v["verdict"] == "confirmed":
            votes.append(claude_sev)
        else:  # disagree_severity
            votes.append(v["suggested_severity"])

    # 다수결: 가장 많이 나온 값 선택. 동점이면 보수적(낮은 severity) 선택.
    non_null = [v for v in votes if v is not None]
    if not non_null:
        return {"final_severity": None, "verdict": "deleted", "dispute": True}
    cnt = Counter(non_null)
    most_common = cnt.most_common()
    top_count = most_common[0][1]
    tied = [sev for sev, c in most_common if c == top_count]
    # 동점이면 SEVERITY_RANK가 낮은 쪽 선택
    final = min(tied, key=lambda s: SEVERITY_RANK.get(s, 0))

    # 이견 여부
    dispute = len(set(non_null)) > 1 or any(v is None for v in votes)
    return {"final_severity": final, "verdict": "kept", "dispute": dispute}
```

## 검증 실패 폴백

| 실패 | 동작 |
|-----|------|
| Codex 타임아웃/실패 | Gemini 단독 결과 + "2/3 불가 — Gemini 단독 판정" 표시 |
| Gemini 타임아웃/실패 | Codex 단독 결과 + 동일 표시 |
| 둘 다 실패 | 검증 전체 스킵. Claude 원본 채택 + "검증 실패" 경고 |
| JSON 파싱 실패 | 해당 검증자만 제외. 단독 모드 전환 |

## manifest 기록

```json
{
  "verification": {
    "mode": "cross",
    "codex_verdicts": [
      {"finding_id": "f-001", "verdict": "confirmed"}
    ],
    "gemini_verdicts": [
      {"finding_id": "f-001", "verdict": "disagree_severity", "suggested_severity": "Medium"}
    ],
    "consensus": [
      {"finding_id": "f-001", "final_severity": "High", "dispute": true}
    ]
  }
}
```
