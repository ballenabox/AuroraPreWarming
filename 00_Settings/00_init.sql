-- PoC용 데이터베이스 생성
CREATE DATABASE pocdb OWNER <USER>;
\c pocdb


-- pgbench 초기화 시 자동 생성되는 테이블들의 DDL
-- Branches: 지점 정보
CREATE TABLE public.pgbench_branches (
  bid      integer      NOT NULL,   -- 지점 ID
  bbalance integer,                 -- 지점 잔액 합계
  filler   char(88)                 -- 패딩용
);
ALTER TABLE public.pgbench_branches
  ADD CONSTRAINT pgbench_branches_pkey PRIMARY KEY (bid);

-- Tellers: 창구원 정보
CREATE TABLE public.pgbench_tellers (
  tid      integer      NOT NULL,   -- 창구원 ID
  bid      integer,                 -- 소속 지점 ID
  tbalance integer,                 -- 창구원 잔액 합계
  filler   char(84)
);
ALTER TABLE public.pgbench_tellers
  ADD CONSTRAINT pgbench_tellers_pkey PRIMARY KEY (tid);

-- Accounts: 계좌 정보
CREATE TABLE public.pgbench_accounts (
  aid      integer      NOT NULL,   -- 계좌 ID
  bid      integer,                 -- 소속 지점 ID
  tid      integer,                 -- 담당 창구원 ID
  abalance integer,                 -- 계좌 잔액
  filler   char(84)
);
ALTER TABLE public.pgbench_accounts
  ADD CONSTRAINT pgbench_accounts_pkey PRIMARY KEY (aid);

-- History: 거래 내역
CREATE TABLE public.pgbench_history (
  tid      integer,                 -- 거래 처리한 창구원 ID
  bid      integer,                 -- 거래 발생 지점 ID
  aid      integer,                 -- 거래 대상 계좌 ID
  delta    integer,                 -- 거래 금액 증감
  mtime    timestamp,               -- 거래 시각
  filler   char(22)
);
-- 기본적으로 히스토리에는 PK가 없으며, 거래 로그용으로만 사용


-- Aurora PostgreSQL에 pg_stat_statements 확장 설치
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Top100 쿼리 추출
SELECT 
  query,
  calls,
  total_exec_time   AS total_time,
  mean_exec_time    AS mean_time
FROM pg_stat_statements
WHERE query NOT ILIKE '%pg_stat_statements%'
ORDER BY total_exec_time DESC
LIMIT 100;

-- pg_cron JOB for export TOP100 query to S3
SELECT cron.schedule(
  'dump_top100_to_s3',        -- 작업 이름
  '0 * * * *',                -- 매 정각
$$
  -- 1) S3 URI 구조 생성 (버킷명, 객체키, 리전)
  WITH uri AS (
    SELECT aws_commons.create_s3_uri(
      'junwoo-test-bucket-250526',
      'top100/' || to_char(now(), 'YYYYMMDD_HH24MI') || '.csv',
      'ap-northeast-2'
    ) AS s3uri
  )
  -- 2) Top100 쿼리 결과를 CSV 형식으로 S3에 내보내기
  SELECT aws_s3.query_export_to_s3(
    $$
      SELECT
        query,
        calls,
        total_exec_time AS total_time,
        mean_exec_time  AS mean_time
      FROM pg_stat_statements
      WHERE query NOT ILIKE '%pg_stat_statements%'
      ORDER BY total_exec_time DESC
      LIMIT 100
    $$,
    uri.s3uri,
    options := 'format csv, header true'
  )
  FROM uri;
$$
);

-- pg_cron 주석 없는 버전
SELECT cron.schedule(
  'dump_top100_to_s3',
  '*/30 * * * *',
$$
  WITH uri AS (
    SELECT aws_commons.create_s3_uri(
      'junwoo-test-bucket-250526',
      'top100/' || to_char(now(), 'YYYYMMDD_HH24MI') || '.csv',
      'ap-northeast-2'
    ) AS s3uri
  )
  SELECT aws_s3.query_export_to_s3(
    $$
      SELECT
        query,
        calls,
        total_exec_time AS total_time,
        mean_exec_time  AS mean_time
      FROM pg_stat_statements
      WHERE query NOT ILIKE '%pg_stat_statements%'
      ORDER BY total_exec_time DESC
      LIMIT 100
    $$,
    uri.s3uri,
    options := 'format csv, header true'
  )
  FROM uri;
$$
);

-- S3 export JOB 수동 실행
WITH uri AS (
  SELECT aws_commons.create_s3_uri(
	'junwoo-test-bucket-250526',
	'top100/' || to_char(now(), 'YYYYMMDD_HH24MI') || '.csv',
	'ap-northeast-2'
  ) AS s3uri
)
SELECT aws_s3.query_export_to_s3(
  $qry$
	SELECT
	  query,
	  calls,
	  total_exec_time AS total_time,
	  mean_exec_time  AS mean_time
	FROM pg_stat_statements
	WHERE query NOT ILIKE '%pg_stat_statements%'
	ORDER BY total_exec_time DESC
	LIMIT 100
  $qry$,
  uri.s3uri,
  options := 'format csv, header true'
)
FROM uri;

