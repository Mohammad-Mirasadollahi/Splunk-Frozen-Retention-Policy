# Splunk Frozen index Data Management Scripts
This repository provides a set of Bash scripts designed to manage frozen indexes data in Splunk environments.

**Note:** These scripts were developed with the assistance of ChatGPT and have been tested successfully with terabytes (TB) of data without any issues.

# Overview
This repository contains two Bash scripts designed to manage and clean up frozen data in a Splunk environment. The primary goal of these scripts is to keep frozen indexes within predefined limits, prevent excessive storage usage, and maintain an organized file structure by cleaning up unnecessary empty directories. The primary script handles index size and retention management, while the secondary script cleans up empty directories. Both scripts are designed to work together to ensure efficient storage management in environments where frozen data is stored.

This script manages frozen indexes in a Splunk environment and performs the following tasks:
1. **Index Monitoring**: It scans the directories containing frozen indexes to assess their size and retention periods.
2. **Identifying Overages**: If an index exceeds the size limit specified in the configuration file or if the retention period of the data exceeds the allowed duration, the script identifies these overages.
3. **Deleting Old Files**: To bring the index back within the allowed limits, the script gradually deletes older files from the index until its size is reduced and the retention period is within the permissible range.
4. **Logging**: All actions, including identifying issues, reasons for file deletions, and a final summary of the index status, are logged for reference.
5. **Executing an External Script (Delete_Empty_Folder)**: After processing each index, an external script is executed to perform additional tasks. This external script first updates a list of all directories (frozen indexes) within the specified `FROZEN_PATH` and then recursively checks each directory to identify and delete any empty directories. It ensures that only directories not listed as indexes are deleted if they are found to be empty.

# Configuration File 
## index_size.conf
The index_size.conf file is a configuration file that contains important settings for managing the frozen indexes within the script. This file is read by the script to determine the size limits and retention periods for each index. 

**Structure of index_size.conf**

The file is expected to be a simple text file, where each line contains the configuration for a specific index. Each line typically includes three key components: the index name, the size limit, and the retention period. These are separated by commas.

Example structure:
```
index=index1,size=5000,retention=30
index=index2,size=7000,retention=45
index=index3,size=6000,retention=60
```
-------------------------------------------------------------------------

**index:**\
The name of the index. This is the identifier that the script uses to apply specific limits and rules to the data stored in frozen index's directory. For example, The script will monitor the directory associated with frozen index1.

**size:**\
This is the maximum allowed size for the index's frozen data, expressed in MB (Megabytes). If the total size of the files in the index directory exceeds this limit, the script will initiate the process of deleting the oldest files to bring the frozen index size back within the limit. For example If the total size of files in the index1 directory exceeds 5000 MB, the script will start deleting the oldest files until the total size is under 5000 MB. 

**retention:**\
This is the maximum number of days that data in the index can be retained. If any data in the index is older than this retention period, the script will delete the oldest files first until the data within the directory complies with the retention policy. For example: If any file in the index1 frozen directory is older than 30 days, the script will delete it to comply with the retention policy.

## Variables
In the context of the script, there are several variables that can change based on your environment. you can (optional) change it based on your environment.

**1. Splunk_Frozen_Retention_Policy.sh**

**FROZEN_PATH=**"/frozen": The directory containing frozen index data.\
**LOG_FILE=**"/var/log/Splunk_Frozen_Data.log": The log file where the script records its operations.\
**CONFIG_FILE=**"/root/scripts/index_size.conf": Path to the configuration file that defines size and retention limits for each index.\
**SCRIPT_PATH=**"/root/scripts/Delete_Empty_Folder.sh": Path to the external script (Delete_Empty_Folder.sh).

**2. Delete_Empty_Folder.sh**

**FROZEN_PATH=**"/frozen": The directory containing frozen index data.\
**INDEX_FILE=**"$PWD/index_list.txt": list of all frozen indexes

**3. Splunk_Frozen_Policy_service.sh**

**SCRIPT_PATH=**"/root/scripts/Splunk_Frozen_Retention_Policy.sh": The full path of the Splunk_Frozen_Retention_Policy.sh

# Quick Start

**Quick Start Guide:**

0. Make sure you are login as root.
   
 ```
 sudo -i
   ```

1. First, download the repository.
   
 ```
 git clone https://github.com/Mohammad-Mirasadollahi/Splunk-Frozen-index-Retention-Policy.git
   ```
2. Move all of them into the `/root/scripts` directory. If the directory does not exist, create it.

 ```
cd Splunk-Frozen-index-Retention-Policy
mkdir -p /root/scripts
mv Splunk_Frozen_Retention_Policy_Scripts.tar.gz /root/scripts/
   ```
3. First go to the /root/scripts/ directory and then, run the following command.
```
cd /root/scripts/
tar xzvf Splunk_Frozen_Retention_Policy_Scripts.tar.gz
   ```

4. Then, just run the following command.
```
bash ./Splunk_Frozen_Policy_service.sh
   ```
5. Finally, check the service status.
```
service Splunk_Frozen_Policy status
   ```
