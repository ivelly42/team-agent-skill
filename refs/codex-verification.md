# Codex 독립 분석 절차

에이전트 결과를 다른 AI 모델(Codex/GPT)로 독립 분석한다.
Claude 에이전트끼리는 같은 맹점을 공유하므로, Codex가 먼저 독립 분석 후 결과를 대조하는 2단계 방식을 사용한다.
이렇게 하면 Claude의 결론에 앵커링되지 않고 진정한 독립 시각을 확보한다.

## 실행 조건

다음 모두 충족 시 실행:
1. `codex` CLI가 설치되어 있음 (`which codex`)
2. 성공한 에이전트가 1명 이상
3. Critical 또는 High 발견 사항이 1건 이상이거나, 발견 사항이 0건 (놓친 게 있을 수 있음), 또는 Medium이 5건 이상

**조건 미충족 시**: 건너뛰고 Phase 5로 진행. "Codex 검증: 건너뜀 (codex 미설치)" 표시.

## 프롬프트 구성

Phase 4-A-2에서 생성한 보고서의 **발견 사항과 아이디어**를 추출하여 Codex에 전달한다.

**보안 원칙**: 모든 동적 값은 **Write 도구 → 파일 → codex stdin** 패턴으로 전달한다. 셸 명령에 사용자 유래 값을 직접 삽입하지 않는다.

### 프롬프트 조립 및 실행

1. **Write 도구**로 `/tmp/ta-${_RUN_ID}-codex-verify.txt`에 프롬프트를 저장한다:

```
너는 독립 분석자다. 아래 프로젝트를 직접 분석하라.
다른 AI 팀이 이미 분석을 수행했으나, 그 결과는 네가 분석을 완료한 후에만 참고하라.

**1단계: 독립 분석** (먼저 수행)
프로젝트의 실제 코드를 직접 읽고 다음을 분석하라:
- 작업 목적에 해당하는 핵심 이슈 (보안, 성능, 품질 등)
- 놓치기 쉬운 엣지 케이스
- 개선 아이디어

프로젝트 경로: {PROJECT_DIR}
작업 목적: {TASK_PURPOSE}
{CONVERSATION_CONTEXT가 있으면 추가}

**2단계: 대조 검증** (1단계 완료 후 수행)
아래 팀 결과와 네 분석을 대조하라:

== 팀 발견 사항 ==
{FINDINGS_SUMMARY — 심각도 높은 순, 2000자 이내}

== 팀 아이디어 ==
{IDEAS_SUMMARY — 영향 높은 순, 1000자 이내}

== 출력 형식 ==
**1단계 결과** (독립 분석):
  🔍 독립 발견 — [이슈 설명, 파일/위치, 심각도]
  💡 독립 아이디어 — [아이디어 설명, 난이도, 영향]

**2단계 결과** (대조 검증):
각 팀 발견에 대해:
  ✅ 검증됨 — [근거]
  ⚠️ 과장됨 — [실제 심각도와 이유]
  ❌ 오류 — [왜 틀렸는지]

각 팀 아이디어에 대해:
  ✅ 실현 가능 — [근거, 난이도/영향 평가 동의 여부]
  ⚠️ 과대평가 — [실제 난이도 또는 영향과 이유]
  ❌ 비실현적 — [왜 불가능한지]

팀이 놓친 이슈 (1단계에서 발견했으나 팀이 놓친 것):
  🆕 추가 발견 — [이슈 설명, 파일/위치, 심각도]

팀이 놓친 아이디어:
  추가 아이디어 — [아이디어 설명, 난이도, 영향]
```

LLM은 `{PROJECT_DIR}`, `{TASK_PURPOSE}`, `{FINDINGS_SUMMARY}`, `{IDEAS_SUMMARY}` 플레이스홀더를 Write 도구로 파일에 쓸 때 실제 값으로 치환한다. 이 값들은 셸을 거치지 않으므로 인젝션이 불가능하다.

2. **Bash 도구**로 codex exec를 stdin 방식으로 실행한다:

```bash
_VERIFY_PROMPT="/tmp/ta-RUN_ID_VALUE-codex-verify.txt"
codex exec - -s read-only \
  -C "PROJECT_DIR_VALUE" \
  --skip-git-repo-check \
  -c 'model_reasoning_effort="xhigh"' < "$_VERIFY_PROMPT" 2>&1
_EXIT=$?
rm -f "$_VERIFY_PROMPT"
echo "EXIT: $_EXIT"
```

LLM은 `RUN_ID_VALUE`와 `PROJECT_DIR_VALUE`만 치환한다 (시스템 값). `< "$_VERIFY_PROMPT"`(stdin 리다이렉트)를 사용하여 프롬프트가 셸 인자로 전달되지 않으므로 ARG_MAX와 셸 재해석 문제가 없다.

## 컨텍스트 구성

- **CONVERSATION_CONTEXT**: 이 대화에서 사용자가 이전에 언급한 문제/불만이 있으면 `사용자 맥락: [요약]` 형태로 포함. 없으면 생략.
- **FINDINGS_SUMMARY**: Phase 4-A-0 품질 필터 적용 후의 발견 사항 테이블. 2,000자 초과 시 심각도 높은 순으로 잘라냄.
- **IDEAS_SUMMARY**: Phase 4-A-0 품질 필터 적용 후의 아이디어 테이블에서 제목 + 난이도 + 영향 + 합의 수를 추출. 1,000자 초과 시 영향 높은 순으로 잘라냄.

## 결과 처리

Codex 응답을 보고서에 추가:

```
### 외부 검증 (Codex)
[Codex 응답 전문 — 요약하거나 편집하지 않음]
```

- `🔍 추가 발견` → Phase 4-A-2 발견 사항 테이블에 `🆕 Codex 추가` 태그와 함께 추가
- `❌ 오류` → 해당 발견 사항에 `⚠️ Codex 이의` 태그 추가
- `💡 추가 아이디어` → 아이디어 테이블에 `🆕 Codex 추가` 태그와 함께 추가
- `⚠️ 과대평가` → 해당 아이디어의 난이도/영향 컬럼에 `⚠️ Codex 교정` 태그 추가
- `❌ 비실현적` → 해당 아이디어에 취소선 + `❌ Codex 기각` 태그 추가

## 타임아웃/실패 처리

Codex가 5분 내 응답하지 않거나 에러 발생 시:
- "Codex 검증: 타임아웃/실패 — 에이전트 결과만으로 보고서 작성" 표시
- 보고서와 히스토리에 `codex_verified: false` 기록
- 스킬을 중단하지 않고 Phase 5로 진행

**성공 시**: 히스토리에 `codex_verified: true`, `codex_additions: N`, `codex_disputes: N`, `codex_idea_additions: N`, `codex_idea_rejections: N` 기록.
