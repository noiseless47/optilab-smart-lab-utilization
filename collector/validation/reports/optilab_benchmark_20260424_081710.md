# OptiLab Collector Benchmark Report

- Generated (UTC): 2026-04-24T08:17:10+00:00
- Report ID: optilab_benchmark_20260424_081710
- Host: aayush-Victus-by-HP-Gaming-Laptop-15-fa0xxx
- Reference system_id: 170

## Discovery Accuracy

- Method: configured_ranges
- Expected hosts: 3
- Discovered hosts: 2
- Total discovered in DB: 4
- Matched hosts: 2
- Accuracy: 66.67%
- Missing hosts: 1
- Unexpected hosts: 0
- Out-of-scope discovered hosts: 2

## Collection Freshness and Throughput

- Total systems: 4
- Fresh systems (last 15 min): 2
- Fresh coverage: 50.00%
- Inserts last hour: 404
- Estimated inserts/hour (observed window): 672.67
- Estimated inserts/hour (rolling 24h): 16.83
- Data coverage in 24h window (hours): 0.60
- Avg interval (sec): 10.696795567164179
- p95 interval (sec): 14.3777632

## Local Collector Variance (CPU/RAM)

- Status: ok
- CPU mean relative error: 97.732%
- CPU p95 relative error: 349.600%
- CPU mean sMAPE: 58.685%
- RAM mean relative error: 0.466%
- RAM p95 relative error: 0.962%
- RAM mean sMAPE: 0.465%

## API Latency

| Endpoint | Mean (ms) | p95 (ms) | Success % |
|---|---:|---:|---:|
| systems_all | 1.7732001333721807 | 2.2500672002252027 | 100.0 |
| departments_all | 2.7320510999895 | 3.6830540998380448 | 100.0 |
| system_metrics_latest | 2.8304367999680835 | 5.4438681000192375 | 100.0 |
| system_metrics_24h | 4.9211911666589 | 6.7555997498175175 | 100.0 |
| system_metrics_hourly | 1.6509582999484944 | 2.0487102498918826 | 100.0 |
| cfrs_metrics_latest | 2.191042999993442 | 3.1323890998692114 | 100.0 |

Skipped endpoints:
- cfrs_score (/systems/170/cfrs/score): No hourly statistics available

## Query Performance Speedups

| Query Pair | Raw p50 (ms) | Optimized p50 (ms) | Speedup (x) |
|---|---:|---:|---:|
| weekly_aggregation | 0.356 | 0.009 | 39.55555555555556 |
| daily_cfrs_tier1_trends | 0.346 | 0.021 | 16.476190476190474 |
| top_cpu_consumers | 0.206 | 0.018 | 11.444444444444445 |

## TimescaleDB Compression

- Status: ok
- Total hypertable size: 720.00 KB (737280.0 bytes)
- Compressed bytes: 192.00 KB (196608.0 bytes)
- Compressed portion: 26.666666666666668%

## CFRS Readiness and Distribution

- Status: ok
- Systems checked: 0
- Systems with complete baselines: 0
- Systems with computed scores: 0
- Risk distribution: low=0, medium=0, high=0, critical=0
