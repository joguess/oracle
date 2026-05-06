#!/usr/bin/env bash
# Monitor Data Guard apply lag (by sequences) from the PRIMARY.
# Usage : monitor_dg_lag.sh -sid CDBDEMO01 -t 100
# Autor : Josselin Joly

set -uo pipefail

# -------- Defaults --------
THRESHOLD=50
DEST_PRIMARY=1
DEST_STANDBY=2

RECIPIENTS="oracle-dba-team@example.local"

MAIL_FROM="oracle-monitor@example.local"
MAIL_SUBJECT_PREFIX="[ALERT][DG]"

ORACLE_SID=""
HOSTNAME_FQDN="$(hostname -f 2>/dev/null || hostname)"
LOG_TAG="monitor_dg_lag"

usage() {
  cat <<EOF
Usage: $0 -sid ORACLE_SID [-t SEUIL]

  -sid  SID Oracle (ex: CDBPRD04)                 [OBLIGATOIRE]
  -t    Seuil du lag (en séquences, défaut: 50)

Exemple :
  $0 -sid CDBPRD04 -t 100
EOF
  exit 1
}

log_info()  { logger -t "${LOG_TAG}" "INFO: $*";  echo "INFO: $*"; }
log_warn()  { logger -t "${LOG_TAG}" "WARN: $*";  echo "WARN: $*" >&2; }
log_error() { logger -t "${LOG_TAG}" "ERROR: $*"; echo "ERROR: $*" >&2; }

# -------- Parse options --------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -sid)
      ORACLE_SID="$2"
      shift 2
      ;;
    -t)
      THRESHOLD="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      usage
      ;;
  esac
done

# -------- Required --------
[ -z "${ORACLE_SID}" ] && usage

# Validate numeric threshold
case "$THRESHOLD" in ''|*[!0-9]*) log_error "Le seuil (-t) doit être un entier."; exit 2 ;; esac

# -------- SID existence checks --------
SID_EXISTS=false

if [[ -f /etc/oratab ]] && grep -E "^${ORACLE_SID}:" /etc/oratab >/dev/null 2>&1; then
  SID_EXISTS=true
fi

if [[ -d "${ORACLE_HOME:-}" ]]; then
  [[ -f "${ORACLE_HOME}/dbs/init${ORACLE_SID}.ora" ]] && SID_EXISTS=true
  [[ -f "${ORACLE_HOME}/dbs/spfile${ORACLE_SID}.ora" ]] && SID_EXISTS=true
fi

if ps -ef | grep -v grep | grep -q "[p]mon_${ORACLE_SID}"; then
  SID_EXISTS=true
fi

if [[ "${SID_EXISTS}" = false ]]; then
  log_error "Le SID '${ORACLE_SID}' n'existe pas sur ce serveur."
  exit 99
fi

# -------- Load Oracle environment --------
command -v oraenv >/dev/null 2>&1 || {
  [[ -f /usr/local/bin/oraenv ]] && PATH="/usr/local/bin:$PATH"
  [[ -f /usr/bin/oraenv ]]       && PATH="/usr/bin:$PATH"
}

export ORACLE_SID
export ORAENV_ASK=NO
. oraenv >/dev/null 2>&1 || { log_error "Chargement oraenv impossible"; exit 3; }

[[ ! -x "${ORACLE_HOME}/bin/sqlplus" ]] && {
  log_error "sqlplus introuvable (ORACLE_HOME=${ORACLE_HOME})"
  exit 3
}

# -------- Mail client --------
if command -v mailx >/dev/null 2>&1; then MAIL_BIN="mailx"
elif command -v mail >/dev/null 2>&1; then MAIL_BIN="mail"
else MAIL_BIN=""; fi

send_mail() {
  local subject="$1"
  local body="$2"

  [[ -z "$MAIL_BIN" ]] && { log_error "Pas de client mail"; return 1; }
  printf "%b" "$body" | $MAIL_BIN -r "$MAIL_FROM" -s "$subject" $(echo "$RECIPIENTS" | tr ',' ' ')
}

# -------- SQL --------
SQL_OUTPUT="$("${ORACLE_HOME}/bin/sqlplus" -s "/ as sysdba" <<EOF
set heading off feedback off pages 0 verify off echo off trimspool on
SELECT
  NVL((SELECT MAX(SEQUENCE#) FROM v\\$archived_log WHERE DEST_ID=${DEST_PRIMARY} AND ARCHIVED='YES'),0)
  || ',' ||
  NVL((SELECT MAX(SEQUENCE#) FROM v\\$archived_log WHERE DEST_ID=${DEST_STANDBY} AND APPLIED='YES'),0)
FROM dual;
EOF
)"

SQL_OUTPUT="$(echo "$SQL_OUTPUT" | tr -d '[:space:]')"
[[ "$SQL_OUTPUT" != *,* ]] && { log_error "Résultat SQL invalide: $SQL_OUTPUT"; exit 4; }

PRIMARY_SEQ="${SQL_OUTPUT%%,*}"
STANDBY_SEQ="${SQL_OUTPUT##*,}"

[[ "$PRIMARY_SEQ" =~ ^[0-9]+$ ]] || exit 4
[[ "$STANDBY_SEQ" =~ ^[0-9]+$ ]] || STANDBY_SEQ=0

LAG=$(( PRIMARY_SEQ - STANDBY_SEQ ))
(( LAG < 0 )) && LAG=0

TS="$(date '+%Y-%m-%d %H:%M:%S %Z')"
log_info "SID=${ORACLE_SID} Host=${HOSTNAME_FQDN} Primary=${PRIMARY_SEQ} Standby=${STANDBY_SEQ} Lag=${LAG}"

# -------- Alert --------
if (( LAG >= THRESHOLD )); then
  SUBJECT="${MAIL_SUBJECT_PREFIX} ${ORACLE_SID} — Lag=${LAG}"
  BODY=$(cat <<EOT
Data Guard Lag Alert
--------------------
Host       : ${HOSTNAME_FQDN}
SID        : ${ORACLE_SID}
Timestamp  : ${TS}

Primary seq: ${PRIMARY_SEQ}
Standby seq: ${STANDBY_SEQ}
Lag        : ${LAG}
Threshold  : ${THRESHOLD}
EOT
)

  send_mail "$SUBJECT" "$BODY" && log_warn "Alerte envoyée"
fi

exit 0
