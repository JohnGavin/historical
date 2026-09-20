#!/usr/bin/env bash
# kraken_zip_inventory.sh — inventory the Kraken OHLCVT source archive
# WITHOUT extracting it (#873, follows #436).
#
# Reads only the zip's central directory (`unzip -l`), so it takes about a
# second on the 7 GB archive. Answers: which bar intervals exist for the
# pairs we ingested, how big are they, and what vintage is the archive?
# Output is a committed CSV so nobody has to re-list the zip to find out.
#
# The ingested-pair list is read from scripts/fetch_kraken_ohlcvt.R
# (csv_prefix = "...") so there is exactly one list of pairs in the repo.
#
# USAGE
#   scripts/kraken_zip_inventory.sh                    # defaults below
#   scripts/kraken_zip_inventory.sh --zip PATH --out PATH
#   scripts/kraken_zip_inventory.sh --selftest
#
# OUTPUT (default inst/extdata/kraken_ohlcvt_inventory.csv), one row per
# ingested-pair x interval file found in the archive:
#   pair, interval_min, uncompressed_bytes, archive_dir, member_date
# A summary of ALL intervals in the archive is printed to stdout.
#
# EXIT CODES (exit-code-conventions)
#   0  PASS: archive listed, every ingested pair found
#   1  FAIL: archive listed, but >=1 ingested pair has no files in it
#   2  usage error
#   3  INDETERMINATE: could not answer (unzip missing/failed, zip unreadable,
#      zero CSV members parsed, pair list unparseable)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ZIP="${KRAKEN_ZIP_PATH:-$HOME/Downloads/Kraken_OHLCVT.zip}"
FETCH_SCRIPT="$SCRIPT_DIR/fetch_kraken_ohlcvt.R"
OUT="$REPO_ROOT/inst/extdata/kraken_ohlcvt_inventory.csv"

usage() { sed -n '2,29p' "$0"; }

run_inventory() {
  local zip="$1" fetch="$2" out="$3"
  local tmp all pairs rc
  tmp="$(mktemp -d)"
  all="$tmp/all.tsv"
  pairs="$tmp/pairs.txt"

  if ! command -v unzip >/dev/null 2>&1; then
    echo "INDETERMINATE: unzip not found on PATH" >&2
    rm -rf "$tmp"; return 3
  fi
  if [ ! -r "$zip" ]; then
    echo "INDETERMINATE: cannot read zip: $zip" >&2
    rm -rf "$tmp"; return 3
  fi

  unzip -l "$zip" > "$tmp/listing.txt" 2> "$tmp/unzip.err"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "INDETERMINATE: unzip -l failed (rc=$rc): $(head -c 200 "$tmp/unzip.err")" >&2
    rm -rf "$tmp"; return 3
  fi

  # Parse "  Length  MM-DD-YYYY HH:MM  path". Skip __MACOSX resource forks.
  # Member basename is {PAIR}_{interval_minutes}.csv (PAIR may contain no '_').
  awk '
    $NF ~ /\.csv$/ && $NF !~ /__MACOSX/ {
      path = $NF; n = split(path, seg, "/"); base = seg[n]
      dir = (n > 1) ? seg[n-1] : ""
      sub(/\.csv$/, "", base)
      i = match(base, /_[0-9]+$/)
      if (i == 0) next
      printf "%s\t%s\t%s\t%s\t%s\n", substr(base, 1, i-1), substr(base, i+1), $1, dir, $2
    }' "$tmp/listing.txt" > "$all"

  if [ ! -s "$all" ]; then
    echo "INDETERMINATE: parsed zero {PAIR}_{interval}.csv members from $zip" >&2
    rm -rf "$tmp"; return 3
  fi

  grep -o 'csv_prefix = "[A-Z0-9]*"' "$fetch" 2>/dev/null | sed 's/.*"\(.*\)"/\1/' > "$pairs"
  if [ ! -s "$pairs" ]; then
    echo "INDETERMINATE: no csv_prefix entries parsed from $fetch" >&2
    rm -rf "$tmp"; return 3
  fi

  # Ingested pairs -> CSV (sorted by pair, then numeric interval).
  {
    echo "pair,interval_min,uncompressed_bytes,archive_dir,member_date"
    awk -F'\t' 'NR==FNR { want[$1]=1; next }
                ($1 in want) { printf "%s,%s,%s,%s,%s\n", $1,$2,$3,$4,$5 }' \
        "$pairs" "$all" | sort -t, -k1,1 -k2,2n
  } > "$out"

  local total_files ivals
  total_files="$(wc -l < "$all" | tr -d ' ')"
  echo "archive:           $zip ($(wc -c < "$zip" | tr -d ' ') bytes)"
  echo "csv files (all):   $total_files"
  echo "archive dir(s):    $(cut -f4 "$all" | sort -u | tr '\n' ' ')"
  echo "member dates:      $(cut -f5 "$all" | sort -u | tr '\n' ' ')"
  echo
  echo "== ALL pairs in archive, by interval =="
  printf '%-14s %8s %16s\n' "interval_min" "files" "uncompressed_B"
  awk -F'\t' '{ n[$2]++; b[$2]+=$3 }
              END { for (k in n) printf "%s\t%d\t%.0f\n", k, n[k], b[k] }' "$all" \
    | sort -n | awk -F'\t' '{ printf "%-14s %8d %16.0f\n", $1, $2, $3 }'
  echo
  echo "== INGESTED pairs ($(wc -l < "$pairs" | tr -d ' ')), by interval =="
  printf '%-14s %8s %16s\n' "interval_min" "files" "uncompressed_B"
  awk -F, 'NR>1 { n[$2]++; b[$2]+=$3 }
           END { for (k in n) printf "%s\t%d\t%.0f\n", k, n[k], b[k] }' "$out" \
    | sort -n | awk -F'\t' '{ printf "%-14s %8d %16.0f\n", $1, $2, $3 }'

  # Every ingested pair must appear at least once.
  local missing=""
  while IFS= read -r p; do
    if ! awk -F, -v p="$p" 'NR>1 && $1==p { f=1 } END { exit !f }' "$out"; then
      missing="$missing $p"
    fi
  done < "$pairs"
  echo
  if [ -n "$missing" ]; then
    echo "FAIL: ingested pair(s) absent from archive:$missing" >&2
    echo "wrote $out"
    rm -rf "$tmp"; return 1
  fi
  echo "wrote $out"
  rm -rf "$tmp"
  return 0
}

