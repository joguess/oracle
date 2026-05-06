# Oracle Diagnostic by Top CPU PID (diag_top_pid.sh)

## Overview

`diag_top_pid.sh` is an advanced **Oracle diagnostic Bash script** designed to help DBAs quickly investigate performance issues starting from the **operating system process consuming the most CPU**.

The script correlates Linux process information with Oracle internal views to identify:
- The Oracle session behind a CPU‑intensive PID
- The SQL statement currently executed
- CPU usage and wait events
- The execution plan with runtime statistics

It produces a **self‑contained HTML diagnostic report** with a **dark‑mode layout**, suitable for sharing and post‑mortem analysis.

---

## Key Features

- Automatic detection of the **top CPU‑consuming OS process**
- Optional manual PID selection
- Automatic detection of `ORACLE_SID` from process name
- PID → Oracle process → session → SQL correlation
- Detailed session diagnostics:
  - SID / SERIAL# / CON_ID
  - CPU usage per session
  - Wait events (color‑coded by wait class)
  - SQL text (collapsible, copy‑to‑clipboard)
  - Execution plan (`DBMS_XPLAN.DISPLAY_CURSOR`, `ALLSTATS LAST`)
- Graceful handling of background jobs (J000 / Scheduler)
- HTML output with OEM‑like dark theme
- Optional email delivery of the diagnostic report

---

## Usage

```bash
./diag_top_pid.sh
./diag_top_pid.sh -p <PID>
./diag_top_pid.sh -c "/ as sysdba" -o /path/to/output
```

### Options

| Option | Description |
|------|-------------|
| `-p <PID>` | Force diagnostic on a specific OS PID |
| `-c <connect>` | SQL*Plus connection string (default: `/ as sysdba`) |
| `-o <outdir>` | Output directory for the generated HTML report |
| `-h`, `--help` | Display help |

---

## How It Works

1. Retrieves the **top 20 CPU‑consuming processes** using `ps`
2. Automatically selects the highest CPU process unless a PID is provided
3. Attempts to detect the Oracle SID from process naming conventions
4. Executes **a single SQL*Plus session** to gather all diagnostics
5. Generates a structured HTML report directly from SQL and shell output
6. Optionally sends the report by email as an attachment

---

## Generated HTML Report

The generated report contains the following sections:

1. Top CPU OS processes snapshot
2. PID to Oracle SID/CON_ID mapping
3. Oracle session details and SQL_ID
4. CPU usage by session
5. Active waits (auto‑colored by wait class)
6. Full SQL text (collapsible with copy button)
7. Execution plan and runtime statistics

The report is **standalone** and can be opened locally in any web browser.

---

## Dependencies

- Bash (version ≥ 4)
- Standard Linux utilities: `ps`, `awk`, `grep`, `sed`
- Oracle environment with:
  - `sqlplus`
  - Access to `v$session`, `v$process`, `v$sql`, `v$sqlarea`, `v$sql_plan`
- `mailx` (optional, for email delivery)

---

## Typical Use Cases

- Diagnosing sudden **CPU spikes** on Oracle servers
- Identifying runaway or poorly performing SQL statements
- Investigating Scheduler or background jobs
- Supporting live incident analysis (P1 / P2 situations)
- Producing clear diagnostics for DBA teams or Oracle Support

---

## Notes and Limitations

- Must be run on the **same host where the PID exists** (important for RAC)
- Execution plan is shown only if the cursor is still present in memory
- Requires sufficient privileges to access dynamic performance views

---

## Security Considerations

- No credentials are stored in the script
- Uses local SQL*Plus authentication
- The generated HTML may contain sensitive SQL or object names — handle accordingly

---

## Author

**Josselin Joly**  
Oracle DBA / Infrastructure

---

## License

Provided **as‑is** for operational and educational purposes.  
Test and adapt before using in production.
