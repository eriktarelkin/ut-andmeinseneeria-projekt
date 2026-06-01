"""Majutusasutuste andmetöövoog.

Skript pärib TU110 andmed Statistikaametist, salvestab need `staging`
kihti, ehitab `mart` kihis otsustamiseks sobivad tabelid ning käivitab
kvaliteedikontrollid.
"""

from __future__ import annotations

import argparse
import os
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path

import psycopg2
from psycopg2.extras import execute_values
import requests


SCRIPT_DIR = Path(__file__).resolve().parent
SEED_SQL      = SCRIPT_DIR / "00_seed.sql"
TRANSFORM_SQL = SCRIPT_DIR / "01_transform.sql"

TU110_BASE_URL = "https://andmed.stat.ee/api/v1/et/stat/TU110"

CODE_TO_COLUMN = {
    "CAP_ESTA":    "majutuskohti_arv",
    "CAP_BEDR":    "tubade_arv",
    "CAP_BEDP":    "voodikohtade_arv",
    "OCC_OR_BEDR": "tubade_taitumus_pct",
    "OCC_OR_BEDP": "voodikohtade_taitumus_pct",
    "OCC_ARR":     "majutatute_arv",
    "OCC_NI":      "oobimiste_arv",
    "OCC_NI_COST": "oopaeva_keskmine_maksumus",
}


class UserFacingError(RuntimeError):
    """Viga, mille sõnum sobib otse kasutajale näitamiseks."""


def log(message: str) -> None:
    print(message, flush=True)


def get_env(name: str, default: str) -> str:
    return os.environ.get(name, default)


def get_connection():
    return psycopg2.connect(
        host=get_env("DB_HOST", "db"),
        port=get_env("DB_PORT", "5432"),
        user=get_env("DB_USER", "praktikum"),
        password=get_env("DB_PASSWORD", "praktikum"),
        dbname=get_env("DB_NAME", "praktikum"),
    )


def execute_sql_file(conn, path: Path) -> None:
    log(f"Käivitan SQL-faili {path.name}.")
    sql = path.read_text(encoding="utf-8")
    with conn.cursor() as cur:
        cur.execute(sql)
    conn.commit()


def fetch_value(conn, query: str):
    with conn.cursor() as cur:
        cur.execute(query)
        return cur.fetchone()[0]


def insert_pipeline_run(conn, *, run_id: uuid.UUID, fetched_at: datetime, status: str, message: str | None) -> None:
    with conn.cursor() as cur:
        cur.execute(
            """
            INSERT INTO staging.pipeline_runs (run_id, fetched_at, source_name, status, message)
            VALUES (%s, %s, %s, %s, %s)
            """,
            (str(run_id), fetched_at, "stat.ee/TU110", status, message),
        )
    conn.commit()


def update_pipeline_run(conn, *, run_id: uuid.UUID, status: str, message: str | None) -> None:
    with conn.cursor() as cur:
        cur.execute(
            "UPDATE staging.pipeline_runs SET status = %s, message = %s WHERE run_id = %s",
            (status, message, str(run_id)),
        )
    conn.commit()


def fetch_tu110_json(api_url: str) -> dict:
    payload = {
        "query": [
            {
                "code": "Näitaja",
                "selection": {
                    "filter": "item",
                    "values": list(CODE_TO_COLUMN.keys()),
                },
            }
        ],
        "response": {"format": "json-stat2"},
    }
    try:
        resp = requests.post(api_url, json=payload, timeout=30)
        resp.raise_for_status()
        return resp.json()
    except requests.RequestException as exc:
        raise UserFacingError(f"TU110 päring ebaõnnestus: {exc}") from exc


def build_raw_rows(payload: dict) -> list[dict]:
    if not isinstance(payload, dict):
        return []
    dim    = payload.get("dimension", {})
    values = payload.get("value", [])
    if not dim or not values:
        return []

    indicators     = list(dim["Näitaja"]["category"]["index"].keys())
    regions        = list(dim["Maakond"]["category"]["index"].keys())
    years          = list(dim["Vaatlusperiood"]["category"]["index"].keys())
    region_labels  = dim["Maakond"]["category"].get("label", {})

    rows, i = [], 0
    for indicator in indicators:
        for region in regions:
            for year in years:
                if i >= len(values):
                    break
                rows.append({
                    "indicator": indicator,
                    "region":    region_labels.get(region, region),
                    "year":      int(year),
                    "value":     values[i],
                })
                i += 1
    return rows


def to_wide_rows(rows: list[dict]) -> list[dict]:
    # Exclude country-level aggregate — we only want county/city level data
    EXCLUDE_REGIONS = {"Eesti"}

    wide: dict[tuple, dict] = {}
    for r in rows:
        if r["region"] in EXCLUDE_REGIONS:
            continue
        col = CODE_TO_COLUMN.get(r["indicator"])
        if not col:
            continue
        key = (r["region"], r["year"])
        if key not in wide:
            wide[key] = {"maakond": r["region"], "aasta": r["year"]}
        wide[key][col] = r["value"]
    return list(wide.values())


