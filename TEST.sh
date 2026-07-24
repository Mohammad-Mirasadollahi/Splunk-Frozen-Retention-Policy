#!/bin/bash

# Directory for testing
TEST_DIR="/tmp/frozen_test"
CONFIG_FILE="index_size.conf"

# Cleanup previous test data
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"

# Create multiple index directories with dummy files
declare -A TEST_INDEXES
TEST_INDEXES["index1"]="100 7"
TEST_INDEXES["index2"]="200 3"
TEST_INDEXES["index3"]="150 5"
TEST_INDEXES["index4"]="50 2"
TEST_INDEXES["index5"]="300 10"
TEST_INDEXES["index6"]="250 15"
TEST_INDEXES["index7"]="180 20"
TEST_INDEXES["index8"]="120 8"
TEST_INDEXES["test"]="100 7"  # Add "test" index with size limit of 100MB and 7 days retention

# Create the configuration file with the indexes' size limits and retention days
rm -f "$CONFIG_FILE"
for INDEX in "${!TEST_INDEXES[@]}"; do
    SIZE=$(echo "${TEST_INDEXES[$INDEX]}" | awk '{print $1}')
    RETENTION=$(echo "${TEST_INDEXES[$INDEX]}" | awk '{print $2}')
    echo "index=$INDEX,size=$SIZE,retention=$RETENTION" >> "$CONFIG_FILE"
done

# Create test files with different sizes and modification dates
for INDEX in "${!TEST_INDEXES[@]}"; do
    INDEX_DIR="$TEST_DIR/$INDEX"
    mkdir -p "$INDEX_DIR"

    # Create dummy files
    for i in {1..10}; do
        FILE_PATH="$INDEX_DIR/log_$i.log"

        # Create files with different sizes (5MB, 10MB, ...)
        dd if=/dev/urandom of="$FILE_PATH" bs=1M count=$((i*5)) 2>/dev/null

        # Modify the timestamp of the file to simulate different log dates
        touch -d "$((i + 1)) days ago" "$FILE_PATH"
    done

    # Create nested directories and files within them
    if [[ "$INDEX" == "index6" || "$INDEX" == "index7" ]]; then
        SUB_DIR="$INDEX_DIR/sub_dir"
        mkdir -p "$SUB_DIR"

        for j in {1..5}; do
            SUB_FILE_PATH="$SUB_DIR/sub_log_$j.log"

            # Create files with different sizes (3MB, 6MB, ...)
            dd if=/dev/urandom of="$SUB_FILE_PATH" bs=1M count=$((j*3)) 2>/dev/null

            # Modify the timestamp of the file to simulate different log dates
            touch -d "$((j + 2)) days ago" "$SUB_FILE_PATH"
        done
    fi
done

# Create the specific test case: "test" index with "test1" directory and a 200MB file
TEST_INDEX_DIR="$TEST_DIR/test/test1"
mkdir -p "$TEST_INDEX_DIR"

# Create a 200MB file in "test1"
dd if=/dev/urandom of="$TEST_INDEX_DIR/large_file.log" bs=1M count=200 2>/dev/null

# Modify the timestamp of the file to simulate 5 days ago
touch -d "5 days ago" "$TEST_INDEX_DIR/large_file.log"

# Modify the timestamps of all files and directories inside "test" to be 5 days ago
find "$TEST_DIR/test" -exec touch -d "5 days ago" {} +

