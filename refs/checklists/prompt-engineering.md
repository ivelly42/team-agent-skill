# 프롬프트 엔지니어링

- [ ] 프롬프트 버전 관리 — 외부 파일 vs 인라인, 버전 태그, 롤백 가능성
- [ ] 시스템·유저 프롬프트 분리 — 역할 혼입 여부
- [ ] Few-shot 구성 — 예시 수·다양성·편향 검토
- [ ] 체인 구조 — CoT/ToT 필요성, 단계별 실패 지점 격리
- [ ] 토큰 예산 — 입력 최대치 검증, truncation 전략
- [ ] 구조화 출력 — JSON schema/function calling 사용, 파싱 실패 폴백
- [ ] 인젝션 방어 — 사용자 입력과 지시어 명확 구분, 구분자 전략
- [ ] 프롬프트 캐싱 — Anthropic cache_control, OpenAI prompt cache 활용
- [ ] 모델 독립성 — 특정 모델에 과적합된 프롬프트인지

**탐색 힌트**: `prompts/`, `*.prompt.*`, `*.md` 내 SYSTEM/USER 블록, openai/anthropic sdk import

