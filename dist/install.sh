#!/bin/bash

# Default app name is "service-restarter"
DEFAULT_APP_NAME="service-restarter"

# Ask for the app name
read -p "Enter the app name (default: $DEFAULT_APP_NAME): " APP_NAME
APP_NAME=${APP_NAME:-$DEFAULT_APP_NAME}

# Set the paths
BIN_PATH="/usr/local/bin/$APP_NAME"
CONF_PATH="/etc/$APP_NAME.conf"
SUPERVISOR_CONF="/etc/supervisor.d/${APP_NAME}.conf"

# Check if /usr/local/bin/$APP_NAME exists
if [[ -f "$BIN_PATH" ]]; then
    echo "$BIN_PATH already exists."
    read -p "Do you want to update it or create a new instance? [update/new]: " CHOICE
else
    CHOICE="new"
fi

# Ask for the app directory path (default to current directory)
read -p "Enter the app directory path (default: $(pwd)): " APP_PATH

# If no input is given, use the current directory
APP_PATH=${APP_PATH:-$(pwd)}

# Validate the app directory
if [ ! -d "$APP_PATH" ]; then
    echo "Error: Directory $APP_PATH does not exist."
    exit 1
fi

if [ ! -w "$APP_PATH" ]; then
    echo "Error: Directory $APP_PATH is not writable."
    exit 1
fi

# Touch the last_update file within the app path
touch "$APP_PATH/last_update"
if [[ $? -ne 0 ]]; then
    echo "Error: Failed to touch last_update in $APP_PATH."
    exit 1
fi
echo "Touched last_update in $APP_PATH."

# Download the service-restarter script
curl -o /tmp/$APP_NAME.sh https://raw.githubusercontent.com/pxpxltd/service-restarter/master/src/service-restarter.sh
if [[ $? -ne 0 ]]; then
    echo "Error: Failed to download service-restarter.sh from GitHub."
    exit 1
fi

# Update or create a new instance based on user input
if [[ "$CHOICE" == "update" ]]; then
    # Backup and update
    cp "$BIN_PATH" "${BIN_PATH}.bak"
    cp /tmp/$APP_NAME.sh "$BIN_PATH"
    chmod +x "$BIN_PATH"
    echo "Updated $BIN_PATH."
else
    # Ask for a new name if creating a new instance
    while [[ -f "$BIN_PATH" ]]; do
        echo "$BIN_PATH already exists."
        read -p "Enter a new app name (e.g., node, php-fpm): " APP_CORE_NAME
        APP_NAME="${APP_CORE_NAME}-restarter"
        BIN_PATH="/usr/local/bin/$APP_NAME"
        CONF_PATH="/etc/$APP_NAME.conf"
        SUPERVISOR_CONF="/etc/supervisor.d/${APP_NAME}.conf"
    done

    # Copy and make executable
    cp /tmp/$APP_NAME.sh "$BIN_PATH"
    chmod +x "$BIN_PATH"
    echo "Created new restarter: $BIN_PATH."
fi

# Step to define services to restart with defaults (modify services if needed)
echo "Define services to restart. Press Enter to accept defaults."
read -p "Systemctl services to restart (default: php-fpm,php8.2-fpm,php8.3-fpm): " SYSTEMCTL_SERVICES
SYSTEMCTL_SERVICES=${SYSTEMCTL_SERVICES:-"php-fpm,php8.2-fpm,php8.3-fpm"}

read -p "Supervisor services to restart (default: none): " SUPERVISOR_SERVICES
SUPERVISOR_SERVICES=${SUPERVISOR_SERVICES:-""}

read -p "PM2 services to restart (default: none): " PM2_SERVICES
PM2_SERVICES=${PM2_SERVICES:-""}

# Download the template configuration file for the service
curl -o /tmp/${APP_NAME}-conf https://raw.githubusercontent.com/pxpxltd/service-restarter/master/templates/etc.conf
if [[ $? -ne 0 ]]; then
    echo "Error: Failed to download configuration file."
    exit 1
fi

# Replace placeholders in the configuration template and copy to /etc
sed -e "s|REPLACE_APP_PATH|$APP_PATH|g" \
    -e "s|REPLACE_APP_NAME|$APP_NAME|g" \
    -e "s|php-fpm,php8.2-fpm,php8.3-fpm|$SYSTEMCTL_SERVICES|g" \
    -e "s|my-supervisor-service-1,my-supervisor-service-2|$SUPERVISOR_SERVICES|g" \
    -e "s|my-pm2-app-1,my-pm2-app-2|$PM2_SERVICES|g" \
    /tmp/${APP_NAME}-conf > "$CONF_PATH"
echo "Configuration file created at $CONF_PATH."

# Download the supervisor template and configure it
curl -o /tmp/${APP_NAME}-supervisor.conf https://raw.githubusercontent.com/pxpxltd/service-restarter/master/templates/supervisor.conf
if [[ $? -ne 0 ]]; then
    echo "Error: Failed to download supervisor config file."
    exit 1
fi

# Replace placeholders in the supervisor template and copy to supervisor.d
# Replace placeholders in the supervisor template and copy to supervisor.d
sed -e "s|APP_NAME|$APP_NAME|g" \
    -e "s|APP_PATH|$APP_PATH|g" \
    -e "s|/usr/local/bin/APP_NAME-restarter|/usr/local/bin/$APP_NAME-restarter|g" \
    /tmp/${APP_NAME}-supervisor.conf > "$SUPERVISOR_CONF"
echo "Supervisor config created at $SUPERVISOR_CONF."

# Reload supervisor to apply the new configuration
supervisorctl reread
read -p "Do you want to start the supervisor services now? [y/N]: " START_SUPERVISOR
if [[ "$START_SUPERVISOR" == "y" ]]; then
    supervisorctl update
fi

echo "Installation of $APP_NAME completed."