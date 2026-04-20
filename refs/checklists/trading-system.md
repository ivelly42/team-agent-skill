# 트레이딩 시스템

- 거래소 API: REST/WebSocket 연결, 인증, 레이트 리밋 준수
- 주문 관리: 주문 생명주기 (생성→체결→취소), 부분 체결 처리
- 체결 엔진: 주문 매칭 로직, 슬리피지 처리, 주문 타입 지원
- 레이턴시: API 응답 시간, WebSocket 지연, 주문-체결 간격
- 장애 복구: API 연결 끊김, 재접속 로직, 미체결 주문 복구
- 자금 관리: 잔고 추적, 마진 계산, 증거금 모니터링
- 동시성: 멀티 거래소/멀티 전략 동시 실행, 락 관리
- 로깅/감사: 모든 주문/체결 이력, 타임스탬프, 감사 추적
- 알림 시스템: 체결/오류/청산경고 알림, 에스컬레이션
- 탐색 힌트: `*exchange*`, `*order*`, `*trade*`, `*api*`, `*ws*`, `*websocket*` 파일. `grep -rn "place.order\|cancel.order\|fill\|balance\|position\|margin\|leverage" --include="*.{py,ts}"` 실행

