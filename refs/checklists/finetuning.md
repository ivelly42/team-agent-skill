# 파인튜닝

- [ ] 데이터 품질 — 정제·중복 제거·라벨 일관성
- [ ] 데이터 분할 — train/val/test 오염 방지, 시간 기반 split
- [ ] 하이퍼파라미터 — LR·배치·epoch 근거, warmup/decay
- [ ] LoRA/QLoRA vs Full — 계산 비용 대비 효과
- [ ] 오버피팅 모니터링 — val loss, 조기 종료
- [ ] 배포 형태 — 어댑터 머지 여부, 양자화 전략
- [ ] 안전성 재검증 — 기본 모델 대비 harmful 응답 증가 여부
- [ ] 재학습 워크플로우 — 데이터 갱신 → 재학습 자동화

**탐색 힌트**: `transformers/`, `peft`, `trainer.py`, `*finetune*`, `datasets/` with jsonl

