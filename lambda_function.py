import os
import json
import boto3
import time
import logging
from botocore.exceptions import ClientError
import psycopg2

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def get_secret_credentials():
    """
    Secret Manager에서 데이터베이스 인증 정보를 가져오는 함수
    
    Returns:
        dict: 사용자 이름과 비밀번호를 포함한 사전
        
    Raises:
        ValueError: 필수 환경 변수가 설정되지 않은 경우
    """
    start_time = time.time()
    logger.info("Secret Manager에서 보안 정보를 가져오는 중...")

    # 환경 변수에서 Secret Manager의 보안 암호 이름 가져오기
    secret_name = os.environ.get('DB_SECRET')
    if not secret_name:
        error_msg = "환경 변수 'DB_SECRET'이 설정되지 않았습니다."
        logger.error(error_msg)
        raise ValueError(error_msg)
        
    # 환경 변수에서 Region 이름 가져오기
    region_name = os.environ.get('REGION_NAME')
    if not region_name:
        error_msg = "환경 변수 'REGION_NAME'이 설정되지 않았습니다."
        logger.error(error_msg)
        raise ValueError(error_msg)
    
    # Secret Manager에서 보안 정보 가져오기
    client = boto3.client(
        service_name='secretsmanager',
        region_name=region_name
    )

    try:
        secret_response = client.get_secret_value(
            SecretId=secret_name
            )
        secret = json.loads(secret_response['SecretString'])
        
        # 결과값 로깅 (비밀번호는 마스킹 처리)
        log_secret = secret.copy()
        if 'password' in log_secret:
            log_secret['password'] = '********'  # 비밀번호 마스킹
        logger.info(f"Secret Manager에서 가져온 결과값: {json.dumps(log_secret)}")

        end_time = time.time()
        logger.info(f"Secret Manager 클라이언트 생성 시간: {end_time - start_time:.2f} 초")
        
        # 데이터베이스 인증 정보 추출 (사용자 이름과 비밀번호만)
        return {
            'username': secret.get('username'),
            'password': secret.get('password')
        }
    except ClientError as e:
        error_message = f"Secret Manager에서 보안 정보를 가져오는 중 오류 발생: {e}"
        raise RuntimeError(error_message) from e

def get_db_connection(host):
    """
    Aurora PostgreSQL 연결을 생성하고 반환하는 함수
    
    Args:
        host (str): 데이터베이스 엔드포인트
    
    Returns:
        psycopg2.connection: PostgreSQL 데이터베이스 연결 객체
        
    Raises:
        ValueError: 필수 환경 변수가 설정되지 않은 경우
    """
    start_time = time.time()
    logger.info(f"데이터베이스 연결을 생성하는 중... 호스트: {host}")

    # 환경 변수에서 포트와 DB 이름 가져오기
    port = int(os.environ.get('DB_PORT', 5432))
    dbname = os.environ.get('DB_NAME')
    
    if not dbname:
        error_msg = "환경 변수 'DB_NAME'이 설정되지 않았습니다."
        logger.error(error_msg)
        raise ValueError(error_msg)
    
    # Secret Manager에서 인증 정보 가져오기
    credentials = get_secret_credentials()
    
    # PostgreSQL 연결 생성 및 반환
    conn = psycopg2.connect(
        host=host,
        port=port,
        dbname=dbname,
        user=credentials['username'],
        password=credentials['password']
    )
    
    end_time = time.time()
    logger.info(f"데이터베이스 연결을 생성하는 데 걸린 시간: {end_time - start_time:.2f} 초")

    return conn

def get_latest_query_file():
    """
    S3 버킷에서 가장 최신 top100 쿼리 파일을 가져오는 함수
    
    Returns:
        str: 파일 내용
        
    Raises:
        ValueError: 필수 환경 변수가 설정되지 않은 경우
    """
    start_time = time.time()
    logger.info("S3에서 최신 쿼리 파일을 가져오는 중...")
    
    # 환경 변수에서 S3 버킷 정보 가져오기
    bucket_name = os.environ.get('S3_BUCKET')
    key_prefix = os.environ.get('S3_KEY_PREFIX')
    
    if not bucket_name:
        error_msg = "환경 변수 'S3_BUCKET'이 설정되지 않았습니다."
        logger.error(error_msg)
        raise ValueError(error_msg)
    
    if not key_prefix:
        error_msg = "환경 변수 'S3_KEY_PREFIX'이 설정되지 않았습니다."
        logger.error(error_msg)
        raise ValueError(error_msg)
    
    # S3 클라이언트 생성
    s3_client = boto3.client('s3')
    
    # 해당 경로의 모든 객체 리스트 가져오기
    response = s3_client.list_objects_v2(
        Bucket=bucket_name,
        Prefix=key_prefix
    )
    
    # 객체가 없는 경우
    if 'Contents' not in response:
        error_msg = f"S3 버킷 {bucket_name}의 {key_prefix} 경로에 파일이 없습니다."
        logger.error(error_msg)
        raise FileNotFoundError(error_msg)
    
    # 최신 파일 찾기 (마지막 수정 시간 기준)
    latest_file = max(response['Contents'], key=lambda x: x['LastModified'])
    latest_file_key = latest_file['Key']
    
    logger.info(f"최신 쿼리 파일: {latest_file_key}")
    
    # 파일 내용 가져오기
    response = s3_client.get_object(
        Bucket=bucket_name,
        Key=latest_file_key
    )
    file_content = response['Body'].read().decode('utf-8')
    
    end_time = time.time()
    logger.info(f"S3에서 파일을 가져오는 데 걸린 시간: {end_time - start_time:.2f} 초")
    
    return file_content

