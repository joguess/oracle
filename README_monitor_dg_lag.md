# Monitor Oracle Data Guard Apply Lag

## Overview

`monitor_dg_lag.sh` is a Bash monitoring script designed to check **Oracle Data Guard apply lag** from the **PRIMARY database**, based on archive log sequence numbers.

The script compares:
- the latest archived redo log sequence on the PRIMARY
- the latest applied redo log sequence on the STANDBY

If the lag exceeds a configurable threshold, an email alert is sent.

> This repository contains an **anonymized version** of a real production script. All identifiers and email addresses are placeholders.

---

## Features

- Checks Data Guard apply lag using `v$archived_log`
- Runs from the PRIMARY database only
- Validates Oracle SID existence
- Configurable lag threshold
- Email alerting
- Syslog logging via `logger`
- Safe numeric validation
- Lightweight (sqlplus only)

---

## Usage

> **Usage is kept identical to the original script**

```bash
monitor_dg_lag.sh -sid ORACLE_SID [-t SEUIL]
```

### Options

| Option | Description |
|------|-------------|
| `-sid` | Oracle SID to monitor (mandatory) |
| `-t` | Lag threshold in archive sequences (default: 50) |
| `-h`, `--help` | Display help |

### Examples

```bash
# Default threshold (50)
monitor_dg_lag.sh -sid CDBDEMO01

# Custom threshold
monitor_dg_lag.sh -sid CDBDEMO01 -t 100
```

---

## How It Works

1. Validates command-line parameters
2. Checks that the Oracle SID exists (oratab, spfile/init, PMON)
3. Loads Oracle environment with `oraenv`
4. Executes SQL query on PRIMARY database
5. Computes Data Guard lag
6. Logs execution details
7. Sends alert email if threshold is exceeded

---

## SQL Logic

```sql
SELECT
  MAX(sequence#) FROM v$archived_log WHERE DEST_ID=1 AND ARCHIVED='YES',
  MAX(sequence#) FROM v$archived_log WHERE DEST_ID=2 AND APPLIED='YES';
```

Variables:
- `DEST_ID=1`: PRIMARY archive destination
- `DEST_ID=2`: STANDBY destination

---

## Alerting

When the lag exceeds the threshold, an email alert includes:
- Hostname
- Oracle SID
- Timestamp
- Primary archived sequence
- Standby applied sequence
- Current lag
- Threshold

Example subject:
```
[ALERT][DG] CDBDEMO01 — Lag=120
```

---

## Dependencies

- Oracle Database (PRIMARY)
- `sqlplus`
- `oraenv`
- `mailx` or `mail`
- `logger` (syslog)
- Bash ≥ 4

---

## Recommended Scheduling

```cron
*/5 * * * * /path/monitor_dg_lag.sh -sid CDBDEMO01
```

---

## Security Notes

- Uses local `/ as sysdba` authentication
- No credentials stored in the script
- Suitable for public repositories

---

## Author

**Josselin Joly**  
Oracle DBA / Infrastructure

---

## License

Provided as-is for educational and operational reference. Test before production use.
