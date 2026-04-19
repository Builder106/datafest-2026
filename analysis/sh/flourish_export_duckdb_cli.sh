#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DB_PATH="${DATAFEST_DUCKDB:-$HOME/.datafest_cache/datafest.duckdb}"
SQL_DIR="$ROOT/analysis/sql"
OUT_ANNUAL="$ROOT/analysis/output/flourish/annual/flourish_transport_ed_by_year.csv"
OUT_Q="$ROOT/analysis/output/flourish/quarterly/flourish_transport_ed_by_quarter.csv"

DUCKDB_BIN="${DUCKDB:-$(command -v duckdb || true)}"

if [[ ! -f "$DB_PATH" ]]; then
  echo "Missing database: $DB_PATH" >&2
  echo "Run the ETL and journey steps first, e.g. Rscript analysis/R/run_all.R" >&2
  exit 1
fi

if [[ -z "$DUCKDB_BIN" ]]; then
  echo "duckdb CLI not found. Install: brew install duckdb" >&2
  echo "Or set DUCKDB to the full path of the duckdb executable." >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT_ANNUAL")" "$(dirname "$OUT_Q")"

run_copy() {
  local label=$1
  local sql_file=$2
  local out_file=$3
  echo "[$label] → $out_file"
  "$DUCKDB_BIN" "$DB_PATH" <<EOSQL
COPY (
$(cat "$sql_file")
) TO '${out_file}' (HEADER, DELIMITER ',');
EOSQL
}

run_copy "annual" "$SQL_DIR/flourish_transport_ed_by_year.sql" "$OUT_ANNUAL"
run_copy "quarterly" "$SQL_DIR/flourish_transport_ed_by_quarter.sql" "$OUT_Q"

echo "Done. Lines (incl. header):"
wc -l "$OUT_ANNUAL" "$OUT_Q"
