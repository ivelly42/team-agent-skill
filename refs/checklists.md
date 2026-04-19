# 역할별 분석 체크리스트

에이전트 프롬프트의 `## 분석 체크리스트`에 해당 역할 섹션만 추출하여 삽입한다.

---

## 보안
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

## 코드 품질
- DRY 원칙 위반 (중복 코드 3곳+ → 추상화 후보)
- 순환 복잡도 과다 (깊은 중첩 3단계+, 함수 50줄+)
- 에러 처리: 누락, 삼킨 에러, 불충분한 에러 메시지, catch-all 남용
- 타입 안전성: any 남용, 제네릭 캐스팅으로 우회, 런타임 타입 불일치
- 데드 코드, 미사용 import/변수, 도달 불가 분기
- 네이밍 일관성 (camelCase/snake_case 혼재, 축약어 남용)
- 매직 넘버/문자열: 의미 불명확한 리터럴
- 함수/메서드 시그니처: 파라미터 3개 초과, boolean 파라미터 남용
- 모듈 응집도: 하나의 파일이 무관한 책임을 과다 포함
- 탐색 힌트: 가장 큰 소스 파일부터 확인. `wc -l *.{ts,py,js} | sort -rn | head -20`

## 성능
- N+1 쿼리 패턴 (ORM 루프 내 쿼리, lazy loading 남용)
- 캐싱 부재 또는 무효화 누락 (TTL 미설정, stale 데이터)
- 인덱스 누락 (자주 조회하는 컬럼, 복합 인덱스 미사용)
- 번들 크기: 불필요한 의존성, tree-shaking 실패, dynamic import 미사용
- 비동기 처리: 병렬 가능한데 순차 실행 (Promise.all 미사용)
- 리소스 정리: 커넥션/파일핸들/타이머/구독 미해제
- 메모리 누수 패턴 (클로저, 이벤트 리스너 미해제, 전역 배열 무한 성장)
- 핫 경로 식별: 초당 호출 빈도 높은 함수의 불필요한 연산
- 페이지네이션 / 스트리밍: 대량 데이터를 한번에 메모리 로드
- 탐색 힌트: `*query*`, `*fetch*`, `*cache*` 파일. `grep -rn "await\|\.then\|Promise\.all\|setInterval" --include="*.{ts,js}"` + DB 쿼리 패턴 검색

## 아키텍처
- 레이어 분리: 비즈니스 로직이 컨트롤러/UI/라우터에 혼재
- API 설계: 일관성, 버저닝, 에러 응답 형식, RESTful 원칙 준수
- 서비스 경계: 순환 의존, 과도한 결합, God 클래스/모듈
- 확장성: 단일 장애 지점, 수평 확장 가능성, stateful vs stateless
- 설정 관리: 환경별 분리, 기본값, 검증
- 이벤트/메시지 패턴: pub/sub, 큐, 이벤트 소싱 적절성
- 탐색 힌트: `src/`, `lib/`, `app/` 디렉토리 구조. 진입점(main, index, app) 파일부터 의존 그래프 추적

## 프론트엔드
- 컴포넌트 구조: 과대 컴포넌트 (200줄+), 책임 혼재, 재사용성
- 상태 관리: prop drilling 3단계+, 불필요한 전역 상태, 상태 동기화 문제
- 접근성: ARIA 속성, 키보드 네비게이션, 색상 대비 (WCAG 2.1 AA)
- 반응형: 브레이크포인트, 모바일 터치 영역, viewport 대응
- 렌더링 최적화: 불필요한 리렌더, memo/useMemo/useCallback 남용 또는 부재
- 에러 바운더리: 컴포넌트 오류 시 전체 앱 크래시 방지
- 폼 처리: 유효성 검증, 에러 메시지, 제출 상태 관리
- 라우팅: 코드 스플릿, 가드, 404 처리
- 탐색 힌트: `src/components/`, `src/hooks/`, `src/app/`, `src/pages/` 우선. 가장 큰 컴포넌트 파일부터 확인

