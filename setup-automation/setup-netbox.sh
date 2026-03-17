#!/bin/bash
set -euo pipefail

###############################################################################
# Retry helper
###############################################################################
retry() {
    local max_attempts=3
    local delay=5
    local desc="$1"
    shift

    for ((i = 1; i <= max_attempts; i++)); do
        echo "Attempt $i/$max_attempts: $desc"
        if "$@"; then
            return 0
        fi
        if [ $i -lt $max_attempts ]; then
            echo "  Failed. Retrying in ${delay}s..."
            sleep $delay
        fi
    done

    echo "FATAL: Failed after $max_attempts attempts: $desc"
    exit 1
}

###############################################################################
# Validate required variables
###############################################################################
for var in SATELLITE_URL SATELLITE_ORG SATELLITE_ACTIVATIONKEY; do
    if [ -z "${!var:-}" ]; then
        echo "ERROR: $var is not set"
        exit 1
    fi
done

###############################################################################
# Clean up existing repos, subscriptions, and registration
###############################################################################
rm -rf /etc/yum.repos.d/*
yum clean all

subscription-manager unregister 2>/dev/null || true
subscription-manager remove --all 2>/dev/null || true
subscription-manager clean

# Remove old Katello consumer RPM if present
OLD_KATELLO=$(rpm -qa | grep katello-ca-consumer || true)
if [ -n "$OLD_KATELLO" ]; then
    rpm -e "$OLD_KATELLO"
fi

###############################################################################
# Register with Satellite
###############################################################################
retry "Download Katello CA cert" \
    curl -sS -k -L \
    "https://${SATELLITE_URL}/pub/katello-server-ca.crt" \
    -o "/etc/pki/ca-trust/source/anchors/${SATELLITE_URL}.ca.crt"

retry "Update CA trust" \
    update-ca-trust

retry "Install Katello consumer RPM" \
    rpm -Uhv --force "https://${SATELLITE_URL}/pub/katello-ca-consumer-latest.noarch.rpm"

retry "Register with Satellite" \
    subscription-manager register \
    --org="${SATELLITE_ORG}" \
    --activationkey="${SATELLITE_ACTIVATIONKEY}"

retry "Refresh subscription" \
    subscription-manager refresh

###############################################################################
# Install packages and Docker
###############################################################################
retry "Install base packages" \
    dnf install -y dnf-utils git nano

retry "Add Docker repo" \
    dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

retry "Install Docker" \
    dnf install -y \
    docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin

setenforce 0

###############################################################################
# Network configuration
###############################################################################
nmcli connection add type ethernet con-name eth1 ifname eth1 \
    ipv4.addresses 192.168.1.15/24 \
    ipv4.method manual \
    connection.autoconnect yes

nmcli connection up eth1

###############################################################################
# /etc/hosts entries
###############################################################################
cat >> /etc/hosts <<EOF
192.168.1.10 control.zta.lab control
192.168.1.11 central.zta.lab keycloak.zta.lab opa.zta.lab
192.168.1.12 vault.zta.lab vault
192.168.1.13 wazuh.zta.lab wazuh
192.168.1.14 node01.zta.lab node01
192.168.1.15 netbox.zta.lab netbox
EOF

###############################################################################
# Clone NetBox Docker repo
###############################################################################
rm -rf /tmp/netbox-docker
retry "Clone netbox-docker repo" \
    git clone --depth=1 -b 3.3.0 \
    https://github.com/netbox-community/netbox-docker.git /tmp/netbox-docker

###############################################################################
# Docker Compose override
###############################################################################
cat > /tmp/netbox-docker/docker-compose.override.yml <<'EOF'
services:
  netbox:
    ports:
      - "8000:8080"
    environment:
      ALLOWED_HOSTS: "*"
      POSTGRES_USER: "netbox"
      POSTGRES_PASSWORD: "netbox"
      POSTGRES_DB: "netbox"
      POSTGRES_HOST: "postgres"
      REDIS_HOST: "redis"
      SKIP_SUPERUSER: "false"
      SUPERUSER_EMAIL: "admin@example.com"
      SUPERUSER_PASSWORD: "netbox"
      SUPERUSER_NAME: "admin"
    healthcheck:
      start_period: 180s
EOF

###############################################################################
# Start Docker and deploy NetBox
###############################################################################
systemctl enable --now docker

# Wait for Docker socket
for i in {1..10}; do
    docker info &>/dev/null && break
    echo "Waiting for Docker daemon... ($i)"
    sleep 2
done

retry "Pull NetBox images" \
    docker compose --project-directory=/tmp/netbox-docker pull

retry "Start NetBox containers" \
    docker compose --project-directory=/tmp/netbox-docker up -d netbox netbox-worker

echo "Setup complete!"
