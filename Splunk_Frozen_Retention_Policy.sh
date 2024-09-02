#!/bin/bash

# Do not output STDERR messages
exec 2>/dev/null

# Set the value for the frozen path
FROZEN_PATH="/frozen"

# Log file path
LOG_FILE="/var/log/Splunk_Frozen_Data.log"

# Configuration file path
CONFIG_FILE="/root/scripts/index_size.conf"

# Specify the path to the script you want to execute after each index processing
SCRIPT_PATH="/root/scripts/Delete_Empty_Folder.sh"

# Read the configuration file and store the size limits and retention days in associative arrays
declare -A INDEX_SIZE_LIMITS
declare -A INDEX_RETENTION_DAYS

# Generate a 6-digit hexadecimal process ID
generate_process_id() {
    openssl rand -hex 3 | tr 'a-f' 'A-F'
}

while IFS=, read -r key value retention
do
    index=$(echo "$key" | awk -F= '{print $2}')
    size=$(echo "$value" | awk -F= '{print $2}')
    days=$(echo "$retention" | awk -F= '{print $2}')
    INDEX_SIZE_LIMITS["$index"]=$size
    INDEX_RETENTION_DAYS["$index"]=$days
done < "$CONFIG_FILE"

# Redirect output to log file and overwrite it
exec > "$LOG_FILE"

# Initialize variables to track the earliest and latest log dates across all indexes
GLOBAL_EARLIEST_LOG_DATE=""
GLOBAL_LATEST_LOG_DATE=""

