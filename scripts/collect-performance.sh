#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="${ALTTY_PERFORMANCE_APP:-$ROOT_DIR/.build/Altty.app}"
IDLE_SECONDS="${ALTTY_IDLE_SECONDS:-300}"
MEMORY_SECONDS="${ALTTY_MEMORY_SECONDS:-1800}"
OUTPUT_DIR="${ALTTY_PERFORMANCE_OUTPUT:-$ROOT_DIR/.build/performance}"
MODE="${ALTTY_PERFORMANCE_MODE:-idle}"
SAMPLE_INTERVAL=1

if [[ "$(uname -m)" != arm64 ]]; then
  print -u2 "Performance acceptance requires arm64 hardware."
  exit 2
fi
if [[ ! -x "$APP_PATH/Contents/MacOS/Altty" ]]; then
  print -u2 "Missing packaged Release app at $APP_PATH"
  exit 2
fi
if (( MEMORY_SECONDS < IDLE_SECONDS )); then
  print -u2 "ALTTY_MEMORY_SECONDS must be at least ALTTY_IDLE_SECONDS."
  exit 2
fi
if [[ "$MODE" != idle && "$MODE" != interaction ]]; then
  print -u2 "ALTTY_PERFORMANCE_MODE must be idle or interaction."
  exit 2
fi

mkdir -p "$OUTPUT_DIR"
SAMPLES="$OUTPUT_DIR/process-samples.tsv"
POWER_RAW="$OUTPUT_DIR/powermetrics.txt"
LOG_RAW="$OUTPUT_DIR/performance.log"
REPORT="$OUTPUT_DIR/report.json"
open -gj "$APP_PATH"
PID="$(pgrep -n -x Altty)"
trap 'kill "$POWER_PID" 2>/dev/null || true' EXIT
codesign --verify --deep --strict "$APP_PATH"

# Exclude launch/readiness queries from the idle window. Any adapter calls
# after this point must have a corresponding system or interaction cause.
sleep 5
START="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

POWER_PID=""
if sudo -n true 2>/dev/null; then
  sudo -n powermetrics --show-process-energy -i 1000 -n "$IDLE_SECONDS" \
    >"$POWER_RAW" 2>&1 &
  POWER_PID=$!
else
  : >"$POWER_RAW"
  print -u2 "Warning: sudo was not primed; wakeups remain unavailable."
fi

print 'elapsed_seconds\tcpu_percent\trss_kb' >"$SAMPLES"
for (( second = 0; second < MEMORY_SECONDS; second += SAMPLE_INTERVAL )); do
  values="$(ps -p "$PID" -o %cpu=,rss= | awk '{$1=$1; print}')"
  [[ -n "$values" ]] || { print -u2 "Altty exited during collection."; exit 1; }
  print "$second\t${values/ /\t}" >>"$SAMPLES"
  sleep "$SAMPLE_INTERVAL"
done
[[ -z "$POWER_PID" ]] || wait "$POWER_PID"

log show --style compact --start "$START" \
  --predicate 'subsystem == "app.altty.macos" AND category == "Performance"' \
  >"$LOG_RAW"

CPU_AVERAGE="$(awk -v limit="$IDLE_SECONDS" 'NR > 1 && $1 < limit {sum += $2; n++} END {printf "%.4f", n ? sum/n : 0}' "$SAMPLES")"
RSS_MAX_KB="$(awk 'NR > 1 && $3 > max {max=$3} END {print max+0}' "$SAMPLES")"
RSS_FIRST_KB="$(awk 'NR == 2 {print $3+0}' "$SAMPLES")"
RSS_LAST_KB="$(awk 'END {print $3+0}' "$SAMPLES")"
AX_CALLS="$(grep -c 'adapter_call adapter=accessibility' "$LOG_RAW" || true)"
SKYLIGHT_CALLS="$(grep -c 'adapter_call adapter=skylight' "$LOG_RAW" || true)"
WAKEUPS="$(awk '/Altty/ {seen=1} seen && /wakeups/ {for (i=1;i<=NF;i++) if ($i ~ /^[0-9]+$/) total += $i; seen=0} END {print total+0}' "$POWER_RAW")"

