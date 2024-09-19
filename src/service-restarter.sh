#!/bin/bash

# Determine the app name based on the script file name
APP_NAME=$(basename "$0")
CONF_FILE="/etc/${APP_NAME}.conf"

# Check if the configuration file exists
if [[ ! -f "$CONF_FILE" ]]; then
    echo "Error: Configuration file $CONF_FILE not found."
    exit 1
fi

# Source the configuration file
source "$CONF_FILE"

# Validate required variables from the configuration file
if [[ -z "$APP_PATH" ]]; then
    echo "Error: APP_PATH is not set in $CONF_FILE."
    exit 1
fi

# Path to the file you want to monitor
FILE_PATH="$APP_PATH/last_update"

# Temporary file to store the last known hash
LAST_HASH_FILE="/tmp/last_known_hash_${APP_NAME}"

# Function to compute the MD5 checksum of the given file
compute_hash() {
    cat "$1" | md5sum | awk '{print $1}'
}

# Function to restart systemctl services
restart_systemctl_services() {
    if [[ -n "$SYSTEMCTL_SERVICES" ]]; then
        IFS=',' read -ra SERVICES <<< "$SYSTEMCTL_SERVICES"
        for SERVICE in "${SERVICES[@]}"; do
            echo "Restarting systemctl service: $SERVICE"
            systemctl restart "$SERVICE"
        done
    fi
}

# Function to restart supervisor services
restart_supervisor_services() {
    if [[ -n "$SUPERVISOR_SERVICES" ]]; then
        IFS=',' read -ra SERVICES <<< "$SUPERVISOR_SERVICES"
        for SERVICE in "${SERVICES[@]}"; do
            echo "Restarting supervisor service: $SERVICE"
            supervisorctl restart "$SERVICE"
        done
    fi
}

# Function to restart pm2 services
restart_pm2_services() {
    if [[ -n "$PM2_SERVICES" ]]; then
        IFS=',' read -ra SERVICES <<< "$PM2_SERVICES"
        for SERVICE in "${SERVICES[@]}"; do
            echo "Restarting pm2 service: $SERVICE"
            pm2 restart "$SERVICE"
        done
    fi
}

# Infinite loop to check the file
while true; do
    # Compute current hash
    CURRENT_HASH=$(compute_hash "$FILE_PATH")

    # If last known hash file exists, read it, otherwise assume empty
    if [[ -f $LAST_HASH_FILE ]]; then
        LAST_HASH=$(cat "$LAST_HASH_FILE")
    else
        LAST_HASH=""
    fi

    # If the hashes don't match, the file has changed
    if [[ $CURRENT_HASH != $LAST_HASH ]]; then
        date
        # Save current hash as the last known hash
        echo "$CURRENT_HASH" > "$LAST_HASH_FILE"

        # Restart the services as per the configuration
        restart_systemctl_services
        restart_supervisor_services
        restart_pm2_services
    fi

    # Wait for a bit before checking again (e.g., 10 seconds)
    sleep 5
done