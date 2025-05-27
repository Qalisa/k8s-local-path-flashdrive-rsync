#!/bin/bash

# Define readonly variables for maintainability
readonly SOURCE_PATH="/var/lib/rancher/k3s/storage/"
readonly SOURCE_FOLDER_NAME="*odoo-community_local-backups*"
readonly USB_LABEL_PATTERN1="odoo"
readonly USB_LABEL_PATTERN2="backup"

# Set log file
LOG_FILE="/var/log/odoo_backup.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Function to log messages
log_message() {
    echo "[$TIMESTAMP] $1" >> "$LOG_FILE"
    echo "$1"
}

# Check for required binaries
log_message "Checking for required binaries"
REQUIRED_BINS=("find" "lsblk" "grep" "awk" "rsync")
for bin in "${REQUIRED_BINS[@]}"; do
    if ! command -v "$bin" &> /dev/null; then
        log_message "ERROR: Required binary '$bin' not found"
        exit 1
    else
        log_message "Found binary: $bin"
    fi
done

# Create or clear log file
> "$LOG_FILE"
log_message "Starting Odoo backup script"

# Step 1: Find folder containing odoo-community_local-backups
log_message "Searching for $SOURCE_FOLDER_NAME folder in $SOURCE_PATH"
SOURCE_DIR=$(find "$SOURCE_PATH" -type d -name "$SOURCE_FOLDER_NAME" | head -n 1)

if [ -z "$SOURCE_DIR" ]; then
    log_message "ERROR: No folder containing '$SOURCE_FOLDER_NAME' found"
    exit 1
else
    log_message "Found source folder: $SOURCE_DIR"
fi

# Step 2: Find USB drive with volume containing both 'odoo' and 'backup' (case insensitive)
log_message "Searching for USB drive with volume containing '$USB_LABEL_PATTERN1' and '$USB_LABEL_PATTERN2'"
USB_MOUNT=$(lsblk -o NAME,MOUNTPOINT,LABEL -l | grep -i "$USB_LABEL_PATTERN1" | grep -i "$USB_LABEL_PATTERN2" | head -n 1 | awk '{print $2}')

if [ -z "$USB_MOUNT" ]; then
    log_message "ERROR: No USB drive with volume containing both '$USB_LABEL_PATTERN1' and '$USB_LABEL_PATTERN2' found"
    exit 1
else
    log_message "Found USB volume mounted at: $USB_MOUNT"
fi

# Step 3: Perform rsync
log_message "Starting rsync from $SOURCE_DIR to $USB_MOUNT"
rsync -av --progress "$SOURCE_DIR/" "$USB_MOUNT/" >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    log_message "Rsync completed successfully"
else
    log_message "ERROR: Rsync failed"
    exit 1
fi

log_message "Backup script completed"
exit 0