## DB
- 스키마 설계: 정규화 수준, 관계 무결성, 제약 조건
- 인덱스: 복합 인덱스, 커버링 인덱스, 인덱스 과다 생성
- 마이그레이션: 안전성(비파괴적), 롤백 가능성, 데이터 보존
- 쿼리 최적화: 풀 스캔, 비효율적 JOIN, 서브쿼리 vs CTE
- 동시성: 락 전략, 데드락 가능성, 격리 수준
- 커넥션 풀: 설정값, 누수, 타임아웃
- 데이터 무결성: 외래 키, unique 제약, check 제약, 캐스케이드 삭제
- 탐색 힌트: `migrations/`, `schema/`, `models/`, `prisma/`, `drizzle/` 디렉토리 우선. ORM 설정 파일 확인

## 테스트
- 테스트 피라미드: 유닛/통합/E2E 비율 (역피라미드 경고)
- 커버리지: 핵심 비즈니스 로직 포함 여부, 분기 커버리지
- 엣지 케이스: 경계값, null/빈값/undefined, 동시성, 타임아웃
- CI 통합: 테스트 자동 실행, 실패 시 블로킹, 리포트 생성
- 테스트 격리: 테스트 간 상태 공유, 순서 의존, 외부 의존 모킹
- 플레이키 테스트: 비결정적 테스트, 타이밍 의존
- 테스트 가독성: 테스트 의도 명확성, Given-When-Then 구조
- 탐색 힌트: `test/`, `tests/`, `__tests__/`, `spec/` 디렉토리. 테스트 설정 파일(jest.config, pytest.ini, vitest.config) 확인

## AI/ML
- 프롬프트 설계: 인젝션 방어, 구조화, 시스템/유저 프롬프트 분리
- 모델 통합: API 키 관리, 폴백, 타임아웃, 재시도 전략
- 평가 메트릭: 정확도/재현율 측정 체계, A/B 테스트
- 안전 가드레일: 출력 필터링, 콘텐츠 정책, 토큰 제한
- 비용 관리: 토큰 사용량 추적, 캐싱, 모델 선택 전략
- 스트리밍: SSE/WebSocket 처리, 부분 응답 핸들링
- 컨텍스트 관리: 히스토리 크기, 요약, 메모리 패턴
- RAG 파이프라인: 청킹, 임베딩, 검색 품질, 할루시네이션 방지
- 탐색 힌트: `*prompt*`, `*llm*`, `*ai*`, `*agent*`, `*chain*` 파일. `grep -rn "openai\|anthropic\|claude\|gpt\|embedding" --include="*.{ts,py}"` 실행

## 인프라/배포
- IaC: 코드로 관리되지 않는 인프라, 드리프트
- CI/CD: 빌드/테스트/배포 파이프라인 완성도, 병렬화
- 컨테이너: 이미지 크기, 멀티스테이지 빌드, 비루트 실행
- 롤백: 배포 실패 시 복구 절차, 카나리/블루-그린
- 비용 최적화: 과잉 프로비저닝, 리저브드 vs 온디맨드
- 모니터링: 헬스체크, 알림, 대시보드, SLA/SLO
- 시크릿: 환경변수 관리, 볼트, 로테이션
- 탐색 힌트: `Dockerfile`, `.github/workflows/`, `terraform/`, `docker-compose*`, `*deploy*`, `k8s/` 파일 우선

## 디버깅
- 에러 패턴: 반복되는 에러, 근본 원인 미해결, 에러 전파 경로
- 로깅: 구조화된 로그, 적절한 로그 레벨, 상관관계 ID
- 레이스 컨디션: 동시 접근, 락 누락, 원자성 보장
- 리그레션: 이전 수정이 되돌아간 패턴
- 에러 핸들링 체인: try-catch 계층, 에러 변환/래핑, 사용자 메시지
- 디버그 도구: 소스맵, 디버거 설정, 프로파일러 지원
- 탐색 힌트: `grep -rn "catch\|except\|error\|throw\|panic\|console\.error" --include="*.{ts,py,go}"` + 로그 설정 파일 확인

