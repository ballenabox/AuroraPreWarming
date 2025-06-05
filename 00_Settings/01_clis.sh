#!/bin/bash
export PGBENCH_CONN="--host=<ENDPOINT> --port=5432 --username=<USER> --dbname=pocdb"

# 1) 데이터베이스 초기화(기존 데이터 제거 후 재생성)
psql $PGBENCH_CONN -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"

# 2) pgbench 초기화
pgbench $PGBENCH_CONN --scale=10 --initialize

# 3) 검증
psql $PGBENCH_CONN -c "SELECT count(*) FROM pgbench_accounts;"
psql $PGBENCH_CONN -c "SELECT pg_database_size('pocdb');"




# pgbench 초기화
pgbench \
  --host=junwoo-pg.cluster-ro-cbuux5qi4dh6.ap-northeast-2.rds.amazonaws.com \
  --port=5432 \
  --username=postgres \
  --dbname=pocdb \
  --scale=10 \
  --initialize

# report before warming
pgbench \
  -h [Read Replica Endpoint] \
  -p 5432 \
  -U postgres \
  -d [Test DB Name] \
  -c 10 \
  -T 30 \
  -f benchmark.sql \
  -r
  > cold_report.txt

# warming
psql \
  -h [Read Replica Endpoint] \
  -p 5432 \
  -U postgres \
  -d [Test DB Name]  \
  -f warming_queries.sql

# report after warming
pgbench \
  -h [Read Replica Endpoint] \
  -p 5432 \
  -U postgres \
  -d [Test DB Name] \
  -c 10 \
  -T 30 \
  -f benchmark.sql \
  -r \
  > warm_report.txt
