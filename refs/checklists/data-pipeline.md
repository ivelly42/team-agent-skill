# 데이터 파이프라인

- 실시간 스트리밍: WebSocket/SSE 처리, 메시지 순서 보장, 재연결
- ETL: 추출-변환-적재 파이프라인, 스케줄링, 실패 재시도
- 이벤트 소싱: 이벤트 저장소, 리플레이, 스냅샷, CQRS
- 시계열 DB: 인플럭스/TimescaleDB/ClickHouse 설계, 보존 정책
- 데이터 품질: 유효성 검증, 스키마 진화, 누락 감지
- 처리량/지연: 초당 메시지, 처리 지연, 백프레셔
- 장애 복구: 데드레터 큐, 재처리, idempotency
- 모니터링: 파이프라인 지연 알림, 데이터 신선도, 누적 지표
- 저장 전략: 파티셔닝, 압축, 콜드/핫 스토리지 분리
- 탐색 힌트: `*pipeline*`, `*stream*`, `*ingest*`, `*etl*`, `*queue*`, `*kafka*`, `*redis*` 파일. `grep -rn "subscribe\|publish\|consume\|produce\|stream\|pipeline\|queue\|kafka\|redis" --include="*.{py,ts,yaml}"` 실행

