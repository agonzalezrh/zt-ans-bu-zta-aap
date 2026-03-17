#!/bin/bash

retry() {
    local cmd="$1"
    local desc="${2:-$1}"
    for i in {1..3}; do
        echo "Attempt $i: $desc"
        if eval "$cmd"; then
            return 0
        fi
        [ $i -lt 3 ] && sleep 5
    done
    echo "Failed after 3 attempts: $desc"
    exit 1
}

# Validate required variables
for var in SATELLITE_URL SATELLITE_ORG SATELLITE_ACTIVATIONKEY; do
    if [ -z "${!var}" ]; then
        echo "ERROR: $var is not set"
        exit 1
    fi
done

# Clean up existing repos, subscriptions, and registration
rm -rf /etc/yum.repos.d/*
yum clean all
subscription-manager unregister 2>/dev/null || true
subscription-manager remove --all 2>/dev/null || true
subscription-manager clean

# Remove old Katello consumer RPM if present
rpm -e $(rpm -qa | grep katello-ca-consumer) 2>/dev/null || true

# Register with Satellite
retry "curl -sS -k -L https://${SATELLITE_URL}/pub/katello-server-ca.crt -o /etc/pki/ca-trust/source/anchors/${SATELLITE_URL}.ca.crt" "Download Katello CA cert"
retry "update-ca-trust" "Update CA trust"
retry "rpm -Uhv --force https://${SATELLITE_URL}/pub/katello-ca-consumer-latest.noarch.rpm" "Install Katello consumer RPM"
retry "subscription-manager register --org=${SATELLITE_ORG} --activationkey=${SATELLITE_ACTIVATIONKEY}" "Register with Satellite"

# Refresh subscription data
retry "subscription-manager refresh" "Refresh subscription"

# Install packages and Docker
retry "dnf install -y dnf-utils git nano" "Install base packages"
retry "dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo" "Add Docker repo"
retry "dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin python3-pip python3-libsemanage git ansible-core python-requests ipa-client sssd oddjob-mkhomedir postgresql-server postgresql python3-psycopg2" "Install Docker and system packages"

setenforce 0

echo "192.168.1.10 control.zta.lab control" >> /etc/hosts
echo "192.168.1.11 central.zta.lab  keycloak.zta.lab  opa.zta.lab" >> /etc/hosts
echo "192.168.1.12 vault.zta.lab vault" >> /etc/hosts
echo "192.168.1.13 wazuh.zta.lab wazuh" >> /etc/hosts
echo "192.168.1.14 node01.zta.lab node01" >> /etc/hosts
echo "192.168.1.15 netbox.zta.lab netbox" >> /etc/hosts

nmcli connection add type ethernet con-name eth1 ifname eth1 ipv4.addresses 192.168.1.14/24 ipv4.method manual connection.autoconnect yes
nmcli connection up eth1
nmcli con mod eth1 ipv4.dns 192.168.1.11
nmcli con mod eth1 ipv4.dns-search zta.lab
nmcli con up eth1