When the Splunk_Frozen_Policy_service.sh script is executed, a service named **Splunk_Frozen_Policy** will be created. This service runs the Splunk_Frozen_Retention_Policy.sh script every 24 hours to check frozen indexes and apply retention policies. If you want to modify 24 hours you must edit /etc/systemd/system/Splunk_Frozen_Policy.timer and change **OnUnitActiveSec** to what ever value you want.

# Logging

## Log for Exceeding Limits
This log is generated when an index exceeds its size or retention limits.

```
timestamp="2024-08-28T15:34:20+00:00" process_id="1a2b3c" frozen_index="index1" action="exceeds_limit" reason="size_limit_exceeded" overage_mb="1500" overage_days="0" exceeds_limit_frozen_size_mb="6500" frozen_size_limit_mb="5000" current_frozen_days_with_logs="20" frozen_retention_days="30" message="Index exceeds the defined limits."
   ```

**timestamp:** The exact date and time when the log was created, formatted as YYYY-MM-DDTHH:MM:SS+TZ.\
**process_id:** A unique 6-digit hexadecimal identifier generated for each index processing.\
**frozen_index:** The name of the index that is being processed.\
**action:** This field is set to "exceeds_limit", indicating that the index has surpassed its allowed limits.\
**reason:** A description of why the index exceeds the limits. This could be size_limit_exceeded, retention_days_exceeded, or both.\
**overage_mb:** The amount of storage (in MB) by which the index exceeds its size limit.\
**overage_days:** The number of days by which the index exceeds its retention period.\
**exceeds_limit_frozen_size_mb:** The total size of the index (in MB) at the time the limit was exceeded.\
**frozen_size_limit_mb:** The size limit (in MB) set for the index in the configuration.\
**current_frozen_days_with_logs:** The number of days for which the index has log files.\
**frozen_retention_days:** The retention period (in days) set for the index in the configuration.\
**message:** A description of the event, typically stating that the index exceeds the defined limits.

## Log for Deleting Files
This log is generated when the script deletes files from an index to bring it within limits.

```
timestamp="2024-08-28T15:35:10+00:00" process_id="1a2b3c" frozen_index="index1" action="deleting_file" deleted_file="/tmp/frozen_test/index1/log2023-08-01.log" deleted_file_size_mb="500" deleted_file_age_days="27" reason="size_limit_exceeded" message="File deleted to comply with size limit."
   ```

**timestamp:** The exact date and time when the log was created.\
**process_id:** The unique identifier for the current index processing.\
**frozen_index:** The name of the index being processed.\
**action:** This field is set to "deleting_file", indicating that a file is being deleted.\
**deleted_file:** The path to the file that was deleted.\
**deleted_file_size_mb:** The size of the deleted file in MB.\
**deleted_file_age_days:** The age of the deleted file in days.\
**reason:** The reason for deleting the file, either size_limit_exceeded or retention_days_exceeded, along with the corresponding overage.\
**message:** A description of the event, indicating that the file was deleted to comply with the policy.\

## Log for Deletion Summary**
This log is generated after the script finishes deleting files to summarize the deletion process.

```
timestamp="2024-08-28T15:37:45+00:00" process_id="1a2b3c" frozen_index="index1" action="deletion_summary" deleted_size_mb="1500" time_taken_sec="155" message="Deleted a total of 1500 MB to bring the index within limits."
   ```

**timestamp:** The exact date and time when the log was created.\
**process_id:** The unique identifier for the current index processing.\
**frozen_index:** The name of the index being processed.\
**action:** This field is set to "deletion_summary", indicating a summary of the deletion process.\
**deleted_size_mb:** The total amount of data (in MB) deleted during the process.\
**time_taken_sec:** The total time (in seconds) it took to delete the files and bring the index within limits.\
**message:** A description of the event, typically stating the total size deleted and the time taken.

## Final Summary Log
This log provides a summary of the index status after processing, regardless of whether limits were exceeded.

```
timestamp="2024-08-28T15:40:00+00:00" process_id="1a2b3c" frozen_index="index1" action="final_summary" earliest_log_date="2023-08-01" latest_log_date="2024-08-28" final_frozen_size_mb="5000" current_frozen_days_with_logs="27" message="Final index status after processing."
   ```

**timestamp:** The exact date and time when the log was created.\
**process_id:** The unique identifier for the current index processing.\
**frozen_index:** The name of the index being processed.\
**action:** This field is set to "final_summary", indicating the final status after processing.\
**earliest_log_date:** The date of the earliest log file in the index (if available).\
**latest_log_date:** The date of the latest log file in the index (if available).\
**final_frozen_size_mb:** The total size of the index (in MB) after processing.\
**current_frozen_days_with_logs:** The number of days for which the index has log files after processing.\
**message:** A description of the final status of the index after processing.
   
# Test Logs
The TEST.sh script is used to create various log files in the /tmp/frozen_test directory, which can be used for testing the Splunk_Frozen_Retention_Policy.sh script.
   
   
   
   
   
   
