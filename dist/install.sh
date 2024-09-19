#!/bin/bash

# Define color codes
BOLD_BLUE="\033[1;34m"
RESET_COLOR="\033[0m"

# Default app name
DEFAULT_APP_NAME="service-restarter"

set_fresh_view() {
    clear
    echo -e "${BOLD_BLUE}Service Restarter Installer${RESET_COLOR}"
    echo "--------------------------"
}

# Function to prompt for app name
get_app_name() {
    set_fresh_view
    read -p "Enter restarter name (default: $DEFAULT_APP_NAME): " APP_NAME
    APP_NAME=${APP_NAME:-$DEFAULT_APP_NAME}
    
    # If user enters a partial name, append '-restarter'
    if [[ "$APP_NAME" != *"-restarter" ]]; then
        APP_NAME="${APP_NAME}-restarter"
    fi
    echo "Using app name: $APP_NAME"
}
# Function to set paths
set_paths() {
    BIN_PATH="/usr/local/bin/$APP_NAME"
    CONF_PATH="/etc/$APP_NAME.conf"
}

# Function to determine supervisor config path
get_supervisor_conf_path() {
    if [ -d "/etc/supervisor.d/" ]; then
        SUPERVISOR_CONF="/etc/supervisor.d/${APP_NAME}.conf"
    elif [ -d "/etc/supervisor/conf.d/" ]; then
        SUPERVISOR_CONF="/etc/supervisor/conf.d/${APP_NAME}.conf"
    else
        echo "Neither /etc/supervisor.d/ nor /etc/supervisor/conf.d/ exists."
        read -p "Please enter the supervisor config directory path: " custom_path
        SUPERVISOR_CONF="${custom_path}/${APP_NAME}.conf"
    fi
    echo "Supervisor config path: $SUPERVISOR_CONF"
}

# Function to validate app path
validate_app_path() {
    read -p "Enter the app directory path (default: $(pwd)): " APP_PATH
    APP_PATH=${APP_PATH:-$(pwd)}
    
    if [ ! -d "$APP_PATH" ]; then
        echo "Error: Directory $APP_PATH does not exist."
        exit 1
    elif [ ! -w "$APP_PATH" ]; then
        echo "Error: Directory $APP_PATH is not writable."
        exit 1
    fi
}

# Function to touch last_update file
touch_last_update() {
    touch "$APP_PATH/last_update"
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to touch last_update in $APP_PATH."
        exit 1
    fi
    echo "Touched last_update in $APP_PATH."
}

download_system_packages() {
    if [[ -f "/usr/bin/apt" ]]
    then
        apt update
        apt install -y curl fzf supervisor
    elif [[ -f "/usr/bin/yum" ]]
    then
        yum install -y curl fzf supervisor
    elif [[ -f "/usr/bin/dnf" ]]
    then
        dnf install -y curl fzf supervisor
    elif [[ -f "/usr/bin/pacman" ]]
    then
        pacman -S --noconfirm curl fzf supervisor
    else
        echo "Error: Could not install dependencies. APT and Yum are supported right now. Please install curl,fzf and supervisor manually."
        exit 1
    fi
}

# Function to download service-restarter script
download_dependencies() {
    curl -s -o /tmp/$APP_NAME.sh https://raw.githubusercontent.com/pxpxltd/service-restarter/refs/heads/master/src/service-restarter.sh
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to download service-restarter.sh from GitHub."
        exit 1
    fi
    curl -s -o /tmp/${APP_NAME}-conf https://raw.githubusercontent.com/pxpxltd/service-restarter/refs/heads/master/templates/etc.conf
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to download config template from GitHub."
        exit 1
    fi

    curl -s -o /tmp/${APP_NAME}-supervisor.conf https://raw.githubusercontent.com/pxpxltd/service-restarter/refs/heads/master/templates/supervisor.conf
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to download config template from GitHub."
        exit 1
    fi
}

# Function to create or update the binary
create_or_update_binary() {
    if [[ -f "$BIN_PATH" ]]; then
        echo "$BIN_PATH already exists."
        read -p "Do you want to update it or create a new instance? [update/new]: " CHOICE
    else
        CHOICE="new"
    fi

    if [[ "$CHOICE" == "update" ]]; then
        cp "$BIN_PATH" "${BIN_PATH}.bak"
        cp /tmp/$APP_NAME.sh "$BIN_PATH"
        chmod +x "$BIN_PATH"
        echo "Updated $BIN_PATH."
    else
        get_app_name
    fi
}

# Function to create a new instance
create_new_instance() {
    while [[ -f "$BIN_PATH" ]]; do
        echo "$BIN_PATH already exists."
        read -p "Enter a new app name (e.g., node, php-fpm): " APP_CORE_NAME
        APP_NAME="${APP_CORE_NAME}-restarter"
        BIN_PATH="/usr/local/bin/$APP_NAME"
        CONF_PATH="/etc/$APP_NAME.conf"
        SUPERVISOR_CONF="/etc/supervisor.d/${APP_NAME}.conf"
    done

    cp /tmp/$APP_NAME.sh "$BIN_PATH"
    chmod +x "$BIN_PATH"
    echo "Created new restarter: $BIN_PATH."
}

