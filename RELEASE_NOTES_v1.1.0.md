# Splunk Frozen Retention Policy Scripts v1.1.0

Bug fix release for frozen path size and retention enforcement.

## Highlights

- Retention now uses oldest file age (days) versus `retention`, not earliest↔latest span.
- Indexes missing from `index_size.conf` are skipped and logged (`skipped_unconfigured`).
- Logs append across runs; stderr is no longer discarded.
- Empty indexes and missing files no longer break the delete loop.
- systemd installer uses `Type=oneshot` and enables the timer only; main script uses `flock`.
- Empty-folder cleanup is built into `Splunk_Frozen_Retention_Policy.sh` (no separate `Delete_Empty_Folder.sh`).

See `CHANGELOG.md` for the full list.
