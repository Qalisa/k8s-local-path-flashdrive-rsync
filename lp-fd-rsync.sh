#!/bin/bash

# Define readonly variables for maintainability
readonly SCRIPT_NAME="lp-fd-rsync"
readonly SOURCE_PATH="/var/lib/rancher/k3s/storage/"
readonly SOURCE_FOLDER_NAME="*odoo-community_local-backups*"
readonly USB_LABEL_PATTERN1="odoo"
readonly USB_LABEL_PATTERN2="backup"
readonly MAX_LOG_LINES=10000
readonly LOG_FILE="/var/log/odoo_backup.log"
readonly MOUNT_POINT="/mnt/odoo_backup"
readonly REQUIRED_BINS=("find" "lsblk" "grep" "awk" "rsync" "wc" "tail" "mount" "umount" "mkdir" "df")

# Function to log messages
log_message() {
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$TIMESTAMP] $1" >> "$LOG_FILE"
    print_message "$1"
}

print_message() {
    echo "[$SCRIPT_NAME] $1"
}

mayTrimLog() {
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
}

##
##
##

log_message "Starting Odoo backup script..."

#
mayTrimLog

# Check for required binaries
print_message "Checking for required binaries..."
for bin in "${REQUIRED_BINS[@]}"; do
    if ! command -v "$bin" &> /dev/null; then
        log_message "ERROR: Required binary [$bin] not found; please install it."
        exit 1
    else
        print_message "-> Found binary: [$bin]"
    fi
done

# Step 1: Find folder containing odoo-community_local-backups
print_message "Searching for pattern [$SOURCE_FOLDER_NAME] folder in [$SOURCE_PATH]..."
SOURCE_DIR=$(find "$SOURCE_PATH" -type d -name "$SOURCE_FOLDER_NAME" | head -n 1)

if [ -z "$SOURCE_DIR" ]; then
    log_message "ERROR: No folder inside [$SOURCE_PATH] with pattern [$SOURCE_FOLDER_NAME] found"
    exit 1
else
    log_message "-> Found source folder: [$SOURCE_DIR]"
fi

# Step 2: Find USB drive with volume containing both 'odoo' and 'backup' (case insensitive)
print_message "Searching for USB drive with volume containing '$USB_LABEL_PATTERN1' and '$USB_LABEL_PATTERN2'..."
USB_INFO=$(lsblk -o NAME,MOUNTPOINT,LABEL,SIZE -b -l | grep -i "$USB_LABEL_PATTERN1" | grep -i "$USB_LABEL_PATTERN2" | head -n 1)
USB_DEVICE=$(echo "$USB_INFO" | awk '{print $1}')
USB_LABEL=$(echo "$USB_INFO" | awk '{print $3}')
USB_SIZE=$(echo "$USB_INFO" | awk '{print $4}' | numfmt --to=iec --suffix=B)
if [ -z "$USB_DEVICE" ]; then
    log_message "ERROR: No USB drive with volume containing both '$USB_LABEL_PATTERN1' and '$USB_LABEL_PATTERN2' found"
    exit 1
fi

# Check if USB is already mounted
USB_MOUNT=$(lsblk -o NAME,MOUNTPOINT -l | grep "^$USB_DEVICE" | awk '{print $2}')
if [ -n "$USB_MOUNT" ]; then
    USB_AVAILABLE=$(df -h "$USB_MOUNT" | tail -n 1 | awk '{print $4}')
    log_message "-> Found USB device: /dev/$USB_DEVICE, Label: [$USB_LABEL], Size: [$USB_SIZE], Available: [$USB_AVAILABLE], already mounted at: [$USB_MOUNT]"
else
    # Create mount point if it doesn't exist
    if [ ! -d "$MOUNT_POINT" ]; then
        print_message "Creating mount point [$MOUNT_POINT]..."
        mkdir -p "$MOUNT_POINT"
        if [ $? -eq 0 ]; then
            log_message "-> Mount point [$MOUNT_POINT] created successfully"
        else
            log_message "ERROR: Failed to create mount point [$MOUNT_POINT]"
            exit 1
        fi
    fi

    # Mount the USB device
    print_message "Mounting USB device /dev/$USB_DEVICE to [$MOUNT_POINT]..."
    mount "/dev/$USB_DEVICE" "$MOUNT_POINT"
    if [ $? -eq 0 ]; then
        USB_AVAILABLE=$(df -h "$MOUNT_POINT" | tail -n 1 | awk '{print $4}')
        log_message "-> USB device: /dev/$USB_DEVICE, Label: [$USB_LABEL], Size: [$USB_SIZE], Available: [$USB_AVAILABLE], mounted successfully at [$MOUNT_POINT]"
        USB_MOUNT="$MOUNT_POINT"
    else
        log_message "ERROR: Failed to mount USB device /dev/$USB_DEVICE to [$MOUNT_POINT]"
        exit 1
    fi
fi

# Step 3: Perform rsync
log_message "Starting rsync from [$SOURCE_DIR] to [$USB_MOUNT]"
rsync -av --progress "$SOURCE_DIR/" "$USB_MOUNT/" >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    log_message "Rsync completed successfully"
else
    log_message "ERROR: Rsync failed"
    # Attempt to unmount before exiting
    if [ "$USB_MOUNT" = "$MOUNT_POINT" ]; then
        print_message "Unmounting USB device from [$MOUNT_POINT] due to rsync failure..."
        umount "$MOUNT_POINT"
        if [ $? -eq 0 ]; then
            log_message "-> USB device unmounted successfully from [$MOUNT_POINT]"
        else
            log_message "ERROR: Failed to unmount USB device from [$MOUNT_POINT]"
        fi
    fi
    exit 1
fi

# Step 4: Unmount USB if we mounted it
if [ "$USB_MOUNT" = "$MOUNT_POINT" ]; then
    print_message "Unmounting USB device from [$MOUNT_POINT]..."
    umount "$MOUNT_POINT"
    if [ $? -eq 0 ]; then
        log_message "-> USB device unmounted successfully from [$MOUNT_POINT]"
    else
        log_message "ERROR: Failed to unmount USB device from [$MOUNT_POINT]"
        exit 1
    fi
fi

print_message "Backup script completed"
exit 0