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

class UserFacingError(RuntimeError):
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
    raise SystemExit(main())