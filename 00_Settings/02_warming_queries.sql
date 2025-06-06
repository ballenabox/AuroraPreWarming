-- warming_queries.sql

-- 1. Point Lookup: pgbench_accounts에서 랜덤 키 조회 (100회)
DO $$
BEGIN
  FOR i IN 1..100 LOOP
    EXECUTE format(
      'SELECT * FROM pgbench_accounts WHERE aid = %s',
      floor(random() * 1000000) + 1
    );
  END LOOP;
END
$$;

-- 2. Range Scan: pgbench_history에서 최근 1일치 레코드 읽기 (10회)
DO $$
BEGIN
  FOR i IN 1..10 LOOP
    EXECUTE '
      SELECT * 
      FROM pgbench_history
      WHERE mtime BETWEEN NOW() - INTERVAL ''1 day'' AND NOW()
    ';
  END LOOP;
END
$$;

-- 3. Join: accounts ↔ tellers를 bid 기준으로 조인 (50회)
DO $$
BEGIN
  FOR i IN 1..50 LOOP
    EXECUTE format(
      'SELECT a.abalance, t.tbalance
       FROM pgbench_accounts a
       JOIN pgbench_tellers t ON a.bid = t.bid
       WHERE a.bid = %s',
      floor(random() * 10) + 1
    );
  END LOOP;
END
$$;

-- 4. Aggregation: history에서 지점별 delta 합계 조회
SELECT bid, SUM(delta) AS total_delta
  FROM pgbench_history
 GROUP BY bid;

-- 5. Full Table Scan: 각 테이블 전체 블록 워밍업
SELECT COUNT(*) AS cnt_accounts   FROM pgbench_accounts;
SELECT COUNT(*) AS cnt_branches   FROM pgbench_branches;
SELECT COUNT(*) AS cnt_tellers    FROM pgbench_tellers;
SELECT COUNT(*) AS cnt_history    FROM pgbench_history;


-- ================================
-- pgbench 샘플 데이터 기반 경량 테스트 쿼리 모음
-- (이전보다 실행 시간이 덜 걸리도록 LIMIT 및 인덱스 조회 위주로 구성)
-- ================================

-- 1) [Primary Key Lookup] 랜덤한 계정 1개 조회
--    ⇒ aid에 대한 인덱스 조회만 수행하므로 실행 속도가 빠릅니다.
SELECT *
  FROM pgbench_accounts
 WHERE aid = floor(random() * 100000 + 1);
-- └─ Scale factor=1 환경에서 aid는 1~100000 사이의 값이므로
--    WHERE 절 조건을 만족하는 행을 바로 인덱스 스캔으로 찾습니다.

-- 2) [LIMIT] 테이블 상위 100개 행 조회
--    ⇒ pgbench_accounts 테이블을 앞쪽부터 100개만 읽고 바로 종료합니다.
SELECT *
  FROM pgbench_accounts
 LIMIT 100;
-- └─ 전체 테이블을 스캔하지 않고, 페이지를 읽어 첫 100개 행만 반환하므로 속도가 빠릅니다.

-- 3) [ORDER BY + LIMIT] aid 내림차순 정렬 후 상위 100개 조회
--    ⇒ aid는 기본 키이므로, 인덱스 스캔 후 LIMIT 절로 100개만 반환합니다.
SELECT aid,
       abalance
  FROM pgbench_accounts
 ORDER BY aid DESC
 LIMIT 100;
-- └─ 기본 키 인덱스 순서대로 뒤에서부터 100개만 가져오기 때문에
--    풀 스캔 없이 빠르게 결과를 얻습니다.

-- 4) [소규모 집계] pgbench_tellers 전체 행 수 집계
--    ⇒ 테이블 크기가 매우 작아(예: 10개 행) 집계에 걸리는 시간이 거의 없습니다.
SELECT count(*) AS teller_count
  FROM pgbench_tellers;
-- └─ Scale factor=1 기준으로 약 10개의 행만 집계하므로 순식간에 결과가 나옵니다.

-- 5) [간단한 JOIN + LIMIT] 계정 ⇆ 지점 ⇆ 창구원 조인 후 상위 50개만 조회
--    ⇒ JOIN은 발생하지만 LIMIT이 있기 때문에 50개 행만 반환되면 바로 종료합니다.
SELECT a.aid,
       a.abalance,
       b.bbalance,
       t.tbalance
  FROM pgbench_accounts AS a
  JOIN pgbench_branches AS b
    ON a.bid = b.bid
  JOIN pgbench_tellers AS t
    ON a.tid = t.tid
 LIMIT 50;
-- └─ JOIN 단계에서 일치하는 첫 50개 조합만 만들어지면 반환 후 종료하므로
--    전체 조인 결과를 모두 생성하지 않아 상대적으로 빠릅니다.