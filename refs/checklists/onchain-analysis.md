# 온체인 분석

- 고래 추적: 대량 이체 감지, 지갑 레이블링, 클러스터링
- 온체인 메트릭: TVL, 활성 주소, 트랜잭션 볼륨, 가스 비용
- MEV: 프론트러닝, 백러닝, 샌드위치 공격 감지/방어
- 네트워크 활동: 블록 생성 시간, 멤풀 상태, 혼잡도
- 토큰 흐름: 거래소 입출금, 브릿지 활동, 디파이 프로토콜 흐름
- 스마트 컨트랙트 이벤트: Transfer, Swap, Mint/Burn 이벤트 파싱
- 데이터 소스: RPC 노드, 인덱서 (The Graph, Dune), API 제공자
- 주소 분류: EOA vs 컨트랙트, 거래소 핫/콜드 월렛, 라벨 DB
- 탐색 힌트: `*chain*`, `*web3*`, `*ethers*`, `*abi*`, `*contract*` 파일. `grep -rn "web3\|ethers\|provider\|abi\|transfer\|swap\|event\|log" --include="*.{py,ts,json}"` 실행

