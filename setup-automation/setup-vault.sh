#!/bin/bash


echo "192.168.1.10 control.zta.lab control" >> /etc/hosts
echo "192.168.1.11 central.zta.lab  keycloak.zta.lab  opa.zta.lab" >> /etc/hosts
echo "192.168.1.12 vault.zta.lab vault" >> /etc/hosts
echo "192.168.1.13 wazuh.zta.lab wazuh" >> /etc/hosts
echo "192.168.1.14 node01.zta.lab node01" >> /etc/hosts
echo "192.168.1.15 netbox.zta.lab netbox" >> /etc/hosts


nmcli connection add type ethernet con-name eth1 ifname eth1 ipv4.addresses 192.168.1.12/24 ipv4.method manual connection.autoconnect yes
nmcli connection up eth1
nmcli con mod eth1 ipv4.dns 192.168.1.11
nmcli con mod eth1 ipv4.dns-search zta.lab
nmcli con up eth1

if [ -n "$VAULT_LIC" ]; then
    # Write new license
    echo "$VAULT_LIC" | sudo tee /etc/vault.d/vault.hclic > /dev/null
    
    # Set proper permissions
    sudo chmod 640 /etc/vault.d/vault.hclic
    sudo chown vault:vault /etc/vault.d/vault.hclic
    
    echo "License file created successfully at /etc/vault.d/vault.hclic"
    
    # Restart Vault
    echo "Restarting Vault..."
    sudo systemctl restart vault
    
    # Wait and check status
    sleep 3
    if sudo systemctl is-active --quiet vault; then
        echo "Vault restarted successfully"
    else
        echo "Warning: Vault service may not be running properly"
        sudo systemctl status vault
        exit 1
    fi
else
    echo "Error: VAULT_LIC environment variable is not set"
    exit 1
fi

# Unseal the Vault instance so users can immediately login at the UI.
vault operator unseal -address=http://127.0.0.1:8200 -tls-skip-verify 1c6a637e70172e3c249f77b653fb64a820749864cad7f5aa7ab6d5aca5197ec5
#
