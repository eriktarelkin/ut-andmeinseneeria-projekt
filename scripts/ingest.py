import requests
import pandas as pd
from config import API_URL

def ingest_api_data():
    data = requests.get(API_URL).json()
    df = pd.DataFrame(data)
    return df

if __name__ == "__main__":
    df = ingest_api_data()
    print(df.head())

import os
import requests
import json
import psycopg2
import argparse
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path
from __future__ import annotations

SCRIPT_DIR = Path(__file__).resolve().parent
DIMENSIONS_SQL = SCRIPT_DIR / "00_seed_dimensions.sql"
TRANSFORM_SQL = SCRIPT_DIR / "01_transform.sql"
QUALITY_SQL = SCRIPT_DIR / "02_quality_tests.sql"

#täpselt veel ei tea mida see kõik teeb

'''class UserFacingError(RuntimeError):
    """Viga, mille sõnum sobib otse õppijale näitamiseks."""

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

def main() -> int:
    args = parse_args()
    try:
        if args.command == "ingest":
            ingest()
        elif args.command == "transform":
            transform()
        elif args.command == "test":
            run_quality_tests()
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
    raise SystemExit(main())'''