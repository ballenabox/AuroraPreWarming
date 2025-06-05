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