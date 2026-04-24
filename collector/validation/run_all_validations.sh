#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

WITH_STRESS=0
BENCH_ARGS=()
STRESS_ARGS=()

print_help() {
  cat <<'EOF'
Usage:
  ./run_all_validations.sh [options] [-- <benchmark args...>]

Options:
  --with-stress         Run optional fault-injection validation after benchmarks
  --bench-arg VALUE     Append one argument token to benchmark runner
  --stress-arg VALUE    Append one argument token to stress runner
  -h, --help            Show this help

Examples:
  ./run_all_validations.sh
  ./run_all_validations.sh --bench-arg --api-base --bench-arg http://localhost:3000/api
  ./run_all_validations.sh --with-stress --stress-arg --scenarios --stress-arg memory,io
  ./run_all_validations.sh -- --api-runs 50 --query-repeats 7
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-stress)
      WITH_STRESS=1
      shift
      ;;
    --bench-arg)
      [[ $# -ge 2 ]] || { echo "Missing value for --bench-arg"; exit 1; }
      BENCH_ARGS+=("$2")
      shift 2
      ;;
    --stress-arg)
      [[ $# -ge 2 ]] || { echo "Missing value for --stress-arg"; exit 1; }
      STRESS_ARGS+=("$2")
      shift 2
      ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do
        BENCH_ARGS+=("$1")
        shift
      done
      ;;
    -h|--help)
      print_help
      exit 0
      ;;
    *)
      BENCH_ARGS+=("$1")
      shift
      ;;
  esac
done

echo "[INFO] Running collector benchmark suite"
python3 "${SCRIPT_DIR}/run_paper_benchmarks.py" "${BENCH_ARGS[@]}"

if [[ ${WITH_STRESS} -eq 1 ]]; then
  echo "[INFO] Running optional fault-injection validation"
  python3 "${SCRIPT_DIR}/run_fault_injection_validation.py" "${STRESS_ARGS[@]}"
fi

echo "[INFO] Validation run(s) completed"