selftest() {
  local t rc fails=0
  t="$(mktemp -d)"
  if ! command -v zip >/dev/null 2>&1; then
    echo "INDETERMINATE: zip not found; cannot run selftest" >&2; return 3
  fi
  check() { # name expected actual
    if [ "$2" = "$3" ]; then echo "  ok   $1"; else echo "  FAIL $1 (expected $2, got $3)"; fails=$((fails+1)); fi
  }
  printf 'csv_prefix = "AAAUSD"\ncsv_prefix = "BBBUSD"\n' > "$t/fetch.R"

  # Case 1: both pairs present, several intervals, plus junk that must be ignored.
  mkdir -p "$t/z1/master_q4" "$t/z1/__MACOSX"
  for f in AAAUSD_1 AAAUSD_60 AAAUSD_1440 BBBUSD_1 BBBUSD_60 OTHERUSD_1; do
    echo "1,2,3" > "$t/z1/master_q4/$f.csv"
  done
  echo x > "$t/z1/__MACOSX/AAAUSD_5.csv"
  echo x > "$t/z1/master_q4/notes.txt"
  (cd "$t/z1" && zip -qr ../z1.zip master_q4 __MACOSX)
  run_inventory "$t/z1.zip" "$t/fetch.R" "$t/o1.csv" > "$t/o1.log" 2>&1; rc=$?
  check "exit 0 when all pairs present" 0 "$rc"
  check "5 ingested rows (no OTHERUSD, no __MACOSX, no txt)" 5 "$(($(wc -l < "$t/o1.csv") - 1))"
  check "interval 1 present for AAAUSD" 1 "$(grep -c '^AAAUSD,1,' "$t/o1.csv")"

  # Case 2: BBBUSD missing -> determinate FAIL (1), not indeterminate.
  mkdir -p "$t/z2/master_q4"
  echo "1,2,3" > "$t/z2/master_q4/AAAUSD_60.csv"
  (cd "$t/z2" && zip -qr ../z2.zip master_q4)
  run_inventory "$t/z2.zip" "$t/fetch.R" "$t/o2.csv" > "$t/o2.log" 2>&1; rc=$?
  check "exit 1 when an ingested pair is absent" 1 "$rc"

  # Case 3: zip with no CSV members -> INDETERMINATE (3), never a pass.
  mkdir -p "$t/z3"
  echo hi > "$t/z3/readme.txt"
  (cd "$t/z3" && zip -qr ../z3.zip readme.txt)
  run_inventory "$t/z3.zip" "$t/fetch.R" "$t/o3.csv" > "$t/o3.log" 2>&1; rc=$?
  check "exit 3 when zip has no csv members" 3 "$rc"

  # Case 4: unreadable/missing zip -> INDETERMINATE (3).
  run_inventory "$t/nope.zip" "$t/fetch.R" "$t/o4.csv" > "$t/o4.log" 2>&1; rc=$?
  check "exit 3 when zip is missing" 3 "$rc"

  # Case 5: unparseable pair list -> INDETERMINATE (3).
  : > "$t/empty_fetch.R"
  run_inventory "$t/z1.zip" "$t/empty_fetch.R" "$t/o5.csv" > "$t/o5.log" 2>&1; rc=$?
  check "exit 3 when pair list is empty" 3 "$rc"

  rm -rf "$t"
  if [ "$fails" -eq 0 ]; then echo "selftest: PASS"; return 0; fi
  echo "selftest: $fails FAILED"; return 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --zip)      ZIP="${2:-}"; shift 2 ;;
    --out)      OUT="${2:-}"; shift 2 ;;
    --fetch-script) FETCH_SCRIPT="${2:-}"; shift 2 ;;
    --selftest) selftest; exit $? ;;
    -h|--help)  usage; exit 0 ;;
    *)          echo "usage error: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

run_inventory "$ZIP" "$FETCH_SCRIPT" "$OUT"
exit $?
