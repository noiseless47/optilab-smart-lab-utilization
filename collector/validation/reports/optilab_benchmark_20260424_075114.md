# OptiLab Collector Benchmark Report

- Generated (UTC): 2026-04-24T07:51:14+00:00
- Report ID: optilab_benchmark_20260424_075114
- Host: aayush-Victus-by-HP-Gaming-Laptop-15-fa0xxx
- Reference system_id: 170

## Discovery Accuracy

- Method: configured_ranges
- Expected hosts: 3
- Discovered hosts: 4
- Matched hosts: 2
- Accuracy: 66.67%
- Missing hosts: 1
- Unexpected hosts: 2

## Collection Freshness and Throughput

- Total systems: 4
- Fresh systems (last 15 min): 2
- Fresh coverage: 50.00%
- Inserts last hour: 114
- Estimated inserts/hour (24h average): 4.75
- Avg interval (sec): 10.639525098214285
- p95 interval (sec): 10.736161899999999

## Local Collector Variance (CPU/RAM)

- Status: ok
- CPU mean relative error: 120.247%
- CPU p95 relative error: 426.552%
- RAM mean relative error: 0.298%
- RAM p95 relative error: 1.083%

## API Latency

| Endpoint | Mean (ms) | p95 (ms) | Success % |
|---|---:|---:|---:|
| systems_all | 3.311740766685034 | 2.7156297998999426 | 100.0 |
| departments_all | 3.5678445333208706 | 4.401686100004553 | 100.0 |
| system_metrics_latest | 3.5892989666839035 | 7.933717450055149 | 100.0 |
| system_metrics_24h | 5.1029946000502 | 6.2317407002183245 | 100.0 |
| system_metrics_hourly | 3.224369166628094 | 5.252513100163011 | 100.0 |
| cfrs_metrics_latest | 3.483583366672368 | 6.059251100077745 | 100.0 |
| cfrs_score | None | None | 0.0 |

## Query Performance Speedups

| Query Pair | Raw p50 (ms) | Optimized p50 (ms) | Speedup (x) |
|---|---:|---:|---:|
| weekly_aggregation | 0.549 | 0.015 | 36.6 |
| daily_cfrs_tier1_trends | 0.433 | 0.032 | 13.53125 |
| top_cpu_consumers | 0.167 | 0.019 | 8.789473684210527 |

## TimescaleDB Compression

- Status: ok
- Total hypertable size: 592.00 KB (606208.0 bytes)
- Compressed bytes: 192.00 KB (196608.0 bytes)
- Compressed portion: 32.432432432432435%

## CFRS Readiness and Distribution

- Status: ok
- Systems checked: 0
- Systems with complete baselines: 0
- Systems with computed scores: 0
- Risk distribution: low=0, medium=0, high=0, critical=0
