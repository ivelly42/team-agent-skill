# 공유 코드맵 생성 프롬프트

Phase 0.3에서 백엔드별로 프롬프트가 달라진다. 공통 지시를 먼저 두고 백엔드별 탐색 지시를 분기한다.

## 공통 지시 (모든 백엔드에 포함)

```
## 역할
너는 코드맵 생성자다. 이 프로젝트의 구조를 스캔하고 refs/codemap-schema.json 형식에 맞는 JSON만 출력하라.

## 탐색 범위
- 루트 디렉토리: {PROJECT_DIR 또는 SCOPE_PATH}
- 제외: node_modules, .git, dist, build, .venv, venv, target, vendor, .next, __pycache__

## 수집 항목 우선순위
1. entrypoints (max 30) — main/api-route/CLI/worker/build/config/test-runner 분류. 확실하지 않으면 제외.
2. hotspots (max 20) — 복잡도 높거나 다수 파일에 import되는 핵심 파일
3. symbols (max 200) — 도메인 핵심 함수/클래스/타입/인터페이스/route. 프로젝트 특성에 맞춰 선택.
4. files (max 100) — LOC 기준 상위 100개. role 분류: core/api/ui/config/test/util/doc/other
5. dependencies (max 500) — from→to 직접 import 관계 1-hop. 추측 없이 실제 import 문에서만 추출.

## 규칙
- 추측 금지. 직접 읽은 파일만 포함.
- symbols의 `signature`는 첫 줄만 200자 이내로 잘라서.
- 파일 경로는 프로젝트 루트 기준 상대경로.
- 결과 JSON은 refs/codemap-schema.json 스키마를 100% 준수.

## 출력
JSON만. 설명·마크다운·주석 금지. 첫 문자는 `{`, 마지막 문자는 `}`.
```

## 백엔드별 탐색 지시 (위 공통 지시에 이어서 삽입)

### Claude Agent 백엔드용

```
## 탐색 도구
Glob/Read/Grep 도구를 사용한다.
1. Glob("**/*")로 전체 파일 목록 확보
2. 디렉토리별 역할 파악을 위해 주요 디렉토리 ls
3. LOC는 Bash 도구로 `wc -l` 배치 호출로 일괄 계산한다 (예: `wc -l $(find . -type f -name "*.py" ! -path "*/.venv/*")`). 상위 100개 파일만 Read로 내용 수집하여 exports·symbols 추출.
4. import/require 문을 Grep으로 수집하여 dependencies 구축
```

### Codex exec 백엔드용

```
## 탐색 지시 (셸 명령)
1. 구조 파악: `find . -maxdepth 3 -type f ! -path "*/node_modules/*" ! -path "*/.git/*" ! -path "*/vendor/*" ! -path "*/dist/*" ! -path "*/.next/*" ! -path "*/target/*" ! -path "*/__pycache__/*" | head -200`
2. 주요 파일 내용: `head -100 <파일>` (대용량은 head)
3. import 수집: `grep -rn "^import \|^from \|^const .* = require(\|^import {\|^use \|^require " --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=vendor --exclude-dir=dist | head -500` (Go 블록 임포트 `import (\n"a"\n"b"\n)` 형태는 `grep -rn -A 20 "^import (" --include="*.go"`로 별도 수집)
4. LOC 계산: `wc -l <파일>` 또는 배치로 `find ... -exec wc -l {} +`
```

### Gemini -p 백엔드용

```
## 탐색 지시 (셸 명령, 1M 컨텍스트 활용)
1. 구조 파악: `find . -maxdepth 4 -type f ! -path "*/node_modules/*" ! -path "*/.git/*" ! -path "*/vendor/*" ! -path "*/dist/*" ! -path "*/.next/*" ! -path "*/target/*" ! -path "*/__pycache__/*" | head -500`
2. 1M 컨텍스트를 활용해 핵심 파일은 `cat` 전체를 읽어라. 대용량 바이너리는 `file <파일>`로 타입 확인 후 텍스트만 읽어라.
3. import 수집: `grep -rn "^import \|^from \|^const .* = require(\|^import {\|^use \|^require " --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=vendor --exclude-dir=dist` (Go 블록 임포트는 `grep -rn -A 20 "^import (" --include="*.go"`로 별도 수집)
4. LOC: `find ... -exec wc -l {} +`
5. 추측 금지. 실제 읽은 파일만 포함하라.
```

## 역할별 필터 힌트 (에이전트 프롬프트 주입 시 함께 포함)

에이전트가 코드맵을 받은 뒤 자기 역할에 맞는 필터를 알 수 있도록 프롬프트에 아래 테이블을 포함:

| 역할 | 필터 힌트 |
|-----|---------|
| 보안 감사 | entrypoints(kind=api-route) + files(role=config) + symbols 중 auth/token/secret 키워드 |
| 성능 엔지니어 | hotspots 전체 + files LOC 상위 + dependencies 중심 노드 |
| DB 아키텍트 | symbols(kind=class) + files(role=core) + schema/migration 경로 |
| 프론트엔드 | files(role=ui) + entrypoints(kind=main) + symbols(component/hook) |
| 백엔드 아키텍트 | entrypoints(kind=api-route/worker) + files(role=core/api) |
| 코드 탐색가 | 전체 코드맵 + dependencies 그래프 분석 |
| 통합 QA | entrypoints(kind=api-route) + files(role=ui) + symbols(kind=route) |
| RAG 아키텍트 | files 중 *retriev*/*embed*/*chunk* 경로 + langchain/llamaindex import |
| 벡터DB 전문가 | files 중 *vector*/*index* 경로 + pinecone/weaviate/qdrant/pgvector import |
| GraphQL 아키텍트 | files 중 *.graphql/schema.graphql + apollo/relay/graphql-js import |
| gRPC 엔지니어 | files 중 *.proto 경로 + grpc 관련 import |
| OpenAPI 설계자 | files 중 openapi.*/swagger.* + FastAPI/NestJS OpenAPI 어댑터 |
| 이벤트 드리븐 아키텍트 | files 중 events/handlers 경로 + kafka/rabbitmq/nats/sqs import |

## 재시도 프롬프트 추가분 (JSON 파싱 실패 시 원본 프롬프트 맨 끝에 append)

```
=== 재시도 지시 (이전 응답이 유효한 JSON이 아님) ===
이전 출력이 JSON으로 파싱되지 않았다. 아래 규칙을 반드시 지켜라:
1. 첫 문자는 `{`, 마지막 문자는 `}` 여야 한다.
2. JSON 외의 모든 텍스트(설명·마크다운·주석·코드펜스) 금지.
3. refs/codemap-schema.json의 enum·required 필드를 엄격히 준수.
4. 큰따옴표를 사용하라 (단일따옴표 금지).
재출력하라.
```

## 실패 대응

- 60초 타임아웃 초과 → 생성 실패로 기록
- JSON 파싱 실패 → 1회 재시도 (프롬프트에 "JSON 형식 엄수 — 중괄호로 시작" 강조 추가)
- 재시도도 실패 → `manifest.codemap_path=null`로 기록하고 에이전트 독립 탐색 모드로 진행
