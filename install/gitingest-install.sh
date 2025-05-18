#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: 1bk
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/cyclotruc/gitingest

# Import Functions und Setup
source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# Installing Dependencies
msg_info "Installing Dependencies"
$STD apt-get update
$STD apt-get install -y \
  python3 \
  python3-pip \
  python3-dev \
  git \
  curl \
  python3-venv
msg_ok "Installed Dependencies"

# Setup App
msg_info "Setting up GitIngest"
RELEASE=$(curl -fsSL https://api.github.com/repos/cyclotruc/gitingest/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
if [ -z "$RELEASE" ]; then
  RELEASE="main"  # Default to main branch if no release is found
fi

# Clone the repository
$STD git clone https://github.com/cyclotruc/gitingest.git /opt/gitingest-source

# Set up the target directory
mkdir -p /opt/gitingest

# Copy the correct files
$STD cp -r /opt/gitingest-source/src/* /opt/gitingest/
$STD cp /opt/gitingest-source/requirements.txt /opt/gitingest/

# Install Python requirements
cd /opt/gitingest
$STD pip install --no-cache-dir -r requirements.txt

# Get the container IP
CONTAINER_IP=$(hostname -I | awk '{print $1}')

# Create the .env file with default settings
cat <<EOF > /opt/gitingest/.env
# Server configuration
ALLOWED_HOSTS="$CONTAINER_IP,localhost,127.0.0.1"
EOF

# Ask for custom domain settings
read -p "${TAB3}Do you want to configure custom domain settings? (y/N): " domain_choice
if [[ "$domain_choice" =~ ^[Yy]$ ]]; then
  read -p "${TAB3}Enter your custom domain (e.g., example.com): " custom_domain
  if [ ! -z "$custom_domain" ]; then
    # Update the ALLOWED_HOSTS with custom domain, wildcard subdomains, and keep the IP address
    sed -i "s|ALLOWED_HOSTS=\".*\"|ALLOWED_HOSTS=\"$custom_domain,*.$custom_domain,$CONTAINER_IP,localhost,127.0.0.1\"|" /opt/gitingest/.env
    
    echo "Custom domain configured: $custom_domain and its subdomains (along with $CONTAINER_IP)"
  fi
fi

# Create a service file for GitIngest
msg_info "Creating GitIngest service"
cat <<EOF > /etc/systemd/system/gitingest.service
[Unit]
Description=GitIngest Service
After=network.target

[Service]
User=root
WorkingDirectory=/opt/gitingest
ExecStart=/usr/bin/python3 -m uvicorn server.main:app --host 0.0.0.0 --port 8000
Restart=always
Environment=PYTHONUNBUFFERED=1
Environment=PYTHONDONTWRITEBYTECODE=1

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the service
systemctl enable -q --now gitingest
msg_ok "Created and started GitIngest service"

# Clean up source files
rm -rf /opt/gitingest-source

# Save version info
echo "${RELEASE}" > /opt/gitingest_version.txt
msg_ok "Set up GitIngest v${RELEASE}"

# Add instructions to /root/GitIngest.creds
{
  echo "GitIngest Installation Information"
  echo "--------------------------------"
  echo "Access URL: http://$CONTAINER_IP:8000"
  echo "To update: Run the update function in the container"
  echo "Version: ${RELEASE}"
} > ~/GitIngest.creds

motd_ssh
customize

# Cleanup
msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
