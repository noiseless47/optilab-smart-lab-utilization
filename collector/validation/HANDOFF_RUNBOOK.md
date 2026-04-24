# Validation Handoff Runbook

Use this when you send the branch to another operator who can execute benchmarks.

## 1. Pull and set up

```bash
git clone <repo-url>
cd dbms
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

## 2. Preflight check

```bash
python3 collector/validation/preflight_check.py \
  --config collector/config.json \
  --api-base http://localhost:3000/api \
  --output collector/validation/reports/preflight.json
```

If status is warning, review missing dependencies in preflight.json before running full suite.

## 3. Prepare expected host inventory (recommended)

Copy and edit:

- collector/validation/expected_hosts_template.csv

Example:

```bash
cp collector/validation/expected_hosts_template.csv collector/validation/expected_hosts.csv
# edit expected_hosts.csv with real host list
```

## 4. Run benchmark suite

```bash
python3 collector/validation/run_paper_benchmarks.py \
  --config collector/config.json \
  --api-base http://localhost:3000/api \
  --expected-hosts-file collector/validation/expected_hosts.csv \
  --expected-hosts-column ip_address \
  --api-runs 50 \
  --query-repeats 7
```

## 5. Optional: run stress validation

Install stress-ng first:

```bash
sudo apt-get update && sudo apt-get install -y stress-ng
```

Then run:

```bash
python3 collector/validation/run_fault_injection_validation.py \
  --collector-script collector/metrics_collector.sh \
  --scenarios memory,io
```

## 6. Package artifacts for sharing

```bash
python3 collector/validation/package_reports.py
```

## Output locations

All outputs are in:

- collector/validation/reports

Main files:

- optilab_benchmark_*.json
- optilab_benchmark_*.md
- optilab_benchmark_*_api_latency.csv
- optilab_benchmark_*_query_speedups.csv
- optilab_fault_validation_*.json (if stress run enabled)
- validation_reports_*.zip (if packaged)
