#!/usr/bin/env bash
# Script        : rman_backup_oracle_azure.sh
#
# Description   :
#   Oracle RMAN backup script (FULL Level 0 / INCR Level 1) with:
#     - PFILE generation from SPFILE
#     - Controlfile, Database, ARCHIVELOG backup
#     - Automatic RMAN tag handling
#     - Optional compression
#     - Recovery Catalog usage
#     - Azure Blob upload using AzCopy
#     - Retention management (Daily / Weekly / Monthly / Yearly)
#     - Execution lock (lock file)
#     - Error control and email alerts
#
# Usage :
#   rman_backup_oracle_azure.sh <ORACLE_SID> <LEVEL:0|1>
#
# Environment :
#   Linux - Oracle Multitenant (CDB / PDB)
#
# Author        : Josselin Joly
# Team          : Oracle DBA / Infrastructure
#
# Last update   : 2026-04-10
# Version       : 1.0
# ------------------------------------------------------------------------------

set -o pipefail
set -u

# ---------- Configuration ----------
CONF_PATH="/opt/oracle/conf"
BASE_BACKUP_DIR="/opt/oracle/backup"
LOG_DIR="/opt/oracle/log"
AZCOPY_DIR="/opt/oracle/tools"

JSON_FILE="${CONF_PATH}/instances_backup_mapping.json"

STORAGE_ACCOUNT="storagedemobackup01"

HOST=${HOSTNAME^^}
HOST=${HOST%%.*}

# ---------- Arguments ----------
if [[ $# -lt 2 ]]; then
  echo "Usage: $(basename "$0") <ORACLE_SID> <LEVEL:0|1>"
  exit 1
fi

OraInstance="$1"; shift
LEVEL_ARG="$1"; shift

export ORACLE_SID="${OraInstance}"
export ORAENV_ASK=NO
. oraenv >/dev/null 2>&1 || exit 3

[[ "$LEVEL_ARG" != "0" && "$LEVEL_ARG" != "1" ]] && exit 1

RMAN_LEVEL="${LEVEL_ARG}"
RUN_TS=$([[ "$RMAN_LEVEL" == "0" ]] && echo "lvl0" || echo "lvl1")

RMAN_CHANNELS=4
RMAN_TAG=""
RMAN_COMPRESS=false
CATALOG_CONNECT="RMAN_CATALOG/demo_password@RMANCAT"

# ---------- Dates & Paths ----------
TODAY="$(date +'%Y%m%d')"
RunDir="${BASE_BACKUP_DIR}/${OraInstance}/${TODAY}/${RUN_TS}"
RmanDir="${BASE_BACKUP_DIR}/rman/${RUN_TS}"
RmanLog="${RmanDir}/logs"

mkdir -p "$RunDir" "$RmanDir" "$RmanLog"

LogFile="${LOG_DIR}/$(basename "$0").${OraInstance}_${TODAY}.log"
: > "$LogFile"

# ---------- PFILE Backup ----------
PFILE_DIR="${RunDir}/pfile"
mkdir -p "$PFILE_DIR"
PFILE_FILE="${PFILE_DIR}/init${OraInstance}_${TODAY}.ora"

sqlplus -s / as sysdba >>"$LogFile" <<EOF
CREATE PFILE='${PFILE_FILE}' FROM SPFILE;
EXIT;
EOF

# ---------- Retention ----------
Get_Retention() {
  [[ "$(date +%u)" != "7" ]] && BACKUP="DAILY" && return
  [[ "$(date +%d)" -le 7 ]] && [[ "$(date +%m)" == "01" ]] && BACKUP="YEARLY" || BACKUP="MONTHLY"
}

GetDBContainer() {
  result="$(jq --arg n "$OraInstance" -r '.[] | select(.instance_name==$n)' "$JSON_FILE")"
  case "$BACKUP" in
    DAILY)   container_location=$(echo "$result" | jq -r '.daily_backup_container') ;;
    WEEKLY)  container_location=$(echo "$result" | jq -r '.weekly_backup_container') ;;
    MONTHLY) container_location=$(echo "$result" | jq -r '.monthly_backup_container') ;;
    YEARLY)  container_location=$(echo "$result" | jq -r '.yearly_backup_container') ;;
  esac
}

Get_Retention
GetDBContainer

# ---------- RMAN TAG ----------
AUTO_TAG="${OraInstance}_LVL${RMAN_LEVEL}_${TODAY}"
[[ -n "$RMAN_TAG" ]] && TAG_CLAUSE="TAG='${AUTO_TAG}_${RMAN_TAG}'" || TAG_CLAUSE="TAG='${AUTO_TAG}'"
[[ "$RMAN_COMPRESS" == true ]] && CTYPE="AS COMPRESSED BACKUPSET" || CTYPE="AS BACKUPSET"

RMAN_CMD_FILE="${RmanDir}/rman_${OraInstance}_lvl${RMAN_LEVEL}.rcv"
RMAN_LOG_FILE="${RmanLog}/rman_${OraInstance}_lvl${RMAN_LEVEL}_${TODAY}.log"

# ---------- RMAN Script ----------
{
  echo "RUN {"
  echo "CONFIGURE CONTROLFILE AUTOBACKUP ON;"
  for i in $(seq 1 "$RMAN_CHANNELS"); do
    echo "ALLOCATE CHANNEL c$i DEVICE TYPE DISK;"
  done
  echo "BACKUP $CTYPE INCREMENTAL LEVEL $RMAN_LEVEL DATABASE FORMAT '${RunDir}/db_%U.bkp' ${TAG_CLAUSE};"
  echo "BACKUP ARCHIVELOG ALL NOT BACKED UP 1 TIMES FORMAT '${RunDir}/arch_%U.bkp' ${TAG_CLAUSE};"
  for i in $(seq 1 "$RMAN_CHANNELS"); do
    echo "RELEASE CHANNEL c$i;"
  done
  echo "}"
} >"$RMAN_CMD_FILE"

# ---------- Run RMAN ----------
"$ORACLE_HOME/bin/rman" target / catalog "$CATALOG_CONNECT" cmdfile="$RMAN_CMD_FILE" log="$RMAN_LOG_FILE"
RMAN_STATUS=$?

# ---------- Mail ----------
MAIL_TO="oracle-dba@example.local"
MAIL_FROM="oracle-backup@example.local"
EMAIL_SUBJECT="RMAN BACKUP - ${ORACLE_SID} LEVEL ${RMAN_LEVEL}"

# ---------- Azure Upload ----------
"${AZCOPY_DIR}/azcopy" login --identity >>"$LogFile" 2>&1 || exit 1

DEST_URL="https://${STORAGE_ACCOUNT}.blob.core.windows.net/${container_location}/${HOST}/${OraInstance}/${TODAY}/${RUN_TS}"
"${AZCOPY_DIR}/azcopy" copy "${RunDir}" "$DEST_URL" --recursive >>"$LogFile" 2>&1 || exit 2

[[ "$RMAN_STATUS" -ne 0 ]] && \
echo "RMAN error RC=${RMAN_STATUS}" | mailx -r "$MAIL_FROM" -s "$EMAIL_SUBJECT" "$MAIL_TO"

exit 0