## 문서
- API 문서: 엔드포인트, 파라미터, 응답 형식, 에러 코드
- 아키텍처 문서: 시스템 구조, 데이터 흐름, 결정 기록 (ADR)
- 온보딩 가이드: 개발 환경 설정, 실행 방법, 기여 가이드
- 인라인 문서: 복잡한 로직의 주석, JSDoc/docstring
- 변경 로그: CHANGELOG 유지, 시맨틱 버저닝

## UI/UX
- 사용성: 직관적 인터페이스, 학습 곡선, 태스크 완료 경로
- 접근성: 스크린 리더, 키보드 전용 사용, 포커스 관리
- 디자인 일관성: 컬러/폰트/간격 통일, 디자인 토큰 사용
- 에러 UX: 사용자 친화적 에러 메시지, 복구 경로, 빈 상태
- 로딩 상태: 스켈레톤, 스피너, 진행률, 옵티미스틱 UI
- 애니메이션/트랜지션: 의미 있는 모션, 성능 영향, 접근성 (prefers-reduced-motion)
- 탐색 힌트: `src/components/`, `src/styles/`, `src/theme/` 우선. 디자인 토큰/테마 파일 확인

## 장애 대응
- 장애 분류: 심각도 정의, 에스컬레이션 경로
- 모니터링: 알림 설정, 대시보드, 로그 집계
- 복구 절차: 런북, 자동 복구, 수동 개입 절차
- 포스트모템: 근본 원인 분석 체계, 재발 방지책
- 장애 격리: 서킷 브레이커, 벌크헤드, 그레이스풀 디그레이데이션

## 언어 전문가
- 관용적 코드: 해당 언어의 베스트 프랙티스, 컨벤션
- 타입 시스템: 언어 고유 타입 기능 활용 (제네릭, 유니온, 패턴 매칭)
- 생태계 활용: 표준 라이브러리, 커뮤니티 패키지 최신 관행
- 동시성 모델: 언어별 동시성 패턴 (async/await, goroutine, actor)
- 메모리 관리: GC 튜닝, 소유권(Rust), 참조 카운팅
- 빌드/패키지: 빌드 도구 설정, 의존성 관리, 모노레포 구조

---

## 게임 디자인
- 코어 루프: 핵심 게임플레이 루프의 명확성과 몰입도
- 시스템 설계: 전투/성장/제작 등 시스템 간 상호작용, 순환 구조
- 밸런싱: 수치 체계 일관성, 성장 곡선, 파워 커브, 뉴메릭 시뮬레이션
- 난이도 곡선: 학습 곡선, 플로우 채널 (불안-지루 사이), 적응형 난이도
- 진행 설계: 언락 구조, 마일스톤, 목표 가시성, 보상 간격
- 피드백 시스템: 시각/청각/촉각 피드백, 반응 딜레이, 타격감
- 메타게임: 장기 목표, 소셜 요소, 경쟁/협동 구조
- UX 흐름: 메뉴 구조, 튜토리얼 설계, 온보딩 경험
- 접근성: 다양한 플레이어 스킬 수준 대응, 난이도 옵션
- 탐색 힌트: `*config*`, `*balance*`, `*game*`, `*level*`, `*stage*` 파일. `grep -rn "damage\|health\|exp\|reward\|drop.rate\|cooldown\|spawn" --include="*.{ts,py,json,yaml}"` 실행

