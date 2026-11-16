FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --only-binary=:all: --require-hashes -r requirements.txt \
    && mkdir -m 0700 /app/data \
    && chown 10001:10001 /app/data
COPY sync_server.py .
USER 10001:10001
CMD ["gunicorn", "--bind=0.0.0.0:8080", "--worker-class=gthread", "--threads=4", "--timeout=90", "sync_server:create_app()"]
