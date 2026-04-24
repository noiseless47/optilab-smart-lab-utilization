#!/usr/bin/env python3
"""
Optional CFRS fault-injection validation runner.

Runs synthetic stress workloads on Linux collector host (or remote host where executed)
and compares baseline vs stressed windows using metrics_collector.sh output.

Use this to generate empirical evidence that Tier-1 CFRS indicators react before
simple CPU-only thresholds in memory thrash / I/O wait / thermal pressure cases.

Safety notes:
- Requires Linux tools (stress-ng and optionally dd).
- Does not modify database state directly.
- Designed to stop workloads cleanly after each phase.
"""

from __future__ import annotations

import argparse
import json
import os
import platform
import signal
import statistics
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence


@dataclass
class PhaseSample:
    timestamp: str
    metrics: Dict[str, Any]


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def parse_json_object(text: str) -> Dict[str, Any]:
    payload = text.strip()
    if payload.startswith("{") and payload.endswith("}"):
        return json.loads(payload)

    start = payload.find("{")
    end = payload.rfind("}")
    if start != -1 and end != -1 and end > start:
        return json.loads(payload[start : end + 1])

    raise ValueError("Unable to parse JSON object")


def safe_float(value: Any) -> Optional[float]:
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def run_command(args: Sequence[str], timeout_seconds: int = 60) -> subprocess.CompletedProcess:
    return subprocess.run(
        args,
        text=True,
        capture_output=True,
        timeout=timeout_seconds,
        check=False,
    )


def command_exists(name: str) -> bool:
    return subprocess.run(["bash", "-lc", f"command -v {name}"], capture_output=True).returncode == 0


def collect_once(collector_script: Path, timeout_seconds: int) -> Dict[str, Any]:
    proc = run_command(["bash", str(collector_script)], timeout_seconds=timeout_seconds)
    if proc.returncode != 0:
        raise RuntimeError(f"collector script failed: {proc.stderr.strip()[:300]}")
    return parse_json_object(proc.stdout)


def collect_phase(
    phase_name: str,
    collector_script: Path,
    samples: int,
    timeout_seconds: int,
    pause_seconds: float,
) -> Dict[str, Any]:
    data: List[PhaseSample] = []
    for _ in range(samples):
        metrics = collect_once(collector_script, timeout_seconds)
        data.append(PhaseSample(timestamp=utc_now_iso(), metrics=metrics))
        time.sleep(pause_seconds)

    return {
        "phase": phase_name,
        "sample_count": samples,
        "samples": [
            {
                "timestamp": s.timestamp,
                "metrics": s.metrics,
            }
            for s in data
        ],
    }


def summarize_phase(phase_payload: Dict[str, Any]) -> Dict[str, Any]:
    keys = [
        "cpu_percent",
        "ram_percent",
        "cpu_iowait_percent",
        "context_switch_rate",
        "swap_in_rate",
        "swap_out_rate",
        "page_fault_rate",
        "major_page_fault_rate",
        "cpu_temperature",
        "gpu_temperature",
    ]

    summary: Dict[str, Any] = {}
    rows = [entry["metrics"] for entry in phase_payload["samples"]]

    for key in keys:
        values = [safe_float(r.get(key)) for r in rows]
        values = [v for v in values if v is not None]
        if not values:
            summary[key] = None
            continue

        summary[key] = {
            "mean": statistics.fmean(values),
            "max": max(values),
            "min": min(values),
        }

    return summary


def start_background(command: str) -> subprocess.Popen:
    return subprocess.Popen(
        ["bash", "-lc", command],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        preexec_fn=os.setsid,
        text=True,
    )


def stop_background(proc: Optional[subprocess.Popen], kill_timeout_seconds: int = 5) -> None:
    if proc is None:
        return
    if proc.poll() is not None:
        return

    try:
        os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
    except ProcessLookupError:
        return

    started = time.time()
    while proc.poll() is None and (time.time() - started) < kill_timeout_seconds:
        time.sleep(0.2)

    if proc.poll() is None:
        try:
            os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
        except ProcessLookupError:
            pass


