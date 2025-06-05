# AuroraPreWarming
Aurora PostgreSQL Read Replica Pre-Warming Project
00_Settings
    사전 데이터 세팅, 성능 테스트, TOP100 쿼리 추출 설정 등을 위한 스크립트
01_StepFunctions
    AWS Step Function 정의 코드
02_Lambda
    WarmingDBInstance.py : DB 인스턴스 warming 함수
    UpdateStaticMembers.py : Custom Endpoint 수정 시 입력할 새로운 Static Member 배열을 반환하는 함수
03_ConnectionTest
    전체 과정 진행 중 Aurora Custom Endpoint 단절 여부 및 신규 인스턴스 편입 여부를 확인하는 스크립트