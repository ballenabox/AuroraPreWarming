#!/usr/bin/env bash
#
# load_select_replica.sh
#
# Usage:
#   PGHOST=<replica-endpoint> \
#   PGPASSWORD=<your_password> \
#   ./load_select_replica.sh \
#     -U <db_user> \
#     -d <db_name> \
#     -c 20 \         # 동시 클라이언트 수 (clients)
#     -j 4 \          # pgbench 쓰레드 수 (threads)
#     -T 300 \        # 실행 시간(초)
#     -s 1            # 스케일 팩터 (init 시 사용한 scale)
#

set -euo pipefail

# Defaults
PGPORT=5432
CLIENTS=10
THREADS=2
DURATION=60
SCALE=1

print_usage() {
  cat <<EOF
Usage: PGHOST=... PGPASSWORD=... $0 -U user -d db [-p port] [-c clients] [-j threads] [-T seconds] [-s scale]
  -U   DB 사용자
  -d   DB 이름
  -p   포트 (기본: 5432)
  -c   동시 클라이언트 수 (기본: 10)
  -j   pgbench 쓰레드 수 (기본: 2)
  -T   실행 시간(초) (기본: 60)
  -s   pgbench init 시 사용한 scale 팩터 (기본: 1)
EOF
  exit 1
}

# 파라미터 파싱
while getopts "U:d:p:c:j:T:s:" opt; do
  case "$opt" in
    U) PGUSER=$OPTARG ;;
    d) PGDATABASE=$OPTARG ;;
    p) PGPORT=$OPTARG ;;
    c) CLIENTS=$OPTARG ;;
    j) THREADS=$OPTARG ;;
    T) DURATION=$OPTARG ;;
    s) SCALE=$OPTARG ;;
    *) print_usage ;;
  esac
done

: "${PGHOST:?환경변수 PGHOST(Replica endpoint)를 설정하세요}"
: "${PGUSER:?-U 옵션으로 DB 유저를 설정하세요}"
: "${PGDATABASE:?-d 옵션으로 DB 이름을 설정하세요}"
: "${PGPASSWORD:?환경변수 PGPASSWORD에 비밀번호를 설정하세요}"

# pgbench init 시 scale 별 테이블 row 수 계산
# 기본 pgbench: branches = 1*scale, tellers = 10*scale, accounts = 100000*scale
N_BRANCHES=$((SCALE * 1))
N_TELLERS=$((SCALE * 10))
N_ACCOUNTS=$((SCALE * 100000))

echo ">>> Read Replica 워크로드 시작"
echo "    Host: $PGHOST:$PGPORT/$PGDATABASE"
echo "    Clients: $CLIENTS, Threads: $THREADS, Duration: ${DURATION}s, Scale: $SCALE"
echo "    Branches: $N_BRANCHES, Tellers: $N_TELLERS, Accounts: $N_ACCOUNTS"

# 1) SELECT-only 커스텀 스크립트 생성
cat > select_load.sql <<EOF
\set aid random(1,$N_ACCOUNTS)
\set tid random(1,$N_TELLERS)
\set bid random(1,$N_BRANCHES)

-- 계좌 잔액 조회
SELECT abalance
  FROM pgbench_accounts
 WHERE aid = :aid;

-- 창구원 잔액 조회
SELECT tbalance
  FROM pgbench_tellers
 WHERE tid = :tid;

-- 지점 잔액 조회
SELECT bbalance
  FROM pgbench_branches
 WHERE bid = :bid;
EOF

# 2) pgbench 실행 (SELECT 전용)
pgbench \
  -h "$PGHOST" \
  -p "$PGPORT" \
  -U "$PGUSER" \
  -d "$PGDATABASE" \
  -c "$CLIENTS" \
  -j "$THREADS" \
  -T "$DURATION" \
  -f select_load.sql \
  --log

echo ">>> 워크로드 완료. 상세 결과는 pgbench log 파일을 확인하세요."