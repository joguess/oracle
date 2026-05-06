# Description   :
#   Script de sauvegarde RMAN Oracle (FULL Level 0 / INCR Level 1) avec :
#     - génération du PFILE depuis le SPFILE
#     - sauvegarde Controlfile, Database, ARCHIVELOG
#     - gestion du TAG RMAN automatique
#     - compression optionnelle des backups
#     - exécution avec Recovery Catalog
#     - upload des fichiers de sauvegarde vers Azure Blob Storage (AzCopy)
#     - gestion de la rétention (Daily / Weekly / Monthly / Yearly)
#     - verrouillage d’exécution (lock file)
#     - contrôle d’erreurs et alertes email
#
# Utilisation   :
#   rman_backup_oracle_azure.sh <ORACLE_SID> <LEVEL:0|1>
#       [--channels N]
#       [--tag TAG]
#       [--compress | --no-compress]
#
# Paramètres    :
#   ORACLE_SID  : Instance Oracle à sauvegarder
#   LEVEL       : 0 = sauvegarde complète (FULL)
#                 1 = sauvegarde incrémentale
#
# Prérequis    :
#   - Oracle RMAN installé et configuré
#   - Recovery Catalog accessible
#   - AzCopy installé et fonctionnel (Managed Identity)
#   - jq installé
#   - Fichier JSON de mapping instances / containers Azure
#   - Variables Oracle configurables via oraenv
#
# Environnement :
#   - Linux
#   - Oracle Multitenant (CDB/PDB)
