# 통합 정합성 검증 (Integration Coherence Verification)

## 핵심 원칙: "양쪽을 동시에 읽어라"

경계면 버그는 각 컴포넌트가 개별적으로 "정상"이지만 연결 지점에서 계약이 어긋날 때 발생한다. 한쪽만 읽어서는 절대 발견할 수 없다. 반드시 생산자와 소비자를 동시에 열고 shape을 비교하라.

## 검증 영역

### 1. API 응답 shape ↔ 프론트 훅 타입

각 API route의 `NextResponse.json()` (또는 `res.json()`) 호출부와 대응 훅의 `fetchJson<T>` 타입을 비교한다.

검증 단계:
1. API route에서 실제로 반환하는 객체의 shape 추출
2. 대응 훅에서 기대하는 타입(T) 확인
3. shape과 T가 일치하는지 비교
4. 래핑 여부 확인 — API가 `{ data: [...] }` 반환 시 훅이 `.data`를 꺼내는지

주의 패턴:
- 페이지네이션 API: `{ items: [], total, page }` vs 프론트가 배열 직접 기대
- snake_case DB 필드 → camelCase API 응답 → 프론트 타입 정의 간 불일치
- 즉시 응답(202 Accepted) vs 최종 결과의 shape 차이
- TypeScript 제네릭 캐스팅(`fetchJson<T>`)은 컴파일러가 런타임 불일치를 못 잡음

### 2. 파일 경로 ↔ 링크/라우터 경로

`src/app/` 하위 page 파일의 URL 경로를 추출하고, 코드 내 모든 `href`, `router.push()`, `redirect()` 값과 대조한다.

검증 단계:
1. src/app/ 하위 page.tsx 경로에서 URL 패턴 추출 — (group)은 URL에서 제거, [param]은 동적 세그먼트
2. 코드 내 모든 href=, router.push(, redirect( 값 수집
3. 각 링크가 실제 존재하는 page 경로와 매칭되는지 확인

### 3. 상태 전이 맵 ↔ 실제 코드

코드에서 모든 `status:` 업데이트를 추출하여 상태 전이 맵과 대조한다.

검증 단계:
1. 상태 전이 맵(STATE_TRANSITIONS 등)에서 허용된 전이 목록 추출
2. 모든 API route에서 `.update({ status: "..." })` 패턴 검색
3. 각 전이가 맵에 정의되어 있는지 확인
4. 맵에 정의된 전이 중 코드에서 실행되지 않는 것 식별 (죽은 전이)
5. 중간 상태에서 최종 상태로의 전환 누락 특히 주의

### 4. API 엔드포인트 ↔ 프론트 훅 1:1 매핑

모든 API route와 프론트 훅을 나열하여 짝이 맞는지 확인한다.

검증 단계:
1. src/app/api/ 하위 route.ts에서 HTTP 메서드별 엔드포인트 목록 추출
2. src/hooks/ 하위 use*.ts에서 fetch 호출 URL 목록 추출
3. API 중 훅에서 호출하지 않는 것 → "사용 안 됨" 플래그
4. "사용 안 됨"이 의도적인지(관리 API 등) 판단

## 실전 버그 패턴 (SatangSlide 프로젝트 사례)

| 버그 | 경계면 | 원인 |
|------|--------|------|
| `projects?.filter is not a function` | API→훅 | API가 `{projects:[]}` 래핑 반환, 훅이 배열 기대 |
| 대시보드 모든 링크 404 | 파일경로→href | `/dashboard/` 접두사 누락 |
| 테마 이미지 안 보임 | API→컴포넌트 | `thumbnailUrl` vs `thumbnail_url` 불일치 |
| 테마 선택 저장 안 됨 | API→훅 | select-theme API 존재, 대응 훅 없음 |
| 생성 페이지 영원히 대기 | 상태전이→코드 | `template_approved` 전이 코드 누락 |
| `data.failedIndices` 크래시 | 즉시응답→프론트 | 백그라운드 결과를 즉시 응답에서 접근 |
| 완료 후 슬라이드 보기 404 | 파일경로→href | `/projects/` → `/dashboard/projects/` |

## 출력 형식

이 에이전트도 동일한 JSON 스키마를 사용한다. `category` 필드에 경계면 유형을 명시:
- `"api-hook-mismatch"` — API 응답 shape ↔ 훅 타입 불일치
- `"route-link-mismatch"` — 파일 경로 ↔ 링크 불일치
- `"state-transition-gap"` — 상태 전이 누락
- `"orphan-endpoint"` — 호출되지 않는 API
