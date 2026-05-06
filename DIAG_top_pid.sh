#!/usr/bin/env bash
# ======================================================================
# diag_top_pid.sh — — Diagnostic Oracle à partir du PID (top CPU) (HTML + Dark Mode A)
# Author: Josselin Joly
# Date  : 25/02/2025
# ======================================================================
#  Ce script :
#   1) Récupère la liste des 20 process les plus consommateurs de CPU :
#        ps -eo pid,user,%cpu,%mem,args --sort=-%cpu | head -20
#   2) Prend le PID en tête de liste (1ère ligne après l’en-tête)
#   3) Lance un SQL embarqué qui :
#        - Associe PID -> v$process -> v$session
#        - Affiche SID/SERIAL#/PDB, SQL_ID, CPU, attentes
#        - Détecte si la session exécute un JOB (DBMS_SCHEDULER/DBMS_JOB)
#          et affiche le nom du job / de la chaîne / de la tâche
#        - Affiche le SQL complet (sql_fulltext)
#        - Affiche le plan d’exécution (DBMS_XPLAN, 'ALLSTATS LAST')
#        - Gère le cas "background Jxxx sans session" (liste Advisor EXECUTING)
#
#  Usage:
#    ./diag_top_pid.sh                # détection auto du PID (top CPU)
#    ./diag_top_pid.sh -p 3010886     # PID imposé
#    ./diag_top_pid.sh -c "/ as sysdba" -o /appli/home/oracle/diag
#
#  Notes:
#   - À lancer sur le nœud où le PID existe (RAC : PID local au nœud)
#   - Connexion par défaut : "/ as sysdba" (modifiable avec -c)
#   - Requiert sqlplus dans le PATH et des privilèges catalogue
# ======================================================================

set -euo pipefail

print_usage() {
  cat <<'USAGE'
Usage:
  diag_top_pid.sh [-p <PID>] [-c "<connect>"] [-o <outdir>]
USAGE
}

PID=""
CONNECT="/ as sysdba"
OUTDIR="$(pwd)"

# --- Parse args ---
while (( "$#" )); do
  case "$1" in
    -p) PID="${2:?}"; shift 2 ;;
    -c) CONNECT="${2:?}"; shift 2 ;;
    -o) OUTDIR="${2:?}"; shift 2 ;;
    -h|--help) print_usage; exit 0 ;;
    *) echo "Unknown option : $1"; exit 1 ;;
  esac
done

# --- Get top CPU ---
PSLIST="$(ps -eo pid,user,%cpu,%mem,args --sort=-%cpu | head -20)"
if [[ -z "${PID}" ]]; then
  PID="$(printf "%s\n" "${PSLIST}" | awk 'NR==2{print $1}')"
  echo "Detected PID : ${PID}"
fi

