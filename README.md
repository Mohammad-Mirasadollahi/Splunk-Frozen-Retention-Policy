# Splunk Frozen index Data Management Scripts
This repository provides a set of Bash scripts designed to manage frozen data in Splunk environments.

**Note:** These scripts were developed with the assistance of ChatGPT and have been tested successfully in an environment with terabytes (TB) of data without any issues.
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

index:\
The name of the index. This is the identifier that the script uses to apply specific limits and rules to the data stored in this index's directory. For example, The script will monitor the directory associated with index1.

size:\
This is the maximum allowed size for the index's frozen data, expressed in MB (Megabytes). If the total size of the files in the index directory exceeds this limit, the script will initiate the process of deleting the oldest files to bring the index size back within the limit. For example If the total size of files in the index1 directory exceeds 5000 MB, the script will start deleting the oldest files until the total size is under 5000 MB. 

retention:\
This is the maximum number of days that data in the index can be retained. If any data in the index is older than this retention period, the script will delete the oldest files first until the data within the directory complies with the retention policy. For example: If any file in the index1 directory is older than 30 days, the script will delete it to comply with the retention policy.

## Variables
In the context of the script, there are several variables that can change based on your environment. you can (optional) change it based on your environment.

**1. Splunk_Frozen_Retention_Policy.sh**

FROZEN_PATH="/frozen": The directory containing frozen index data.\
LOG_FILE="/var/log/Splunk_Frozen_Data.log": The log file where the script records its operations.\
CONFIG_FILE="/root/scripts/index_size.conf": Path to the configuration file that defines size and retention limits for each index.\
SCRIPT_PATH="/root/scripts/Delete_Empty_Folder.sh": Path to the external script (Delete_Empty_Folder.sh).

**2. Delete_Empty_Folder.sh**

FROZEN_PATH="/frozen": The directory containing frozen index data.\
INDEX_FILE="$PWD/index_list.txt": list of all frozen indexes

**3. Splunk_Frozen_Policy_service.sh**

SCRIPT_PATH="/root/scripts/Splunk_Frozen_Retention_Policy.sh": The full path of the Splunk_Frozen_Retention_Policy.sh

# Quick Start

**Quick Start Guide:**

1. First, download the repository.
   
 ```
 git clone https://github.com/Mohammad-Mirasadollahi/Splunk-Frozen-Retention-Policy.git
   ```
2. After extracting the files, move all of them into the `/root/scripts` directory. If the directory does not exist, create it.

 ```
mkdir -p /root/scripts
cp -r * /root/scripts/
   ```
3. Then, run the following command:
```
bash ./Splunk_Frozen_Policy_service.sh
   ```
   
   
   
   
   
   
   
   
   
   
   
   
   
   