## 게임 QA
- 엣지케이스: 경계값 (0, 음수, 최대치 오버플로, 동시 입력)
- 밸런스 브레이크: 무한 리소스, 스킵 가능 구간, 의도치 않은 콤보
- 익스플로잇: 치트 가능 경로, 클라이언트 조작, 리플레이 어택
- 재현 시나리오: 버그 재현 절차 명확성, 로그 충분성
- 상태 일관성: 세이브/로드, 접속 끊김, 재접속 시 상태 복원
- 동시성 이슈: 멀티플레이어 동기화, 레이스 컨디션, 데스싱크
- 성능 스트레스: 대량 오브젝트, 파티클, AI 동시 처리 시 프레임 드롭
- 플랫폼 호환: 해상도, 입력 장치, OS별 동작 차이
- 탐색 힌트: `*test*`, `*cheat*`, `*hack*`, `*exploit*` 파일. 상태 머신, 게임 루프, 물리 엔진 관련 코드 우선 확인

## 내러티브 디자인
- 스토리 구조: 3막 구조, 기승전결, 서사적 아크의 완결성
- 세계관 일관성: 설정 간 모순, 타임라인 정합성, 용어 통일
- 캐릭터 설계: 동기 부여, 성격 일관성, 성장 아크
- 퀘스트 설계: 목표 명확성, 선택지 의미, 보상 서사적 연결
- 분기 구조: 선택-결과 매핑, 분기점 자연스러움, 합류 처리
- 대사/텍스트: 톤 일관성, 캐릭터별 음성, 현지화 대비
- 환경 서사: 레벨/맵 내 스토리텔링, 발견형 서사
- 감정 곡선: 텐션 그래프, 감정 페이싱, 카타르시스 배치
- 탐색 힌트: `*story*`, `*dialogue*`, `*quest*`, `*narrative*`, `*lore*`, `*script*` 파일. `grep -rn "dialogue\|npc\|cutscene\|chapter\|episode" --include="*.{json,yaml,ts,py}"` 실행

## 게임 이코노미
- 재화 설계: 재화 종류, 획득/소비 채널, 교환비율
- 싱크/소스 분석: 각 재화의 유입(source)과 유출(sink) 밸런스
- 인플레이션 관리: 장기 재화 팽창 예측, 골드 싱크 장치
- 가치 체계: 아이템 가치 기준, 희소성 설계, 등급 체계
- 거래 시스템: P2P 거래, 경매장, 가격 안정 장치
- 확률 설계: 드롭률, 가챠 확률, 피티 시스템, 확률 공개
- 시뮬레이션: 경제 시뮬레이터 존재 여부, 파라미터 테이블 관리
- BM 연결: 유료 재화-무료 재화 교환비, 과금 압박 수준
- 탐색 힌트: `*economy*`, `*currency*`, `*shop*`, `*gacha*`, `*drop*`, `*reward*`, `*price*` 파일. `grep -rn "gold\|gem\|diamond\|coin\|price\|cost\|rate\|prob" --include="*.{json,yaml,ts,py}"` 실행

## 모네타이제이션
- 과금 모델: IAP/구독/광고/배틀패스, 모델별 장단점
- 확률형 아이템: 가챠 설계, 확률 표시 (법적 요건), 피티/천장
- LTV 설계: 유저 생애가치 극대화 경로, 과금 단계
- ARPU/ARPPU: 과금 유저 비율, 평균 과금액 추정
- 이탈 방지: 과금 후 이탈, 과금 피로도, 리텐션-매출 균형
- 지역별 가격: 국가별 가격 차등, 환율 대응
- 광고 통합: 보상형 광고 배치, 빈도 제한, UX 영향
- 윤리적 설계: 미성년자 보호, 과금 한도, 도박성 방지
- 탐색 힌트: `*shop*`, `*store*`, `*purchase*`, `*iap*`, `*billing*`, `*subscription*` 파일. `grep -rn "purchase\|buy\|price\|sku\|product.id\|receipt" --include="*.{ts,py,json,swift,kt}"` 실행

