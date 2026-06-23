FROM python:3.11-slim

RUN apt-get update && apt-get install -y curl

WORKDIR /app

COPY requirements.txt /app/

RUN pip install --no-cache-dir -r requirements.txt

COPY app.py /app/

RUN groupadd -r appgroup && \
    useradd -r -g appgroup -s /bin/bash appuser && \
    chown -R appuser:appgroup /app

EXPOSE 5000

USER appuser

CMD ["python", "app.py"]