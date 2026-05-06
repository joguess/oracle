#!/usr/bin/env bash
# check_db_activity_html.sh
# Multi-instance Oracle activity snapshot → HTML report + email attachment
# Exit codes: 0 ok, 1 partial (some SIDs failed), 2 fatal
# Autor : Josselin Joly
# Output : HTML file

set -euo pipefail

# -------- Config --------
ORATAB="${ORATAB:-/etc/oratab}"
NLS_LANG="${NLS_LANG:-AMERICAN_AMERICA.AL32UTF8}"
export NLS_LANG

LOG_DIR="${LOG_DIR:-/appli/home/oracle/dbascripts/logs}"
mkdir -p "$LOG_DIR"
RUN_TS="$(date '+%Y-%m-%d_%H-%M-%S')"

HOST_N="$(hostname -s 2>/dev/null || hostname)"
OUT_HTML="$LOG_DIR/db_activity_${HOST_N}_${RUN_TS}.html"

say() { printf '%s %s\n' "[$(date '+%F %T')]" "$*"; }
have_cmd() { command -v "$1" >/dev/null 2>&1; }
fatal() { echo "FATAL: $*" >&2; exit 2; }

# -------- Pre-checks --------
have_cmd sqlplus || fatal "sqlplus not found in PATH (source Oracle environment first)."
[ -r "$ORATAB" ] || fatal "Cannot read $ORATAB (needed by oraenv)."

# Try to make oraenv available (function or script)
if ! have_cmd oraenv; then
  for p in /usr/local/bin/oraenv /usr/bin/oraenv; do
    [ -f "$p" ] && PATH="$(dirname "$p"):$PATH"
  done
fi
have_cmd oraenv || fatal "oraenv not available in PATH."

# Resolve oraenv path if not a function
ORAENV_CMD="oraenv"
if ! type oraenv >/dev/null 2>&1; then
  ORAENV_CMD="$(command -v oraenv)"
fi

# -------- Build SID list --------
SIDS=()
if [ "$#" -gt 0 ]; then
  for s in "$@"; do SIDS+=("$s"); done
else
  # Auto-detect from PMON processes
  while read -r _u _pid _ppid _c _d _tty _time pname; do
    sid="$(echo "$pname" | sed -n 's/.*ora_pmon_//p')"
    [ -n "$sid" ] && SIDS+=("$sid")
  done < <(/usr/bin/ps -ef | awk '$8 ~ /ora_pmon_/')
fi

# Deduplicate preserving order
uniq_sids=()
for s in "${SIDS[@]}"; do
  skip=0; for u in "${uniq_sids[@]}"; do [ "$u" = "$s" ] && { skip=1; break; }; done
  [ $skip -eq 0 ] && uniq_sids+=("$s")
done
SIDS=("${uniq_sids[@]}")

[ "${#SIDS[@]}" -gt 0 ] || fatal "No ORACLE_SID found (from PMON or args)."

say "Starting HTML activity report for: ${SIDS[*]}"
say "Output: $OUT_HTML"
fail_count=0

