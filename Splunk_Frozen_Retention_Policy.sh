#!/bin/bash
# Splunk Frozen Retention Policy v1.1.0
# Enforces per-index frozen size (MB) and retention (oldest file age in days).

set -u

FROZEN_PATH="${FROZEN_PATH:-/frozen}"
LOG_FILE="${LOG_FILE:-/var/log/Splunk_Frozen_Data.log}"
CONFIG_FILE="${CONFIG_FILE:-/root/scripts/index_size.conf}"
LOCK_FILE="${LOCK_FILE:-/var/lock/Splunk_Frozen_Retention_Policy.lock}"

declare -A INDEX_SIZE_LIMITS
declare -A INDEX_RETENTION_DAYS
declare -A INDEX_ROOTS

generate_process_id() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex 3 | tr 'a-f' 'A-F'
    else
        printf '%04X%02X' "$RANDOM" "$((RANDOM % 256))"
    fi
}

kb_to_mb() {
    local kb="$1"
    if command -v bc >/dev/null 2>&1; then
        echo "scale=2; ${kb}/1024" | bc
    else
        awk -v kb="${kb}" 'BEGIN { printf "%.2f", kb/1024 }'
    fi
}

log_line() {
    echo "$1"
}

# Single-instance guard (timer overlap / manual re-run)
mkdir -p "$(dirname "$LOCK_FILE")" 2>/dev/null || true
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    CURR_DATE="$(date +%Y-%m-%dT%H:%M:%S%z)"
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    echo "timestamp=\"$CURR_DATE\",action=\"skipped_locked\",message=\"Another Splunk Frozen Retention Policy run is active\"" >>"$LOG_FILE"
    exit 0
fi

# Append logs; keep stderr visible in the same log
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
exec >>"$LOG_FILE" 2>&1

if [[ ! -f "$CONFIG_FILE" ]]; then
    CURR_DATE="$(date +%Y-%m-%dT%H:%M:%S%z)"
    log_line "timestamp=\"$CURR_DATE\",action=\"error\",message=\"Config file not found: $CONFIG_FILE\""
    exit 1
fi

if [[ ! -d "$FROZEN_PATH" ]]; then
    CURR_DATE="$(date +%Y-%m-%dT%H:%M:%S%z)"
    log_line "timestamp=\"$CURR_DATE\",action=\"error\",message=\"Frozen path not found: $FROZEN_PATH\""
    exit 1
fi