def load_raw_rows(conn, run_id: uuid.UUID, rows: list[dict]) -> int:
    if not rows:
        return 0
    values = [
        (
            str(run_id),
            r.get("maakond"), r.get("aasta"),
            r.get("majutuskohti_arv"), r.get("tubade_arv"), r.get("voodikohtade_arv"),
            r.get("tubade_taitumus_pct"), r.get("voodikohtade_taitumus_pct"),
            r.get("oopaeva_keskmine_maksumus"), r.get("majutatute_arv"), r.get("oobimiste_arv"),
        )
        for r in rows
    ]
    sql = """
        INSERT INTO staging.raw_tu110 (
            run_id, maakond, aasta,
            majutuskohti_arv, tubade_arv, voodikohtade_arv,
            tubade_taitumus_pct, voodikohtade_taitumus_pct,
            oopaeva_keskmine_maksumus, majutatute_arv, oobimiste_arv
        ) VALUES %s
        ON CONFLICT (maakond, aasta) DO UPDATE SET
            run_id                    = EXCLUDED.run_id,
            majutuskohti_arv          = EXCLUDED.majutuskohti_arv,
            tubade_arv                = EXCLUDED.tubade_arv,
            voodikohtade_arv          = EXCLUDED.voodikohtade_arv,
            tubade_taitumus_pct       = EXCLUDED.tubade_taitumus_pct,
            voodikohtade_taitumus_pct = EXCLUDED.voodikohtade_taitumus_pct,
            oopaeva_keskmine_maksumus = EXCLUDED.oopaeva_keskmine_maksumus,
            majutatute_arv            = EXCLUDED.majutatute_arv,
            oobimiste_arv             = EXCLUDED.oobimiste_arv,
            loaded_at                 = now(),
            source                    = 'stat.ee/TU110'
    """
    with conn.cursor() as cur:
        execute_values(cur, sql, values)
    conn.commit()
    return len(values)


def ingest() -> uuid.UUID:
    api_url    = get_env("API_URL", TU110_BASE_URL)
    run_id     = uuid.uuid4()
    fetched_at = datetime.now(timezone.utc)

    conn = get_connection()
    try:
        insert_pipeline_run(conn, run_id=run_id, fetched_at=fetched_at,
                            status="running", message="Laadimine algas.")
        log(f"Pärin TU110 andmeid: {api_url}.")
        payload = fetch_tu110_json(api_url)
        rows    = build_raw_rows(payload)

        if not rows:
            raise UserFacingError(
                "TU110 vastusest ei saadud ühtegi rida. "
                "API võib tagastada metaandmeid ilma vaatlusväärtusteta."
            )

        total = load_raw_rows(conn, run_id, to_wide_rows(rows))
        update_pipeline_run(conn, run_id=run_id, status="success",
                            message=f"Laadisin {total} rida tabelisse staging.raw_tu110.")
        log(f"Andmete vastuvõtt valmis. Käivituse ID: {run_id}.")
        return run_id
    except Exception as exc:
        conn.rollback()
        try:
            update_pipeline_run(conn, run_id=run_id, status="error", message=str(exc))
        except Exception:
            pass
        raise
    finally:
        conn.close()


def transform() -> None:
    conn = get_connection()
    try:
        execute_sql_file(conn, SEED_SQL)
        execute_sql_file(conn, TRANSFORM_SQL)
        fact_rows  = fetch_value(conn, "SELECT COUNT(*) FROM mart.fact_oobimised")
        skoor_rows = fetch_value(conn, "SELECT COUNT(*) FROM mart.fact_skoor")
        log(f"Transformatsioon valmis. fact_oobimised: {fact_rows} rida, fact_skoor: {skoor_rows} rida.")
    finally:
        conn.close()


def print_query(conn, title: str, query: str) -> None:
    print()
    print(title)
    print("-" * len(title))
    with conn.cursor() as cur:
        cur.execute(query)
        rows    = cur.fetchall()
        columns = [desc[0] for desc in cur.description]
    if not rows:
        print("Ridu ei ole.")
        return
    print(" | ".join(columns))
    for row in rows:
        print(" | ".join("" if v is None else str(v) for v in row))


def check_results() -> None:
    conn = get_connection()
    try:
        print_query(conn, "Viimased laadimised",
            "SELECT run_id, fetched_at, source_name, status, message FROM staging.pipeline_runs ORDER BY fetched_at DESC LIMIT 5")
        print_query(conn, "Maakonnad dimensioonis",
            "SELECT maakond_nimi FROM mart.dim_maakond ORDER BY maakond_nimi")
        print_query(conn, "Top 5 piirkonda",
            "SELECT maakond_nimi, skoor_pct, soovitus, kategooria_nimi FROM mart.v_piirkondade_edetabel LIMIT 5")
    finally:
        conn.close()


def reset_data() -> None:
    conn = get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                TRUNCATE TABLE
                    mart.fact_skoor,
                    mart.fact_oobimised,
                    mart.dim_maakond,
                    staging.raw_tu110,
                    staging.pipeline_runs
                CASCADE
                """
            )
        conn.commit()
        execute_sql_file(conn, SEED_SQL)
        log("Andmetabelid on tühjendatud ja dimensioonid taastatud.")
    finally:
        conn.close()


def run_all() -> None:
    ingest()
    transform()
    log("Kogu töövoog õnnestus.")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Majutusasutuste andmetöövoog.")
    parser.add_argument(
        "command",
        choices=["ingest", "transform", "check", "reset", "run-all"],
        help="Töövoo samm, mida käivitada.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        if args.command == "ingest":
            ingest()
        elif args.command == "transform":
            transform()
        elif args.command == "check":
            check_results()
        elif args.command == "reset":
            reset_data()
        elif args.command == "run-all":
            run_all()
        return 0
    except UserFacingError as exc:
        print(f"Viga: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
