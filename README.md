# Splunk Frozen Bucket (Path) Data Management Scripts

Bash scripts to enforce size and retention limits on Splunk frozen bucket paths, then remove leftover empty directories.

| Item | Value |
| --- | --- |
| **Latest release** | **v1.1.0** |
| **Release package** | `Splunk_Frozen_Retention_Policy_Scripts_v1.1.0.tar.gz` |
| **Release URL** | https://github.com/Mohammad-Mirasadollahi/Splunk-Frozen-Retention-Policy/releases/tag/v1.1.0 |
| **Changelog** | [CHANGELOG.md](CHANGELOG.md) |

**Note:** These scripts were developed with the help of ChatGPT and have been tested successfully with terabytes (TB) of data.

---

## Package contents (v1.1.0)

| File | Purpose |
| --- | --- |
| `Splunk_Frozen_Retention_Policy.sh` | Main policy: size + retention + empty-dir cleanup |
| `Splunk_Frozen_Policy_service.sh` | Installs systemd oneshot service + 24h timer |
| `index_size.conf` | Per-index size (MB) and retention (days) |
| `TEST.sh` | Optional helper to generate sample frozen test data |
| `run_real_tests.sh` | Recommended real feature test suite (mock data) |
| `CHANGELOG.md` / `RELEASE_NOTES_v1.1.0.md` | Release notes |

`Delete_Empty_Folder.sh` was **removed in v1.1.0** (logic merged into the main script).

---

## Overview

1. **Frozen path monitoring** — Scan each index directory under `FROZEN_PATH`.
2. **Overage detection** — Compare size (MB) and oldest-file age (days) to `index_size.conf`.
3. **Delete oldest files first** — Until size and retention are within limits.
4. **Logging** — Append structured events to the log file.
5. **Empty directory cleanup** — After all indexes, remove empty non-index directories (index roots are kept).
6. **Skip unconfigured indexes** — Directories not listed in `index_size.conf` are left unchanged (`skipped_unconfigured`).

---

## Configuration: `index_size.conf`

Each non-comment line:

```
index=index1,size=5000,retention=30
index=index2,size=7000,retention=45
index=index3,size=6000,retention=60
```

Blank lines and lines starting with `#` are ignored.

| Field | Meaning |
| --- | --- |
| `index` | Directory name under `FROZEN_PATH` |
| `size` | Max frozen size in **MB** |
| `retention` | Max age in **days** of any file (mtime vs now). Oldest files are deleted until the oldest remaining file is within this window |

If an index directory exists but is missing from the config, it is **not** modified; only a skip log line is written.

---

## Variables (optional)

Edit near the top of `Splunk_Frozen_Retention_Policy.sh` (or export before run):

| Variable | Default | Meaning |
| --- | --- | --- |
| `FROZEN_PATH` | `/frozen` | Frozen data root |
| `LOG_FILE` | `/var/log/Splunk_Frozen_Data.log` | Append-only log |
| `CONFIG_FILE` | `/root/scripts/index_size.conf` | Limits config |
| `LOCK_FILE` | `/var/lock/Splunk_Frozen_Retention_Policy.lock` | Prevent overlapping runs |

Installer script:

| Variable | Default |
| --- | --- |
| `SCRIPT_PATH` | `/root/scripts/Splunk_Frozen_Retention_Policy.sh` |

---

## Installation (v1.1.0) — Quick Start

Use the **v1.1.0** package (not the old `v1.0.0` / tag `Splunk` asset).

### 1. Download

```bash
wget https://github.com/Mohammad-Mirasadollahi/Splunk-Frozen-Retention-Policy/releases/download/v1.1.0/Splunk_Frozen_Retention_Policy_Scripts_v1.1.0.tar.gz
```

### 2. Install into `/root/scripts`

```bash
mkdir -p /root/scripts
mv Splunk_Frozen_Retention_Policy_Scripts_v1.1.0.tar.gz /root/scripts/
cd /root/scripts/
tar xzvf Splunk_Frozen_Retention_Policy_Scripts_v1.1.0.tar.gz
rm -f Splunk_Frozen_Retention_Policy_Scripts_v1.1.0.tar.gz
chmod 750 Splunk_Frozen_Retention_Policy.sh Splunk_Frozen_Policy_service.sh
```

### 3. Edit configuration

```bash
vi /root/scripts/index_size.conf
```

Align `FROZEN_PATH` / `CONFIG_FILE` / `LOG_FILE` in `Splunk_Frozen_Retention_Policy.sh` with your environment if they differ from the defaults.

### 4. Install and start the systemd timer

```bash
bash ./Splunk_Frozen_Policy_service.sh
```

### 5. Verify

```bash
systemctl status Splunk_Frozen_Policy.timer
systemctl list-timers | grep Splunk_Frozen
```

The installer creates a **Type=oneshot** service and enables **only** `Splunk_Frozen_Policy.timer` (every 24 hours by default). To change the interval:

```bash
vi /etc/systemd/system/Splunk_Frozen_Policy.timer   # edit OnUnitActiveSec
systemctl daemon-reload
systemctl restart Splunk_Frozen_Policy.timer
```

### Manual one-shot run (without waiting for the timer)

```bash
bash /root/scripts/Splunk_Frozen_Retention_Policy.sh
tail -n 50 /var/log/Splunk_Frozen_Data.log
```

---

## Upgrade from v1.0.0

1. Stop/disable the old timer if present: `systemctl stop Splunk_Frozen_Policy.timer` (optional).
2. Install the **v1.1.0** tarball into `/root/scripts` (overwrite scripts).
3. Remove obsolete `Delete_Empty_Folder.sh` if it is still on disk (no longer used).
4. Re-run `bash ./Splunk_Frozen_Policy_service.sh` so the oneshot + timer-only unit files are refreshed.
5. Confirm logs append (history is no longer truncated each run).

---

## Logging

Logs are **appended** to `LOG_FILE`.

### Exceeds limits

```
timestamp="2024-08-28T15:34:20+00:00",process_id="1a2b3c",frozen_index="index1",action="exceeds_limit",reason="size_limit_exceeded",overage_mb=1500,exceeds_limit_frozen_size_mb="6500",frozen_size_limit_mb="5000",current_frozen_days_with_logs="20",frozen_retention_days="30",message="Index exceeds defined limits"
```

`current_frozen_days_with_logs` = age in days of the **oldest** file (mtime vs now).

### Deleting a file

```
timestamp="...",process_id="...",frozen_index="index1",action="deleting_file",deleted_file="...",deleted_file_size_mb="...",deleted_file_age_days="...",reason=size_limit_exceeded,overage_mb=...,message="Deleting file to comply with policy"
```

### Deletion summary / final summary

Emitted after cleanup for an index (`deletion_summary` when deletions happened; `final_summary` always for configured indexes).

### Skipped unconfigured index

```
timestamp="...",process_id="...",frozen_index="other_index",action="skipped_unconfigured",final_frozen_size_mb="120",message="Index not defined in config; left unchanged"
```

Other actions: `deleted_empty_dir`, `empty_folder_cleanup_done`, `skipped_locked`.

---

## Testing

### Real feature tests (recommended)

Builds verified mock data, validates fixtures first, then asserts each feature:

```bash
bash ./run_real_tests.sh
```

### Legacy sample data helper

`TEST.sh` can create sample files under `/tmp/frozen_test` for manual experiments. Adjust paths inside the script as needed.

---

## Requirements

- Linux with `bash`, `find`, `du`, `flock`, `stat`
- `openssl` and `bc` optional (fallbacks included)
- root (or equivalent) for default paths and systemd install
