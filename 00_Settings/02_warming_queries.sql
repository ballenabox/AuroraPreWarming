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
-- pgbench 샘플 데이터 기반 테스트 쿼리 모음
-- (반복 실행 시 Top100에 올라갈 정도의 부하를 유발하도록 설계)
-- ================================

-- 1) [Sequential Scan] 특정 Branch(bid) 전체 행 읽기
--    ⇒ bid에 인덱스가 없으므로, 전체 pgbench_accounts 테이블을 순차 스캔하게 됩니다.
SELECT *
  FROM pgbench_accounts
 WHERE bid = 1;
-- └─ Scale factor=1 환경에서, bid=1이면 모든 계정(약 100,000개 행)을 읽어오기 때문에
--    디스크→버퍼 로드 부하가 큽니다.

-- 2) [Sequential Scan + Filter] abalance 범위 조회
--    ⇒ abalance 컬럼을 인덱스화하지 않았다면, 전체 테이블을 스캔하며 필터링하므로 시간이 더 걸립니다.
SELECT *
  FROM pgbench_accounts
 WHERE abalance BETWEEN 500000 AND 1000000;
-- └─ 적당히 넓은 범위(예: abalance가 중간값 이상)에 해당하는 많은 행을 걸러야 하므로
--    단일 쿼리로도 충분한 부하가 걸립니다.

-- 3) [Aggregation] Branch별 계정 수 집계
--    ⇒ pgbench_accounts를 순차 스캔한 뒤 GROUP BY가 실행되므로, 테이블 전체를 한 번 훑어야 합니다.
SELECT bid,
       COUNT(*) AS account_count
  FROM pgbench_accounts
 GROUP BY bid;
-- └─ Scale factor=1 기준으로 bid가 1개만 존재하더라도 COUNT(*) 연산으로 전체 행을 센 뒤
--    GROUP BY가 처리되므로 부하가 발생합니다. (테이블 스캔 + 그룹 바이트 정리)

-- 4) [Sort + Limit] abalance 내림차순 정렬 후 상위 1,000개 추출
--    ⇒ 정렬(sort)이 필요하므로 메모리·CPU 부하가 큽니다.
SELECT aid
  FROM pgbench_accounts
 ORDER BY abalance DESC
 LIMIT 1000;
-- └─ 100,000개 행 전체를 abalance 기준으로 정렬해야 상위 1,000개를 찾을 수 있으므로,
--    메모리 정렬 및 페이지 스캔 비용이 발생합니다.

-- 5) [Join + Filter] Accounts ⇆ Branches ⇆ Tellers 결합 후 필터링
--    ⇒ 두 번의 조인(join)과 적절한 필터링을 거쳐야 하므로, 실행 계획이 복잡해지고 I/O 부하도 커집니다.
SELECT a.aid,
       a.abalance,
       b.bbalance,
       t.tbalance
  FROM pgbench_accounts AS a
  JOIN pgbench_branches AS b
    ON a.bid = b.bid
  JOIN pgbench_tellers AS t
    ON a.tid = t.tid
 WHERE a.abalance > 500000;
-- └─ a.abalance > 500000 조건으로, 먼저 a 테이블에서 abalance 필터를 거친 뒤(between 같은 범위),
--    해당 행과 일치하는 b, t 테이블의 행을 조인해야 합니다. → 조인 순서에 따라 대량 I/O가 발생합니다.
