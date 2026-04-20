# 퀀트 전략

- 알파 생성: 알파 팩터 정의, 수익률 분포, 시그널 강도
- 팩터 분석: 멀티팩터 모델, 팩터 상관관계, 팩터 디케이
- 백테스트 엄밀성: look-ahead bias, survivorship bias, 거래 비용 반영
- 리스크 조정 수익: 샤프 비율, 소르티노 비율, 최대 드로다운
- 포지션 사이징: 켈리 기준, 고정 비율, 변동성 타겟팅
- 실행 전략: TWAP/VWAP, 아이스버그, 시장가 vs 지정가
- 시장 레짐: 추세/횡보/변동성 구분, 레짐 전환 감지
- 오버피팅 방지: 표본 외 검증, 워크포워드, 교차 검증
- 상관관계 분석: 자산 간 상관, 전략 간 상관, 포트폴리오 분산
- 탐색 힌트: `*strategy*`, `*signal*`, `*alpha*`, `*factor*`, `*indicator*` 파일. `grep -rn "sharpe\|drawdown\|pnl\|return\|backtest\|signal\|alpha\|factor" --include="*.{py,ts,json}"` 실행

