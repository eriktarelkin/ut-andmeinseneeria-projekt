FROM python:3.13-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends cron postgresql-client \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY scripts/requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

CMD ["sleep", "infinity"]
