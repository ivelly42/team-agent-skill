# 라이브옵스

- 시즌 설계: 시즌 기간, 보상 구조, 시즌패스 진행률
- 이벤트 설계: 이벤트 종류, 기간, 보상 밸런스, 반복 주기
- 컨텐츠 케이던스: 업데이트 주기, 드라이 컨텐츠 기간, 파이프라인
- 운영 KPI: DAU/MAU, 리텐션 D1/D7/D30, 매출, LTV
- A/B 테스트: 테스트 설계, 세그먼트, 유의성 검증
- 핫픽스 절차: 긴급 패치 배포 프로세스, 롤백
- 공지/푸시: 인앱 공지, 푸시 알림, 점검 공지 시스템
- 어뷰징 대응: 치터 감지, 제재 시스템, 로그 보존
- 탐색 힌트: `*event*`, `*season*`, `*campaign*`, `*notice*`, `*banner*` 파일. `grep -rn "event.start\|event.end\|season\|maintenance\|hotfix" --include="*.{ts,py,json,yaml}"` 실행

