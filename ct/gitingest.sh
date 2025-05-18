#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/1bk/ProxmoxVE/feature%2Fadd-gitingest/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: 1bk
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/cyclotruc/gitingest

# App Default Values
APP="GitIngest"
# Ensure app is defined properly to match APP in lowercase
export app="gitingest"
var_tags="${var_tags:-ingest;code-tools}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  # Check if installation is present
  if [[ ! -d /opt/gitingest ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  # Check for new version on GitHub
  CURRENT_VERSION=$(cat /opt/${APP}_version.txt 2>/dev/null || echo "0.0.0")
  RELEASE=$(curl -fsSL https://api.github.com/repos/cyclotruc/gitingest/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
  
  if [[ "${RELEASE}" != "${CURRENT_VERSION}" ]]; then
    msg_info "Updating ${APP} to v${RELEASE}"
    
    # Stop service
    msg_info "Stopping GitIngest service"
    systemctl stop gitingest
    msg_ok "Stopped GitIngest service"
    
    # Create backup
    msg_info "Creating backup"
    BACKUP_DIR="/opt/gitingest_backup_$(date +%F_%H-%M-%S)"
    mkdir -p $BACKUP_DIR
    cp -r /opt/gitingest/. $BACKUP_DIR/
    msg_ok "Created backup at $BACKUP_DIR"
    
    # Update application
    msg_info "Installing new version"
    $STD git clone https://github.com/cyclotruc/gitingest.git /opt/gitingest-source
    
    # Preserve the .env file
    if [ -f /opt/gitingest/.env ]; then
      cp /opt/gitingest/.env /opt/gitingest-source/
    fi
    
    # Replace installation with new version
    rm -rf /opt/gitingest
    mkdir -p /opt/gitingest
    $STD cp -r /opt/gitingest-source/src/* /opt/gitingest/
    $STD cp /opt/gitingest-source/requirements.txt /opt/gitingest/
    
    # Restore the .env file
    if [ -f /opt/gitingest-source/.env ]; then
      cp /opt/gitingest-source/.env /opt/gitingest/
    else
      # Get the container IP
      CONTAINER_IP=$(hostname -I | awk '{print $1}')
      
      # Create default .env file if none exists
      cat <<EOF > /opt/gitingest/.env
# Server configuration
ALLOWED_HOSTS="$CONTAINER_IP,localhost,127.0.0.1"
EOF
    fi
    
    # Install Python requirements
    cd /opt/gitingest
    $STD pip install --no-cache-dir -r requirements.txt
    
    # Clean up source files
    rm -rf /opt/gitingest-source
    
    # Start service
    msg_info "Starting GitIngest service"
    systemctl start gitingest
    msg_ok "Started GitIngest service"
    
    # Update version file
    echo "${RELEASE}" > /opt/${APP}_version.txt
    
    # Cleanup
    msg_info "Cleaning up"
    rm -rf $BACKUP_DIR
    msg_ok "Cleaned up"
    
    msg_ok "Updated ${APP} to v${RELEASE}"
  else
    msg_ok "No update required. ${APP} is already at v${RELEASE}"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8000${CL}"
