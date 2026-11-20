#!/usr/bin/env bash

set -Eeuo pipefail

TARGET_TABLES=${TARGET_TABLES:-1000000}
DATABASES=${DATABASES:-100}
CONCURRENCY=${CONCURRENCY:-100}
WORKERS_PER_DATABASE=${WORKERS_PER_DATABASE:-1}
DB_PREFIX=${DB_PREFIX:-million_region_}
WORK_DIR=${WORK_DIR:-$HOME/million-region-load}
MYSQL_PORT=${MYSQL_PORT:-4000}
MAX_ATTEMPTS=${MAX_ATTEMPTS:-10}
TIDB_HOSTS_CSV=${TIDB_HOSTS_CSV:-172.31.7.1,172.31.7.2,172.31.7.3}
PD_URL=${PD_URL:-http://172.31.8.1:2379}

IFS=',' read -r -a tidb_hosts <<<"$TIDB_HOSTS_CSV"

if (( TARGET_TABLES < 1 || DATABASES < 1 || CONCURRENCY < 1 || WORKERS_PER_DATABASE < 1 )); then
  echo "TARGET_TABLES, DATABASES, CONCURRENCY, and WORKERS_PER_DATABASE must be positive" >&2
  exit 2
fi
if (( TARGET_TABLES % DATABASES != 0 )); then
  echo "TARGET_TABLES must be evenly divisible by DATABASES" >&2
  exit 2
fi
if (( ${#tidb_hosts[@]} == 0 )); then
  echo "TIDB_HOSTS_CSV must contain at least one host" >&2
  exit 2
fi

tables_per_database=$((TARGET_TABLES / DATABASES))
mkdir -p "$WORK_DIR/logs" "$WORK_DIR/done" "$WORK_DIR/failed"

exec 9>"$WORK_DIR/load.lock"
if ! flock -n 9; then
  echo "another loader is already using $WORK_DIR" >&2
  exit 1
fi

generate_sql() {
  local database=$1
  local worker=$2
  awk -v database="$database" -v tables="$tables_per_database" \
    -v worker="$worker" -v workers="$WORKERS_PER_DATABASE" 'BEGIN {
    printf "CREATE DATABASE IF NOT EXISTS `%s`;\nUSE `%s`;\n", database, database
    for (i = worker; i < tables; i += workers) {
      printf "CREATE TABLE IF NOT EXISTS `t_%07d` (id BIGINT NOT NULL AUTO_RANDOM(1), payload VARBINARY(16), PRIMARY KEY (id) CLUSTERED) PRE_SPLIT_REGIONS=1;\n", i
    }
  }'
}

table_count() {
  local host=$1
  local database=$2
  mysql --connect-timeout=30 -h "$host" -P "$MYSQL_PORT" -u root -Nse \
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = '$database' AND table_type = 'BASE TABLE'"
}

run_shard() {
  local index=$1
  local database host count worker pid stream_failed
  printf -v database '%s%04d' "$DB_PREFIX" "$index"
  host=${tidb_hosts[$((index % ${#tidb_hosts[@]}))]}
  rm -f "$WORK_DIR/failed/$database"
  if [[ -f "$WORK_DIR/done/$database" ]]; then
    count=$(table_count "$host" "$database" 2>/dev/null || true)
    if [[ "$count" == "$tables_per_database" ]]; then
      return 0
    fi
    rm -f "$WORK_DIR/done/$database"
  fi

  stream_failed=0
  local stream_pids=()
  for ((worker = 0; worker < WORKERS_PER_DATABASE; worker++)); do
    (
      local attempt log_file
      log_file="$WORK_DIR/logs/$database.worker-$worker.log"
      for ((attempt = 1; attempt <= MAX_ATTEMPTS; attempt++)); do
        printf '[%s] attempt=%d host=%s worker=%d/%d\n' \
          "$(date -u +%FT%TZ)" "$attempt" "$host" "$worker" "$WORKERS_PER_DATABASE" >>"$log_file"
        if generate_sql "$database" "$worker" | \
          mysql --connect-timeout=30 -h "$host" -P "$MYSQL_PORT" -u root >>"$log_file" 2>&1; then
          exit 0
        fi
        printf '[%s] retrying stream\n' "$(date -u +%FT%TZ)" >>"$log_file"
        sleep $((attempt * 2))
      done
      exit 1
    ) &
    stream_pids+=("$!")
  done

  for pid in "${stream_pids[@]}"; do
    wait "$pid" || stream_failed=1
  done

  count=$(table_count "$host" "$database" 2>/dev/null || true)
  printf '[%s] observed_tables=%s expected_tables=%d stream_failed=%d\n' \
    "$(date -u +%FT%TZ)" "$count" "$tables_per_database" "$stream_failed" \
    >>"$WORK_DIR/logs/$database.summary.log"
  if (( stream_failed == 0 )) && [[ "$count" == "$tables_per_database" ]]; then
    printf '%s\n' "$count" >"$WORK_DIR/done/$database"
    return 0
  fi

  printf 'failed after %d attempts\n' "$MAX_ATTEMPTS" >"$WORK_DIR/failed/$database"
  return 1
}

monitor() {
  while true; do
    local now regions done_count failed_count
    now=$(date -u +%FT%TZ)
    regions=$(curl -fsS --max-time 15 "$PD_URL/pd/api/v1/stats/region" | jq -r '.count' 2>/dev/null || echo unknown)
    done_count=$(find "$WORK_DIR/done" -type f | wc -l | tr -d ' ')
    failed_count=$(find "$WORK_DIR/failed" -type f | wc -l | tr -d ' ')
    printf '%s regions=%s completed_databases=%s/%s failed_databases=%s\n' \
      "$now" "$regions" "$done_count" "$DATABASES" "$failed_count" | tee -a "$WORK_DIR/progress.log"
    sleep 60
  done
}

initial_regions=$(curl -fsS --max-time 15 "$PD_URL/pd/api/v1/stats/region" | jq -r '.count')
printf 'started_at=%s target_tables=%d target_new_regions=%d databases=%d tables_per_database=%d database_concurrency=%d workers_per_database=%d initial_regions=%s\n' \
  "$(date -u +%FT%TZ)" "$TARGET_TABLES" "$((TARGET_TABLES * 2))" "$DATABASES" \
  "$tables_per_database" "$CONCURRENCY" "$WORKERS_PER_DATABASE" "$initial_regions" | tee "$WORK_DIR/summary.log"

monitor &
monitor_pid=$!
worker_failed=0
pids=()

for ((index = 0; index < DATABASES; index++)); do
  run_shard "$index" &
  pids+=("$!")
  if (( ${#pids[@]} >= CONCURRENCY )); then
    for pid in "${pids[@]}"; do
      wait "$pid" || worker_failed=1
    done
    pids=()
  fi
done

for pid in "${pids[@]}"; do
  wait "$pid" || worker_failed=1
done

kill "$monitor_pid" 2>/dev/null || true
wait "$monitor_pid" 2>/dev/null || true

final_regions=$(curl -fsS --max-time 15 "$PD_URL/pd/api/v1/stats/region" | jq -r '.count')
completed_databases=$(find "$WORK_DIR/done" -type f | wc -l | tr -d ' ')
failed_databases=$(find "$WORK_DIR/failed" -type f | wc -l | tr -d ' ')
printf 'finished_at=%s final_regions=%s region_delta=%d completed_databases=%s/%s failed_databases=%s\n' \
  "$(date -u +%FT%TZ)" "$final_regions" "$((final_regions - initial_regions))" \
  "$completed_databases" "$DATABASES" "$failed_databases" | tee -a "$WORK_DIR/summary.log"

if (( worker_failed != 0 || completed_databases != DATABASES || failed_databases != 0 )); then
  exit 1
fi