def diff_summary(baseline: Dict[str, Any], stressed: Dict[str, Any]) -> Dict[str, Any]:
    out: Dict[str, Any] = {}

    for key, bstats in baseline.items():
        sstats = stressed.get(key)
        if not isinstance(bstats, dict) or not isinstance(sstats, dict):
            continue

        bmean = bstats.get("mean")
        smean = sstats.get("mean")
        if bmean is None or smean is None:
            continue

        delta = smean - bmean
        rel = None
        if abs(bmean) > 1e-9:
            rel = (delta / abs(bmean)) * 100.0

        out[key] = {
            "baseline_mean": bmean,
            "stressed_mean": smean,
            "absolute_delta": delta,
            "relative_delta_percent": rel,
        }

    return out


def run_memory_thrash_scenario(
    collector_script: Path,
    samples_per_phase: int,
    collector_timeout: int,
    sample_pause_seconds: float,
    stress_seconds: int,
) -> Dict[str, Any]:
    if not command_exists("stress-ng"):
        return {
            "status": "skipped",
            "reason": "stress-ng not installed",
        }

    baseline = collect_phase(
        "baseline",
        collector_script,
        samples_per_phase,
        collector_timeout,
        sample_pause_seconds,
    )

    mem_stressor = start_background(
        f"stress-ng --vm 1 --vm-bytes 85% --vm-method all --timeout {stress_seconds}s --metrics-brief"
    )

    try:
        stressed = collect_phase(
            "memory_thrash",
            collector_script,
            samples_per_phase,
            collector_timeout,
            sample_pause_seconds,
        )
    finally:
        stop_background(mem_stressor)

    baseline_summary = summarize_phase(baseline)
    stressed_summary = summarize_phase(stressed)

    return {
        "status": "ok",
        "scenario": "memory_thrash",
        "baseline": baseline,
        "stressed": stressed,
        "baseline_summary": baseline_summary,
        "stressed_summary": stressed_summary,
        "comparison": diff_summary(baseline_summary, stressed_summary),
    }


def run_io_saturation_scenario(
    collector_script: Path,
    samples_per_phase: int,
    collector_timeout: int,
    sample_pause_seconds: float,
    stress_seconds: int,
    io_target_file: Path,
) -> Dict[str, Any]:
    if not command_exists("stress-ng"):
        return {
            "status": "skipped",
            "reason": "stress-ng not installed",
        }

    baseline = collect_phase(
        "baseline",
        collector_script,
        samples_per_phase,
        collector_timeout,
        sample_pause_seconds,
    )

    io_target_file.parent.mkdir(parents=True, exist_ok=True)
    stress_cmd = (
        f"stress-ng --hdd 1 --hdd-bytes 4G --temp-path {io_target_file.parent} "
        f"--timeout {stress_seconds}s --metrics-brief"
    )
    io_stressor = start_background(stress_cmd)

    try:
        stressed = collect_phase(
            "io_saturation",
            collector_script,
            samples_per_phase,
            collector_timeout,
            sample_pause_seconds,
        )
    finally:
        stop_background(io_stressor)

    baseline_summary = summarize_phase(baseline)
    stressed_summary = summarize_phase(stressed)

    return {
        "status": "ok",
        "scenario": "io_saturation",
        "baseline": baseline,
        "stressed": stressed,
        "baseline_summary": baseline_summary,
        "stressed_summary": stressed_summary,
        "comparison": diff_summary(baseline_summary, stressed_summary),
    }


def score_tier1_alerts(summary_diff: Dict[str, Any], cpu_threshold: float = 90.0) -> Dict[str, Any]:
    tier1_keys = [
        "cpu_iowait_percent",
        "context_switch_rate",
        "swap_out_rate",
        "major_page_fault_rate",
        "cpu_temperature",
        "gpu_temperature",
    ]

    triggered: List[str] = []

    for key in tier1_keys:
        entry = summary_diff.get(key)
        if not isinstance(entry, dict):
            continue

        rel = entry.get("relative_delta_percent")
        abs_delta = entry.get("absolute_delta")

        # Generic objective rule: either >= 30% relative increase or strong absolute increase.
        if rel is not None and rel >= 30.0:
            triggered.append(key)
            continue

        if abs_delta is not None:
            if key in {"cpu_temperature", "gpu_temperature"} and abs_delta >= 5.0:
                triggered.append(key)
            elif key in {"cpu_iowait_percent"} and abs_delta >= 5.0:
                triggered.append(key)
            elif key in {"swap_out_rate", "major_page_fault_rate"} and abs_delta >= 10.0:
                triggered.append(key)
            elif key == "context_switch_rate" and abs_delta >= 1000.0:
                triggered.append(key)

    cpu_only_triggered = False
    cpu_entry = summary_diff.get("cpu_percent")
    if isinstance(cpu_entry, dict):
        stressed_mean = cpu_entry.get("stressed_mean")
        if stressed_mean is not None and stressed_mean >= cpu_threshold:
            cpu_only_triggered = True

    return {
        "tier1_trigger_count": len(set(triggered)),
        "tier1_triggered_metrics": sorted(set(triggered)),
        "cpu_threshold_triggered": cpu_only_triggered,
        "cpu_threshold_percent": cpu_threshold,
    }