## 라이브옵스
- 시즌 설계: 시즌 기간, 보상 구조, 시즌패스 진행률
- 이벤트 설계: 이벤트 종류, 기간, 보상 밸런스, 반복 주기
- 컨텐츠 케이던스: 업데이트 주기, 드라이 컨텐츠 기간, 파이프라인
- 운영 KPI: DAU/MAU, 리텐션 D1/D7/D30, 매출, LTV
- A/B 테스트: 테스트 설계, 세그먼트, 유의성 검증
- 핫픽스 절차: 긴급 패치 배포 프로세스, 롤백
- 공지/푸시: 인앱 공지, 푸시 알림, 점검 공지 시스템
- 어뷰징 대응: 치터 감지, 제재 시스템, 로그 보존
- 탐색 힌트: `*event*`, `*season*`, `*campaign*`, `*notice*`, `*banner*` 파일. `grep -rn "event.start\|event.end\|season\|maintenance\|hotfix" --include="*.{ts,py,json,yaml}"` 실행

## 유저 리서치
- 메트릭 체계: DAU/MAU/리텐션/세션 길이/퍼널 정의
- 코호트 분석: 가입일/과금/레벨 기준 그룹 비교
- A/B 테스트: 가설-실험-검증 루프, 유의성, 샘플 크기
- 퍼널 분석: 튜토리얼→첫 과금→장기 리텐션 전환율
- 유저 세그먼트: 고래/돌고래/미넛, 하드코어/캐주얼 분류
- 행동 데이터: 이벤트 로깅, 추적 계획, 데이터 파이프라인
- 서베이/인터뷰: 정성 데이터 수집 방법, NPS
- 대시보드: 실시간 KPI 모니터링, 이상 감지 알림
- 탐색 힌트: `*analytics*`, `*tracking*`, `*metric*`, `*event*`, `*log*` 파일. `grep -rn "track\|analytics\|metric\|event\|amplitude\|mixpanel\|firebase" --include="*.{ts,py,json}"` 실행

---

## 퀀트 전략
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

## 트레이딩 시스템
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

## 리스크 관리
- 포지션 사이징: 계좌 대비 최대 포지션, 단일 거래 최대 손실
- 손절/익절: SL/TP 로직, 트레일링 스탑, 동적 조정
- 최대 드로다운: 일일/주간/총 드로다운 한도, 자동 정지
- 청산 방어: 마진 비율 모니터링, 사전 경고, 자동 디레버리징
- VaR/CVaR: 가치 위험, 극단 시나리오 손실 추정
- 포트폴리오 리스크: 자산 간 상관, 집중 리스크, 섹터 노출
- 자금 관리: 일일 거래 한도, 최대 동시 포지션 수
- 시스템 리스크: API 장애, 가격 피드 이상, 블랙스완 대비
- 규제 리스크: 거래소 규제, 자금세탁 방지, 세금 보고
- 탐색 힌트: `*risk*`, `*position*`, `*stop*`, `*liquidat*`, `*margin*` 파일. `grep -rn "stop.loss\|take.profit\|max.drawdown\|liquidat\|margin.ratio\|risk.limit" --include="*.{py,ts,json}"` 실행

## 마켓 마이크로스트럭처
- 오더북 분석: 호가 깊이, 스프레드, 임밸런스, 호가 벽
- 슬리피지 모델: 예상 vs 실제 체결가, 크기별 영향
- 마켓메이킹: 양방향 호가, 스프레드 관리, 재고 리스크
- 거래량 프로파일: 시간대별 유동성, VWAP, 거래량 클러스터
- 가격 영향: 주문 크기에 따른 시장 충격, 최적 실행 크기
- 틱 데이터: 틱 크기, 최소 주문 단위, 소수점 정밀도
- 유동성 측정: bid-ask spread, 체결 빈도, 시장 깊이
- HFT 패턴: 프론트러닝, 레이어링, 스푸핑 감지
- 페어 트레이딩: 공적분, 스프레드 거래, 평균 회귀
- 탐색 힌트: `*orderbook*`, `*spread*`, `*depth*`, `*tick*`, `*market.mak*` 파일. `grep -rn "bid\|ask\|spread\|depth\|volume\|tick\|orderbook\|book" --include="*.{py,ts}"` 실행