# -------- HTML Header --------
cat > "$OUT_HTML" <<'HTML_HEAD'
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8" />
<meta http-equiv="x-ua-compatible" content="ie=edge" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>Oracle DB Activity Report</title>
<style>
  :root {
    --bg:#0f172a; --fg:#e5e7eb; --muted:#94a3b8; --border:#334155;
    --card:#111827; --thead:#1f2937; --accent:#60a5fa; --ok:#16a34a; --warn:#dc2626;
  }
  body.light { --bg:#f8fafc; --fg:#0f172a; --muted:#475569; --border:#cbd5e1;
               --card:#ffffff; --thead:#e5e7eb; --accent:#1d4ed8; --ok:#166534; --warn:#b91c1c; }
  body { margin:0; padding:24px; background:var(--bg); color:var(--fg); font-family:system-ui,-apple-system,Segoe UI,Roboto,Ubuntu,Cantarell,Helvetica Neue,Arial,Noto Sans,sans-serif; }
  .container { max-width:1200px; margin:0 auto; }
  .header { display:flex; align-items:center; justify-content:space-between; gap:12px; margin-bottom:16px; padding-bottom:12px; border-bottom:1px solid var(--border); }
  .title { font-size:20px; font-weight:700; }
  .meta  { color:var(--muted); font-size:14px; }
  button.toggle { border:1px solid var(--border); background:transparent; color:var(--fg); padding:6px 10px; border-radius:8px; cursor:pointer; }
  .card { background:var(--card); border:1px solid var(--border); border-radius:10px; padding:14px; margin:16px 0; }
  h2 { margin:8px 0 10px 0; font-size:18px; }
  h3 { margin:10px 0 6px 0; font-size:15px; color:var(--accent); }
  pre { background:transparent; color:var(--fg); border:1px solid var(--border); border-radius:8px; padding:10px; overflow:auto; }
  .tag { display:inline-block; padding:2px 8px; border-radius:999px; border:1px solid var(--border); font-size:12px; }
  .ok { color:var(--ok); } .warn { color:var(--warn); font-weight:600; }
  .footer { margin-top:12px; color:var(--muted); font-size:12px; }
  details { border:1px solid var(--border); border-radius:8px; padding:8px 10px; margin:8px 0; }
  summary { cursor:pointer; font-weight:600; color:var(--accent); }
</style>
<script>
  function toggleTheme(){
    document.body.classList.toggle('light');
    localStorage.setItem('theme', document.body.classList.contains('light') ? 'light':'dark');
  }
  (function initTheme(){
    const saved = localStorage.getItem('theme');
    if(saved==='light'){ document.body.classList.add('light'); }
  })();
</script>
</head>
<body>
<div class="container">
  <div class="header">
    <div>
      <div class="title">Oracle DB Activity Report</div>
      <div class="meta" id="meta"></div>
    </div>
    <div><button class="toggle" onclick="toggleTheme()">Light / Dark</button></div>
  </div>
HTML_HEAD

# Inject runtime meta
cat >> "$OUT_HTML" <<HTML_META
<script>
  document.getElementById('meta').textContent = "Host: ${HOST_N} — Generated: ${RUN_TS} — SIDs: ${SIDS[*]}";
</script>
HTML_META

# -------- Helper: escape HTML --------
# Usage: escape_html <file/stdin>
escape_html() {
  sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

# -------- Helper: append a section (title + SQL output) --------
# append_section "TITLE" "SQL_TEXT"
append_section() {
  local title="$1"
  local sql_text="$2"
  {
    echo "<h3>${title}</h3>"
    echo "<pre>"
    # run SQL and escape HTML special chars
    sqlplus -s '/ as sysdba' <<SQL | escape_html
SET PAGES 250 LINES 350 TRIMSPOOL ON TAB OFF FEEDBACK ON HEADING ON VERIFY OFF
${sql_text}
SQL
    echo "</pre>"
  } >> "$OUT_HTML"
}

# -------- Loop over SIDs --------
for SID in "${SIDS[@]}"; do
  {
    echo
    echo "============================================================"
    echo "ORACLE_SID = $SID"
    echo "============================================================"
  }

  # 1) Set ORACLE_SID for this iteration
  export ORACLE_SID="$SID"
  export ORAENV_ASK=NO

  # 2) Validate SID exists in oratab
  if ! awk -F: -v s="$SID" '($1==s){found=1} END{exit found?0:1}' "$ORATAB"; then
    echo "[WARN] $SID not found in $ORATAB — skipping." >&2
    fail_count=$((fail_count+1))
    continue
  fi

  # 3) Load env via oraenv (function or script path)
  if ! . "$ORAENV_CMD" >/dev/null 2>&1; then
    echo "[WARN] oraenv failed for $SID — skipping." >&2
    fail_count=$((fail_count+1))
    continue
  fi

  # 4) Ensure ORACLE_HOME is set
  if [ -z "${ORACLE_HOME:-}" ]; then
    echo "[WARN] ORACLE_HOME empty after oraenv for $SID — skipping." >&2
    fail_count=$((fail_count+1))
    continue
  else
    echo "[INFO] Using ORACLE_HOME=${ORACLE_HOME} for SID=$SID"
  fi

  # 5) Connectivity check
  if ! echo "select 'OK' from dual;" | sqlplus -s '/ as sysdba' >/dev/null; then
    echo "[WARN] Cannot connect as sysdba on $SID — skipping." >&2
    fail_count=$((fail_count+1))
    continue
  fi

  # 6) Start card for this SID
  {
    echo "<div class=\"card\">"
    echo "  <h2>Instance: ${SID}</h2>"
  } >> "$OUT_HTML"

  # --- [1/6] Instance / Database state ---
  append_section "[1/6] Instance / Database state" "
SET COLSEP ' | '
COLUMN ts             HEADING 'TS'             FORMAT A28
COLUMN instance_name  HEADING 'INSTANCE_NAME'  FORMAT A13
COLUMN host_name      HEADING 'HOST_NAME'      FORMAT A48
COLUMN status         HEADING 'STATUS'         FORMAT A10
COLUMN database_role  HEADING 'DATABASE_ROLE'  FORMAT A16
COLUMN open_mode      HEADING 'OPEN_MODE'      FORMAT A20
SELECT TO_CHAR(SYSTIMESTAMP, 'YYYY-MM-DD HH24:MI:SS TZH:TZM') ts,
       i.instance_name, i.host_name, i.status,
       d.database_role, d.open_mode
FROM   v\$instance i CROSS JOIN v\$database d;"

  # --- [2/6] Sessions ---
  append_section "[2/6] Sessions — Active user sessions (non-background)" "
SELECT COUNT(*) AS active_user_sessions
FROM   gv\$session
WHERE  status = 'ACTIVE'
AND    type <> 'BACKGROUND';"

  append_section "[2/6] Sessions — Blocking / Blocked locks" "
SELECT
  (SELECT COUNT(*) FROM gv\$lock l1 WHERE l1.block = 1) AS blocking_locks,
  (SELECT COUNT(*) FROM gv\$lock l2 WHERE l2.request > 0) AS waiting_locks
FROM dual;"

  # --- [3/6] Top 3 sessions (approx via last_call_et) ---
  append_section "[3/6] Top 3 sessions by recent activity" "
SET LINES 300 PAGES 200 TRIMSPOOL ON TAB OFF FEEDBACK ON HEADING ON VERIFY OFF
SET COLSEP ' | '
COLUMN sid_serial       HEADING 'SID_SERIAL'       FORMAT A15
COLUMN username         HEADING 'USERNAME'         FORMAT A20
COLUMN machine          HEADING 'MACHINE'          FORMAT A35
COLUMN program          HEADING 'PROGRAM'          FORMAT A48
COLUMN sql_id           HEADING 'SQL_ID'           FORMAT A13
COLUMN event            HEADING 'EVENT'            FORMAT A45
COLUMN state            HEADING 'STATE'            FORMAT A20
COLUMN seconds_in_wait  HEADING 'SECONDS_IN_WAIT'  FORMAT 999,999
SELECT s.sid||','||s.serial# AS sid_serial,
       s.username,
       s.machine,
       s.program,
       s.sql_id,
       s.event,
       s.state,
       s.seconds_in_wait
FROM   gv\$session s
WHERE  s.status = 'ACTIVE'
AND    s.type <> 'BACKGROUND'
ORDER  BY s.last_call_et DESC
FETCH FIRST 3 ROWS ONLY;"

  # --- [4/6] Wait classes snapshot ---
  append_section "[4/6] Wait classes snapshot (current)" "
SET LINES 300 PAGES 200 TRIMSPOOL ON TAB OFF FEEDBACK ON HEADING ON VERIFY OFF
SET COLSEP ' | '
COLUMN wait_class HEADING 'WAIT_CLASS' FORMAT A32
COLUMN sess       HEADING 'SESS'       FORMAT 999,999
SELECT wait_class,
       COUNT(*) AS sess
FROM   gv\$session
WHERE  status = 'ACTIVE'
AND    type <> 'BACKGROUND'
GROUP  BY wait_class
ORDER  BY sess DESC;"

  # --- [5/6] Data Guard (if standby) ---
  # We'll try; if empty, add a NOTE
  DG_OUT="$(sqlplus -s '/ as sysdba' <<'SQL'
SET PAGES 200 LINES 300 TRIMSPOOL ON TAB OFF FEEDBACK OFF HEADING OFF VERIFY OFF
SELECT name, value
FROM   v$dataguard_stats
WHERE  name IN ('transport lag','apply lag','apply finish time')
ORDER  BY name;
EXIT
SQL
)"
  echo "<h3>[5/6] Data Guard stats (if STANDBY)</h3>" >> "$OUT_HTML"
  if [ -z "${DG_OUT//[[:space:]]/}" ]; then
    echo "<pre>NOTE: No Data Guard stats (database is PRIMARY or stats not available).</pre>" >> "$OUT_HTML"
  else
    printf "%s" "$DG_OUT" | escape_html | awk 'BEGIN{print "<pre>"} {print} END{print "</pre>"}' >> "$OUT_HTML"
  fi

  # --- [6/6] Long operations ---
  append_section "[6/6] Long operations (top 5 ongoing)" "
SELECT opname,
       sofar,
       totalwork,
       CASE WHEN totalwork > 0 THEN ROUND(sofar*100/totalwork,1) END AS pct_done,
       elapsed_seconds,
       time_remaining,
       sid, serial#
FROM   v\$session_longops
WHERE  sofar < totalwork
ORDER  BY elapsed_seconds DESC FETCH FIRST 5 ROWS ONLY;"

  # Close card
  echo "</div>" >> "$OUT_HTML"

done

# -------- HTML Footer --------
cat >> "$OUT_HTML" <<'HTML_FOOT'
  <div class="footer">
    Generated by check_db_activity_html.sh
  </div>
</div>
</body>
</html>
HTML_FOOT

echo "HTML report generated: $OUT_HTML"

# ======================================================================
#  MAIL — Send the HTML report as attachment (always)
# ======================================================================
RECIPIENTS="oracle-dba-team@example.local"
MAIL_FROM="oracle-monitor@example.local"
MAIL_SUBJECT="${MAIL_SUBJECT:-[Oracle] DB activity HTML report on ${HOST_N} @ ${RUN_TS}}"
MAIL_BODY="${MAIL_BODY:-Bonjour,\n\nVeuillez trouver ci-joint le rapport d'activité Oracle (HTML) généré.\n\nCordialement,\nL'équipe DBA GEMS.}"

send_with_mailx() {
  printf "%b" "${MAIL_BODY}" | mailx -r "${MAIL_FROM}" -s "${MAIL_SUBJECT}" -a "${OUT_HTML}" ${RECIPIENTS}
}

echo "Attempting to send email with attachment: ${OUT_HTML}"
if [ ! -f "${OUT_HTML}" ]; then
  echo "ERROR: Output file does not exist: ${OUT_HTML}" >&2
  exit 2
fi

if command -v mailx >/dev/null 2>&1; then
  if send_with_mailx; then
    echo "Email sent with mailx to: ${RECIPIENTS}"
  else
    echo "WARNING: mailx failed to send the email." >&2
    echo "Generated file remains at: ${OUT_HTML}"
    exit 1
  fi
else
  echo "ERROR: 'mailx' not found; cannot send email." >&2
  echo "Generated file remains at: ${OUT_HTML}"
  exit 1
fi

# -------- Exit code (partial failures => 1) --------
if [ $fail_count -gt 0 ]; then exit 1; fi
exit 0