def parse_args() -> argparse.Namespace:
    script_dir = Path(__file__).resolve().parent
    default_collector = script_dir.parent / "metrics_collector.sh"
    default_output = script_dir / "reports"

    parser = argparse.ArgumentParser(description="Run CFRS stress validation scenarios")
    parser.add_argument("--collector-script", default=str(default_collector))
    parser.add_argument("--samples-per-phase", type=int, default=6)
    parser.add_argument("--collector-timeout", type=int, default=180)
    parser.add_argument("--sample-pause-seconds", type=float, default=1.0)
    parser.add_argument("--stress-seconds", type=int, default=45)

    parser.add_argument(
        "--scenarios",
        default="memory,io",
        help="Comma-separated: memory,io",
    )
    parser.add_argument("--cpu-threshold", type=float, default=90.0)

    parser.add_argument("--output-dir", default=str(default_output))
    parser.add_argument("--report-prefix", default="optilab_fault_validation")
    parser.add_argument(
        "--io-target-file",
        default="/tmp/optilab-io-stress.bin",
        help="Temporary path for I/O stress activity",
    )

    return parser.parse_args()


def main() -> int:
    args = parse_args()
    collector_script = Path(args.collector_script).resolve()
    output_dir = Path(args.output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    if platform.system().lower() != "linux":
        print("[ERROR] This validator currently supports Linux only", file=sys.stderr)
        return 1

    if not collector_script.exists():
        print(f"[ERROR] Collector script not found: {collector_script}", file=sys.stderr)
        return 1

    requested = {s.strip().lower() for s in args.scenarios.split(",") if s.strip()}
    report_id = f"{args.report_prefix}_{datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')}"

    results: Dict[str, Any] = {
        "report_id": report_id,
        "generated_at_utc": utc_now_iso(),
        "host": platform.node(),
        "collector_script": str(collector_script),
        "scenarios_requested": sorted(requested),
        "samples_per_phase": args.samples_per_phase,
        "stress_seconds": args.stress_seconds,
        "cpu_threshold_percent": args.cpu_threshold,
        "results": {},
    }

    if "memory" in requested:
        mem_result = run_memory_thrash_scenario(
            collector_script=collector_script,
            samples_per_phase=args.samples_per_phase,
            collector_timeout=args.collector_timeout,
            sample_pause_seconds=args.sample_pause_seconds,
            stress_seconds=args.stress_seconds,
        )

        if mem_result.get("status") == "ok":
            mem_result["detection_summary"] = score_tier1_alerts(
                mem_result.get("comparison", {}),
                cpu_threshold=args.cpu_threshold,
            )

        results["results"]["memory_thrash"] = mem_result

    if "io" in requested:
        io_result = run_io_saturation_scenario(
            collector_script=collector_script,
            samples_per_phase=args.samples_per_phase,
            collector_timeout=args.collector_timeout,
            sample_pause_seconds=args.sample_pause_seconds,
            stress_seconds=args.stress_seconds,
            io_target_file=Path(args.io_target_file),
        )

        if io_result.get("status") == "ok":
            io_result["detection_summary"] = score_tier1_alerts(
                io_result.get("comparison", {}),
                cpu_threshold=args.cpu_threshold,
            )

        results["results"]["io_saturation"] = io_result

    json_path = output_dir / f"{report_id}.json"
    json_path.write_text(json.dumps(results, indent=2), encoding="utf-8")

    print("[OK] Fault-injection validation completed")
    print(f"[OK] Report: {json_path}")

    # Brief console summary
    for name, payload in results["results"].items():
        status = payload.get("status")
        print(f"[SUMMARY] {name}: {status}")
        if status == "ok":
            detect = payload.get("detection_summary", {})
            print(
                "[SUMMARY] "
                f"{name} tier1 triggers={detect.get('tier1_trigger_count')} "
                f"cpu_threshold_triggered={detect.get('cpu_threshold_triggered')}"
            )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