def parse_queries_from_csv(csv_content):
    """
    CSV 파일에서 쿼리를 추출하는 함수
    
    Args:
        csv_content (str): CSV 파일 내용
        
    Returns:
        list: 추출된 쿼리 목록
    """
    start_time = time.time()
    logger.info("CSV 파일에서 쿼리 추출 중...")
    
    queries = []
    lines = csv_content.strip().split('\n')
    
    # 헤더 건너뛰기
    if lines and len(lines) > 1:
        header = lines[0]
        
        # 쿼리가 있는 열 인덱스 찾기 (일반적으로 'query' 또는 'sql' 열)
        headers = header.split(',')
        query_index = -1
        
        for i, h in enumerate(headers):
            if 'query' in h.lower() or 'sql' in h.lower():
                query_index = i
                break
        
        if query_index == -1:
            logger.warning("CSV 파일에서 쿼리 열을 찾을 수 없습니다. 첫 번째 열을 사용합니다.")
            query_index = 0
        
        # 각 행에서 쿼리 추출
        for i in range(1, len(lines)):
            try:
                row = lines[i].split(',')
                if len(row) > query_index:
                    query = row[query_index].strip()
                    if query:
                        queries.append(query)
            except Exception as e:
                logger.warning(f"행 {i} 처리 중 오류 발생: {str(e)}")
    
    end_time = time.time()
    logger.info(f"쿼리 추출 완료: {len(queries)}개 쿼리, 소요 시간: {end_time - start_time:.2f} 초")
    
    return queries

def execute_warming_queries(conn, queries):
    """
    DB warming을 위해 쿼리를 실행하는 함수
    
    Args:
        conn (psycopg2.connection): 데이터베이스 연결
        queries (list): 실행할 쿼리 목록
        
    Returns:
        int: 성공적으로 실행된 쿼리 수
    """
    start_time = time.time()
    logger.info(f"DB warming 시작: {len(queries)}개 쿼리 실행")
    
    success_count = 0
    cursor = conn.cursor()
    
    for i, query in enumerate(queries):
        query_start_time = time.time()
        try:
            cursor.execute(query)
            query_end_time = time.time()
            success_count += 1
            logger.info(f"쿼리 {i+1}/{len(queries)} 실행 성공: {query_end_time - query_start_time:.2f} 초")
        except Exception as e:
            logger.warning(f"쿼리 {i+1}/{len(queries)} 실행 실패: {str(e)}")
    
    cursor.close()
    
    end_time = time.time()
    logger.info(f"DB warming 완료: {success_count}/{len(queries)} 쿼리 성공, 총 소요 시간: {end_time - start_time:.2f} 초")
    
    return success_count

def lambda_handler(event, context):
    """
    Lambda 함수의 진입점
    
    Args:
        event (dict): Lambda 함수 입력값
        context (object): Lambda 컨텍스트 객체
    
    Returns:
        dict: Lambda 함수 응답
    """
    start_time = time.time()
    logger.info(f"Lambda 함수 시작: {json.dumps(event)}")
    
    try:
        # 입력값에서 DB 엔드포인트 가져오기
        payload = event.get('Payload', {})
        db_endpoint = payload.get('Address')
        
        if not db_endpoint:
            error_msg = 'DB 엔드포인트가 제공되지 않았습니다.'
            logger.error(error_msg)
            return {
                'statusCode': 400,
                'body': json.dumps(error_msg)
            }
        
        # 데이터베이스 연결 가져오기
        conn = get_db_connection(db_endpoint)
        
        # S3에서 최신 쿼리 파일 가져오기
        csv_content = get_latest_query_file()
        
        # CSV 파일에서 쿼리 추출
        queries = parse_queries_from_csv(csv_content)
        
        # DB warming 쿼리 실행
        success_count = execute_warming_queries(conn, queries)
        
        # 작업 완료 후 연결 종료
        conn.close()
        
        end_time = time.time()
        total_time = end_time - start_time
        logger.info(f"Lambda 함수 성공적으로 완료: 총 실행 시간 {total_time:.2f} 초")
        
        return {
            'statusCode': 200,
            'body': json.dumps(f'DB warming 완료: {success_count}/{len(queries)} 쿼리 성공'),
            'executionTime': f"{total_time:.2f} 초"
        }
    
    except Exception as e:
        logger.error(f"Lambda 함수 실행 중 오류 발생: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'오류 발생: {str(e)}')
        }