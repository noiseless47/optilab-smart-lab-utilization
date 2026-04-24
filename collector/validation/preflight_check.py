#!/usr/bin/env python3
"""
Preflight checks for collector validation suite.

Checks:
- Python/runtime dependencies
- Collector config and DB connectivity
- Key database tables/views
- Backend API reachability
- Local script/tool availability
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import platform
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional
from urllib.error import HTTPError
from urllib.request import Request, urlopen


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def check_command(name: str) -> bool:
    try:
        return subprocess.run(["bash", "-lc", f"command -v {name}"], capture_output=True).returncode == 0
    except FileNotFoundError:
        return shutil.which(name) is not None


def check_module(module_name: str) -> bool:
    return importlib.util.find_spec(module_name) is not None


def load_json(path: Path) -> Dict[str, Any]:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def check_api(url: str, timeout_seconds: int = 5) -> Dict[str, Any]:
    try:
        req = Request(url=url, method="GET")
        with urlopen(req, timeout=timeout_seconds) as resp:
            _ = resp.read()
            return {"ok": True, "status": int(resp.status)}
    except HTTPError as ex:
        return {"ok": False, "status": int(ex.code), "error": f"HTTP {ex.code}"}
    except Exception as ex:  # noqa: BLE001
        return {"ok": False, "status": None, "error": str(ex)}


def check_db(dsn: str) -> Dict[str, Any]:
    try:
        import psycopg2
        from psycopg2.extras import RealDictCursor
    except Exception as ex:  # noqa: BLE001
        return {"ok": False, "error": f"psycopg2 import failed: {ex}"}

    out: Dict[str, Any] = {
        "ok": False,
        "tables": {},
        "views": {},
    }

    try:
        conn = psycopg2.connect(dsn)
    except Exception as ex:  # noqa: BLE001
        out["error"] = f"DB connect failed: {ex}"
        return out

    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("SELECT version() AS version")
            out["version"] = cur.fetchone()["version"]

            checks = {
                "metrics": "public.metrics",
                "systems": "public.systems",
                "hourly_performance_stats": "public.hourly_performance_stats",
                "cfrs_hourly_stats": "public.cfrs_hourly_stats",
                "cfrs_system_baselines": "public.cfrs_system_baselines",
            }

            for key, fqname in checks.items():
                cur.execute("SELECT to_regclass(%s) IS NOT NULL AS exists", (fqname,))
                out["tables"][key] = bool(cur.fetchone()["exists"])

            cur.execute("SELECT COUNT(*)::int AS cnt FROM systems")
            out["systems_count"] = int(cur.fetchone()["cnt"])

            cur.execute("SELECT COUNT(*)::int AS cnt FROM metrics")
            out["metrics_count"] = int(cur.fetchone()["cnt"])

            out["ok"] = True
    except Exception as ex:  # noqa: BLE001
        out["error"] = f"DB query failed: {ex}"
    finally:
        conn.close()

    return out


def parse_args() -> argparse.Namespace:
    script_dir = Path(__file__).resolve().parent
    default_config = script_dir.parent / "config.json"

    parser = argparse.ArgumentParser(description="Preflight check for collector validation suite")
    parser.add_argument("--config", default=str(default_config), help="Path to collector config.json")
    parser.add_argument("--db-dsn", default=None, help="Override DB DSN")
    parser.add_argument("--api-base", default="http://localhost:3000/api", help="API base URL")
    parser.add_argument("--output", default=None, help="Optional JSON output path")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    config_path = Path(args.config).resolve()

    report: Dict[str, Any] = {
        "generated_at_utc": utc_now_iso(),
        "host": platform.node(),
        "platform": platform.platform(),
        "python_version": sys.version.split()[0],
        "checks": {},
    }

    report["checks"]["python_ok"] = sys.version_info >= (3, 9)
    report["checks"]["psycopg2_installed"] = check_module("psycopg2")

    collector_script = config_path.parent / "metrics_collector.sh"
    report["checks"]["collector_script_exists"] = collector_script.exists()

    report["checks"]["tools"] = {
        "bash": check_command("bash"),
        "stress_ng": check_command("stress-ng"),
        "nmap": check_command("nmap"),
    }

    if not config_path.exists():
        report["checks"]["config_exists"] = False
        report["status"] = "failed"
        report["error"] = f"Config not found: {config_path}"
    else:
        report["checks"]["config_exists"] = True
        cfg = load_json(config_path)
        dsn = args.db_dsn or cfg.get("db", {}).get("dsn")
        report["db_dsn_redacted"] = dsn.split("@")[-1] if isinstance(dsn, str) and "@" in dsn else "provided"

        if dsn:
            report["checks"]["db"] = check_db(dsn)
        else:
            report["checks"]["db"] = {"ok": False, "error": "db.dsn missing"}

        report["checks"]["api"] = check_api(args.api_base.rstrip("/") + "/systems/all")

        db_ok = bool(report["checks"]["db"].get("ok"))
        api_ok = bool(report["checks"]["api"].get("ok"))
        core_ok = (
            report["checks"]["python_ok"]
            and report["checks"]["psycopg2_installed"]
            and report["checks"]["collector_script_exists"]
            and db_ok
            and api_ok
        )
        report["status"] = "ok" if core_ok else "warning"

    if args.output:
        output_path = Path(args.output).resolve()
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(json.dumps(report, indent=2), encoding="utf-8")

    print(json.dumps(report, indent=2))
    return 0 if report.get("status") == "ok" else 2


if __name__ == "__main__":
    raise SystemExit(main())
