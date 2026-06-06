#!/usr/bin/env bash
set -euo pipefail

CRON_EXPR="${PIPELINE_CRON:-*/5 * * * *}"
RUN_ON_STARTUP="${RUN_ON_STARTUP:-true}"
ENV_FILE="/tmp/pipeline_env.sh"
CRON_FILE="/etc/cron.d/majutus-pipeline"

write_export() {
    local name="$1"
    local value="${!name-}"
    printf "export %s=%q\n" "$name" "$value" >> "$ENV_FILE"
}

rm -f "$ENV_FILE"
for name in DB_HOST DB_PORT DB_USER DB_PASSWORD DB_NAME API_URL; do
    write_export "$name"
done

cat > "$CRON_FILE" <<EOF
SHELL=/bin/bash
$CRON_EXPR root . $ENV_FILE; cd /app && /usr/local/bin/python scripts/run_pipeline.py run-all >> /proc/1/fd/1 2>> /proc/1/fd/2
EOF

chmod 0644 "$CRON_FILE"

echo "Scheduler kasutab croni ajastust: $CRON_EXPR"

if [ "$RUN_ON_STARTUP" = "true" ]; then
    echo "Käivitan töövoo scheduler'i stardil."
    . "$ENV_FILE"
    cd /app
    /usr/local/bin/python scripts/run_pipeline.py run-all
fi

exec cron -f
