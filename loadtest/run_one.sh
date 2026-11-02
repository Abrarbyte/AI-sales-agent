#!/usr/bin/env bash
# One self-contained load-test run: start the test copy, run locust, stop the copy.
#   run_one.sh <name> <users> <spawn-rate> <seconds>   (PACE and MIX from the environment)
cd "$(dirname "$0")" || exit 1
name=$1; users=$2; rate=$3; secs=$4
python serve_copy.py > "serve_$name.log" 2>&1 &
until curl -s -m 3 -o /dev/null -w "%{http_code}" http://127.0.0.1:8013/api/health/ | grep -q 200; do sleep 2; done
echo "started $(date +%H:%M:%S)"
ltvenv/Scripts/python -m locust -f locustfile.py --headless -u "$users" -r "$rate" -t "${secs}s" \
  --reset-stats --host http://127.0.0.1 --csv "$name" --only-summary > "$name.log" 2>&1
echo "finished $(date +%H:%M:%S)"
powershell -NoProfile -ExecutionPolicy Bypass -File stop_copy.ps1
python summarize.py "$name"
echo "failures:"; head -5 "${name}_failures.csv"
