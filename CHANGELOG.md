# Changelog

## v1.1.0

### Bug fixes

1. **Retention used date span, not age** — The policy compared earliest↔latest file mtime span to `retention`. Indexes whose files were all old but spanned few days were never cleaned. Retention now uses the oldest file age in days versus `retention`, matching the README.
2. **Unconfigured indexes were not skipped** — Indexes missing from `index_size.conf` still entered numeric comparisons with empty limits (silent `[` errors because stderr was discarded). They are now logged as `skipped_unconfigured` and left unchanged.
3. **Stderr discarded** — `exec 2>/dev/null` hid failures. Stderr is appended to the same log file.
4. **Log overwritten each run** — `exec > "$LOG_FILE"` truncated history. Logs are appended.
5. **Empty / no-file directories** — Empty date strings fed `date -d` and the delete loop. Empty indexes are handled without crashing; the delete loop stops when no files remain.
6. **Brittle delete loop** — Missing `OLDEST_FILE` could still call `rm`/`du`. The loop now validates the path and exits cleanly. If `rm` fails or the path remains, the loop logs `delete_failed` and stops (avoids spinning).
7. **systemd double-start / wrong unit type** — The installer enabled both a multi-user `.service` and a `.timer`, and the service was not `Type=oneshot`. Installer now writes an oneshot service, enables the timer only, and the main script uses `flock` against overlapping runs.

### Other

- Safer `index_size.conf` parsing (blank lines and `#` comments).
- Fallbacks when `openssl` or `bc` are unavailable.
- Quick Start updated for the `v1.1.0` release asset.
- **Merged empty-folder cleanup into the main retention script** — empty non-index directories are cleaned in-process; the separate helper and `index_list.txt` are removed.
- Added `run_real_tests.sh` for verified mock fixtures and per-feature real assertions.
