# Aurora Pre-Warming

## 개발 목적
Aurora에서는 노드별로 캐시가 다르기 때문에 Auto Scaling으로 생성된 인스턴스스(Read Replica)는 캐시가 없는 상태.
캐싱 성능이 중요한 워크로드에서는 일시적으로 성능 문제가 발생할 수 있다.
서비스에 신규 인스턴스를 추가하기 전에 캐시 데이터를 적재시키면 서비스 성능 개선에 도움이 될 수 있다.

## 상세 개요
Auto Scaling으로 생성된 Read Replica가 캐시 데이터를 적재한 상태로 서비스에 제공되는 것이 목표.
- 신규 Read Replica에 대해 Warming을 진행
- Warming은 데이터베이스의 Top100 쿼리 기반으로 실행
- Warming이 끝나면 Read Replica를 Custom Endpoint에 추가

## 사용 기술/서비스
- Amazon EventBridge : CloudTrail의 Read Replica 생성 이벤트(CreateDBInstance) 트리거 목적
- AWS Step Function : Warming 프로세스의 단계적 실행 및 추적을 위해 선택
- AWS Lambda : Warming 작업 및 Step Function으로 구현이 어려운 부분을 대체하기 위해 사용
- Python : Lambda(Python 3.12) 개발 언어
- Aurora PostgreSQL : 본 프로젝트의 대상이 되는 데이터베이스
- PostgreSQL : TOP100 쿼리 최신 버전 유지를 위해 pg_cron으로 TOP100 쿼리를 S3로 export

## 기능 상세
Aurora PostgreSQL
1. Auto Scaling 구성에 의해 부하 발생 시 Scale Out 진행

EventBridge
1. Aurora PostgreSQL에서 Scale Out 발생 시 CloudTrail에 기록되는 이벤트(CreateDBInstance) 감지
2. 이벤트가 감지되면 Rule에 연결된 대상(Step Function) 작동

[Step Function][STEP]
1. EventBridge를 통해 트리거 이벤트(CreateDBInstance)의 정보(JSON)를 Input 값으로 입력 받음
2. Input 값을 통해 생성된 DB 인스턴스의 정보 확인
3. 생성된 DB 인스턴스의 상태가 사용 가능(Available) 상태가 될 때까지 대기 및 확인
4. DB 인스턴스의 상태가 확인되면 일정 시간 동안의 해당 인스턴스의 지표(AuroraReplicaLag)를 확인하여 Warming이 가능한 상태인지 확인
5. 지표가 정상인 것까지 확인되었다면 DB 인스턴스 대상으로 Warming 작업 진행(WarmingDBInstance.py)
6. Warming 작업 정상 종료 후, DB 인스턴스를 Custom Endpoint로 편입하기 위해 Custom Endpoint 정보 확인
7. 확인된 정보 기반으로 Custom Endpoint의 인스턴스 목록 업데이트(UpdateStaticMembers.py)
8. 업데이트된 목록으로 Custom Endpoint 수정

Lambda
1. [WarmingDBInstance.py][WDBP] : 3에 있는 TOP100 쿼리 파일을 조회하고, 입력된 DB 인스턴스 대상으로 Warming 진행
2. [UpdateStaticMembers.py][USMP] : 확인된 Custom Endpoint의 기존 인스턴스 목록(Static Members)에 신규 인스턴스 추가


## 개선 필요

- 프로세스 진행 중 이슈가 발생했을 때 알림을 받을 수 있도록 관련 구성 필요
- Aurora에서 Failover 발생 시 Custom Endpoint에 포함된 인스턴스가 Writer 인스턴스가 될 수 있으므로 관련 조정 방안 필요
- Lambda/Step Function 코드에 대한 관리 방안 필요





   [STEP]: <https://github.com/ballenabox/AuroraPreWarming/blob/main/01_StepFunction/StepFunction.json>
   [WDBP]: <https://github.com/ballenabox/AuroraPreWarming/blob/main/02_Lambda/WarmingDBInstance.py>
   [USMP]: <https://github.com/ballenabox/AuroraPreWarming/blob/main/02_Lambda/UpdateStaticMembers.py>
