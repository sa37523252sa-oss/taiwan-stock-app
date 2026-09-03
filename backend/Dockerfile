FROM python:3.13-slim
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends gcc \
    && rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
RUN mkdir -p /seed && mv stocks.db /seed/stocks.db
EXPOSE 8080
ENTRYPOINT ["/entrypoint.sh"]
ENTRYPOINT ["/app/entrypoint.sh"]