## 온체인 분석
- 고래 추적: 대량 이체 감지, 지갑 레이블링, 클러스터링
- 온체인 메트릭: TVL, 활성 주소, 트랜잭션 볼륨, 가스 비용
- MEV: 프론트러닝, 백러닝, 샌드위치 공격 감지/방어
- 네트워크 활동: 블록 생성 시간, 멤풀 상태, 혼잡도
- 토큰 흐름: 거래소 입출금, 브릿지 활동, 디파이 프로토콜 흐름
- 스마트 컨트랙트 이벤트: Transfer, Swap, Mint/Burn 이벤트 파싱
- 데이터 소스: RPC 노드, 인덱서 (The Graph, Dune), API 제공자
- 주소 분류: EOA vs 컨트랙트, 거래소 핫/콜드 월렛, 라벨 DB
- 탐색 힌트: `*chain*`, `*web3*`, `*ethers*`, `*abi*`, `*contract*` 파일. `grep -rn "web3\|ethers\|provider\|abi\|transfer\|swap\|event\|log" --include="*.{py,ts,json}"` 실행

## DeFi 분석
- 스마트 컨트랙트: 감사 상태, 업그레이드 가능성, 프록시 패턴
- 유동성 풀: LP 구조, 임퍼머넌트 로스, 풀 깊이
- 프로토콜 리스크: TVL 변동, 해킹 이력, 팀 신뢰도
- 수익률 분석: APY/APR 계산, 지속가능성, 인플레이션 소스
- 오라클: 가격 피드 소스, 지연, 조작 가능성
- 거버넌스: 투표 구조, 토큰 분배, 중앙화 리스크
- 크로스 체인: 브릿지 리스크, 멀티체인 지원, 유동성 파편화
- 플래시론: 플래시론 공격 벡터, 방어 패턴
- 탐색 힌트: `*defi*`, `*pool*`, `*swap*`, `*farm*`, `*vault*`, `*lend*` 파일. `grep -rn "liquidity\|pool\|swap\|stake\|yield\|apy\|apr\|oracle\|flash" --include="*.{py,ts,sol}"` 실행

## 백테스트/시뮬레이션
- 오버피팅 방지: 표본 내/외 분리, 워크포워드 분석, 파라미터 민감도
- 슬리피지 모델링: 고정/동적 슬리피지, 주문 크기 영향
- 거래 비용: 수수료, 스프레드, 펀딩 비용 정확한 반영
- 데이터 품질: 누락 데이터 처리, 이상치, 타임존, 시차
- 몬테카를로: 랜덤 시뮬레이션, 분포 가정, 신뢰 구간
- 스트레스 테스트: 극단 시나리오, 블랙스완 이벤트, 상관관계 붕괴
- 벤치마크: 수익률 비교 기준 (시장 수익, 바이앤홀드, 동종 전략)
- 시간 프레임: 틱/분봉/시봉/일봉별 전략 성능 차이
- 시뮬레이션 인프라: 이벤트 기반 vs 벡터 기반, 실행 속도, 병렬화
- 탐색 힌트: `*backtest*`, `*simulate*`, `*engine*`, `*result*` 파일. `grep -rn "backtest\|simulate\|monte.carlo\|walk.forward\|sharpe\|drawdown\|equity.curve" --include="*.{py,ts}"` 실행

---

