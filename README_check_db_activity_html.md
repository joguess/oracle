# Oracle Database Activity HTML Report

## Script: `check_db_activity_html.sh`

## Overview

`check_db_activity_html.sh` is a **Bash script for Oracle DBAs** that generates a **multi-instance Oracle database activity snapshot** as a **self-contained HTML report**, with optional email delivery.

The script connects locally to one or more Oracle instances using SYSDBA privileges, collects key runtime and performance indicators, and renders the results in a clean, readable **HTML report with Dark / Light mode support**.

It is designed for quick diagnostics, operational checks, and incident analysis on servers hosting one or more Oracle databases.

---

## Key Features

- Multi-instance support (auto-detection via PMON or explicit SID list)
- Single consolidated HTML report for all instances
- Dark / Light theme toggle (client-side, browser-based)
- Human-readable layout with sections and cards
- Partial failure tolerant (one failing SID does not stop the report)
- Optional email delivery with the HTML report attached
- No external dependencies beyond standard Oracle tools

---

## Usage

```bash
check_db_activity_html.sh [ORACLE_SID ...]
```

### Examples

```bash
# Auto-detect all running Oracle instances on the host
./check_db_activity_html.sh

# Generate a report for specific instances only
./check_db_activity_html.sh CDB01 CDB02
```

If no SID is provided, the script automatically detects running Oracle instances using `ora_pmon_*` processes.

---

## Collected Information

For each Oracle SID, the HTML report includes:

### 1. Instance / Database State
- Instance name
- Host name
- Instance status
- Database role (PRIMARY / STANDBY)
- Open mode

### 2. Sessions Overview
- Number of active user sessions (non-background)
- Blocking locks vs waiting locks

### 3. Top Active Sessions
- Top 3 active user sessions (based on `LAST_CALL_ET`)
- SID / SERIAL#
- Username
- Client machine
- Program
- SQL_ID
- Current wait event and state

### 4. Wait Classes Snapshot
- Distribution of active sessions by wait class

### 5. Data Guard Statistics (if applicable)
- Transport lag
- Apply lag
- Apply finish time

If the database is PRIMARY or Data Guard is not configured, a note is displayed instead.

### 6. Long Operations
- Top 5 ongoing long operations
- Completion percentage
- Elapsed and remaining time

---

## How It Works

1. Performs prerequisite checks (`sqlplus`, `oraenv`, `/etc/oratab`)
2. Builds the list of Oracle SIDs (arguments or PMON auto-detection)
3. Iterates over each SID:
   - Loads the Oracle environment with `oraenv`
   - Verifies SYSDBA connectivity
   - Executes predefined diagnostic SQL queries
4. Escapes SQL output for safe HTML rendering
5. Generates a single themed HTML report
6. Optionally sends the report via email

---

## Output

The script produces a file similar to:

```text
db_activity_<HOST>_YYYY-MM-DD_HH-MM-SS.html
```

Characteristics:
- Fully self-contained (embedded CSS and JavaScript)
- Can be opened locally in any modern web browser
- Theme preference stored in browser local storage

---

## Exit Codes

| Code | Description |
|---|---|
| `0` | Report generated successfully |
| `1` | Partial failure (one or more SIDs failed) |
| `2` | Fatal error (script could not run) |

---

## Dependencies

- Bash ≥ 4
- Oracle Client or Server installation
- `sqlplus`
- `oraenv`
- Read access to `/etc/oratab`
- Standard Unix tools (`ps`, `awk`, `sed`)
- `mailx` (optional, for email delivery)

---

## Security Considerations

- No credentials are stored in the script
- Uses local `/ as sysdba` authentication
- The generated HTML report may contain sensitive operational data
- Handle generated files and email distribution appropriately

---

## Typical Use Cases

- Daily DBA activity snapshots
- Rapid situation awareness during incidents
- Pre- and post-maintenance checks
- Lightweight alternative to full monitoring platforms
- Sharing readable status reports within DBA teams

---

## Author

**Josselin Joly**  
Oracle DBA / Infrastructure

---

## License

Provided **as-is** for educational and operational reference.  
Test and adapt before using in production environments.
