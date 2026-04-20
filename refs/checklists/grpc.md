# gRPC

- [ ] proto 스키마 — reserved 필드, wire format 호환성
- [ ] 스트리밍 — 언제 unary/server/client/bidi 쓰는지
- [ ] 데드라인·취소 — 모든 RPC에 데드라인 강제
- [ ] 재시도·idempotency — safe retry, jitter
- [ ] 인증 — mTLS, metadata 기반 인증
- [ ] 버전 관리 — 패키지명 버저닝, 하위 호환 규칙
- [ ] 로드 밸런싱 — 클라이언트 LB vs proxy, picker 전략
- [ ] 관찰성 — tracing context 전파, error code 매핑

**탐색 힌트**: `*.proto`, `grpc_gen/`, grpc-go/grpc-js import

