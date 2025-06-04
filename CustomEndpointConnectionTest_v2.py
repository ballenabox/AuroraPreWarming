import argparse
import time
import psycopg2
from psycopg2 import OperationalError
from datetime import datetime
import getpass
import configparser
import os
import boto3
import csv
import io

def parse_arguments():
    parser = argparse.ArgumentParser(
        description="Query an Aurora Custom Endpoint using top queries from S3 CSV file."
    )
    parser.add_argument(
        "--config",
        required=True,
        help="Connection 및 테스트 설정이 담긴 INI 파일 경로"
    )
    return parser.parse_args()

def load_config(path):
    """
    INI 파일(path)을 읽어서 필요한 파라미터를 반환
    """
    if not os.path.isfile(path):
        raise FileNotFoundError(f"Config 파일을 찾을 수 없습니다: {path}")

    cfg = configparser.ConfigParser()
    cfg.read(path)

    # [connection] 섹션 확인
    if "connection" not in cfg:
        raise KeyError("INI 파일에 [connection] 섹션이 없습니다.")
    conn_cfg = cfg["connection"]

    # [test] 섹션 확인 (duration, interval)
    if "test" not in cfg:
        raise KeyError("INI 파일에 [test] 섹션이 없습니다.")
    test_cfg = cfg["test"]
    
    # [s3] 섹션 확인
    if "s3" not in cfg:
        raise KeyError("INI 파일에 [s3] 섹션이 없습니다.")
    s3_cfg = cfg["s3"]

    # 필수 파라미터를 읽어온다 (없으면 예외)
    endpoint = conn_cfg.get("endpoint", fallback=None)
    port     = conn_cfg.getint("port", fallback=None)
    database = conn_cfg.get("database", fallback=None)
    user     = conn_cfg.get("user", fallback=None)

    duration = test_cfg.getint("duration", fallback=None)
    interval = test_cfg.getfloat("interval", fallback=None)
    
    bucket = s3_cfg.get("bucket", fallback=None)
    prefix = s3_cfg.get("prefix", fallback=None)

    missing = []
    if endpoint is None: missing.append("endpoint")
    if port     is None: missing.append("port")
    if database is None: missing.append("database")
    if user     is None: missing.append("user")
    if duration is None: missing.append("duration")
    if interval is None: missing.append("interval")
    if bucket   is None: missing.append("bucket")
    if prefix   is None: missing.append("prefix")
    if missing:
        raise ValueError(f"INI 파일에서 다음 항목이 누락되었습니다: {', '.join(missing)}")

    return {
        "endpoint": endpoint,
        "port": port,
        "database": database,
        "user": user,
        "duration": duration,
        "interval": interval,
        "bucket": bucket,
        "prefix": prefix
    }

def get_top_query_from_s3(bucket, prefix):
    """
    S3에서 CSV 파일을 읽어 total_time이 가장 긴 쿼리를 반환
    """
    s3 = boto3.client('s3')
    
    # S3에서 객체 목록 가져오기
    response = s3.list_objects_v2(Bucket=bucket, Prefix=prefix)
    
    if 'Contents' not in response:
        raise ValueError(f"S3 버킷 {bucket}의 {prefix} 경로에 파일이 없습니다.")
    
    # 가장 최근 파일 선택 (일반적으로 가장 마지막 파일)
    latest_file = sorted(response['Contents'], key=lambda x: x['LastModified'], reverse=True)[0]
    file_key = latest_file['Key']
    
    print(f"S3에서 파일을 읽는 중: {file_key}")
    
    # 파일 내용 가져오기
    obj = s3.get_object(Bucket=bucket, Key=file_key)
    csv_content = obj['Body'].read().decode('utf-8')
    
    # CSV 파싱
    csv_reader = csv.DictReader(io.StringIO(csv_content))
    
    # total_time이 가장 긴 쿼리 찾기
    top_query = None
    max_time = 0
    
    for row in csv_reader:
        try:
            total_time = float(row.get('total_time', 0))
            query = row.get('query', '')
            
            # SELECT 쿼리만 고려하고, 실행 가능한 쿼리인지 확인
            if query.strip().upper().startswith('SELECT') and total_time > max_time:
                max_time = total_time
                top_query = query
        except (ValueError, TypeError):
            continue
    
    if not top_query:
        raise ValueError("유효한 쿼리를 찾을 수 없습니다.")
    
    print(f"선택된 쿼리 (실행 시간: {max_time}초):\n{top_query[:100]}...")
    return top_query

def main():
    # 1) CLI에서 인자 파싱
    args = parse_arguments()

    # 2) INI 파일을 로드하여 파라미터 딕셔너리로 가져온다
    cfg = load_config(args.config)

    # 3) S3에서 가장 시간이 오래 걸린 쿼리 가져오기 (스크립트 시작 시 1번만 실행)
    test_query = get_top_query_from_s3(cfg["bucket"], cfg["prefix"])

    # 4) 비밀번호는 실행 후 프롬프트로 안전하게 입력받는다
    password = getpass.getpass(prompt="Database password: ")

    # 5) 테스트 종료 시각을 계산
    end_time = time.time() + cfg["duration"]

    while time.time() < end_time:
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        try:
            # 6) 커넥션 연결 전/후 시간 측정
            conn_start = time.time()
            conn = psycopg2.connect(
                host=cfg["endpoint"],
                port=cfg["port"],
                dbname=cfg["database"],
                user=cfg["user"],
                password=password,
                connect_timeout=5
            )
            conn_end = time.time()

            cur = conn.cursor()

            # 7) S3에서 가져온 테스트 쿼리 실행 전/후 시간 측정
            query_start = time.time()
            cur.execute(test_query)
            query_results = cur.fetchall()
            query_end = time.time()

            # 8) 연결 시간 및 쿼리 실행 시간 계산
            conn_time = conn_end - conn_start
            query_time = query_end - query_start

            # 9) 로그 출력
            server_ip = conn.get_dsn_parameters().get('host')
            result_count = len(query_results)
            
            print(
                f"[{timestamp}] "
                f"IP: {server_ip} | "
                f"Connect: {conn_time:.3f}s | "
                f"Query: {query_time:.3f}s | "
                f"Result rows: {result_count}"
            )

            cur.close()
            conn.close()
        except OperationalError as e:
            print(f"[{timestamp}] Connection/query failed: {e}")
        except Exception as e:
            print(f"[{timestamp}] Unexpected error: {e}")

        # 10) 다음 반복 전 잠시 대기
        time.sleep(cfg["interval"])

if __name__ == "__main__":
    main()