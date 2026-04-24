#!/usr/bin/env python3
"""
Collector-side benchmark suite for validating OptiLab paper metrics.

What this script measures:
- Discovery accuracy (against expected host inventory or configured ranges)
- Collection freshness and ingest throughput
- Local metric variance (collector vs native CPU/RAM readings)
- API latency (mean, p50, p95, max)
- Query speedups (raw metrics vs continuous aggregates)
- TimescaleDB compression indicators
- CFRS readiness and current risk distribution

Outputs:
- JSON report with full raw results
- Markdown report for paper-ready summaries
- CSV tables for API/query benchmarks
"""

from __future__ import annotations

import argparse
import csv
import ipaddress
import json
import math
import os
import platform
import statistics
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

import psycopg2
from psycopg2.extras import RealDictCursor


@dataclass
class HttpSample:
    elapsed_ms: float
    status: Optional[int]
    ok: bool
    error: Optional[str] = None


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def percentile(values: Sequence[float], p: float) -> Optional[float]:
    if not values:
        return None
    sorted_values = sorted(values)
    if len(sorted_values) == 1:
        return float(sorted_values[0])

    k = (len(sorted_values) - 1) * (p / 100.0)
    floor_idx = math.floor(k)
    ceil_idx = math.ceil(k)

    if floor_idx == ceil_idx:
        return float(sorted_values[int(k)])

    lower = sorted_values[floor_idx]
    upper = sorted_values[ceil_idx]
    return float(lower + (upper - lower) * (k - floor_idx))


def safe_float(value: Any) -> Optional[float]:
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def fmt_num(value: Any, digits: int = 3) -> str:
    number = safe_float(value)
    if number is None:
        return "n/a"
    return f"{number:.{digits}f}"


def human_bytes(num_bytes: Optional[float]) -> Optional[str]:
    if num_bytes is None:
        return None
    units = ["B", "KB", "MB", "GB", "TB", "PB"]
    value = float(num_bytes)
    idx = 0
    while value >= 1024.0 and idx < len(units) - 1:
        value /= 1024.0
        idx += 1
    return f"{value:.2f} {units[idx]}"


def relative_percent_error(observed: float, reference: float) -> float:
    denominator = max(abs(reference), 1.0)
    return abs(observed - reference) / denominator * 100.0


def load_json(path: Path) -> Dict[str, Any]:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def parse_json_object(text: str) -> Dict[str, Any]:
    candidate = text.strip()
    if candidate.startswith("{") and candidate.endswith("}"):
        return json.loads(candidate)

    start = candidate.find("{")
    end = candidate.rfind("}")
    if start != -1 and end != -1 and end > start:
        return json.loads(candidate[start : end + 1])

    raise ValueError("No JSON object found in output")


