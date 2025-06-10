# 1) Lambda 공식 Python 3.12 베이스 이미지 사용
FROM public.ecr.aws/lambda/python:3.12

# 2) 의존성 정의 파일 복사 및 설치
#    requirements.txt에 psycopg2-binary를 포함하세요.
COPY requirements.txt .
RUN pip install --upgrade pip \
 && pip install -r requirements.txt -t ${LAMBDA_TASK_ROOT}

# 3) 함수 소스 복사
COPY WarmingDBInstance.py ${LAMBDA_TASK_ROOT}/

# 4) 핸들러 지정
CMD ["WarmingDBInstance.lambda_handler"]
