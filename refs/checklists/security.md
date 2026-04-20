# 보안

- OWASP Top 10 (인젝션, 인증 우회, XSS, CSRF, SSRF, IDOR)
- 인증/인가: 토큰 검증, 세션 관리, 권한 상승, JWT 만료/갱신
- 시크릿 관리: 하드코딩된 키/토큰/비밀번호, .env 커밋 여부
- CORS 설정, CSP 헤더, X-Frame-Options
- 입력 검증 및 출력 인코딩 (서버/클라이언트 양측)
- 의존성 취약점 (알려진 CVE, 오래된 패키지)
- 암호화: 전송 중(TLS) + 저장 시(at-rest) 암호화 여부
- Rate limiting / brute-force 방어
- 로깅에 민감 정보 노출 여부
- 탐색 힌트: `.env`, `*config*`, `*auth*`, `*secret*`, `*middleware*` 파일 우선. `grep -rn "password\|secret\|api.key\|token\|private" --include="*.{ts,py,go,js}"` 실행

