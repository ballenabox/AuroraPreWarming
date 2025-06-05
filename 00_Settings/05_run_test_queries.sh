#!/bin/bash
#
# run_test_queries.sh
# pgbench 스키마 대상 테스트 쿼리를 여러 번 실행하도록 수정된 스크립트
# - DB 접속 정보는 실행 시 첫 번째 파라미터로 전달된 설정 파일(db_config.ini)을 참조
# - 실행할 SQL 파일은 실행 시 두 번째 파라미터로 전달
# - 비밀번호는 실행 시 입력받음
#
# 사용법:
#   ./run_test_queries.sh /path/to/db_config.ini /path/to/test_queries.sql
#

# ──────────────────────────────────────────────────────────────
# 1) 파라미터 확인
if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: $0 <path_to_db_config.ini> <path_to_sql_file>"
  exit 1
fi

CONFIG_FILE="$1"
SQL_FILE="$2"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Config file '$CONFIG_FILE' not found."
  exit 1
fi

if [ ! -f "$SQL_FILE" ]; then
  echo "Error: SQL file '$SQL_FILE' not found."
  exit 1
fi

# 2) 설정 파일로부터 접속 정보 파싱
#    [connection] 섹션에 아래 키들이 있다고 가정
#      endpoint = <호스트명>
#      port     = <포트번호>
#      database = <DB 이름>
#      user     = <유저명>
ENDPOINT=$(grep -E '^endpoint' "$CONFIG_FILE" | awk -F'=' '{gsub(/ /, "", $2); print $2}')
PORT=$(grep -E '^port' "$CONFIG_FILE"     | awk -F'=' '{gsub(/ /, "", $2); print $2}')
DATABASE=$(grep -E '^database' "$CONFIG_FILE" | awk -F'=' '{gsub(/ /, "", $2); print $2}')
DB_USER=$(grep -E '^user' "$CONFIG_FILE"    | awk -F'=' '{gsub(/ /, "", $2); print $2}')

# 3) 비밀번호 입력받기 (프롬프트에서 숨김)
read -s -p "Enter password for user $DB_USER: " PGPASSWORD
echo

# 4) 반복 실행 설정
ITERATIONS=50  # 필요에 따라 반복 횟수를 조정

# ──────────────────────────────────────────────────────────────

echo "===== 테스트 쿼리 반복 실행 시작: $(date) ====="
for i in $(seq 1 $ITERATIONS); do
  echo "[$i/$ITERATIONS] 쿼리 실행 중..."
  PGPASSWORD="$PGPASSWORD" psql \
    --host="$ENDPOINT" \
    --port="$PORT" \
    --dbname="$DATABASE" \
    --username="$DB_USER" \
    --file="$SQL_FILE" \
    --no-psqlrc \
    --quiet \
    --echo-errors \
    --single-transaction
done
echo "===== 테스트 쿼리 반복 실행 완료: $(date) ====="