# Iterate through each index in the frozen path
for _dir in "$FROZEN_PATH"/*/
do
    # Generate a process ID for the current index
    PROCESS_ID=$(generate_process_id)

    # Extract the index name from the directory path
    CURR_IDX=$(basename "$_dir")

    # Calculate the total size of the index directory in MB
    FROZEN_SIZE_MB=$(du -cms "$_dir" | grep 'total' | awk '{print $1}')

    # Find the earliest and latest log file dates in the index directory
    EARLIEST_LOG_DATE=$(find "$_dir" -type f -printf '%TY-%Tm-%Td\n' | sort | head -1)
    LATEST_LOG_DATE=$(find "$_dir" -type f -printf '%TY-%Tm-%Td\n' | sort | tail -1)

    # Update the global earliest and latest log dates
    if [[ -z "$GLOBAL_EARIEST_LOG_DATE" || "$EARLIEST_LOG_DATE" < "$GLOBAL_EARLIEST_LOG_DATE" ]]; then
        GLOBAL_EARLIEST_LOG_DATE="$EARLIEST_LOG_DATE"
    fi
    if [[ -z "$GLOBAL_LATEST_LOG_DATE" || "$LATEST_LOG_DATE" > "$GLOBAL_LATEST_LOG_DATE" ]]; then
        GLOBAL_LATEST_LOG_DATE="$LATEST_LOG_DATE"
    fi

    # Calculate the number of days between the earliest and latest log files
    DAYS_WITH_LOGS=$(( ( $(date -d "$LATEST_LOG_DATE" +%s) - $(date -d "$EARLIEST_LOG_DATE" +%s) ) / (60*60*24) ))

    # Initialize variables for logging the action
    EXCEEDS_LIMIT=false

    # Check if the index size exceeds the limit or retention days are exceeded
    if [ ${INDEX_SIZE_LIMITS[$CURR_IDX]} -lt $FROZEN_SIZE_MB ] || [ $DAYS_WITH_LOGS -gt ${INDEX_RETENTION_DAYS[$CURR_IDX]} ]; then
        EXCEEDS_LIMIT=true
        START_TIME=$(date +%s)

        # Initialize variables for reason and overages
        REASON=""
        OVERAGE_MB=""
        OVERAGE_DAYS=""

        # Check if size limit is exceeded
        if [ ${INDEX_SIZE_LIMITS[$CURR_IDX]} -lt $FROZEN_SIZE_MB ]; then
            SIZE_OVERAGE=$((FROZEN_SIZE_MB - ${INDEX_SIZE_LIMITS[$CURR_IDX]}))
            REASON="size_limit_exceeded"
            OVERAGE_MB="overage_mb=$SIZE_OVERAGE"
        fi

        # Check if retention days limit is exceeded
        if [ $DAYS_WITH_LOGS -gt ${INDEX_RETENTION_DAYS[$CURR_IDX]} ]; then
            RETENTION_OVERAGE=$((DAYS_WITH_LOGS - ${INDEX_RETENTION_DAYS[$CURR_IDX]}))
            if [ -n "$REASON" ]; then
                REASON="$REASON | retention_days_exceeded"
            else
                REASON="retention_days_exceeded"
            fi
            OVERAGE_DAYS="overage_days=$RETENTION_OVERAGE"
        fi

        # Combine the overage information
        OVERAGES=""
        if [ -n "$OVERAGE_MB" ]; then
            OVERAGES="$OVERAGE_MB"
        fi
        if [ -n "$OVERAGE_DAYS" ]; then
            if [ -n "$OVERAGES" ]; then
                OVERAGES="$OVERAGES,$OVERAGE_DAYS"
            else
                OVERAGES="$OVERAGE_DAYS"
            fi
        fi

        # Log the event of exceeding limits with detailed reasons (update timestamp for each log)
        CURR_DATE="$(date +%Y-%m-%dT%H:%M:%S%z)"
        echo "timestamp=\"$CURR_DATE\",process_id=\"$PROCESS_ID\",frozen_index=\"$CURR_IDX\",action=\"exceeds_limit\",reason=\"$REASON\",$OVERAGES,exceeds_limit_frozen_size_mb=\"$FROZEN_SIZE_MB\",frozen_size_limit_mb=\"${INDEX_SIZE_LIMITS[$CURR_IDX]}\",current_frozen_days_with_logs=\"$DAYS_WITH_LOGS\",frozen_retention_days=\"${INDEX_RETENTION_DAYS[$CURR_IDX]}\",message=\"Index exceeds defined limits\""

        # Initialize the variable to keep track of deleted size
        DELETED_SIZE=0

        # Start deleting files until the index is within size and retention limits
        while [ ${INDEX_SIZE_LIMITS[$CURR_IDX]} -lt $FROZEN_SIZE_MB ] || [ $DAYS_WITH_LOGS -gt ${INDEX_RETENTION_DAYS[$CURR_IDX]} ]; do
            # Find the oldest file in the index directory
            OLDEST_FILE=$(find "$_dir" -type f -printf '%T+ %p\n' | sort | head -1 | awk '{print $2}')
            FILE_SIZE=$(du -k "$OLDEST_FILE" | cut -f1)
            FILE_SIZE_MB=$(echo "scale=2; $FILE_SIZE/1024" | bc)

            # Calculate the age of the file in days
            FILE_DATE=$(stat -c %Y "$OLDEST_FILE")
            FILE_AGE_DAYS=$(( ( $(date +%s) - FILE_DATE ) / (60*60*24) ))

            # Accumulate the total deleted size
            DELETED_SIZE=$((DELETED_SIZE + FILE_SIZE))
            DELETED_REASON=""

            # Determine the reason for file deletion
            if [ ${INDEX_SIZE_LIMITS[$CURR_IDX]} -lt $FROZEN_SIZE_MB ]; then
                SIZE_OVERAGE=$((FROZEN_SIZE_MB - ${INDEX_SIZE_LIMITS[$CURR_IDX]}))
                DELETED_REASON="reason=size_limit_exceeded,overage_mb=$SIZE_OVERAGE"
            elif [ $FILE_AGE_DAYS -gt ${INDEX_RETENTION_DAYS[$CURR_IDX]} ]; then
                RETENTION_OVERAGE=$((FILE_AGE_DAYS - ${INDEX_RETENTION_DAYS[$CURR_IDX]}))
                DELETED_REASON="reason=retention_days_exceeded,overage_days=$RETENTION_OVERAGE"
            fi

            # Log the file deletion event (update timestamp for each log)
            CURR_DATE="$(date +%Y-%m-%dT%H:%M:%S%z)"
            echo "timestamp=\"$CURR_DATE\",process_id=\"$PROCESS_ID\",frozen_index=\"$CURR_IDX\",action=\"deleting_file\",deleted_file=\"$OLDEST_FILE\",deleted_file_size_mb=\"$FILE_SIZE_MB\",deleted_file_age_days=\"$FILE_AGE_DAYS\",$DELETED_REASON,message=\"Deleting file to comply with policy\""

            # Delete the oldest file
            rm "$OLDEST_FILE"

            # Recalculate the directory size after deletion
            FROZEN_SIZE_MB=$(du -cms "$_dir" | grep 'total' | awk '{print $1}')

            # Update the earliest log date and recalculate the days with logs
            EARLIEST_LOG_DATE=$(find "$_dir" -type f -printf '%TY-%Tm-%Td\n' | sort | head -1)
            LATEST_LOG_DATE=$(find "$_dir" -type f -printf '%TY-%Tm-%Td\n' | sort | tail -1)
            DAYS_WITH_LOGS=$(( ( $(date -d "$LATEST_LOG_DATE" +%s) - $(date -d "$EARLIEST_LOG_DATE" +%s) ) / (60*60*24) ))
        done

        # Calculate the time taken for the deletion process
        END_TIME=$(date +%s)
        TIME_TAKEN=$((END_TIME - START_TIME))

        # Calculate and log the total size deleted after processing (update timestamp for each log)
        DELETED_SIZE_MB=$(echo "scale=2; $DELETED_SIZE/1024" | bc)
        CURR_DATE="$(date +%Y-%m-%dT%H:%M:%S%z)"
        echo "timestamp=\"$CURR_DATE\",process_id=\"$PROCESS_ID\",frozen_index=\"$CURR_IDX\",action=\"deletion_summary\",deleted_size_mb=\"$DELETED_SIZE_MB\",time_taken_sec=\"$TIME_TAKEN\",message=\"Total size deleted and time taken to bring index within limits\""
    fi

    # Log a final summary for each index, regardless of whether limits were exceeded or not (update timestamp for each log)
    CURR_DATE="$(date +%Y-%m-%dT%H:%M:%S%z)"
    if [[ -n "$EARLIEST_LOG_DATE" && -n "$LATEST_LOG_DATE" ]]; then
        echo "timestamp=\"$CURR_DATE\",process_id=\"$PROCESS_ID\",frozen_index=\"$CURR_IDX\",action=\"final_summary\",earliest_log_date=\"$EARLIEST_LOG_DATE\",latest_log_date=\"$LATEST_LOG_DATE\",final_frozen_size_mb=\"$FROZEN_SIZE_MB\",current_frozen_days_with_logs=\"$DAYS_WITH_LOGS\",message=\"Final summary after processing\""
    else
        echo "timestamp=\"$CURR_DATE\",process_id=\"$PROCESS_ID\",frozen_index=\"$CURR_IDX\",action=\"final_summary\",final_frozen_size_mb=\"$FROZEN_SIZE_MB\",current_frozen_days_with_logs=\"$DAYS_WITH_LOGS\",message=\"Final summary after processing\""
    fi
done

	# Execute the external script
	if [ -x "$SCRIPT_PATH" ]; then
		bash "$SCRIPT_PATH"
	else
		echo "Script at $SCRIPT_PATH is not executable. Setting execute permission."
		chmod 750 "$SCRIPT_PATH"
		if [ $? -eq 0 ]; then
			bash "$SCRIPT_PATH"
		else
			echo "Error: Could not set execute permission for $SCRIPT_PATH."
		fi
	fi
