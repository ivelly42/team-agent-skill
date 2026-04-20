# 성능

- N+1 쿼리 패턴 (ORM 루프 내 쿼리, lazy loading 남용)
- 캐싱 부재 또는 무효화 누락 (TTL 미설정, stale 데이터)
- 인덱스 누락 (자주 조회하는 컬럼, 복합 인덱스 미사용)
- 번들 크기: 불필요한 의존성, tree-shaking 실패, dynamic import 미사용
- 비동기 처리: 병렬 가능한데 순차 실행 (Promise.all 미사용)
- 리소스 정리: 커넥션/파일핸들/타이머/구독 미해제
- 메모리 누수 패턴 (클로저, 이벤트 리스너 미해제, 전역 배열 무한 성장)
- 핫 경로 식별: 초당 호출 빈도 높은 함수의 불필요한 연산
- 페이지네이션 / 스트리밍: 대량 데이터를 한번에 메모리 로드
- 탐색 힌트: `*query*`, `*fetch*`, `*cache*` 파일. `grep -rn "await\|\.then\|Promise\.all\|setInterval" --include="*.{ts,js}"` + DB 쿼리 패턴 검색