# Function to get services to restart
get_services_to_restart() {
    # Check if fzf is installed
    if ! command -v fzf &> /dev/null; then
        echo "fzf not installed. Please install fzf to use this feature."
        exit 1
    fi

    echo "Select the services to restart. Use TAB to select multiple entries and Enter to confirm."

    # Get available systemctl services
    SYSTEMCTL_SERVICES_LIST=$(systemctl list-units --type=service --all  | awk '{print $1}' | fzf --multi --prompt="Select systemctl services (TAB to select, ENTER to proceed): ")

    if [[ -z "$SYSTEMCTL_SERVICES_LIST" ]]; then
        SYSTEMCTL_SERVICES_LIST="php-fpm,php8.2-fpm,php8.3-fpm"
        echo "No systemctl services selected. Using defaults: $SYSTEMCTL_SERVICES_LIST"
    else
        SYSTEMCTL_SERVICES_LIST=$(echo "$SYSTEMCTL_SERVICES_LIST" | tr '\n' ',')
        SYSTEMCTL_SERVICES_LIST=${SYSTEMCTL_SERVICES_LIST%,}  # Remove trailing comma
        echo "Selected systemctl services: $SYSTEMCTL_SERVICES_LIST"
    fi

    # Check for supervisor services
    if [[ -d "/etc/supervisor.d/" || -d "/etc/supervisor/conf.d/" ]]; then
        SUPERVISOR_SERVICES_LIST=$(supervisorctl status | awk '{print $1}' | fzf --multi --prompt="Select supervisor services: ")

        if [[ -z "$SUPERVISOR_SERVICES_LIST" ]]; then
            SUPERVISOR_SERVICES_LIST=""
            echo "No supervisor services selected."
        else
            SUPERVISOR_SERVICES_LIST=$(echo "$SUPERVISOR_SERVICES_LIST" | tr '\n' ',')
            SUPERVISOR_SERVICES_LIST=${SUPERVISOR_SERVICES_LIST%,}
            echo "Selected supervisor services: $SUPERVISOR_SERVICES_LIST"
        fi
    else
        SUPERVISOR_SERVICES_LIST=""
        echo "No supervisor services found."
    fi

    # Check if PM2 is installed and list services
    if command -v pm2 &> /dev/null; then
        PM2_SERVICES_LIST=$(pm2 list | awk 'NR>3 {print $2}' | fzf --multi --prompt="Select PM2 services: ")

        if [[ -z "$PM2_SERVICES_LIST" ]]; then
            PM2_SERVICES_LIST=""
            echo "No PM2 services selected."
        else
            PM2_SERVICES_LIST=$(echo "$PM2_SERVICES_LIST" | tr '\n' ',')
            PM2_SERVICES_LIST=${PM2_SERVICES_LIST%,}
            echo "Selected PM2 services: $PM2_SERVICES_LIST"
        fi
    else
        PM2_SERVICES_LIST=""
        echo "PM2 is not installed or no services found."
    fi

    # Assign the selected values to global variables
    SYSTEMCTL_SERVICES=${SYSTEMCTL_SERVICES_LIST:-"php-fpm,php8.2-fpm,php8.3-fpm"}
    SUPERVISOR_SERVICES=${SUPERVISOR_SERVICES_LIST:-""}
    PM2_SERVICES=${PM2_SERVICES_LIST:-""}
}

# Function to configure service restarter
configure_service_restarter() {
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to download configuration file."
        exit 1
    fi

    sed -e "s|REPLACE_APP_PATH|$APP_PATH|g" \
        -e "s|REPLACE_APP_NAME|$APP_NAME|g" \
        -e "s|php-fpm,php8.2-fpm,php8.3-fpm|$SYSTEMCTL_SERVICES|g" \
        -e "s|my-supervisor-service-1,my-supervisor-service-2|$SUPERVISOR_SERVICES|g" \
        -e "s|my-pm2-app-1,my-pm2-app-2|$PM2_SERVICES|g" \
        /tmp/${APP_NAME}-conf > "$CONF_PATH"

    echo "Configuration file created at $CONF_PATH."
}

# Function to configure supervisor
configure_supervisor() {
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to download supervisor config file."
        exit 1
    fi

    sed -e "s|APP_NAME|$APP_NAME|g" \
        -e "s|APP_PATH|$APP_PATH|g" \
        -e "s|/usr/local/bin/APP_NAME|/usr/local/bin/$APP_NAME|g" \
        /tmp/${APP_NAME}-supervisor.conf > "$SUPERVISOR_CONF"

    echo "Supervisor config created at $SUPERVISOR_CONF."
}

# Function to reload supervisor
reload_supervisor() {
    supervisorctl reread
    read -p "Do you want to start the supervisor services now? [y/N]: " START_SUPERVISOR
    if [[ "$START_SUPERVISOR" == "y" ]]; then
        supervisorctl update
    fi
}

# Function to clean up temporary files
cleanup() {
    echo "Cleaning up temporary files..."
    rm /tmp/$APP_NAME.sh /tmp/${APP_NAME}-conf /tmp/${APP_NAME}-supervisor.conf
    echo "Installation of $APP_NAME completed."
}

# Main execution flow
main() {
    get_app_name
    set_paths
    download_dependencies
    create_or_update_binary
    get_supervisor_conf_path
    validate_app_path
    touch_last_update
    get_services_to_restart
    configure_service_restarter
    configure_supervisor
    reload_supervisor
    cleanup
}

# Run the main function
main