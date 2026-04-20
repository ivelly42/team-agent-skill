# 이벤트 드리븐

- [ ] 이벤트 스키마 — 버전 관리, 스키마 레지스트리(Confluent·Apicurio)
- [ ] idempotency — consumer 중복 처리 방어, dedup key
- [ ] 순서 보장 — 파티션 키 전략, 순서 필요성 재검토
- [ ] at-least-once vs exactly-once — 트레이드오프 명시
- [ ] 재처리·리플레이 — DLQ, 오프셋 리셋 절차
- [ ] 스키마 진화 — 하위 호환, forward/backward compatibility
- [ ] 백프레셔·처리량 — consumer lag 모니터링, scaling 정책
- [ ] 분산 트랜잭션 — Saga/outbox 패턴 적용 여부

**탐색 힌트**: `*.avsc`, kafka/rabbitmq/nats/sqs config, `events/`, `handlers/`