def load_expected_ips(expected_file: Path, csv_column: str = "ip_address") -> List[str]:
    suffix = expected_file.suffix.lower()
    ips: List[str] = []

    if suffix == ".csv":
        with expected_file.open("r", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            if reader.fieldnames and csv_column in reader.fieldnames:
                for row in reader:
                    value = (row.get(csv_column) or "").strip()
                    if value:
                        ips.append(value)
            else:
                f.seek(0)
                plain_reader = csv.reader(f)
                for row in plain_reader:
                    if not row:
                        continue
                    value = row[0].strip()
                    if value and value.lower() != csv_column.lower():
                        ips.append(value)
    elif suffix == ".json":
        payload = json.loads(expected_file.read_text(encoding="utf-8"))
        if isinstance(payload, list):
            for item in payload:
                if isinstance(item, str):
                    ips.append(item)
                elif isinstance(item, dict) and csv_column in item:
                    ips.append(str(item[csv_column]))
        elif isinstance(payload, dict):
            values = payload.get("ips", [])
            if isinstance(values, list):
                ips.extend(str(v) for v in values)
    else:
        for line in expected_file.read_text(encoding="utf-8").splitlines():
            value = line.strip()
            if value and not value.startswith("#"):
                ips.append(value)

    normalized: List[str] = []
    for ip in ips:
        try:
            normalized.append(str(ipaddress.ip_address(ip.strip())))
        except ValueError:
            continue

    return sorted(set(normalized))


def expand_range(from_ip: str, to_ip: str, max_size: int = 200_000) -> List[str]:
    start = int(ipaddress.ip_address(from_ip))
    end = int(ipaddress.ip_address(to_ip))
    if end < start:
        return []

    size = end - start + 1
    if size > max_size:
        return []

    return [str(ipaddress.ip_address(n)) for n in range(start, end + 1)]


def connect_db(dsn: str):
    return psycopg2.connect(dsn)


def read_cpu_jiffies_linux() -> Tuple[float, float]:
    with open("/proc/stat", "r", encoding="utf-8") as f:
        first = f.readline().strip()

    parts = first.split()
    if len(parts) < 5 or parts[0] != "cpu":
        raise RuntimeError("Unexpected /proc/stat format")

    values = [float(v) for v in parts[1:]]
    idle = values[3] + (values[4] if len(values) > 4 else 0.0)
    total = sum(values)
    return idle, total


def native_cpu_percent_linux(interval_seconds: float = 1.0) -> float:
    idle_1, total_1 = read_cpu_jiffies_linux()
    time.sleep(interval_seconds)
    idle_2, total_2 = read_cpu_jiffies_linux()

    total_delta = total_2 - total_1
    idle_delta = idle_2 - idle_1
    if total_delta <= 0:
        return 0.0

    usage = (1.0 - (idle_delta / total_delta)) * 100.0
    return max(0.0, min(100.0, usage))


def native_ram_percent_linux() -> float:
    mem_total = None
    mem_available = None

    with open("/proc/meminfo", "r", encoding="utf-8") as f:
        for line in f:
            if line.startswith("MemTotal:"):
                mem_total = float(line.split()[1])
            elif line.startswith("MemAvailable:"):
                mem_available = float(line.split()[1])

    if not mem_total or mem_available is None:
        raise RuntimeError("MemTotal or MemAvailable not found")

    mem_used = mem_total - mem_available
    return max(0.0, min(100.0, (mem_used / mem_total) * 100.0))


def run_command(args: Sequence[str], timeout_seconds: int = 120) -> Tuple[int, str, str]:
    completed = subprocess.run(
        args,
        text=True,
        capture_output=True,
        timeout=timeout_seconds,
        check=False,
    )
    return completed.returncode, completed.stdout, completed.stderr


def benchmark_http_endpoint(
    url: str,
    runs: int,
    timeout_seconds: int,
    expected_statuses: Iterable[int],
    method: str = "GET",
    body: Optional[bytes] = None,
    headers: Optional[Dict[str, str]] = None,
) -> Dict[str, Any]:
    expected = set(expected_statuses)
    samples: List[HttpSample] = []

    for _ in range(runs):
        started = time.perf_counter()
        status: Optional[int] = None
        ok = False
        err_text: Optional[str] = None

        try:
            req = Request(url=url, data=body, method=method)
            for k, v in (headers or {}).items():
                req.add_header(k, v)

            with urlopen(req, timeout=timeout_seconds) as resp:
                status = int(resp.status)
                _ = resp.read()
                ok = status in expected
        except HTTPError as ex:
            status = int(ex.code)
            _ = ex.read()
            ok = status in expected
            if not ok:
                err_text = f"HTTP {status}"
        except URLError as ex:
            err_text = f"URLError: {ex.reason}"
        except Exception as ex:  # noqa: BLE001
            err_text = f"Error: {ex}"

        elapsed_ms = (time.perf_counter() - started) * 1000.0
        samples.append(HttpSample(elapsed_ms=elapsed_ms, status=status, ok=ok, error=err_text))

    ok_samples = [s.elapsed_ms for s in samples if s.ok]
    statuses: Dict[str, int] = {}
    errors: Dict[str, int] = {}

    for s in samples:
        key = str(s.status) if s.status is not None else "none"
        statuses[key] = statuses.get(key, 0) + 1
        if s.error:
            errors[s.error] = errors.get(s.error, 0) + 1

    return {
        "url": url,
        "runs": runs,
        "success_count": len(ok_samples),
        "failure_count": runs - len(ok_samples),
        "success_rate_percent": (len(ok_samples) / runs * 100.0) if runs else 0.0,
        "status_histogram": statuses,
        "error_histogram": errors,
        "mean_ms": statistics.fmean(ok_samples) if ok_samples else None,
        "p50_ms": percentile(ok_samples, 50),
        "p95_ms": percentile(ok_samples, 95),
        "max_ms": max(ok_samples) if ok_samples else None,
        "min_ms": min(ok_samples) if ok_samples else None,
    }


def explain_execution_time_ms(conn, query: str, params: Sequence[Any]) -> float:
    explain_sql = f"EXPLAIN (ANALYZE, FORMAT JSON) {query}"
    with conn.cursor() as cur:
        cur.execute(explain_sql, params)
        row = cur.fetchone()

    if row is None:
        raise RuntimeError("No EXPLAIN output returned")

    payload = row[0]
    if isinstance(payload, str):
        payload = json.loads(payload)

    if isinstance(payload, list):
        top = payload[0]
    else:
        top = payload

    value = top.get("Execution Time")
    if value is None:
        plan = top.get("Plan", {})
        value = plan.get("Actual Total Time")

    if value is None:
        raise RuntimeError("Unable to extract execution time")

    return float(value)


def run_query_pair(
    conn,
    label: str,
    raw_query: str,
    raw_params: Sequence[Any],
    optimized_query: str,
    optimized_params: Sequence[Any],
    repeats: int,
) -> Dict[str, Any]:
    raw_times: List[float] = []
    optimized_times: List[float] = []

    for _ in range(repeats):
        raw_times.append(explain_execution_time_ms(conn, raw_query, raw_params))
    for _ in range(repeats):
        optimized_times.append(explain_execution_time_ms(conn, optimized_query, optimized_params))

    raw_median = percentile(raw_times, 50)
    opt_median = percentile(optimized_times, 50)

    speedup = None
    if raw_median is not None and opt_median is not None and opt_median > 0:
        speedup = raw_median / opt_median

    return {
        "label": label,
        "raw_ms": {
            "samples": raw_times,
            "mean": statistics.fmean(raw_times),
            "p50": raw_median,
            "p95": percentile(raw_times, 95),
        },
        "optimized_ms": {
            "samples": optimized_times,
            "mean": statistics.fmean(optimized_times),
            "p50": opt_median,
            "p95": percentile(optimized_times, 95),
        },
        "speedup_x": speedup,
    }


def risk_level_from_score(score: float) -> str:
    if score < 1.0:
        return "low"
    if score < 2.0:
        return "medium"
    if score < 3.0:
        return "high"
    return "critical"


def choose_reference_system(conn, preferred_system_id: Optional[int]) -> Optional[int]:
    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        if preferred_system_id:
            cur.execute("SELECT system_id FROM systems WHERE system_id = %s", (preferred_system_id,))
            row = cur.fetchone()
            if row:
                return int(row["system_id"])

        cur.execute(
            """
            SELECT s.system_id
            FROM systems s
            LEFT JOIN (
                SELECT system_id, MAX(timestamp) AS last_ts
                FROM metrics
                GROUP BY system_id
            ) m ON m.system_id = s.system_id
            ORDER BY (m.last_ts IS NOT NULL) DESC, m.last_ts DESC NULLS LAST, s.system_id ASC
            LIMIT 1
            """
        )
        row = cur.fetchone()
        if row:
            return int(row["system_id"])

    return None


def collect_discovery_accuracy(
    conn,
    config: Dict[str, Any],
    expected_hosts_file: Optional[Path],
    expected_hosts_column: str,
) -> Dict[str, Any]:
    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute("SELECT host(ip_address) AS ip FROM systems")
        rows = cur.fetchall()

    discovered_ips = sorted({str(r["ip"]) for r in rows if r.get("ip")})

    expected_ips: List[str] = []
    method = "configured_ranges"

    if expected_hosts_file and expected_hosts_file.exists():
        expected_ips = load_expected_ips(expected_hosts_file, expected_hosts_column)
        method = "inventory_file"
    else:
        ranges = []
        for lab in config.get("labs", []):
            ip_range = lab.get("ip_range", {})
            from_ip = ip_range.get("from")
            to_ip = ip_range.get("to")
            if from_ip and to_ip:
                ranges.append((from_ip, to_ip))

        expanded: List[str] = []
        for from_ip, to_ip in ranges:
            expanded.extend(expand_range(from_ip, to_ip))
        expected_ips = sorted(set(expanded))

    expected_set = set(expected_ips)
    discovered_set = set(discovered_ips)

    matched = sorted(expected_set.intersection(discovered_set))
    missing = sorted(expected_set.difference(discovered_set))
    unexpected = sorted(discovered_set.difference(expected_set))

    if expected_set:
        accuracy = len(matched) / len(expected_set) * 100.0
    else:
        accuracy = None

    return {
        "method": method,
        "expected_count": len(expected_set),
        "discovered_count": len(discovered_set),
        "matched_count": len(matched),
        "accuracy_percent": accuracy,
        "missing_count": len(missing),
        "unexpected_count": len(unexpected),
        "missing_examples": missing[:20],
        "unexpected_examples": unexpected[:20],
    }


def collect_ingest_and_freshness(
    conn,
    fresh_window_minutes: int,
    sample_window_hours: int,
) -> Dict[str, Any]:
    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute("SELECT COUNT(*) AS cnt FROM systems")
        total_systems = int(cur.fetchone()["cnt"])

        cur.execute(
            """
            SELECT COUNT(DISTINCT system_id) AS cnt
            FROM metrics
            WHERE timestamp >= NOW() - (%s * INTERVAL '1 minute')
            """,
            (fresh_window_minutes,),
        )
        fresh_systems = int(cur.fetchone()["cnt"])

        cur.execute(
            "SELECT COUNT(*) AS cnt FROM metrics WHERE timestamp >= NOW() - INTERVAL '1 hour'"
        )
        inserts_last_hour = int(cur.fetchone()["cnt"])

        cur.execute(
            "SELECT COUNT(*) AS cnt FROM metrics WHERE timestamp >= NOW() - INTERVAL '24 hours'"
        )
        inserts_last_24h = int(cur.fetchone()["cnt"])

        cur.execute(
            """
            WITH deltas AS (
                SELECT
                    system_id,
                    EXTRACT(EPOCH FROM (timestamp - LAG(timestamp) OVER (
                        PARTITION BY system_id ORDER BY timestamp
                    ))) AS delta_sec
                FROM metrics
                WHERE timestamp >= NOW() - (%s * INTERVAL '1 hour')
            )
            SELECT
                AVG(delta_sec) AS avg_delta_sec,
                PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY delta_sec) AS p50_delta_sec,
                PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY delta_sec) AS p95_delta_sec,
                COUNT(*) AS sample_count
            FROM deltas
            WHERE delta_sec IS NOT NULL AND delta_sec > 0
            """,
            (sample_window_hours,),
        )
        row = cur.fetchone()

    freshness = None
    if total_systems > 0:
        freshness = fresh_systems / total_systems * 100.0

    return {
        "total_systems": total_systems,
        "fresh_systems": fresh_systems,
        "fresh_window_minutes": fresh_window_minutes,
        "fresh_coverage_percent": freshness,
        "inserts_last_hour": inserts_last_hour,
        "inserts_last_24h": inserts_last_24h,
        "estimated_inserts_per_hour_from_24h": (inserts_last_24h / 24.0) if inserts_last_24h else 0.0,
        "collection_interval_stats": {
            "window_hours": sample_window_hours,
            "sample_count": int(row["sample_count"]) if row and row.get("sample_count") else 0,
            "avg_seconds": safe_float(row["avg_delta_sec"]) if row else None,
            "p50_seconds": safe_float(row["p50_delta_sec"]) if row else None,
            "p95_seconds": safe_float(row["p95_delta_sec"]) if row else None,
        },
    }


def run_local_metric_variance(
    collector_script: Path,
    samples: int,
    timeout_seconds: int,
) -> Dict[str, Any]:
    if platform.system().lower() != "linux":
        return {
            "status": "skipped",
            "reason": "Local variance check currently supports Linux only",
        }

    if not collector_script.exists():
        return {
            "status": "skipped",
            "reason": f"Collector script not found: {collector_script}",
        }

    cpu_errors: List[float] = []
    ram_errors: List[float] = []
    cpu_abs_deltas: List[float] = []
    ram_abs_deltas: List[float] = []
    samples_raw: List[Dict[str, Any]] = []

    for idx in range(samples):
        rc, stdout, stderr = run_command(["bash", str(collector_script)], timeout_seconds=timeout_seconds)
        if rc != 0:
            return {
                "status": "failed",
                "reason": f"collector script failed at sample {idx + 1}",
                "stderr": stderr.strip()[:400],
            }

        try:
            payload = parse_json_object(stdout)
        except Exception as ex:  # noqa: BLE001
            return {
                "status": "failed",
                "reason": f"invalid JSON from collector script at sample {idx + 1}",
                "error": str(ex),
                "stdout_excerpt": stdout.strip()[:400],
            }

        collector_cpu = safe_float(payload.get("cpu_percent"))
        collector_ram = safe_float(payload.get("ram_percent"))

        native_cpu = native_cpu_percent_linux(interval_seconds=1.0)
        native_ram = native_ram_percent_linux()

        if collector_cpu is not None:
            cpu_errors.append(relative_percent_error(collector_cpu, native_cpu))
            cpu_abs_deltas.append(abs(collector_cpu - native_cpu))

        if collector_ram is not None:
            ram_errors.append(relative_percent_error(collector_ram, native_ram))
            ram_abs_deltas.append(abs(collector_ram - native_ram))

        samples_raw.append(
            {
                "sample": idx + 1,
                "collector_cpu": collector_cpu,
                "native_cpu": native_cpu,
                "collector_ram": collector_ram,
                "native_ram": native_ram,
            }
        )

    return {
        "status": "ok",
        "sample_count": samples,
        "cpu_relative_error_percent": {
            "mean": statistics.fmean(cpu_errors) if cpu_errors else None,
            "p95": percentile(cpu_errors, 95),
            "max": max(cpu_errors) if cpu_errors else None,
        },
        "ram_relative_error_percent": {
            "mean": statistics.fmean(ram_errors) if ram_errors else None,
            "p95": percentile(ram_errors, 95),
            "max": max(ram_errors) if ram_errors else None,
        },
        "cpu_absolute_delta_percent_points": {
            "mean": statistics.fmean(cpu_abs_deltas) if cpu_abs_deltas else None,
            "p95": percentile(cpu_abs_deltas, 95),
            "max": max(cpu_abs_deltas) if cpu_abs_deltas else None,
        },
        "ram_absolute_delta_percent_points": {
            "mean": statistics.fmean(ram_abs_deltas) if ram_abs_deltas else None,
            "p95": percentile(ram_abs_deltas, 95),
            "max": max(ram_abs_deltas) if ram_abs_deltas else None,
        },
        "sample_preview": samples_raw[:5],
    }


def run_api_latency_suite(
    api_base: str,
    system_id: Optional[int],
    runs: int,
    timeout_seconds: int,
) -> Dict[str, Any]:
    api_base = api_base.rstrip("/")

    endpoints = [
        {
            "name": "systems_all",
            "path": "/systems/all",
            "expected": [200],
        },
        {
            "name": "departments_all",
            "path": "/departments",
            "expected": [200],
        },
    ]

    if system_id is not None:
        endpoints.extend(
            [
                {
                    "name": "system_metrics_latest",
                    "path": f"/systems/{system_id}/metrics/latest",
                    "expected": [200],
                },
                {
                    "name": "system_metrics_24h",
                    "path": f"/systems/{system_id}/metrics?hours=24&limit=200",
                    "expected": [200],
                },
                {
                    "name": "system_metrics_hourly",
                    "path": f"/systems/{system_id}/metrics/hourly?hours=24",
                    "expected": [200],
                },
                {
                    "name": "cfrs_metrics_latest",
                    "path": f"/systems/{system_id}/metrics/cfrs/latest",
                    "expected": [200],
                },
                {
                    "name": "cfrs_score",
                    "path": f"/systems/{system_id}/cfrs/score",
                    "expected": [200, 400],
                },
            ]
        )

    results: Dict[str, Any] = {"api_base": api_base, "runs_per_endpoint": runs, "endpoints": []}

    all_ok_latencies: List[float] = []

    for endpoint in endpoints:
        url = api_base + endpoint["path"]
        measured = benchmark_http_endpoint(
            url=url,
            runs=runs,
            timeout_seconds=timeout_seconds,
            expected_statuses=endpoint["expected"],
        )
        measured["name"] = endpoint["name"]
        measured["path"] = endpoint["path"]
        results["endpoints"].append(measured)

        if measured["mean_ms"] is not None:
            all_ok_latencies.append(measured["mean_ms"])

    ok_endpoints = [e for e in results["endpoints"] if e.get("success_rate_percent") == 100.0]

    results["summary"] = {
        "fully_successful_endpoints": len(ok_endpoints),
        "total_endpoints": len(results["endpoints"]),
        "mean_of_endpoint_means_ms": statistics.fmean(all_ok_latencies) if all_ok_latencies else None,
        "p95_of_endpoint_means_ms": percentile(all_ok_latencies, 95),
    }

    return results


def run_query_performance_suite(
    conn,
    system_id: Optional[int],
    repeats: int,
    statement_timeout_ms: int,
) -> Dict[str, Any]:
    if system_id is None:
        return {
            "status": "skipped",
            "reason": "No reference system id available",
        }

    with conn.cursor() as cur:
        cur.execute("SET statement_timeout = %s", (statement_timeout_ms,))

    query_pairs = [
        {
            "label": "weekly_aggregation",
            "raw": (
                """
                SELECT
                    date_trunc('hour', timestamp) AS hour_bucket,
                    AVG(cpu_percent) AS avg_cpu_percent,
                    AVG(ram_percent) AS avg_ram_percent
                FROM metrics
                WHERE system_id = %s
                  AND timestamp >= NOW() - INTERVAL '7 days'
                GROUP BY 1
                ORDER BY 1 DESC
                """,
                [system_id],
            ),
            "optimized": (
                """
                SELECT
                    hour_bucket,
                    avg_cpu_percent,
                    avg_ram_percent
                FROM hourly_performance_stats
                WHERE system_id = %s
                  AND hour_bucket >= NOW() - INTERVAL '7 days'
                ORDER BY hour_bucket DESC
                """,
                [system_id],
            ),
        },
        {
            "label": "daily_cfrs_tier1_trends",
            "raw": (
                """
                SELECT
                    date_trunc('day', timestamp) AS day_bucket,
                    AVG(cpu_iowait_percent) AS avg_cpu_iowait,
                    AVG(context_switch_rate) AS avg_context_switch,
                    AVG(swap_out_rate) AS avg_swap_out
                FROM metrics
                WHERE system_id = %s
                  AND timestamp >= NOW() - INTERVAL '30 days'
                GROUP BY 1
                ORDER BY 1 DESC
                """,
                [system_id],
            ),
            "optimized": (
                """
                SELECT
                    day_bucket,
                    avg_cpu_iowait,
                    avg_context_switch,
                    avg_swap_out
                FROM cfrs_daily_stats
                WHERE system_id = %s
                  AND day_bucket >= NOW() - INTERVAL '30 days'
                ORDER BY day_bucket DESC
                """,
                [system_id],
            ),
        },
        {
            "label": "top_cpu_consumers",
            "raw": (
                """
                SELECT
                    m.system_id,
                    AVG(m.cpu_percent) AS avg_cpu_percent
                FROM metrics m
                WHERE m.timestamp >= NOW() - INTERVAL '24 hours'
                GROUP BY m.system_id
                ORDER BY avg_cpu_percent DESC
                LIMIT 10
                """,
                [],
            ),
            "optimized": (
                """
                SELECT
                    h.system_id,
                    AVG(h.avg_cpu_percent) AS avg_cpu_percent
                FROM hourly_performance_stats h
                WHERE h.hour_bucket >= NOW() - INTERVAL '24 hours'
                GROUP BY h.system_id
                ORDER BY avg_cpu_percent DESC
                LIMIT 10
                """,
                [],
            ),
        },
    ]

    results: Dict[str, Any] = {"status": "ok", "pairs": [], "statement_timeout_ms": statement_timeout_ms}

    for pair in query_pairs:
        try:
            entry = run_query_pair(
                conn=conn,
                label=pair["label"],
                raw_query=pair["raw"][0],
                raw_params=pair["raw"][1],
                optimized_query=pair["optimized"][0],
                optimized_params=pair["optimized"][1],
                repeats=repeats,
            )
            results["pairs"].append(entry)
        except Exception as ex:  # noqa: BLE001
            results["pairs"].append(
                {
                    "label": pair["label"],
                    "status": "failed",
                    "error": str(ex),
                }
            )

    speedups = [
        p["speedup_x"]
        for p in results["pairs"]
        if isinstance(p, dict) and p.get("speedup_x") is not None
    ]

    results["summary"] = {
        "pairs_total": len(results["pairs"]),
        "pairs_with_speedup": len(speedups),
        "min_speedup_x": min(speedups) if speedups else None,
        "max_speedup_x": max(speedups) if speedups else None,
        "mean_speedup_x": statistics.fmean(speedups) if speedups else None,
    }

    return results


def collect_compression_stats(conn) -> Dict[str, Any]:
    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute("SELECT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'timescaledb') AS installed")
        installed = bool(cur.fetchone()["installed"])

        if not installed:
            return {
                "status": "skipped",
                "reason": "TimescaleDB extension not installed",
            }

        cur.execute(
            """
            SELECT
                COALESCE(SUM(total_bytes), 0)::bigint AS total_bytes,
                COALESCE(SUM(compressed_total_bytes), 0)::bigint AS compressed_total_bytes,
                COUNT(*)::int AS chunk_count
            FROM timescaledb_information.chunks
            WHERE hypertable_name = 'metrics'
            """
        )
        chunk_stats = cur.fetchone()

        total_bytes = safe_float(chunk_stats.get("total_bytes")) if chunk_stats else 0.0
        compressed_bytes = safe_float(chunk_stats.get("compressed_total_bytes")) if chunk_stats else 0.0
        chunk_count = int(chunk_stats.get("chunk_count", 0)) if chunk_stats else 0

        compressed_portion = None
        if total_bytes and total_bytes > 0:
            compressed_portion = compressed_bytes / total_bytes * 100.0

        # Try to pull before/after compression bytes if available in this Timescale version.
        savings = None
        before_bytes = None
        after_bytes = None

        cur.execute(
            """
            SELECT column_name
            FROM information_schema.columns
            WHERE table_schema = 'timescaledb_information'
              AND table_name = 'compression_settings'
            """
        )
        column_names = {row["column_name"] for row in cur.fetchall()}

        if {"before_compression_total_bytes", "after_compression_total_bytes", "hypertable_name"}.issubset(
            column_names
        ):
            cur.execute(
                """
                SELECT
                    before_compression_total_bytes,
                    after_compression_total_bytes
                FROM timescaledb_information.compression_settings
                WHERE hypertable_name = 'metrics'
                """
            )
            row = cur.fetchone()
            if row:
                before_bytes = safe_float(row.get("before_compression_total_bytes"))
                after_bytes = safe_float(row.get("after_compression_total_bytes"))
                if before_bytes and before_bytes > 0 and after_bytes is not None:
                    savings = (1.0 - (after_bytes / before_bytes)) * 100.0

        return {
            "status": "ok",
            "chunk_count": chunk_count,
            "total_bytes": total_bytes,
            "compressed_total_bytes": compressed_bytes,
            "total_size_human": human_bytes(total_bytes),
            "compressed_size_human": human_bytes(compressed_bytes),
            "compressed_portion_percent": compressed_portion,
            "before_compression_total_bytes": before_bytes,
            "after_compression_total_bytes": after_bytes,
            "storage_savings_percent": savings,
        }


def collect_cfrs_readiness(conn, api_base: str, max_systems: int = 25) -> Dict[str, Any]:
    result: Dict[str, Any] = {
        "status": "ok",
        "systems_checked": 0,
        "systems_with_complete_baselines": 0,
        "systems_with_scores": 0,
        "risk_distribution": {"low": 0, "medium": 0, "high": 0, "critical": 0},
        "score_samples": [],
    }

    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        try:
            cur.execute(
                """
                SELECT system_id, COUNT(*)::int AS baseline_count
                FROM cfrs_system_baselines
                WHERE is_active = TRUE
                GROUP BY system_id
                ORDER BY baseline_count DESC, system_id ASC
                """
            )
            baseline_rows = cur.fetchall()
        except Exception as ex:  # noqa: BLE001
            return {
                "status": "skipped",
                "reason": f"cfrs_system_baselines unavailable: {ex}",
            }

    complete = [r for r in baseline_rows if int(r.get("baseline_count", 0)) >= 11]
    candidate_ids = [int(r["system_id"]) for r in complete[:max_systems]]

    result["systems_checked"] = len(candidate_ids)
    result["systems_with_complete_baselines"] = len(complete)

    for system_id in candidate_ids:
        url = api_base.rstrip("/") + f"/systems/{system_id}/cfrs/score"
        started = time.perf_counter()
        try:
            req = Request(url=url, method="GET")
            with urlopen(req, timeout=10) as resp:
                status = int(resp.status)
                payload = json.loads(resp.read().decode("utf-8"))
        except HTTPError as ex:
            status = int(ex.code)
            payload = {}
            try:
                payload = json.loads(ex.read().decode("utf-8"))
            except Exception:  # noqa: BLE001
                payload = {"error": str(ex)}
        except Exception as ex:  # noqa: BLE001
            status = None
            payload = {"error": str(ex)}

        elapsed_ms = (time.perf_counter() - started) * 1000.0
        score = safe_float(payload.get("cfrs_score")) if isinstance(payload, dict) else None

        if status == 200 and score is not None:
            level = risk_level_from_score(score)
            result["risk_distribution"][level] += 1
            result["systems_with_scores"] += 1

            result["score_samples"].append(
                {
                    "system_id": system_id,
                    "cfrs_score": score,
                    "risk": level,
                    "latency_ms": elapsed_ms,
                }
            )
        else:
            result["score_samples"].append(
                {
                    "system_id": system_id,
                    "status": status,
                    "error": payload.get("error") if isinstance(payload, dict) else "unknown",
                    "latency_ms": elapsed_ms,
                }
            )

    return result


def write_csv_tables(output_dir: Path, report_id: str, results: Dict[str, Any]) -> Dict[str, str]:
    files: Dict[str, str] = {}

    api_result = results.get("api_latency")
    if isinstance(api_result, dict) and api_result.get("endpoints"):
        api_csv = output_dir / f"{report_id}_api_latency.csv"
        with api_csv.open("w", encoding="utf-8", newline="") as f:
            writer = csv.writer(f)
            writer.writerow([
                "endpoint",
                "path",
                "runs",
                "success_rate_percent",
                "mean_ms",
                "p50_ms",
                "p95_ms",
                "max_ms",
                "failure_count",
            ])
            for row in api_result["endpoints"]:
                writer.writerow(
                    [
                        row.get("name"),
                        row.get("path"),
                        row.get("runs"),
                        row.get("success_rate_percent"),
                        row.get("mean_ms"),
                        row.get("p50_ms"),
                        row.get("p95_ms"),
                        row.get("max_ms"),
                        row.get("failure_count"),
                    ]
                )
        files["api_latency_csv"] = str(api_csv)

    query_result = results.get("query_performance")
    if isinstance(query_result, dict) and query_result.get("pairs"):
        query_csv = output_dir / f"{report_id}_query_speedups.csv"
        with query_csv.open("w", encoding="utf-8", newline="") as f:
            writer = csv.writer(f)
            writer.writerow([
                "pair",
                "raw_p50_ms",
                "raw_p95_ms",
                "optimized_p50_ms",
                "optimized_p95_ms",
                "speedup_x",
                "status",
            ])
            for pair in query_result["pairs"]:
                if pair.get("status") == "failed":
                    writer.writerow(
                        [
                            pair.get("label"),
                            "",
                            "",
                            "",
                            "",
                            "",
                            f"failed: {pair.get('error')}",
                        ]
                    )
                    continue

                writer.writerow(
                    [
                        pair.get("label"),
                        pair.get("raw_ms", {}).get("p50"),
                        pair.get("raw_ms", {}).get("p95"),
                        pair.get("optimized_ms", {}).get("p50"),
                        pair.get("optimized_ms", {}).get("p95"),
                        pair.get("speedup_x"),
                        "ok",
                    ]
                )
        files["query_speedups_csv"] = str(query_csv)

    return files


def build_markdown(results: Dict[str, Any]) -> str:
    lines: List[str] = []

    lines.append("# OptiLab Collector Benchmark Report")
    lines.append("")
    lines.append(f"- Generated (UTC): {results.get('generated_at_utc')}")
    lines.append(f"- Report ID: {results.get('report_id')}")
    lines.append(f"- Host: {results.get('host')}")
    lines.append(f"- Reference system_id: {results.get('reference_system_id')}")
    lines.append("")

    discovery = results.get("discovery")
    if isinstance(discovery, dict):
        lines.append("## Discovery Accuracy")
        lines.append("")
        lines.append(f"- Method: {discovery.get('method')}")
        lines.append(f"- Expected hosts: {discovery.get('expected_count')}")
        lines.append(f"- Discovered hosts: {discovery.get('discovered_count')}")
        lines.append(f"- Matched hosts: {discovery.get('matched_count')}")
        acc = discovery.get("accuracy_percent")
        lines.append(f"- Accuracy: {acc:.2f}%" if isinstance(acc, (float, int)) else "- Accuracy: n/a")
        lines.append(f"- Missing hosts: {discovery.get('missing_count')}")
        lines.append(f"- Unexpected hosts: {discovery.get('unexpected_count')}")
        lines.append("")

    ingest = results.get("ingest_and_freshness")
    if isinstance(ingest, dict):
        interval = ingest.get("collection_interval_stats", {})
        lines.append("## Collection Freshness and Throughput")
        lines.append("")
        lines.append(f"- Total systems: {ingest.get('total_systems')}")
        lines.append(
            f"- Fresh systems (last {ingest.get('fresh_window_minutes')} min): {ingest.get('fresh_systems')}"
        )
        cov = ingest.get("fresh_coverage_percent")
        lines.append(f"- Fresh coverage: {cov:.2f}%" if isinstance(cov, (float, int)) else "- Fresh coverage: n/a")
        lines.append(f"- Inserts last hour: {ingest.get('inserts_last_hour')}")
        lines.append(
            "- Estimated inserts/hour (24h average): "
            + fmt_num(ingest.get("estimated_inserts_per_hour_from_24h"), digits=2)
        )
        lines.append(f"- Avg interval (sec): {interval.get('avg_seconds')}")
        lines.append(f"- p95 interval (sec): {interval.get('p95_seconds')}")
        lines.append("")

    local_var = results.get("local_variance")
    if isinstance(local_var, dict):
        lines.append("## Local Collector Variance (CPU/RAM)")
        lines.append("")
        lines.append(f"- Status: {local_var.get('status')}")
        if local_var.get("status") == "ok":
            lines.append(
                "- CPU mean relative error: "
                + f"{fmt_num(local_var.get('cpu_relative_error_percent', {}).get('mean'))}%"
            )
            lines.append(
                "- CPU p95 relative error: "
                + f"{fmt_num(local_var.get('cpu_relative_error_percent', {}).get('p95'))}%"
            )
            lines.append(
                "- RAM mean relative error: "
                + f"{fmt_num(local_var.get('ram_relative_error_percent', {}).get('mean'))}%"
            )
            lines.append(
                "- RAM p95 relative error: "
                + f"{fmt_num(local_var.get('ram_relative_error_percent', {}).get('p95'))}%"
            )
        else:
            lines.append(f"- Reason: {local_var.get('reason')}")
        lines.append("")

    api = results.get("api_latency")
    if isinstance(api, dict):
        lines.append("## API Latency")
        lines.append("")
        lines.append("| Endpoint | Mean (ms) | p95 (ms) | Success % |")
        lines.append("|---|---:|---:|---:|")
        for row in api.get("endpoints", []):
            lines.append(
                f"| {row.get('name')} | {row.get('mean_ms')} | {row.get('p95_ms')} | {row.get('success_rate_percent')} |"
            )
        lines.append("")

    perf = results.get("query_performance")
    if isinstance(perf, dict):
        lines.append("## Query Performance Speedups")
        lines.append("")
        lines.append("| Query Pair | Raw p50 (ms) | Optimized p50 (ms) | Speedup (x) |")
        lines.append("|---|---:|---:|---:|")
        for pair in perf.get("pairs", []):
            if pair.get("status") == "failed":
                lines.append(f"| {pair.get('label')} | failed | failed | failed |")
            else:
                lines.append(
                    f"| {pair.get('label')} | {pair.get('raw_ms', {}).get('p50')} | {pair.get('optimized_ms', {}).get('p50')} | {pair.get('speedup_x')} |"
                )
        lines.append("")

    compression = results.get("compression")
    if isinstance(compression, dict):
        lines.append("## TimescaleDB Compression")
        lines.append("")
        lines.append(f"- Status: {compression.get('status')}")
        if compression.get("status") == "ok":
            lines.append(
                f"- Total hypertable size: {compression.get('total_size_human')} ({compression.get('total_bytes')} bytes)"
            )
            lines.append(
                f"- Compressed bytes: {compression.get('compressed_size_human')} ({compression.get('compressed_total_bytes')} bytes)"
            )
            lines.append(f"- Compressed portion: {compression.get('compressed_portion_percent')}%")
            savings = compression.get("storage_savings_percent")
            if savings is not None:
                lines.append(f"- Storage savings (before/after): {savings:.2f}%")
        else:
            lines.append(f"- Reason: {compression.get('reason')}")
        lines.append("")

    cfrs = results.get("cfrs_readiness")
    if isinstance(cfrs, dict):
        lines.append("## CFRS Readiness and Distribution")
        lines.append("")
        lines.append(f"- Status: {cfrs.get('status')}")
        if cfrs.get("status") == "ok":
            lines.append(f"- Systems checked: {cfrs.get('systems_checked')}")
            lines.append(f"- Systems with complete baselines: {cfrs.get('systems_with_complete_baselines')}")
            lines.append(f"- Systems with computed scores: {cfrs.get('systems_with_scores')}")
            dist = cfrs.get("risk_distribution", {})
            lines.append(
                "- Risk distribution: "
                + ", ".join(f"{k}={v}" for k, v in dist.items())
            )
        else:
            lines.append(f"- Reason: {cfrs.get('reason')}")
        lines.append("")

    return "\n".join(lines).rstrip() + "\n"


def parse_args() -> argparse.Namespace:
    script_dir = Path(__file__).resolve().parent
    default_config = script_dir.parent / "config.json"
    default_collector = script_dir.parent / "metrics_collector.sh"
    default_output = script_dir / "reports"

    parser = argparse.ArgumentParser(
        description="Run collector-side benchmark suite for OptiLab paper metrics"
    )
    parser.add_argument("--config", default=str(default_config), help="Path to collector config.json")
    parser.add_argument("--db-dsn", default=None, help="Override PostgreSQL DSN")
    parser.add_argument("--api-base", default="http://localhost:3000/api", help="Backend API base URL")
    parser.add_argument("--system-id", type=int, default=None, help="Reference system_id for system-specific checks")

    parser.add_argument(
        "--expected-hosts-file",
        default=None,
        help="Optional expected inventory file (csv/json/txt) for discovery accuracy",
    )
    parser.add_argument(
        "--expected-hosts-column",
        default="ip_address",
        help="CSV/JSON field name containing IPs (default: ip_address)",
    )

    parser.add_argument("--fresh-window-minutes", type=int, default=15)
    parser.add_argument("--sample-window-hours", type=int, default=24)

    parser.add_argument("--collector-script", default=str(default_collector))
    parser.add_argument("--local-variance-samples", type=int, default=10)
    parser.add_argument("--local-variance-timeout", type=int, default=180)

    parser.add_argument("--api-runs", type=int, default=30)
    parser.add_argument("--api-timeout", type=int, default=10)

    parser.add_argument("--query-repeats", type=int, default=5)
    parser.add_argument("--statement-timeout-ms", type=int, default=120000)

    parser.add_argument("--output-dir", default=str(default_output))
    parser.add_argument("--report-prefix", default="optilab_benchmark")

    parser.add_argument("--skip-discovery", action="store_true")
    parser.add_argument("--skip-local-variance", action="store_true")
    parser.add_argument("--skip-api", action="store_true")
    parser.add_argument("--skip-query", action="store_true")
    parser.add_argument("--skip-compression", action="store_true")
    parser.add_argument("--skip-cfrs", action="store_true")

    return parser.parse_args()


def main() -> int:
    args = parse_args()

    config_path = Path(args.config).resolve()
    output_dir = Path(args.output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    if not config_path.exists():
        print(f"[ERROR] Config file not found: {config_path}", file=sys.stderr)
        return 1

    config = load_json(config_path)
    dsn = args.db_dsn or config.get("db", {}).get("dsn")
    if not dsn:
        print("[ERROR] Database DSN not found. Use --db-dsn or set db.dsn in config.json", file=sys.stderr)
        return 1

    conn = connect_db(dsn)

    report_id = f"{args.report_prefix}_{datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')}"

    results: Dict[str, Any] = {
        "report_id": report_id,
        "generated_at_utc": utc_now_iso(),
        "host": platform.node(),
        "platform": platform.platform(),
        "python_version": sys.version.split()[0],
        "config_path": str(config_path),
        "api_base": args.api_base,
        "db_dsn_redacted": dsn.split("@")[-1] if "@" in dsn else "provided",
    }

    try:
        reference_system_id = choose_reference_system(conn, args.system_id)
        results["reference_system_id"] = reference_system_id

        if not args.skip_discovery:
            expected_file = Path(args.expected_hosts_file).resolve() if args.expected_hosts_file else None
            results["discovery"] = collect_discovery_accuracy(
                conn=conn,
                config=config,
                expected_hosts_file=expected_file,
                expected_hosts_column=args.expected_hosts_column,
            )

        results["ingest_and_freshness"] = collect_ingest_and_freshness(
            conn=conn,
            fresh_window_minutes=args.fresh_window_minutes,
            sample_window_hours=args.sample_window_hours,
        )

        if not args.skip_local_variance:
            results["local_variance"] = run_local_metric_variance(
                collector_script=Path(args.collector_script).resolve(),
                samples=args.local_variance_samples,
                timeout_seconds=args.local_variance_timeout,
            )

        if not args.skip_api:
            results["api_latency"] = run_api_latency_suite(
                api_base=args.api_base,
                system_id=reference_system_id,
                runs=args.api_runs,
                timeout_seconds=args.api_timeout,
            )

        if not args.skip_query:
            results["query_performance"] = run_query_performance_suite(
                conn=conn,
                system_id=reference_system_id,
                repeats=args.query_repeats,
                statement_timeout_ms=args.statement_timeout_ms,
            )

        if not args.skip_compression:
            results["compression"] = collect_compression_stats(conn)

        if not args.skip_cfrs:
            results["cfrs_readiness"] = collect_cfrs_readiness(
                conn=conn,
                api_base=args.api_base,
                max_systems=25,
            )

    finally:
        conn.close()

    csv_paths = write_csv_tables(output_dir=output_dir, report_id=report_id, results=results)
    results["csv_outputs"] = csv_paths

    json_path = output_dir / f"{report_id}.json"
    md_path = output_dir / f"{report_id}.md"

    json_path.write_text(json.dumps(results, indent=2, sort_keys=False), encoding="utf-8")
    md_path.write_text(build_markdown(results), encoding="utf-8")

    print("[OK] Benchmark run completed")
    print(f"[OK] JSON report: {json_path}")
    print(f"[OK] Markdown report: {md_path}")
    for name, path in csv_paths.items():
        print(f"[OK] {name}: {path}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
