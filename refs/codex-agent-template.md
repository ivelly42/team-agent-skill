# Codex 에이전트 프롬프트 탐색 지시

codex exec 백엔드 에이전트는 Claude의 Glob/Read/Grep 도구가 없다.
대신 셸 명령으로 파일을 탐색한다. 에이전트 프롬프트의 `## 탐색 지시` 섹션을 아래로 대체:

```
## 탐색 지시 (필수 — 분석 전에 반드시 실행)
1. `find . -maxdepth 3 -type f -name "*.EXT" ! -path "*/node_modules/*" ! -path "*/.git/*" ! -path "*/vendor/*" ! -path "*/dist/*" ! -path "*/.next/*" ! -path "*/target/*" | head -50` 로 프로젝트 구조를 파악하라
2. `cat <파일>` 로 주요 설정 파일을 읽어라 (대용량 파일은 `head -100 <파일>` 사용)
3. `grep -rn "패턴" --include="*.ts" --include="*.py" --include="*.js" --include="*.go" --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=vendor --exclude-dir=dist` 로 담당 영역 관련 핵심 소스를 탐색하라
4. 탐색 결과 기반으로 분석 범위를 결정하라

탐색 없이 기본 정보만으로 분석하지 말라. 직접 코드를 읽고 판단하라.
```

## 추가 주의사항

- codex exec는 `-s read-only` 모드에서 셸 명령 실행이 허용되지만 파일 쓰기는 차단된다
- `ls -R` 사용 금지 — node_modules 등이 포함되어 출력이 수만 줄에 달할 수 있다. `find -maxdepth 3` 또는 `tree -L 2 -I 'node_modules|.git|vendor'` 사용
- 대용량 파일은 `head -100 <파일>` 또는 `sed -n '10,50p' <파일>`로 부분 읽기
- 바이너리 파일은 `file <파일>`로 타입 확인 후 텍스트만 읽기

## 치환 규칙

프롬프트 조립 시 아래 플레이스홀더를 역할/스택에 맞게 치환한다:

| 플레이스홀더 | 치환 기준 | 예시 |
|------------|----------|------|
| `*.EXT` | 감지된 스택의 주요 확장자 | TypeScript → `*.ts` `*.tsx`, Python → `*.py` |
| `패턴` | 역할의 핵심 키워드 (refs/checklists.md 참조) | 보안 → `password\|secret\|api.key\|token` |
| `<파일>` | 스택 설정 파일 | `package.json`, `pyproject.toml` 등 |

LLM은 에이전트 역할과 PROJECT_CONTEXT의 스택 정보를 기반으로 구체적 값을 삽입한다.