## 수학/통계
- 확률 분포: 수익률 분포 가정 (정규/로그정규/팻테일), 적합도 검정
- 기대값 계산: EV 분석, 켈리 기준, 기회비용
- 가설 검정: p-value, 유의 수준, 다중 비교 보정 (Bonferroni, FDR)
- 회귀 분석: 선형/비선형, 다중공선성, 과적합
- 시계열 분석: 정상성, 자기상관, ARIMA, 계절성
- 최적화: 목적 함수, 제약 조건, 수렴, 로컬/글로벌 최적
- 베이지안 방법: 사전/사후 분포, MCMC, 베이지안 업데이트
- 수치 안정성: 부동소수점 오차, 언더플로/오버플로, 정밀도
- 차원 축소: PCA, t-SNE, 특성 선택
- 탐색 힌트: `*stats*`, `*math*`, `*model*`, `*analysis*` 파일. `grep -rn "mean\|std\|variance\|correlation\|pvalue\|regression\|distribution\|optimize" --include="*.{py,ts,r}"` 실행

## 데이터 파이프라인
- 실시간 스트리밍: WebSocket/SSE 처리, 메시지 순서 보장, 재연결
- ETL: 추출-변환-적재 파이프라인, 스케줄링, 실패 재시도
- 이벤트 소싱: 이벤트 저장소, 리플레이, 스냅샷, CQRS
- 시계열 DB: 인플럭스/TimescaleDB/ClickHouse 설계, 보존 정책
- 데이터 품질: 유효성 검증, 스키마 진화, 누락 감지
- 처리량/지연: 초당 메시지, 처리 지연, 백프레셔
- 장애 복구: 데드레터 큐, 재처리, idempotency
- 모니터링: 파이프라인 지연 알림, 데이터 신선도, 누적 지표
- 저장 전략: 파티셔닝, 압축, 콜드/핫 스토리지 분리
- 탐색 힌트: `*pipeline*`, `*stream*`, `*ingest*`, `*etl*`, `*queue*`, `*kafka*`, `*redis*` 파일. `grep -rn "subscribe\|publish\|consume\|produce\|stream\|pipeline\|queue\|kafka\|redis" --include="*.{py,ts,yaml}"` 실행

## RAG 아키텍처

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

## 벡터DB

- [ ] DB 선택 근거 — 규모·쿼리 특성·운영 비용 적합성
- [ ] 인덱스 파라미터 — HNSW M/efConstruction, IVF nlist 등 튜닝 여부
- [ ] 메타데이터 필터 — pre-filtering vs post-filtering 성능 영향
- [ ] 업서트 패턴 — 전체 재인덱싱 vs 증분, 중복 방지 키
- [ ] 파티셔닝 — 테넌트·시간·언어 분리
- [ ] 백업·복구 — 인덱스 재구축 시간, 스냅샷 전략
- [ ] 쿼리 성능 — p95/p99 레이턴시, N+1 embed 호출 감지
- [ ] 비용 — 인덱스 메모리 사용, 쿼리당 비용

**탐색 힌트**: `*vector*`, `*index*`, pinecone/weaviate/qdrant/chroma/pgvector import

## 프롬프트 엔지니어링

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

## 모델 평가/eval

- [ ] 평가 데이터셋 — 크기·다양성·실사용 분포 일치 여부
- [ ] 메트릭 선택 — task별 적합성 (BLEU/ROUGE/F1/LLM-as-judge/human)
- [ ] 베이스라인 — 이전 버전·경쟁 모델 비교 설정
- [ ] 리그레션 감지 — CI에서 eval 실행, 임계값 alerting
- [ ] LLM-as-judge 편향 — 판정자 모델과 평가 대상 같은 모델 사용 금지
- [ ] 에지 케이스 커버리지 — 긴 입력, 다국어, 악의적 입력, 빈 입력
- [ ] 재현성 — seed/temperature 고정, 실행 환경 명시
- [ ] 비용 추적 — eval 실행 비용, 샘플링 전략

**탐색 힌트**: `eval*/`, `benchmark*/`, `tests/**/llm*`, pytest에서 OpenAI/Anthropic 호출

## 파인튜닝

