# Gemini 에이전트 프롬프트 탐색 지시

gemini -p 백엔드 에이전트는 Claude의 Glob/Read/Grep 도구가 없다.
대신 셸 명령으로 파일을 탐색한다. 에이전트 프롬프트의 `## 탐색 지시` 섹션을 아래로 대체:

```
## 탐색 지시 (필수 — 분석 전에 반드시 실행)
1. `find . -maxdepth 4 -type f -name "*.EXT" ! -path "*/node_modules/*" ! -path "*/.git/*" ! -path "*/vendor/*" ! -path "*/dist/*" ! -path "*/.next/*" ! -path "*/target/*" ! -path "*/__pycache__/*" | head -100` 로 프로젝트 구조를 파악하라
2. 1M 토큰 컨텍스트를 가진다. 핵심 파일은 `cat <파일>`로 전체 읽어도 좋다. 대용량 바이너리는 `file <파일>`로 확인.
3. `grep -rn "패턴" --include="*.ts" --include="*.py" --include="*.js" --include="*.go" --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=vendor --exclude-dir=dist` 로 담당 영역 관련 핵심 소스를 탐색하라
4. 탐색 결과 기반으로 분석 범위를 결정하라

추측 없이 항상 원문 근거를 인용하라. 직접 읽은 코드만 보고하라.
```

## 추가 주의사항

- gemini CLI는 `-s read-only` 같은 샌드박스 옵션이 없다. 파일 수정은 프롬프트 지시로 금지("절대 파일을 수정·생성하지 말라")
- `ls -R` 사용 금지 — node_modules 등으로 출력 폭발
- 대용량 파일은 `head -200 <파일>`, 범위 읽기는 `sed -n '10,80p' <파일>`
- 바이너리 파일은 `file <파일>`로 타입 확인 후 텍스트만 읽기

## Gemini 강점 활용

- 1M 토큰 컨텍스트 → 전체 프로젝트를 한 번에 훑기 좋음
- 대량 파일 구조 스캔 → 코드맵 생성 역할에 적합
- 단점: 정밀 추론은 Claude/Codex가 우세 → ×1.5 정밀 역할은 배정하지 않음

## 치환 규칙 (Codex 템플릿과 동일)

| 플레이스홀더 | 치환 기준 | 예시 |
|------------|----------|------|
| `*.EXT` | 감지된 스택의 주요 확장자 | TypeScript → `*.ts` `*.tsx`, Python → `*.py` |
| `패턴` | 역할의 핵심 키워드 (refs/checklists.md 참조) | 보안 → `password\|secret\|api.key\|token` |

LLM은 에이전트 역할과 PROJECT_CONTEXT의 스택 정보를 기반으로 구체적 값을 삽입한다.
