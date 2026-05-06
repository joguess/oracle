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
