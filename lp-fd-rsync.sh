#!/bin/bash

# Define readonly variables for maintainability
readonly SCRIPT_NAME="lp-fd-rsync"
readonly SOURCE_PATH="/var/lib/rancher/k3s/storage/"
readonly SOURCE_FOLDER_NAME="*odoo-community_local-backups*"
readonly USB_LABEL_PATTERN1="odoo"
readonly USB_LABEL_PATTERN2="backup"
readonly MAX_LOG_LINES=10000
readonly LOG_FILE="/var/log/odoo_backup.log"


# Function to log messages
log_message() {
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$TIMESTAMP] $1" >> "$LOG_FILE"
    print_message "$1"
}

print_message() {
    echo "[$SCRIPT_NAME] $1"
}

#
log_message "Starting Odoo backup script..."

# Check for required binaries
print_message "Checking for required binaries..."
REQUIRED_BINS=("find" "lsblk" "grep" "awk" "rsync" "wc" "tail")
for bin in "${REQUIRED_BINS[@]}"; do
    if ! command -v "$bin" &> /dev/null; then
        log_message "ERROR: Required binary [$bin] not found; please install it."
        exit 1
    else
        print_message "-> Found binary: [$bin]"
    fi
done

# Check and trim log file if it exceeds MAX_LOG_LINES
if [ -f "$LOG_FILE" ]; then
    LINE_COUNT=$(wc -l < "$LOG_FILE")
    if [ "$LINE_COUNT" -gt "$MAX_LOG_LINES" ]; then
        print_message "Log file exceeds $MAX_LOG_LINES lines ($LINE_COUNT lines), trimming old entries"
        tail -n "$MAX_LOG_LINES" "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
        print_message "Log file trimmed to last $MAX_LOG_LINES lines"
    fi
else
    > "$LOG_FILE"  # Create empty log file if it doesn't exist
fi

# Step 1: Find folder containing odoo-community_local-backups
print_message "Searching for [$SOURCE_FOLDER_NAME] folder in [$SOURCE_PATH]..."
SOURCE_DIR=$(find "$SOURCE_PATH" -type d -name "$SOURCE_FOLDER_NAME" | head -n 1)

if [ -z "$SOURCE_DIR" ]; then
    log_message "ERROR: No folder containing [$SOURCE_FOLDER_NAME] found"
    exit 1
else
    log_message "-> Found source folder: [$SOURCE_DIR]"
fi

# Step 2: Find USB drive with volume containing both 'odoo' and 'backup' (case insensitive)
print_message "Searching for USB drive with volume containing '$USB_LABEL_PATTERN1' and '$USB_LABEL_PATTERN2'..."
USB_MOUNT=$(lsblk -o NAME,MOUNTPOINT,LABEL -l | grep -i "$USB_LABEL_PATTERN1" | grep -i "$USB_LABEL_PATTERN2" | head -n 1 | awk '{print $2}')

if [ -z "$USB_MOUNT" ]; then
    log_message "ERROR: No USB drive with volume containing both '$USB_LABEL_PATTERN1' and '$USB_LABEL_PATTERN2' found"
    exit 1
else
    log_message "-> Found USB volume mounted containing both '$USB_LABEL_PATTERN1' and '$USB_LABEL_PATTERN2' at: $USB_MOUNT"
fi

# Step 3: Perform rsync
log_message "Starting rsync from [$SOURCE_DIR] to [$USB_MOUNT]"
rsync -av --progress "$SOURCE_DIR/" "$USB_MOUNT/" >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    log_message "Rsync completed successfully"
else
    log_message "ERROR: Rsync failed"
    exit 1
fi

print_message "Backup script completed"
exit 0
