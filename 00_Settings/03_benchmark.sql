-- benchmark.sql

-- 1) Point lookup: aid 기준 랜덤 조회
\set aid random(1,1000000)
SELECT * FROM pgbench_accounts WHERE aid = :aid;

-- 2) Range scan: 최근 1일치 history 일부 조회
SELECT * 
FROM pgbench_history
WHERE mtime BETWEEN NOW() - INTERVAL '1 day' AND NOW()
LIMIT 500;

-- 3) Join lookup: branch 기준
\set bid random(1,10)
SELECT a.abalance, t.tbalance
  FROM pgbench_accounts a
  JOIN pgbench_tellers t ON a.bid = t.bid
 WHERE a.bid = :bid;

-- 4) Aggregation: branch별 delta 합계
SELECT bid, SUM(delta) AS sum_delta
  FROM pgbench_history
 GROUP BY bid;

-- 5) Full scan: accounts 전체 row수
SELECT COUNT(*) FROM pgbench_accounts;