- [ ] 데이터 품질 — 정제·중복 제거·라벨 일관성
- [ ] 데이터 분할 — train/val/test 오염 방지, 시간 기반 split
- [ ] 하이퍼파라미터 — LR·배치·epoch 근거, warmup/decay
- [ ] LoRA/QLoRA vs Full — 계산 비용 대비 효과
- [ ] 오버피팅 모니터링 — val loss, 조기 종료
- [ ] 배포 형태 — 어댑터 머지 여부, 양자화 전략
- [ ] 안전성 재검증 — 기본 모델 대비 harmful 응답 증가 여부
- [ ] 재학습 워크플로우 — 데이터 갱신 → 재학습 자동화

**탐색 힌트**: `transformers/`, `peft`, `trainer.py`, `*finetune*`, `datasets/` with jsonl

## GraphQL

- [ ] 스키마 설계 — nullable 정책, interface/union 활용, 버전 관리
- [ ] 리졸버 N+1 — DataLoader 사용, 배치 해결
- [ ] 권한 모델 — 필드 단위 인가, 디렉티브 vs 미들웨어
- [ ] 쿼리 복잡도 — depth/complexity limit, timeout
- [ ] 캐싱 — persisted query, response 캐시, field 캐시
- [ ] 에러 처리 — partial errors, extensions 표준
- [ ] 스키마 진화 — deprecation 절차, breaking change 탐지
- [ ] 클라이언트 코드젠 — 타입 동기화, 트리 셰이킹

**탐색 힌트**: `*.graphql`, `schema.graphql`, apollo/relay/graphql-js import

## gRPC

- [ ] proto 스키마 — reserved 필드, wire format 호환성
- [ ] 스트리밍 — 언제 unary/server/client/bidi 쓰는지
- [ ] 데드라인·취소 — 모든 RPC에 데드라인 강제
- [ ] 재시도·idempotency — safe retry, jitter
- [ ] 인증 — mTLS, metadata 기반 인증
- [ ] 버전 관리 — 패키지명 버저닝, 하위 호환 규칙
- [ ] 로드 밸런싱 — 클라이언트 LB vs proxy, picker 전략
- [ ] 관찰성 — tracing context 전파, error code 매핑

**탐색 힌트**: `*.proto`, `grpc_gen/`, grpc-go/grpc-js import

## OpenAPI/REST 계약

- [ ] 계약 위치 — spec vs 코드 생성 방향(code-first vs spec-first)
- [ ] 버전 전략 — URL path vs header, 동시 지원 기간
- [ ] 에러 스키마 — RFC 7807 Problem Details 준수
- [ ] 페이지네이션·필터·정렬 — 표준화 여부
- [ ] idempotency — POST/PUT/DELETE 키 전략
- [ ] 인증 스킴 — OAuth2/JWT/API key 혼용 문제
- [ ] 계약 테스트 — pact/dredd, CI 통합
- [ ] 드리프트 탐지 — 런타임 스펙과 실제 응답 일치

**탐색 힌트**: `openapi.{yaml,json}`, `swagger.*`, FastAPI/NestJS/Express OpenAPI 어댑터

## 이벤트 드리븐

- [ ] 이벤트 스키마 — 버전 관리, 스키마 레지스트리(Confluent·Apicurio)
- [ ] idempotency — consumer 중복 처리 방어, dedup key
- [ ] 순서 보장 — 파티션 키 전략, 순서 필요성 재검토
- [ ] at-least-once vs exactly-once — 트레이드오프 명시
- [ ] 재처리·리플레이 — DLQ, 오프셋 리셋 절차
- [ ] 스키마 진화 — 하위 호환, forward/backward compatibility
- [ ] 백프레셔·처리량 — consumer lag 모니터링, scaling 정책
- [ ] 분산 트랜잭션 — Saga/outbox 패턴 적용 여부

**탐색 힌트**: `*.avsc`, kafka/rabbitmq/nats/sqs config, `events/`, `handlers/`
