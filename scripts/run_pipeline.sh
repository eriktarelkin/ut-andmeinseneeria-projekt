#!/bin/bash
set -e

echo "[pipeline] Käivitan run-all (ingest + transform + quality-check)..."
python /app/scripts/run_pipeline.py run-all

echo "[pipeline] Valmis. Konteiner jääb ootele (docker compose exec pipeline ... uuesti käivitamiseks)."
sleep infinity
