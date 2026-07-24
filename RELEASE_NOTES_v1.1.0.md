# Splunk Frozen Retention Policy Scripts v1.1.0

Bug fix and hardening release. **Install this version** (`Splunk_Frozen_Retention_Policy_Scripts_v1.1.0.tar.gz`), not the older `v1.0.0` / tag `Splunk` package.

## Highlights

- Retention now uses oldest file age (days) versus `retention`, not earliest↔latest span.
- Indexes missing from `index_size.conf` are skipped and logged (`skipped_unconfigured`).
- Logs append across runs; stderr is no longer discarded.
- Empty indexes and missing files no longer break the delete loop.
- systemd installer uses `Type=oneshot` and enables the timer only; main script uses `flock`.
- Empty-folder cleanup is built into `Splunk_Frozen_Retention_Policy.sh` (no separate `Delete_Empty_Folder.sh`).
- Unified `TEST.sh`: default assert suite; `--sample` / `--run` for mock data (replaces `run_real_tests.sh`).
- Delete loop stops on `rm` failure (`delete_failed`) to avoid spinning.

See `CHANGELOG.md` and the Installation / Testing sections in `README.md`.