# --- Auto-detect ORACLE_SID from ps output (based on PSLIST) ---
detect_sid() {
  printf "%s\n" "${PSLIST}" \
  | awk '
      NR==1 { next }            # skip header
      $2!="oracle" { next }     # only processes owned by oracle
      {
        for (i=5; i<=NF; i++) {
          # Pattern 1: oracle<SID>   e.g. oracleCDBNPD07 (LOCAL=NO)
          if (match($i, /^oracle([A-Za-z0-9_$#]+)/, m)) { print m[1]; exit }
          # Pattern 2: ora_xxx_<SID> e.g. ora_j000_CDBNPD07
          if (match($i, /^ora_[^ ]*_([A-Za-z0-9_$#]+)/, m)) { print m[1]; exit }
        }
      }
  '
}

ORACLE_SID_DET="$(detect_sid || true)"
if [[ -n "${ORACLE_SID_DET:-}" ]]; then
  export ORACLE_SID="${ORACLE_SID_DET}"
  echo "Detected ORACLE_SID : ${ORACLE_SID}"
else
  echo "WARNING: ORACLE_SID could not be auto-detected from ps top 20." >&2
fi

mkdir -p "${OUTDIR}"
TS="$(date +%Y%m%d_%H%M%S)"
OUTFILE="${OUTDIR}/diag_${PID}_${TS}.html"

RUN_DT="$(date '+%Y-%m-%d %H:%M:%S')"
HOST_N="$(hostname)"

echo "Generating HTML diagnostic → ${OUTFILE}"

# ======================================================================
#  HTML HEADER (Dark Mode A) — écrit par Bash
# ======================================================================
{
cat <<HTML_HEAD
<html>
<head>
  <meta charset="utf-8"/>
  <title>Oracle Diagnostic — PID ${PID} — ${TS}</title>
  <style>
    /* Dark Mode A (OEM-like) */
    body { background:#1e1e1e; color:#dddddd; font-family: Arial, sans-serif; margin:20px; line-height:1.5; }
    h1 { color:#4ea3ff; border-bottom:2px solid #4ea3ff; padding-bottom:8px; }
    h2 { color:#4ea3ff; margin-top:1.6em; }
    .section { background:#242424; border:1px solid #444; border-radius:6px; padding:15px; margin:20px 0; box-shadow:0 1px 3px rgba(0,0,0,0.4); }
    table { border-collapse: collapse; margin-top:10px; font-family:'Courier New', monospace; font-size:14px; width:auto; }
    table td { border:1px solid #555; padding:6px 12px; }
    table tr.header { background:#2c5282; color:#fff; font-weight:bold; text-align:center; }
    table tr.even { background:#2a2a2a; }
    table tr.odd  { background:#333333; }
    pre { background:#111; border:1px solid #333; padding:12px; border-radius:4px; white-space:pre; overflow-x:auto; font-family:'Courier New', monospace; font-size:14px; color:#ddd; }
    details summary { cursor:pointer; color:#ffcc00; font-weight:bold; font-size:15px; }
    a, a:visited { color:#4ea3ff; }
    .kv { color:#9cdcfe; } .val { color:#ce9178; }
    footer { text-align:center; color:#9aa0a6; margin-top:35px; font-size:0.9em; }
    .btn { background:#4ea3ff; border:none; padding:6px 12px; color:#000; margin:10px 0; border-radius:4px; cursor:pointer; font-weight:bold; }
    .btn:hover { filter:brightness(1.1); }
  </style>
</head>
<body>

<h1>DIAG BY TOP PID — PID ${PID}</h1>
<p><span class="kv">Date:</span> <span class="val">${RUN_DT}</span><br>
<span class="kv">Host:</span> <span class="val">${HOST_N}</span><br>
<span class="kv">Connection:</span> <span class="val">${CONNECT}</span></p>
<hr>

<div class="section">
  <h2>Top 20 CPU Processes (from ps)</h2>
  <pre>
${PSLIST}
  </pre>
</div>
HTML_HEAD
} > "${OUTFILE}"

# ======================================================================
# SQL*Plus — UNE SEULE INVOCATION, tout le HTML via PROMPT
# ======================================================================
sqlplus -s "${CONNECT}" >> "${OUTFILE}" <<EOF
SET ECHO OFF VERIFY OFF FEEDBACK OFF HEADING OFF
SET PAGESIZE 0 LINESIZE 32767 LONG 200000 LONGCHUNKSIZE 200000
SET WRAP OFF TRIMSPOOL ON
SET SERVEROUTPUT ON SIZE UNLIMITED

DEFINE pid='${PID}'

-----------------------------------------------------------------------
--  [Step 1]  FIND SID / CON_ID  → TABLE (Style 2)
-----------------------------------------------------------------------
PROMPT <div class="section"><h2>Step 1 : Find SID / CON_ID</h2>

PROMPT <pre>
VAR v_sid NUMBER
VAR v_serial NUMBER
VAR v_con_id NUMBER
VAR v_is_bg NUMBER
VAR v_sql_id VARCHAR2(30)
VAR v_sql_child NUMBER

BEGIN
  :v_sid := NULL;
  :v_serial := NULL;
  :v_con_id := NULL;
  :v_is_bg := 0;
  BEGIN
    SELECT s.sid, s.serial#, s.con_id,
           CASE WHEN p.background='YES' THEN 1 ELSE 0 END,
           s.sql_id, s.sql_child_number
      INTO :v_sid, :v_serial, :v_con_id, :v_is_bg,
           :v_sql_id, :v_sql_child
      FROM v\$process p LEFT JOIN v\$session s ON p.addr = s.paddr
     WHERE p.spid = &pid;
  EXCEPTION WHEN NO_DATA_FOUND THEN
    :v_is_bg := 1;
  END;
END;
/
PROMPT </pre>

-- Imprime la ligne de tableau avec les BINDS (dans la même session)
PROMPT <table>
PROMPT   <tr class="header">
PROMPT     <td>SID</td><td>SERIAL#</td><td>CON_ID</td><td>IS_BG</td><td>SQL_ID</td><td>SQL_CHILD#</td>
PROMPT   </tr>
SELECT '<tr class="even"><td>' || :v_sid       || '</td><td>' ||
                         :v_serial   || '</td><td>' ||
                         :v_con_id   || '</td><td>' ||
                         :v_is_bg    || '</td><td>' ||
                         :v_sql_id   || '</td><td>' ||
                         :v_sql_child|| '</td></tr>'
FROM dual;
PROMPT </table>

PROMPT </div>


-----------------------------------------------------------------------
--  [1/6]  SESSION + SQL_ID  → TABLE (Style 2)
-----------------------------------------------------------------------
PROMPT <div class="section"><h2>[1/6] Session + SQL_ID</h2>
PROMPT <table>
PROMPT   <tr class="header">
PROMPT     <td>SID</td><td>SERIAL#</td><td>USERNAME</td><td>STATUS</td><td>EVENT</td><td>SQL_ID</td>
PROMPT   </tr>

SELECT '<tr class="even"><td>'||sid||'</td><td>'||serial#||'</td><td>'||
       NVL(username,'-')||'</td><td>'||status||'</td><td>'||
       event||'</td><td>'||NVL(sql_id,'-')||'</td></tr>'
FROM   v\$session
WHERE  sid = :v_sid;

PROMPT </table>
PROMPT </div>


-----------------------------------------------------------------------
--  [2/6]  CPU USED  → TABLE (Style 2)
-----------------------------------------------------------------------
PROMPT <div class="section"><h2>[2/6] CPU used</h2>
PROMPT <table>
PROMPT   <tr class="header"><td>CPU_ms</td></tr>

SELECT '<tr class="even"><td>'||r.value||'</td></tr>'
FROM   v\$sesstat r
JOIN   v\$statname n USING(statistic#)
WHERE  n.name='CPU used by this session'
AND    r.sid=:v_sid;

PROMPT </table>
PROMPT </div>


-----------------------------------------------------------------------
--  [3/6]  WAITS  → TABLE (Style 2 + Auto-color Wait Class)
-----------------------------------------------------------------------
PROMPT <div class="section"><h2>[3/6] Waits</h2>
PROMPT <table>
PROMPT   <tr class="header"><td>EVENT</td><td>WAIT_CLASS</td><td>SECONDS</td><td>STATE</td></tr>

SELECT
  '<tr class="even"><td>'||event||'</td>'||
  '<td><span style="color:'||
    CASE wait_class
      WHEN 'CPU'          THEN '#ff6b6b'
      WHEN 'User I/O'     THEN '#ff9f43'
      WHEN 'System I/O'   THEN '#feca57'
      WHEN 'Network'      THEN '#54a0ff'
      WHEN 'Concurrency'  THEN '#c56cf0'
      WHEN 'Application'  THEN '#ff6fa1'
      WHEN 'Configuration'THEN '#48dbfb'
      WHEN 'Commit'       THEN '#10ac84'
      WHEN 'Idle'         THEN '#8395a7'
      ELSE                     '#dddddd'
    END
  ||';">'||wait_class||'</span></td>'||
  '<td>'||seconds_in_wait||'</td>'||
  '<td>'||state||'</td></tr>'
FROM   v\$session
WHERE  sid=:v_sid;

PROMPT </table>
PROMPT </div>


-----------------------------------------------------------------------
--  [4/6]  FULL SQL  → COLLAPSIBLE + Copy button
-----------------------------------------------------------------------
PROMPT <div class="section"><h2>[4/6] FULL SQL</h2>
PROMPT <details>
PROMPT   <summary>Show / Hide SQL text</summary>
PROMPT   <button class="btn" onclick="copySQL()">Copy SQL</button>
PROMPT   <pre id="sqlblock">

DECLARE
  c CLOB;
BEGIN
  BEGIN
    SELECT sql_fulltext INTO c FROM v\$sql WHERE sql_id = :v_sql_id;
  EXCEPTION WHEN NO_DATA_FOUND THEN
    BEGIN
      SELECT sql_fulltext INTO c FROM v\$sqlarea WHERE sql_id = :v_sql_id;
    EXCEPTION WHEN NO_DATA_FOUND THEN
      c := NULL;
    END;
  END;

  IF c IS NULL THEN
    DBMS_OUTPUT.PUT_LINE('No SQL found.');
  ELSE
    FOR i IN 0 .. CEIL(DBMS_LOB.getlength(c)/30000) LOOP
      DBMS_OUTPUT.PUT_LINE(DBMS_LOB.SUBSTR(c,30000,i*30000+1));
    END LOOP;
  END IF;
END;
/
PROMPT   </pre>
PROMPT </details>
PROMPT </div>


-----------------------------------------------------------------------
--  [5/6]  PLAN PRESENCE CHECK
-----------------------------------------------------------------------
PROMPT <div class="section"><h2>[5/6] Checking the plan in V\$SQL_PLAN</h2>
PROMPT <pre>

DECLARE
  n NUMBER;
BEGIN
  SELECT COUNT(*) INTO n
  FROM v\$sql_plan
  WHERE sql_id       = :v_sql_id
    AND child_number = :v_sql_child;

  IF n = 0 THEN
    DBMS_OUTPUT.PUT_LINE(
      'NOTE: No execution plan found in cache for SQL_ID='||:v_sql_id||
      ' (cursor evicted or never compiled).'
    );
  ELSE
    DBMS_OUTPUT.PUT_LINE(
      'Execution plan found in cache for SQL_ID=' || :v_sql_id
    );
  END IF;
END;
/
PROMPT </pre>
PROMPT </div>


-----------------------------------------------------------------------
--  [6/6]  EXECUTION PLAN  → COLLAPSIBLE + <pre>
-----------------------------------------------------------------------
PROMPT <div class="section"><h2>[6/6] EXECUTION PLAN (DBMS_XPLAN)</h2>
PROMPT <details open>
PROMPT   <summary>Show / Hide Execution Plan</summary>
PROMPT   <pre>

COLUMN PLAN_TABLE_OUTPUT FORMAT A32767
SET PAGESIZE 0

SELECT plan_table_output
FROM   TABLE(DBMS_XPLAN.DISPLAY_CURSOR(:v_sql_id, :v_sql_child, 'ALLSTATS LAST'));

SET PAGESIZE 500
PROMPT   </pre>
PROMPT </details>
PROMPT </div>


-----------------------------------------------------------------------
--  FOOTER
-----------------------------------------------------------------------
PROMPT <footer>Generated on $(date '+%Y-%m-%d %H:%M:%S') — diag_top_pid.sh</footer>

EOF

# Petit JS (copie SQL) — ajouté par Bash en fin de fichier
cat >> "${OUTFILE}" <<'HTML_TAIL'
<script>
function copySQL() {
  const el = document.getElementById('sqlblock');
  if (!el) { alert('SQL block not found.'); return; }
  const text = el.innerText;
  navigator.clipboard.writeText(text).then(
    ()=> alert('SQL copied to clipboard!'),
    ()=> alert('Failed to copy SQL.')
  );
}
</script>
</body></html>
HTML_TAIL

echo "Diagnostic finished → ${OUTFILE}"

# ======================================================================
#  MAIL — Envoi du fichier HTML généré en pièce jointe
# ======================================================================

RECIPIENTS="oracle-dba-team@example.local"
MAIL_FROM="oracle-monitor@example.local"
MAIL_SUBJECT="[Oracle] DIAG by PID ${PID} on ${HOST_N} @ ${RUN_DT}"
MAIL_BODY="Bonjour,\n\nVeuillez trouver ci-joint le diagnostic HTML généré.\n\nCordialement,\n L'équipe DBA GEMS."

send_with_mailx() {
  # Heirloom/s-nail mailx: -a <attach>; -s <subject>
  printf "%b" "${MAIL_BODY}" | mailx -r "${MAIL_FROM}" -s "${MAIL_SUBJECT}" -a "${OUTFILE}" "${RECIPIENTS}"
}

echo "Attempting to send email with attachment: ${OUTFILE}"
if command -v mailx >/dev/null 2>&1; then
  if send_with_mailx; then
    echo "Email sent with mailx to: ${RECIPIENTS}"
  else
    echo "WARNING: mailx failed to send the email." >&2
    exit 1
  fi
else
  echo "ERROR:  'mailx'  found; cannot send email." >&2
  echo "Generated file remains at: ${OUTFILE}"
  exit 1
fi
