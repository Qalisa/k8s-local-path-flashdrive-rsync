#!/bin/bash

# Define readonly variables for maintainability
readonly REQUIRED_BINS=("find" "lsblk" "grep" "sed" "rsync" "wc" "tail" "mount" "umount" "mkdir" "df")
readonly SCRIPT_NAME="lp-fd-rsync"
readonly SOURCE_PATH="/var/lib/rancher/k3s/storage/"
readonly SOURCE_FOLDER_NAME="*odoo-community_local-backups*"
readonly USB_LABEL_PATTERN1="odoo"
readonly USB_LABEL_PATTERN2="backup"
readonly MAX_LOG_LINES=10000
readonly LOG_FILE="/var/log/odoo_backup.log"
readonly MOUNT_POINT="/mnt/odoo_backup"

# Function to wrap text in brackets
bracket() {
    echo "[$1]"
}

# Function to log messages to file and console
log_message() {
    local TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$TIMESTAMP] $1" >> "$LOG_FILE"
    echo "[$SCRIPT_NAME] $1"
}

# Function to handle errors
handle_error() {
    log_message "ERROR: $1"
    exit 1
}

# Function to get USB stats (label, size, available)
get_usb_stats() {
    local device="$1" mount_point="$2"
    USB_LABEL=$(lsblk -o NAME,LABEL -P | grep "NAME=\"$device\"" | sed -n 's/.*LABEL="\([^"]*\)".*/\1/p')
    USB_SIZE=$(df -h "$mount_point" | tail -n 1 | awk '{print $2}')
    USB_AVAILABLE=$(df -h "$mount_point" | tail -n 1 | awk '{print $4}')
    log_message "-> Looking at USB device: /dev/$device, Label: $(bracket "$USB_LABEL"), Size: $(bracket "$USB_SIZE"), Available: $(bracket "$USB_AVAILABLE"), mounted at: $(bracket "$mount_point")"
}

# Check and trim log file if it exceeds MAX_LOG_LINES
if [ -f "$LOG_FILE" ]; then
    LINE_COUNT=$(wc -l < "$LOG_FILE")
    if [ "$LINE_COUNT" -gt "$MAX_LOG_LINES" ]; then
        log_message "Log file exceeds $(bracket "$MAX_LOG_LINES") lines ($(bracket "$LINE_COUNT") lines), trimming old entries"
        tail -n "$MAX_LOG_LINES" "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE" || handle_error "Failed to trim log file"
        log_message "Log file trimmed to last $(bracket "$MAX_LOG_LINES") lines"
    fi
else
    > "$LOG_FILE" || handle_error "Failed to create log file"
fi

log_message "Starting Odoo backup script..."

# Check for required binaries
log_message "Checking for required binaries..."
for bin in "${REQUIRED_BINS[@]}"; do
    command -v "$bin" &> /dev/null || handle_error "Required binary $(bracket "$bin") not found; please install it"
    log_message "-> Found binary: $(bracket "$bin")"
done

# Step 1: Find folder containing odoo-community_local-backups
log_message "Searching for pattern $(bracket "$SOURCE_FOLDER_NAME") folder in $(bracket "$SOURCE_PATH")..."
SOURCE_DIR=$(find "$SOURCE_PATH" -type d -name "$SOURCE_FOLDER_NAME" | head -n 1)
[ -z "$SOURCE_DIR" ] && handle_error "No folder inside $(bracket "$SOURCE_PATH") with pattern $(bracket "$SOURCE_FOLDER_NAME") found"
log_message "-> Found source folder: $(bracket "$SOURCE_DIR")"

# Step 2: Find and mount USB drive
log_message "Searching for USB drive with volume containing '$USB_LABEL_PATTERN1' and '$USB_LABEL_PATTERN2'..."
USB_DEVICE=$(lsblk -o NAME,LABEL -P | grep -i "LABEL=.*$USB_LABEL_PATTERN1" | grep -i "LABEL=.*$USB_LABEL_PATTERN2" | sed -n 's/.*NAME="\([^"]*\)".*/\1/p' | head -n 1)
[ -z "$USB_DEVICE" ] && handle_error "No USB drive with volume containing both '$USB_LABEL_PATTERN1' and '$USB_LABEL_PATTERN2' found"

log_message "-> Found in [/dev/$USB_DEVICE] !"

# Check if USB is already mounted
USB_MOUNT=$(lsblk -o NAME,MOUNTPOINT -P | grep "NAME=\"$USB_DEVICE\"" | sed -n 's/.*MOUNTPOINT="\([^"]*\)".*/\1/p')
if [ -n "$USB_MOUNT" ]; then
    get_usb_stats "$USB_DEVICE" "$USB_MOUNT"
else
    # Create mount point if it doesn't exist
    [ -d "$MOUNT_POINT" ] || { log_message "Creating mount point $(bracket "$MOUNT_POINT")..."; mkdir -p "$MOUNT_POINT" || handle_error "Failed to create mount point $(bracket "$MOUNT_POINT")"; log_message "-> Mount point $(bracket "$MOUNT_POINT") created successfully"; }
    
    # Mount the USB device
    log_message "Mounting USB device /dev/$USB_DEVICE to $(bracket "$MOUNT_POINT")..."
    mount "/dev/$USB_DEVICE" "$MOUNT_POINT" || handle_error "Failed to mount USB device /dev/$USB_DEVICE to $(bracket "$MOUNT_POINT")"
    USB_MOUNT="$MOUNT_POINT"
    get_usb_stats "$USB_DEVICE" "$USB_MOUNT"
fi

# Step 3: Perform rsync
log_message "Starting rsync from $(bracket "$SOURCE_DIR") to $(bracket "$USB_MOUNT")"
rsync -av --progress "$SOURCE_DIR/" "$USB_MOUNT/" >> "$LOG_FILE" 2>&1 || { 
    [ "$USB_MOUNT" = "$MOUNT_POINT" ] && { log_message "Unmounting USB device from $(bracket "$MOUNT_POINT") due to rsync failure..."; umount "$MOUNT_POINT" && log_message "-> USB device unmounted successfully from $(bracket "$MOUNT_POINT")" || log_message "ERROR: Failed to unmount USB device from $(bracket "$MOUNT_POINT")"; }
    handle_error "Rsync failed"
}

log_message "Rsync completed successfully"

# Step 4: Unmount USB if we mounted it
if [ "$USB_MOUNT" = "$MOUNT_POINT" ]; then
    log_message "Unmounting USB device from $(bracket "$MOUNT_POINT")..."
    umount "$MOUNT_POINT" && log_message "-> USB device unmounted successfully from $(bracket "$MOUNT_POINT")" || handle_error "Failed to unmount USB device from $(bracket "$MOUNT_POINT")"
fi

log_message "Backup script completed"
exit 0