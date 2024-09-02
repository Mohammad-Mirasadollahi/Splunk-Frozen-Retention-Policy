#!/bin/bash

# Base path to check for directories
FROZEN_PATH="/frozen"
INDEX_FILE="$PWD/index_list.txt"

# Function to update the list of indexes
update_index_list() {
  # Create or clear the index list file
  : > "$INDEX_FILE"

  # Save the names of all directories in FROZEN_PATH as indexes
  for index_dir in "$FROZEN_PATH"/*; do
    if [ -d "$index_dir" ]; then
      echo "$index_dir" >> "$INDEX_FILE"
    fi
  done
}

# Function to delete empty directories recursively
delete_empty_dirs() {
  local dir="$1"

  # Check directories within the current directory
  for sub_dir in "$dir"/*; do
    if [ -d "$sub_dir" ]; then
      # Recursively return to subdirectories
      delete_empty_dirs "$sub_dir"
    fi
  done

  # Delete empty directory if it is not an index
  if [ -d "$dir" ] && [ -z "$(ls -A "$dir")" ]; then
    local is_index=false
    while IFS= read -r index; do
      if [ "$dir" == "$index" ]; then
        is_index=true
        break
      fi
    done < "$INDEX_FILE"
    if [ "$is_index" == false ]; then
      rmdir "$dir"
    fi
  fi
}

# Update the list of indexes
update_index_list

# Run the function to delete empty directories from the frozen path
for index_dir in "$FROZEN_PATH"/*; do
  if [ -d "$index_dir" ]; then
    delete_empty_dirs "$index_dir"
  fi
done
