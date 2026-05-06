#!/usr/bin/env bash
# check_db_activity.sh
# Quick multi-instance Oracle activity check (PMON-based or args)
# Exit codes: 0 ok, 1 partial, 2 fatal
# Autor : Josselin Joly
# Output : log file

set -euo pipefail

# -------- Config --------
ORATAB="${ORATAB:-/etc/oratab}"
NLS_LANG="${NLS_LANG:-AMERICAN_AMERICA.AL32UTF8}"
export NLS_LANG

LOG_DIR="/opt/oracle/dbascripts/logs"
mkdir -p "$LOG_DIR"

RUN_TS="$(date '+%Y-%m-%d_%H-%M-%S')"
REPORT="$LOG_DIR/db_activity_${RUN_TS}.log"

say() { printf '[%s] %s\n' "$(date '+%F %T')" "$*" | tee -a "$REPORT"; }
have_cmd() { command -v "$1" >/dev/null 2>&1; }
fatal() { echo "FATAL: $*" | tee -a "$REPORT" >&2; exit 2; }

# -------- Pre-checks --------
have_cmd sqlplus || fatal "sqlplus not found (Oracle env not loaded)."
[ -r "$ORATAB" ] || fatal "Cannot read $ORATAB."

if ! have_cmd oraenv; then
  for p in /usr/local/bin/oraenv /usr/bin/oraenv; do
    [ -f "$p" ] && PATH="$(dirname "$p"):$PATH"
  done
fi
have_cmd oraenv || fatal "oraenv not available in PATH."

ORAENV_CMD="oraenv"
type oraenv >/dev/null 2>&1 || ORAENV_CMD="$(command -v oraenv)"

# -------- Build SID list --------
SIDS=()
if [ "$#" -gt 0 ]; then
  for s in "$@"; do SIDS+=("$s"); done
else
  while read -r _ _ _ _ _ _ _ pname; do
    sid="${pname#*ora_pmon_}"
    [ "$sid" != "$pname" ] && SIDS+=("$sid")
  done < <(ps -ef | awk '$8 ~ /ora_pmon_/')
fi

# Deduplicate preserving order
uniq=()
for s in "${SIDS[@]}"; do
  [[ " ${uniq[*]} " =~ " $s " ]] || uniq+=("$s")
done
SIDS=("${uniq[@]}")

[ "${#SIDS[@]}" -gt 0 ] || fatal "No ORACLE_SID detected."

say "Starting DB activity check for: ${SIDS[*]}"
say "Report: $REPORT"

fail_count=0

# -------- SQL block --------
SQL_BLOCK="$(cat <<'SQL'
SET PAGES 999 LINES 300 FEEDBACK OFF VERIFY OFF HEADING ON
COLUMN ts FORMAT A25
COLUMN instance_name FORMAT A12
COLUMN host_name FORMAT A20
COLUMN status FORMAT A10
COLUMN database_role FORMAT A16
COLUMN open_mode FORMAT A14

PROMPT === [1/6] Instance / Database ===
SELECT TO_CHAR(SYSTIMESTAMP,'YYYY-MM-DD HH24:MI:SS TZH:TZM') ts,
       i.instance_name, i.host_name, i.status,
       d.database_role, d.open_mode
FROM v$instance i CROSS JOIN v$database d;

PROMPT
PROMPT === [2/6] Active sessions ===
SELECT COUNT(*) active_user_sessions
FROM gv$session
WHERE status='ACTIVE'
AND type <> 'BACKGROUND';

PROMPT
PROMPT === [3/6] Top 3 sessions (last_call_et) ===
SELECT sid||','||serial# sid_serial,
       username, machine, program, sql_id, event
FROM gv$session
WHERE status='ACTIVE'
AND type <> 'BACKGROUND'
ORDER BY last_call_et DESC
FETCH FIRST 3 ROWS ONLY;

PROMPT
PROMPT === [4/6] Wait classes ===
SELECT wait_class, COUNT(*) sessions
FROM gv$session
WHERE status='ACTIVE'
AND type <> 'BACKGROUND'
GROUP BY wait_class
ORDER BY sessions DESC;

PROMPT
PROMPT === [5/6] Data Guard (if applicable) ===
SELECT name, value
FROM v$dataguard_stats
WHERE name IN ('transport lag','apply lag','apply finish time');

PROMPT
PROMPT === [6/6] Long operations ===
SELECT opname, sofar, totalwork,
       ROUND(sofar*100/NULLIF(totalwork,0),1) pct_done,
       elapsed_seconds, time_remaining, sid, serial#
FROM v$session_longops
WHERE sofar < totalwork
FETCH FIRST 5 ROWS ONLY;
SQL
)"

# -------- Loop over SIDs --------
for SID in "${SIDS[@]}"; do
  {
    echo
    echo "============================================================"
    echo "ORACLE_SID = $SID"
    echo "============================================================"
  } | tee -a "$REPORT"

  export ORACLE_SID="$SID"
  export ORAENV_ASK=NO

  awk -F: -v s="$SID" '$1==s{found=1} END{exit !found}' "$ORATAB" || {
    say "WARN: $SID not found in oratab — skipping"
    ((fail_count++))
    continue
  }

  . "$ORAENV_CMD" >/dev/null 2>&1 || {
    say "WARN: oraenv failed for $SID"
    ((fail_count++))
    continue
  }

  [ -n "${ORACLE_HOME:-}" ] || {
    say "WARN: ORACLE_HOME unset for $SID"
    ((fail_count++))
    continue
  }

  say "Using ORACLE_HOME=$ORACLE_HOME"

  sqlplus -s '/ as sysdba' <<EOF >>"$REPORT"
$SQL_BLOCK
EOF

done

say "Completed. Failures: $fail_count"
[ "$fail_count" -gt 0 ] && exit 1

# -------- Mail (optional) --------
OUTFILE="$REPORT"
RECIPIENTS="${RECIPIENTS:-oracle-dba-team@example.local}"
MAIL_FROM="${MAIL_FROM:-oracle-monitor@example.local}"

HOST_N="$(hostname -s 2>/dev/null || hostname)"
RUN_DT="$(date '+%Y-%m-%d %H:%M:%S %Z')"

MAIL_SUBJECT="${MAIL_SUBJECT:-[Oracle] DB activity report on ${HOST_N} @ ${RUN_DT}}"
MAIL_BODY="${MAIL_BODY:-Please find attached the Oracle activity report.}"

if command -v mailx >/dev/null 2>&1; then
  printf "%b" "$MAIL_BODY" | mailx -r "$MAIL_FROM" \
    -s "$MAIL_SUBJECT" -a "$OUTFILE" "$RECIPIENTS"
fi

exit 0