# Load config (skip blank lines and # comments)
while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%$'\r'}"
    [[ -z "${line//[[:space:]]/}" ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue

    IFS=, read -r key value retention <<<"$line"
    index=$(awk -F= '{print $2}' <<<"$key" | tr -d '[:space:]')
    size=$(awk -F= '{print $2}' <<<"$value" | tr -d '[:space:]')
    days=$(awk -F= '{print $2}' <<<"$retention" | tr -d '[:space:]')

    [[ -z "$index" || -z "$size" || -z "$days" ]] && continue
    [[ "$size" =~ ^[0-9]+$ && "$days" =~ ^[0-9]+$ ]] || continue

    INDEX_SIZE_LIMITS["$index"]=$size
    INDEX_RETENTION_DAYS["$index"]=$days
done <"$CONFIG_FILE"

refresh_index_metrics() {
    local dir="$1"
    FROZEN_SIZE_MB=$(du -cms "$dir" 2>/dev/null | awk '/total/ {print $1; exit}')
    FROZEN_SIZE_MB=${FROZEN_SIZE_MB:-0}

    EARLIEST_LOG_DATE=$(find "$dir" -type f -printf '%TY-%Tm-%Td\n' 2>/dev/null | sort | head -1)
    LATEST_LOG_DATE=$(find "$dir" -type f -printf '%TY-%Tm-%Td\n' 2>/dev/null | sort | tail -1)

    OLDEST_FILE_EPOCH=$(find "$dir" -type f -printf '%T@\n' 2>/dev/null | sort -n | head -1)
    if [[ -n "${OLDEST_FILE_EPOCH:-}" ]]; then
        OLDEST_AGE_DAYS=$(( ( $(date +%s) - ${OLDEST_FILE_EPOCH%.*} ) / (60 * 60 * 24) ))
        FILE_COUNT=$(find "$dir" -type f 2>/dev/null | wc -l)
    else
        OLDEST_AGE_DAYS=0
        FILE_COUNT=0
        EARLIEST_LOG_DATE=""
        LATEST_LOG_DATE=""
    fi
}

index_exceeds_limits() {
    local size_limit="$1"
    local retention_days="$2"
    [[ "$FROZEN_SIZE_MB" -gt "$size_limit" ]] && return 0
    [[ "$FILE_COUNT" -gt 0 && "$OLDEST_AGE_DAYS" -gt "$retention_days" ]] && return 0
    return 1
}

# Recursively remove empty non-index directories under an index root.
delete_empty_dirs() {
    local dir="${1%/}"
    local sub_dir

    for sub_dir in "$dir"/*; do
        if [[ -d "$sub_dir" ]]; then
            delete_empty_dirs "$sub_dir"
        fi
    done

    # Never remove top-level index directories themselves
    if [[ -n "${INDEX_ROOTS[$dir]+x}" ]]; then
        return 0
    fi

    if [[ -d "$dir" ]] && [[ -z "$(find "$dir" -mindepth 1 -maxdepth 1 2>/dev/null | head -1)" ]]; then
        if rmdir "$dir" 2>/dev/null; then
            CURR_DATE="$(date +%Y-%m-%dT%H:%M:%S%z)"
            log_line "timestamp=\"$CURR_DATE\",action=\"deleted_empty_dir\",deleted_dir=\"$dir\",message=\"Removed empty directory\""
        fi
    fi
}

cleanup_empty_folders() {
    local index_dir
    INDEX_ROOTS=()
    shopt -s nullglob
    for index_dir in "$FROZEN_PATH"/*; do
        if [[ -d "$index_dir" ]]; then
            INDEX_ROOTS["${index_dir%/}"]=1
        fi
    done
    for index_dir in "$FROZEN_PATH"/*; do
        if [[ -d "$index_dir" ]]; then
            delete_empty_dirs "$index_dir"
        fi
    done
    shopt -u nullglob
}

shopt -s nullglob
for _dir in "$FROZEN_PATH"/*/
do
    PROCESS_ID=$(generate_process_id)
    CURR_IDX=$(basename "${_dir%/}")

    if [[ -z "${INDEX_SIZE_LIMITS[$CURR_IDX]+x}" ]]; then
        refresh_index_metrics "$_dir"
        CURR_DATE="$(date +%Y-%m-%dT%H:%M:%S%z)"
        log_line "timestamp=\"$CURR_DATE\",process_id=\"$PROCESS_ID\",frozen_index=\"$CURR_IDX\",action=\"skipped_unconfigured\",final_frozen_size_mb=\"$FROZEN_SIZE_MB\",message=\"Index not defined in config; left unchanged\""
        continue
    fi

    SIZE_LIMIT=${INDEX_SIZE_LIMITS[$CURR_IDX]}
    RETENTION_DAYS=${INDEX_RETENTION_DAYS[$CURR_IDX]}

    refresh_index_metrics "$_dir"

    if index_exceeds_limits "$SIZE_LIMIT" "$RETENTION_DAYS"; then
        START_TIME=$(date +%s)
        REASON=""
        OVERAGES=""

        if [[ "$FROZEN_SIZE_MB" -gt "$SIZE_LIMIT" ]]; then
            SIZE_OVERAGE=$((FROZEN_SIZE_MB - SIZE_LIMIT))
            REASON="size_limit_exceeded"
            OVERAGES="overage_mb=$SIZE_OVERAGE"
        fi

        if [[ "$FILE_COUNT" -gt 0 && "$OLDEST_AGE_DAYS" -gt "$RETENTION_DAYS" ]]; then
            RETENTION_OVERAGE=$((OLDEST_AGE_DAYS - RETENTION_DAYS))
            if [[ -n "$REASON" ]]; then
                REASON="$REASON | retention_days_exceeded"
            else
                REASON="retention_days_exceeded"
            fi
            if [[ -n "$OVERAGES" ]]; then
                OVERAGES="$OVERAGES,overage_days=$RETENTION_OVERAGE"
            else
                OVERAGES="overage_days=$RETENTION_OVERAGE"
            fi
        fi

        CURR_DATE="$(date +%Y-%m-%dT%H:%M:%S%z)"
        log_line "timestamp=\"$CURR_DATE\",process_id=\"$PROCESS_ID\",frozen_index=\"$CURR_IDX\",action=\"exceeds_limit\",reason=\"$REASON\",$OVERAGES,exceeds_limit_frozen_size_mb=\"$FROZEN_SIZE_MB\",frozen_size_limit_mb=\"$SIZE_LIMIT\",current_frozen_days_with_logs=\"$OLDEST_AGE_DAYS\",frozen_retention_days=\"$RETENTION_DAYS\",message=\"Index exceeds defined limits\""

        DELETED_SIZE=0

        while index_exceeds_limits "$SIZE_LIMIT" "$RETENTION_DAYS"; do
            OLDEST_FILE=$(find "$_dir" -type f -printf '%T+ %p\n' 2>/dev/null | sort | head -1 | awk '{ $1=""; sub(/^ /,""); print }')
            if [[ -z "$OLDEST_FILE" || ! -f "$OLDEST_FILE" ]]; then
                CURR_DATE="$(date +%Y-%m-%dT%H:%M:%S%z)"
                log_line "timestamp=\"$CURR_DATE\",process_id=\"$PROCESS_ID\",frozen_index=\"$CURR_IDX\",action=\"delete_loop_stop\",message=\"No deletable files remain\""
                break
            fi

            FILE_SIZE=$(du -k "$OLDEST_FILE" 2>/dev/null | cut -f1)
            FILE_SIZE=${FILE_SIZE:-0}
            FILE_SIZE_MB=$(kb_to_mb "$FILE_SIZE")
            FILE_DATE=$(stat -c %Y "$OLDEST_FILE")
            FILE_AGE_DAYS=$(( ( $(date +%s) - FILE_DATE ) / (60 * 60 * 24) ))

            DELETED_REASON=""
            if [[ "$FROZEN_SIZE_MB" -gt "$SIZE_LIMIT" ]]; then
                SIZE_OVERAGE=$((FROZEN_SIZE_MB - SIZE_LIMIT))
                DELETED_REASON="reason=size_limit_exceeded,overage_mb=$SIZE_OVERAGE"
            elif [[ "$FILE_AGE_DAYS" -gt "$RETENTION_DAYS" ]]; then
                RETENTION_OVERAGE=$((FILE_AGE_DAYS - RETENTION_DAYS))
                DELETED_REASON="reason=retention_days_exceeded,overage_days=$RETENTION_OVERAGE"
            else
                # Should not happen; stop to avoid a tight loop
                break
            fi

            CURR_DATE="$(date +%Y-%m-%dT%H:%M:%S%z)"
            log_line "timestamp=\"$CURR_DATE\",process_id=\"$PROCESS_ID\",frozen_index=\"$CURR_IDX\",action=\"deleting_file\",deleted_file=\"$OLDEST_FILE\",deleted_file_size_mb=\"$FILE_SIZE_MB\",deleted_file_age_days=\"$FILE_AGE_DAYS\",$DELETED_REASON,message=\"Deleting file to comply with policy\""

            rm -f -- "$OLDEST_FILE"
            DELETED_SIZE=$((DELETED_SIZE + FILE_SIZE))
            refresh_index_metrics "$_dir"
        done

        END_TIME=$(date +%s)
        TIME_TAKEN=$((END_TIME - START_TIME))
        DELETED_SIZE_MB=$(kb_to_mb "$DELETED_SIZE")
        CURR_DATE="$(date +%Y-%m-%dT%H:%M:%S%z)"
        log_line "timestamp=\"$CURR_DATE\",process_id=\"$PROCESS_ID\",frozen_index=\"$CURR_IDX\",action=\"deletion_summary\",deleted_size_mb=\"$DELETED_SIZE_MB\",time_taken_sec=\"$TIME_TAKEN\",message=\"Total size deleted and time taken to bring index within limits\""
    fi

    CURR_DATE="$(date +%Y-%m-%dT%H:%M:%S%z)"
    if [[ -n "$EARLIEST_LOG_DATE" && -n "$LATEST_LOG_DATE" ]]; then
        log_line "timestamp=\"$CURR_DATE\",process_id=\"$PROCESS_ID\",frozen_index=\"$CURR_IDX\",action=\"final_summary\",earliest_log_date=\"$EARLIEST_LOG_DATE\",latest_log_date=\"$LATEST_LOG_DATE\",final_frozen_size_mb=\"$FROZEN_SIZE_MB\",current_frozen_days_with_logs=\"$OLDEST_AGE_DAYS\",message=\"Final summary after processing\""
    else
        log_line "timestamp=\"$CURR_DATE\",process_id=\"$PROCESS_ID\",frozen_index=\"$CURR_IDX\",action=\"final_summary\",final_frozen_size_mb=\"$FROZEN_SIZE_MB\",current_frozen_days_with_logs=\"$OLDEST_AGE_DAYS\",message=\"Final summary after processing\""
    fi
done
shopt -u nullglob

cleanup_empty_folders
CURR_DATE="$(date +%Y-%m-%dT%H:%M:%S%z)"
log_line "timestamp=\"$CURR_DATE\",action=\"empty_folder_cleanup_done\",message=\"Empty non-index directories cleaned\""
