# 모델 평가/eval

- [ ] 평가 데이터셋 — 크기·다양성·실사용 분포 일치 여부
- [ ] 메트릭 선택 — task별 적합성 (BLEU/ROUGE/F1/LLM-as-judge/human)
- [ ] 베이스라인 — 이전 버전·경쟁 모델 비교 설정
- [ ] 리그레션 감지 — CI에서 eval 실행, 임계값 alerting
- [ ] LLM-as-judge 편향 — 판정자 모델과 평가 대상 같은 모델 사용 금지
- [ ] 에지 케이스 커버리지 — 긴 입력, 다국어, 악의적 입력, 빈 입력
- [ ] 재현성 — seed/temperature 고정, 실행 환경 명시
- [ ] 비용 추적 — eval 실행 비용, 샘플링 전략

**탐색 힌트**: `eval*/`, `benchmark*/`, `tests/**/llm*`, pytest에서 OpenAI/Anthropic 호출

