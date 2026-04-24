#!/usr/bin/env python3
"""
Package generated validation reports into a timestamped zip archive.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
from pathlib import Path
import zipfile


def parse_args() -> argparse.Namespace:
    script_dir = Path(__file__).resolve().parent
    default_reports = script_dir / "reports"
    parser = argparse.ArgumentParser(description="Zip validation report files")
    parser.add_argument("--reports-dir", default=str(default_reports))
    parser.add_argument("--output", default=None, help="Optional zip output path")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    reports_dir = Path(args.reports_dir).resolve()
    if not reports_dir.exists():
        print(f"[ERROR] Reports directory not found: {reports_dir}")
        return 1

    files = sorted([p for p in reports_dir.iterdir() if p.is_file()])
    if not files:
        print(f"[ERROR] No report files found in: {reports_dir}")
        return 1

    if args.output:
        zip_path = Path(args.output).resolve()
    else:
        ts = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
        zip_path = reports_dir / f"validation_reports_{ts}.zip"

    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for file_path in files:
            zf.write(file_path, arcname=file_path.name)

    print(f"[OK] Packaged {len(files)} files into: {zip_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
