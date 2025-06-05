import argparse
import time
import psycopg2
from psycopg2 import OperationalError
from datetime import datetime
import getpass
import configparser
import os

def parse_arguments():
    parser = argparse.ArgumentParser(
        description="Query an Aurora Custom Endpoint using pgbench schema, with settings read from a config file."
    )
    parser.add_argument(
        "--config",
        required=True,
        help="Connection 및 테스트 설정이 담긴 INI 파일 경로"
    )
    return parser.parse_args()

def load_config(path):
    """
    INI 파일(path)을 읽어서 필요한 파라미터(endpoint, port, database, user, duration, interval)를 반환
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

    # 필수 파라미터를 읽어온다 (없으면 예외)
    endpoint = conn_cfg.get("endpoint", fallback=None)
    port     = conn_cfg.getint("port", fallback=None)
    database = conn_cfg.get("database", fallback=None)
    user     = conn_cfg.get("user", fallback=None)

    duration = test_cfg.getint("duration", fallback=None)
    interval = test_cfg.getfloat("interval", fallback=None)

    missing = []
    if endpoint is None: missing.append("endpoint")
    if port     is None: missing.append("port")
    if database is None: missing.append("database")
    if user     is None: missing.append("user")
    if duration is None: missing.append("duration")
    if interval is None: missing.append("interval")
    if missing:
        raise ValueError(f"INI 파일에서 다음 항목이 누락되었습니다: {', '.join(missing)}")

    return {
        "endpoint": endpoint,
        "port": port,
        "database": database,
        "user": user,
        "duration": duration,
        "interval": interval
    }

def main():
    # 1) CLI에서 --config 인자로 INI 파일 경로를 받는다
    args = parse_arguments()

    # 2) INI 파일을 로드하여 파라미터 딕셔너리로 가져온다
    cfg = load_config(args.config)

    # 3) 비밀번호는 실행 후 프롬프트로 안전하게 입력받는다
    password = getpass.getpass(prompt="Database password: ")

    # 4) 테스트 종료 시각을 계산
    end_time = time.time() + cfg["duration"]

    while time.time() < end_time:
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        try:
            # 5) 커넥션 연결 전/후 시간 측정
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

            # 6) pgbench 스키마 기반 테스트 쿼리 수행 전/후 시간 측정
            query_start = time.time()
            cur.execute("""
                SELECT 
                  inet_server_addr() AS server_ip, 
                  (SELECT COUNT(*) FROM pgbench_accounts) AS account_count;
            """)
            server_ip, account_count = cur.fetchone()
            query_end = time.time()

            # 7) 연결 시간 및 쿼리 실행 시간 계산
            conn_time  = conn_end - conn_start
            query_time = query_end - query_start

            # 8) 로그 출력
            print(
                f"[{timestamp}] "
                f"IP: {server_ip} | "
                f"Connect: {conn_time:.3f}s | "
                f"Query: {query_time:.3f}s | "
                f"Accounts: {account_count}"
            )

            cur.close()
            conn.close()
        except OperationalError as e:
            print(f"[{timestamp}] Connection/query failed: {e}")
        except Exception as e:
            print(f"[{timestamp}] Unexpected error: {e}")

        # 9) 다음 반복 전 잠시 대기
        time.sleep(cfg["interval"])

if __name__ == "__main__":
    main()
