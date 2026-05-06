[README.md](https://github.com/user-attachments/files/27431096/README.md)
# Oracle RMAN Backup to Azure Blob Storage

## 📌 Overview

This repository provides **two productiongrade Bash scripts** to manage **Oracle RMAN backups** and store them securely in **Azure Blob Storage** using **AzCopy with Managed Identity**.

The solution covers:
- **Full & Incremental database backups**
- **Frequent archivelog backups**
- **Retentionbased container routing**
- **Execution locking**
- **Recovery Catalog support**
- **Automatic purge after successful upload**

> ⚠️ This repository contains an **anonymized version** of real production scripts.  
> All names, credentials, paths, and identifiers are **placeholders only**.

---

## 📂 Repository Structure

```text
.
├── rman_backup_oracle_azure.sh        # FULL / INCR RMAN backups
├── rman_archlogs_azcopy.sh            # Archivelog RMAN backups
├── instances_backup_mapping.json.example
├── README.md
└── .gitignore
```

---

## 🧰 Scripts Overview

### 1️⃣ rman_backup_oracle_azure.sh

Performs **Oracle RMAN database backups**:
- Level 0 (FULL)
- Level 1 (INCREMENTAL)

Includes:
- PFILE generation from SPFILE
- Controlfile backup
- Database backup
- Archivelog backup
- Retention routing
- Azure upload
- Error handling & alerts

#### Usage

```bash
rman_backup_oracle_azure.sh <ORACLE_SID> <LEVEL:0|1>
    [--channels N]
    [--tag TAG]
    [--compress | --no-compress]
```

---

### 2️⃣ rman_archlogs_azcopy.sh

Backs up **Oracle archivelogs**, expected to run every **1015 minutes**.

#### Usage

```bash
rman_archlogs_azcopy.sh <ORACLE_SID>
    [--channels N]
    [--force-log-switch]
    [--catalog 'user/password@tns']
```

---

## 🗂 JSON Mapping

Both scripts rely on a JSON mapping file to resolve Azure containers based on retention policy.

```json
[
  {
    "instance_name": "CDBDEMO01",
    "daily_backup_container": "oracle-daily",
    "weekly_backup_container": "oracle-weekly",
    "monthly_backup_container": "oracle-monthly",
    "yearly_backup_container": "oracle-yearly"
  }
]
```

---

## 🕒 Scheduling Example

```cron
# Archivelogs every 15 minutes
*/15 * * * * rman_archlogs_azcopy.sh CDBDEMO01

# Weekly full backup
0 2 * * 0 rman_backup_oracle_azure.sh CDBDEMO01 0

# Daily incremental backup
0 2 * * 1-6 rman_backup_oracle_azure.sh CDBDEMO01 1
```

---

## ✅ Dependencies

- Oracle RMAN
- oraenv
- azcopy
- jq
- Bash ≥ 4

---

## 👤 Author

**Josselin Joly**  
Oracle DBA / Infrastructure

---

## 📄 License

Provided as-is for educational and operational reference.
