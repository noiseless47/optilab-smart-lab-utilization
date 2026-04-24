# Collector Validation Suite for Paper-Grade Metrics

This folder contains reproducible scripts to collect real measurement evidence for the
claims in optilab_ieee_paper.tex.

## Scripts

- run_paper_benchmarks.py
  - Non-invasive benchmark suite.
  - Produces JSON, Markdown, and CSV reports.
- run_fault_injection_validation.py
  - Optional Linux stress validation to verify Tier-1 CFRS response.
  - Produces JSON report.
- run_all_validations.sh
  - Wrapper to run benchmark suite and optional stress validation.
- preflight_check.py
   - Checks environment, DB/API reachability, and required artifacts before execution.
- package_reports.py
   - Zips generated reports for sharing/review.
- HANDOFF_RUNBOOK.md
   - End-to-end execution instructions for remote operators/reviewers.

## Claim-to-Metric Mapping

The benchmark runner covers these major claim categories:

1. Discovery accuracy
   - Measures matched discovered hosts vs expected host inventory.
   - Uses expected_hosts_file (recommended) or configured collector ranges.
2. Collection freshness and throughput
   - Fresh coverage over recent window.
   - Inserts per hour and interval stability from metrics timestamps.
3. Collector measurement quality
   - Local Linux variance check for CPU and RAM.
   - Compares metrics_collector.sh output vs native /proc values.
4. API response performance
   - Measures mean, p50, p95, max latency and success rate.
   - Includes core endpoints and probes CFRS score endpoint readiness.
   - CFRS score benchmark is skipped automatically if backend returns non-ready server errors.
5. Query acceleration
   - Compares raw metrics queries vs continuous aggregates.
   - Reports speedup_x for each query pair.
6. Timescale compression evidence
   - Reports hypertable bytes and compressed bytes.
   - Includes storage_savings_percent when available in Timescale view.
7. CFRS operational readiness
   - Checks active baselines and computes score distribution where possible.

## Prerequisites

- Python 3.9+
- psycopg2-binary installed
- Collector config.json with valid db.dsn
- Backend API running for API latency tests (default: http://localhost:3000/api)
- For optional stress validation:
  - Linux host
  - stress-ng installed

## Quick Start

Run benchmark suite only:

```bash
cd collector/validation
python3 run_paper_benchmarks.py
```

Run preflight first (recommended for handoff execution):

```bash
python3 preflight_check.py --output ./reports/preflight.json
```

Run with explicit expected inventory:

```bash
python3 run_paper_benchmarks.py \
  --expected-hosts-file ./expected_hosts_template.csv \
  --expected-hosts-column ip_address
```

Run with custom API base and stronger sampling:

```bash
python3 run_paper_benchmarks.py \
  --api-base http://localhost:3000/api \
  --api-runs 50 \
  --query-repeats 7 \
  --local-variance-samples 20
```

Run both benchmark and optional stress validation:

```bash
./run_all_validations.sh --with-stress
```

Package report outputs:

```bash
python3 package_reports.py
```

## Output Files

Reports are written to collector/validation/reports:

- optilab_benchmark_YYYYMMDD_HHMMSS.json
- optilab_benchmark_YYYYMMDD_HHMMSS.md
- optilab_benchmark_YYYYMMDD_HHMMSS_api_latency.csv
- optilab_benchmark_YYYYMMDD_HHMMSS_query_speedups.csv
- optilab_fault_validation_YYYYMMDD_HHMMSS.json (if stress run enabled)

## Important Notes

- Use expected-hosts inventory for true discovery-accuracy reporting.
- Query speedups depend on available data volume and aggregate freshness.
- CFRS scoring requires active baselines in cfrs_system_baselines.
- CPU instant variance can be noisy under bursty load; rely on RAM variance and long-window CPU aggregates for publication claims.
- Stress validation is optional and should be run on controlled test nodes.