percentile() {
  local metric="$1" percentile="$2" values count rank
  values="$(awk -v metric="$metric" '$0 ~ "metric=" metric {for(i=1;i<=NF;i++) if($i ~ /^nanoseconds=/) {sub("nanoseconds=", "", $i); print $i}}' "$LOG_RAW" | sort -n)"
  count="$(print -r -- "$values" | awk 'NF {n++} END {print n+0}')"
  (( count > 0 )) || { print 0; return; }
  rank=$(( (percentile * count + 99) / 100 ))
  print -r -- "$values" | sed -n "${rank}p"
}

sample_count() {
  local metric="$1"
  grep -c "metric=$metric" "$LOG_RAW" || true
}

FOCUS_COUNT="$(sample_count shortcut_to_focus_start)"
FOCUS_P50="$(percentile shortcut_to_focus_start 50)"
FOCUS_P95="$(percentile shortcut_to_focus_start 95)"
FOCUS_P99="$(percentile shortcut_to_focus_start 99)"
PANEL_COUNT="$(sample_count shortcut_to_panel_presentation)"
PANEL_P50="$(percentile shortcut_to_panel_presentation 50)"
PANEL_P95="$(percentile shortcut_to_panel_presentation 95)"
PANEL_P99="$(percentile shortcut_to_panel_presentation 99)"

cat >"$REPORT" <<EOF
{
  "hardware_model": "$(sysctl -n hw.model)",
  "os_version": "$(sw_vers -productName) $(sw_vers -productVersion) ($(sw_vers -buildVersion))",
  "build_sha": "$(git -C "$ROOT_DIR" rev-parse HEAD)",
  "cpu_average_percent": $CPU_AVERAGE,
  "resident_memory_bytes": $(( RSS_MAX_KB * 1024 )),
  "resident_memory_growth_bytes": $(( (RSS_LAST_KB - RSS_FIRST_KB) * 1024 )),
  "wakeups": $WAKEUPS,
  "adapter_call_counts": {"accessibility": $AX_CALLS, "skylight": $SKYLIGHT_CALLS},
  "latencies": {
    "shortcut_to_focus_start": {"sample_count": $FOCUS_COUNT, "p50_nanoseconds": $FOCUS_P50, "p95_nanoseconds": $FOCUS_P95, "p99_nanoseconds": $FOCUS_P99},
    "shortcut_to_panel_presentation": {"sample_count": $PANEL_COUNT, "p50_nanoseconds": $PANEL_P50, "p95_nanoseconds": $PANEL_P95, "p99_nanoseconds": $PANEL_P99}
  }
}
EOF

print "$REPORT"

failed=0
if [[ "$MODE" == idle ]]; then
  awk -v value="$CPU_AVERAGE" 'BEGIN {exit !(value >= 0.2)}' && {
    print -u2 "FAIL: idle CPU $CPU_AVERAGE% is not below 0.2%."
    failed=1
  }
  (( RSS_MAX_KB * 1024 < 50 * 1024 * 1024 )) || {
    print -u2 "FAIL: idle RSS exceeds 50 MB."
    failed=1
  }
  (( AX_CALLS == 0 && SKYLIGHT_CALLS == 0 )) || {
    print -u2 "FAIL: idle run contained uncaused adapter calls."
    failed=1
  }
else
  (( FOCUS_COUNT >= 100 )) || {
    print -u2 "FAIL: interaction run requires at least 100 focus samples."
    failed=1
  }
  (( PANEL_COUNT >= 100 )) || {
    print -u2 "FAIL: interaction run requires at least 100 panel samples."
    failed=1
  }
  (( FOCUS_P95 < 30_000_000 )) || {
    print -u2 "FAIL: shortcut-to-focus-start p95 is not below 30 ms."
    failed=1
  }
  (( PANEL_P50 >= 100_000_000 && PANEL_P99 <= 150_000_000 )) || {
    print -u2 "FAIL: panel presentation samples fall outside 100-150 ms."
    failed=1
  }
fi
exit "$failed"
