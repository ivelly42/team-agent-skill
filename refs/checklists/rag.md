# RAG 아키텍처

- [ ] 문서 청킹 전략 — 고정 크기 vs 의미 단위, 오버랩, 청크 크기가 임베딩 모델 최대 토큰과 일치
- [ ] 임베딩 모델 선택 근거 — 도메인 특화 vs 범용, 차원 수, 다국어 지원
- [ ] 리트리버 방식 — dense only / sparse(BM25) / hybrid / re-ranking
- [ ] top-k·threshold — 검색 결과 수와 유사도 컷오프가 품질 측정으로 튜닝됨
- [ ] 컨텍스트 주입 — 원문 위치 표시, 인용 강제, 컨텍스트 길이 제한
- [ ] 캐시 전략 — 질의/임베딩/응답 캐시, 무효화 조건
- [ ] 할루시네이션 방어 — "컨텍스트에 없으면 모른다" 지시, 인용 누락 감지
- [ ] 평가 메트릭 — retrieval recall/precision, answer faithfulness, 수동 샘플 검토
- [ ] 인덱스 갱신 주기 — 실시간 vs 배치, 증분 업데이트 가능성

**탐색 힌트**: `*retriev*`, `*embed*`, `*chunk*`, `prompt.*.yaml`, langchain/llamaindex import

