#!/bin/bash

# --- Configuration ---
# The internal storage root on the phone
SDCARD_ROOT="/sdcard"

# The local directory where backups will be stored (created in the current directory)
LOCAL_BACKUP_DIR="./Backups"

# --- Source Directories ---
# These paths are relative to /sdcard/ on the device
DIRECTORIES=(
    "Alarms"
    "AppManager"
    "DCIM"
    "Download"
    "Movies"
    "Notifications"
    "Podcasts"
    "Ringtones"
    "SwiftBackup"
    "Audiobooks"
    "Documents"
    "Mods"
    "Music"
    "Pictures"
    "Recordings"
    "Snapseed"
    "Tasker"
)

# The specific path for WhatsApp media (handled separately due to its structure)
WHATSAPP_MEDIA_PATH="Android/media/com.whatsapp"

# Array to hold only the paths confirmed to exist on the device (relative to /sdcard)
declare -a EXISTING_DIRECTORIES

# --- Core Functions ---

# Function to check ADB connection
check_adb_status() {
    echo "--- System Check ---"
    if ! adb get-state > /dev/null 2>&1; then
        echo "🛑 ERROR: ADB not connected or device offline."
        echo "Please ensure USB Debugging is enabled and the device is connected."
        exit 1
    fi
    echo "✅ ADB connection verified."
    # Use adb shell to get device model info
    DEVICE_MODEL=$(adb shell getprop ro.product.model | tr -d '\r')
    echo "Device Model: ${DEVICE_MODEL:-Unknown Android Device}"
    echo "Local Backup Path: $(pwd)/$LOCAL_BACKUP_DIR"
    echo "Device Storage Root: $SDCARD_ROOT"
    echo "--------------------"
}

# Function to check which directories exist on the device
check_device_directories() {
    echo "--- Device Directory Check ---"
    
    # Check standard directories
    for dir in "${DIRECTORIES[@]}"; do
        FULL_PATH="$SDCARD_ROOT/$dir"
        # adb shell test -d checks if the path is a directory. $? returns 0 if true.
        if adb shell test -d "$FULL_PATH"; then
            EXISTING_DIRECTORIES+=("$dir")
        else
            echo "⚠️  MISSING: $FULL_PATH"
        fi
    done
    
    # Check WhatsApp media path separately
    WHATSAPP_FULL_PATH="$SDCARD_ROOT/$WHATSAPP_MEDIA_PATH"
    if adb shell test -d "$WHATSAPP_FULL_PATH"; then
        EXISTING_DIRECTORIES+=("$WHATSAPP_MEDIA_PATH")
    else
        echo "⚠️  MISSING: $WHATSAPP_FULL_PATH"
    fi

    echo "----------------------------"
    echo "✅ ${#EXISTING_DIRECTORIES[@]} of $(( ${#DIRECTORIES[@]} + 1 )) directories confirmed to exist and will be used."
    echo "----------------------------"
}

# Function to display the list of directories being backed up/restored
show_directory_list() {
    echo "Directories Targeted for Transfer (Confirmed to Exist on Device):"
    for dir in "${EXISTING_DIRECTORIES[@]}"; do
        echo "  - $SDCARD_ROOT/$dir"
    done
}

# Function to perform the Backup operation (adb pull)
perform_backup() {
    echo ""
    echo "--- Starting Backup (adb pull) ---"
    
    # 1. Create the local backup directory
    mkdir -p "$LOCAL_BACKUP_DIR"
    echo "Created local backup directory: $LOCAL_BACKUP_DIR"
    echo ""

    # 2. Process only the directories that were confirmed to exist
    for dir in "${EXISTING_DIRECTORIES[@]}"; do
        
        # FIX: Ensure we always use the full absolute path for adb pull
        SOURCE_PATH="$SDCARD_ROOT/$dir"
        
        echo "  > Backing up: $SOURCE_PATH"
        # adb pull copies the source path to the local directory
        adb pull "$SOURCE_PATH" "$LOCAL_BACKUP_DIR/"
        
        if [ $? -ne 0 ]; then
            echo "  [WARNING] Failed to pull $SOURCE_PATH. (Check device storage access or permissions)"
        fi
    done

    echo ""
    echo "--- Backup Complete ---"
    echo "All available files copied to: $LOCAL_BACKUP_DIR"
}

# Function to perform the Restore operation (adb push)
perform_restore() {
    echo ""
    echo "--- Starting Restore (adb push) ---"
    
    # 1. Check if the local backup directory exists
    if [ ! -d "$LOCAL_BACKUP_DIR" ]; then
        echo "🛑 ERROR: Backup directory not found at $LOCAL_BACKUP_DIR."
        echo "Cannot restore. Please run this script in the correct location."
        exit 1
    fi
    echo "Source backup directory verified: $LOCAL_BACKUP_DIR"
    echo "Files will be MERGED, and existing files on the phone will be OVERRIDDEN."
    echo ""
    
    # 2. Process all original target directories, checking for existence in the backup locally
    for dir in "${DIRECTORIES[@]}"; do
        SOURCE_PATH="$LOCAL_BACKUP_DIR/$dir"

        if [ -d "$SOURCE_PATH" ]; then
            echo "  > Restoring: $SOURCE_PATH to $SDCARD_ROOT/$dir"
            # adb push: copies the entire directory structure, overriding existing files.
            # Pushing the local folder 'DCIM' to '/sdcard/' results in '/sdcard/DCIM'
            adb push "$SOURCE_PATH" "$SDCARD_ROOT/"
            if [ $? -ne 0 ]; then
                echo "  [WARNING] Failed to push $SOURCE_PATH. (Check device permissions)"
            fi
        else
            echo "  [WARNING] Local directory not found in backup: $dir (Skipping restore)"
        fi
    done

    # 3. Handle the specific WhatsApp path (pushing the parent 'Android' folder)
    WHATSAPP_SOURCE_DIR="$LOCAL_BACKUP_DIR/Android"
    
    if [ -d "$WHATSAPP_SOURCE_DIR" ]; then
        echo "  > Restoring: $WHATSAPP_SOURCE_DIR to $SDCARD_ROOT/Android"
        # Pushing local 'Android' to '/sdcard/' results in '/sdcard/Android/'
        adb push "$WHATSAPP_SOURCE_DIR" "$SDCARD_ROOT/"
        if [ $? -ne 0 ]; then
            echo "  [WARNING] Failed to push $WHATSAPP_SOURCE_DIR. (Check device permissions)"
        fi
    else
        echo "  [WARNING] Local 'Android' directory (containing WhatsApp media) not found in backup. (Skipping restore)"
    fi

    echo ""
    echo "--- Restore Complete ---"
    echo "Files successfully pushed to the Pixel's storage."
}


# --- Main CLI Logic ---

# 1. Initial checks
check_adb_status

# 2. Check for device directories and populate the list of existing ones
check_device_directories

# 3. Show details before prompting
show_directory_list

# 4. Ask user for action
echo ""
read -r -p "What operation do you want to perform? (Enter 'B' for Backup or 'R' for Restore): " action

case "$action" in
    [Bb]* )
        perform_backup
        ;;
    [Rr]* )
        perform_restore
        ;;
    * )
        echo "Invalid choice. Exiting script."
        exit 1
        ;;
esac

# 5. Final confirmation message
echo ""
echo "Script finished executing."