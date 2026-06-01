#!/bin/bash
set -e

echo "[pipeline] Käivitan ingest..."
python /app/scripts/run_pipeline.py ingest

echo "[pipeline] Käivitan transformatsiooni..."
python /app/scripts/run_pipeline.py transform

echo "[pipeline] Valmis. Konteiner jääb ootele (docker compose exec pipeline ... uuesti käivitamiseks)."
sleep infinity
