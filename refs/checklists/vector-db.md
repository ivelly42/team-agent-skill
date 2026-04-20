# 벡터DB

- [ ] DB 선택 근거 — 규모·쿼리 특성·운영 비용 적합성
- [ ] 인덱스 파라미터 — HNSW M/efConstruction, IVF nlist 등 튜닝 여부
- [ ] 메타데이터 필터 — pre-filtering vs post-filtering 성능 영향
- [ ] 업서트 패턴 — 전체 재인덱싱 vs 증분, 중복 방지 키
- [ ] 파티셔닝 — 테넌트·시간·언어 분리
- [ ] 백업·복구 — 인덱스 재구축 시간, 스냅샷 전략
- [ ] 쿼리 성능 — p95/p99 레이턴시, N+1 embed 호출 감지
- [ ] 비용 — 인덱스 메모리 사용, 쿼리당 비용

**탐색 힌트**: `*vector*`, `*index*`, pinecone/weaviate/qdrant/chroma/pgvector import

