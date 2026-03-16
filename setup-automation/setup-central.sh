#!/bin/bash

systemctl stop systemd-tmpfiles-setup.service
systemctl disable systemd-tmpfiles-setup.service

rm -rf /etc/yum.repos.d/*
yum clean all
subcription-manager clean

curl -k  -L https://${SATELLITE_URL}/pub/katello-server-ca.crt -o /etc/pki/ca-trust/source/anchors/${SATELLITE_URL}.ca.crt
update-ca-trust
rpm -Uhv https://${SATELLITE_URL}/pub/katello-ca-consumer-latest.noarch.rpm
subscription-manager register --org=${SATELLITE_ORG} --activationkey=${SATELLITE_ACTIVATIONKEY}

##
########
## install python3 libraries needed for the Cloud Report
dnf install -y python3-pip python3-libsemanage git ansible-core python-requests

mkdir /tmp/group_vars

tee /tmp/group_vars/all.yml << EOF
---
# ── Lab Identity ─────────────────────────────────────────────────────
# Auto-discovered from the target VM's facts.  Override at runtime:
#   ansible-playbook <playbook> -e idm_domain=custom.lab

idm_hostname: central.zta.lab
idm_domain: zta.lab
idm_realm: "{{ idm_domain | upper }}"
idm_admin_password: ansible123!
idm_dm_password: ansible123!

# ── OPA (Open Policy Agent) — runs on central alongside IdM ─────────
opa_url: "http://central.zta.lab:8181"
opa_container_name: opa
opa_policy_dir: /opt/opa/policies

# ── HashiCorp Vault (own VM) ────────────────────────────────────────
vault_addr: "https://vault.zta.lab:8200"
vault_skip_verify: true

# ── Netbox / CMDB (own VM) ──────────────────────────────────────────
netbox_url: "http://netbox.zta.lab:8000"
netbox_token: "{{ lookup('env', 'NETBOX_TOKEN') }}"

# ── Gitea / Git Server (own container) ──────────────────────────────
gitea_url: "http://gitea.zta.lab:3000"
gitea_org: zta-workshop
gitea_repo: zta-app
gitea_webhook_secret: "{{ lookup('env', 'GITEA_WEBHOOK_SECRET') | default('zta-webhook-secret', true) }}"

# ── Wazuh / SIEM (own VM) ──────────────────────────────────────────
wazuh_url: "https://wazuh.zta.lab"
wazuh_api_url: "https://wazuh.zta.lab:55000"
wazuh_api_user: wazuh
wazuh_api_password: "{{ lookup('env', 'WAZUH_API_PASSWORD') | default('wazuh', true) }}"
wazuh_manager_host: wazuh.zta.lab

# ── AAP Controller (own VM) ─────────────────────────────────────────
aap_controller_url: "https://aap.zta.lab"
aap_validate_certs: false

# ── Cisco Catalyst 8000v (own VM) ───────────────────────────────────
cisco_switch_host: switch01.zta.lab

# ── Database / PostgreSQL (own VM) ──────────────────────────────────
db_host: db.zta.lab
db_port: 5432
db_name: ztaapp
db_admin_user: postgres
db_admin_password: "{{ lookup('env', 'DB_ADMIN_PASSWORD') | default('postgres123!', true) }}"

# ── Application Server (own VM) ─────────────────────────────────────
app_host: app.zta.lab
app_port: 8080
app_deploy_dir: /opt/ztaapp

# ── IdM Teams (organisational units) ────────────────────────────────
idm_teams:
  - name: team-infrastructure
    description: Infrastructure & Platform Engineering
  - name: team-devops
    description: DevOps & CI/CD
  - name: team-security
    description: Security Operations & Compliance
  - name: team-applications
    description: Application Development

# ── IdM Functional Groups (used in OPA policies for RBAC) ──────────
idm_groups:
  - name: zta-admins
    description: ZTA Lab Administrators — full access
  - name: patch-admins
    description: Server patching operators
  - name: network-admins
    description: Network configuration operators
  - name: app-deployers
    description: Application deployment operators
  - name: security-ops
    description: Security operations — Wazuh, audit, compliance
  - name: db-admins
    description: Database administration
  - name: change-approvers
    description: Can approve maintenance windows and change requests

# ── IdM Users ──────────────────────────────────────────────────────
# The first 4 are the primary workshop scenario users.
# The remaining 15 populate the directory to make it feel real-world.
# All passwords: {{ idm_admin_password }}
idm_workshop_users:
  # Workshop scenario accounts
  - uid: ztauser
    first: ZTA
    last: User
    title: Workshop Admin
    groups: [zta-admins, patch-admins, app-deployers, team-infrastructure]
  - uid: netadmin
    first: Network
    last: Admin
    title: Workshop Network Admin
    groups: [zta-admins, network-admins, team-infrastructure]
  - uid: appdev
    first: App
    last: Developer
    title: Workshop App Developer
    groups: [app-deployers, team-applications]
  - uid: neteng
    first: Network
    last: Engineer
    title: Workshop Network Engineer (no groups — will be denied)
    groups: []

  # Infrastructure team
  - uid: jsmith
    first: James
    last: Smith
    title: Infrastructure Team Lead
    groups: [zta-admins, patch-admins, change-approvers, team-infrastructure]
  - uid: rwilson
    first: Robert
    last: Wilson
    title: Senior Systems Administrator
    groups: [patch-admins, team-infrastructure]
  - uid: nobrien
    first: Nora
    last: O'Brien
    title: Database Administrator
    groups: [db-admins, patch-admins, team-infrastructure]
  - uid: djohnson
    first: David
    last: Johnson
    title: Network Architect
    groups: [network-admins, change-approvers, team-infrastructure]
  - uid: agarcia
    first: Ana
    last: Garcia
    title: Network Engineer
    groups: [network-admins, team-infrastructure]

  # DevOps team
  - uid: lkim
    first: Lisa
    last: Kim
    title: DevOps Lead
    groups: [zta-admins, app-deployers, change-approvers, team-devops]
  - uid: mchen
    first: Michael
    last: Chen
    title: DevOps Engineer
    groups: [app-deployers, patch-admins, team-devops]
  - uid: ksato
    first: Kenji
    last: Sato
    title: Platform Engineer
    groups: [app-deployers, patch-admins, team-devops]

  # Security team
  - uid: mrodriguez
    first: Maria
    last: Rodriguez
    title: Security Lead
    groups: [zta-admins, security-ops, change-approvers, team-security]
  - uid: spatel
    first: Sarah
    last: Patel
    title: Security Analyst
    groups: [security-ops, team-security]

  # Application team
  - uid: twright
    first: Tom
    last: Wright
    title: Junior Developer
    groups: [app-deployers, team-applications]
  - uid: ebell
    first: Emma
    last: Bell
    title: Senior Developer
    groups: [app-deployers, team-applications]
  - uid: cmorales
    first: Carlos
    last: Morales
    title: QA Engineer
    groups: [team-applications]
  - uid: pryan
    first: Patricia
    last: Ryan
    title: Release Manager
    groups: [app-deployers, change-approvers, team-applications]
  - uid: fnguyen
    first: Felix
    last: Nguyen
    title: SOC Analyst
    groups: [security-ops, team-security]

# ── Vault Paths ─────────────────────────────────────────────────────
vault_db_secrets_path: database
vault_kv_secrets_path: secret
vault_db_role_name: ztaapp-short-lived
vault_db_max_ttl: 1h
vault_db_default_ttl: 5m

# ── Network Segmentation ────────────────────────────────────────────
vlans:
  app_tier:
    id: 20
    name: APP-TIER
    network: 10.20.0.0/24
  data_tier:
    id: 30
    name: DATA-TIER
    network: 10.30.0.0/24
  management:
    id: 10
    name: MGMT
    network: 10.10.0.0/24
EOF


tee /tmp/requirements.yml << EOF
---
collections:
  - name: cisco.ios
  - name: ansible.netcommon
  - name: community.postgresql
  - name: community.general

EOF

tee /tmp/inventory << EOF
# ZTA Workshop Inventory

[zta_services]
central ansible_host=central.zta.lab

[vault_servers]
vault ansible_host=vault.zta.lab

[netbox_servers]
netbox ansible_host=netbox.zta.lab

[wazuh_servers]
wazuh ansible_host=wazuh.zta.lab

# [gitea_servers]
# gitea ansible_host=gitea.zta.lab

[automation]
control ansible_host=control.zta.lab

[app_servers]
app ansible_host=node01.zta.lab

[db_servers]
db ansible_host=node01.zta.lab

# [network]
# cisco ansible_host=cisco

# All Linux hosts except central (IdM server) and the Cisco switch.
# Used by setup/enroll-idm-clients.yml.
[idm_clients:children]
vault_servers
netbox_servers
wazuh_servers
#gitea_servers
#automation
app_servers
db_servers

[all:vars]
ansible_user=rhel
ansible_password=ansible123!
ansible_become_password=ansible123!
ansible_python_interpreter=/usr/bin/python3

# [network:vars]
# ansible_user=admin
# ansible_password=cisco123!
# ansible_network_os=cisco.ios.ios
# ansible_connection=ansible.netcommon.network_cli

EOF


ansible-galaxy collection install -r collections/requirements.yml

echo "192.168.1.10 control.zta.lab control" >> /etc/hosts
echo "192.168.1.11 central.zta.lab  keycloak.zta.lab  opa.zta.lab" >> /etc/hosts
echo "192.168.1.12 vault.zta.lab vault" >> /etc/hosts
echo "192.168.1.13 wazuh.zta.lab wazuh" >> /etc/hosts
echo "192.168.1.14 node01.zta.lab node01" >> /etc/hosts
echo "192.168.1.15 netbox.zta.lab netbox" >> /etc/hosts

nmcli connection add type ethernet con-name enp2s0 ifname enp2s0 ipv4.addresses 192.168.1.11/24 ipv4.method manual connection.autoconnect yes
nmcli connection up enp2s0

## Correct Keycloak
podman stop keycloak
podman rm keycloak

podman run -d \
  --name keycloak \
  --restart=always \
  -p 8180:8080 \
  -p 8543:8443 \
  -e KEYCLOAK_ADMIN=admin \
  -e KEYCLOAK_ADMIN_PASSWORD=ansible123! \
  -e KC_HTTP_ENABLED=true \
  -e KC_HOSTNAME_STRICT=false \
  -e KC_PROXY=edge \
  -e KC_HTTPS_CERTIFICATE_FILE=/opt/certs/server.crt \
  -e KC_HTTPS_CERTIFICATE_KEY_FILE=/opt/certs/server.key \
  -v /opt/keycloak/certs:/opt/certs:Z \
  registry.redhat.io/rhbk/keycloak-rhel9:latest \
  start \
  --hostname-strict=false \
  --proxy=edge \
  --https-port=8443 \
  --http-enabled=true
##



# Create a playbook for the user to execute
tee /tmp/zta-setup.yml << EOF

---
- name: Verify ZTA Lab services on central.zta.lab
  hosts: localhost
  become: true
  gather_facts: true

  tasks:

    - name: Start IdM services
      ansible.builtin.command:
        cmd: ipactl start

    - name: Check hostname
      ansible.builtin.command:
        cmd: hostname -f
      register: hostname_check
      changed_when: false

    - name: Check IP address
      ansible.builtin.debug:
        msg: "IP: {{ ansible_default_ipv4.address }} | Hostname: {{ hostname_check.stdout }}"

    - name: Verify IdM services
      ansible.builtin.command:
        cmd: ipactl status
      register: ipa_status
      changed_when: false
      failed_when: false

    - name: Display IdM status
      ansible.builtin.debug:
        var: ipa_status.stdout_lines

    - name: Flag any stopped IdM services
      ansible.builtin.assert:
        that:
          - "'STOPPED' not in ipa_status.stdout"
          - ipa_status.rc == 0
        fail_msg: "One or more IdM services are not running"
        success_msg: "All IdM services are running"

    - name: Check Keycloak container
      ansible.builtin.command:
        cmd: podman ps --filter name=keycloak --format "{{ '{{' }}.Status{{ '}}' }}"
      register: keycloak_status
      changed_when: false
      failed_when: false

    - name: Start Keycloak if not running
      ansible.builtin.systemd:
        name: container-keycloak
        state: started
      when: "'Up' not in keycloak_status.stdout"

    - name: Verify Keycloak HTTP responds
      ansible.builtin.uri:
        url: "http://localhost:{{ keycloak_http_port | default(8180) }}"
        method: GET
        status_code: 200
        validate_certs: false
      register: keycloak_health
      retries: 5
      delay: 10
      until: keycloak_health.status == 200

    - name: Check OPA container
      ansible.builtin.command:
        cmd: podman ps --filter name=opa --format "{{ '{{' }}.Status{{ '}}' }}"
      register: opa_status
      changed_when: false
      failed_when: false

    - name: Start OPA if not running
      ansible.builtin.systemd:
        name: container-opa
        state: started
      when: "'Up' not in opa_status.stdout"

    - name: Verify OPA health endpoint
      ansible.builtin.uri:
        url: "http://localhost:{{ opa_http_port | default(8181) }}/health"
        method: GET
        status_code: 200
      register: opa_health
      retries: 5
      delay: 5
      until: opa_health.status == 200

    - name: Verify OPA policies are loaded
      ansible.builtin.uri:
        url: "http://localhost:{{ opa_http_port | default(8181) }}/v1/policies"
        method: GET
        status_code: 200
        return_content: true
      register: opa_policies

    - name: Verify DNS resolution
      ansible.builtin.command:
        cmd: "dig +short {{ item }} @127.0.0.1"
      register: dns_checks
      changed_when: false
      failed_when: dns_checks.stdout | length == 0
      loop:
        - central.zta.lab
        - keycloak.zta.lab
        - opa.zta.lab

    - name: Verify Kerberos
      ansible.builtin.shell:
        cmd: echo '{{ idm_admin_password | default("ansible123!") }}' | kinit admin && klist
      register: krb_check
      changed_when: false
      no_log: true

    - name: Verification summary
      ansible.builtin.debug:
        msg:
          - "============================================="
          - "  ZTA Lab - Verification Results"
          - "============================================="
          - "  Hostname:   {{ hostname_check.stdout }}"
          - "  IP Address: {{ ansible_default_ipv4.address }}"
          - ""
          - "  IdM:        {{ 'OK - All services running' if ipa_status.rc == 0 else 'FAILED' }}"
          - "  Keycloak:   {{ 'OK - HTTP 200' if keycloak_health.status == 200 else 'FAILED' }}"
          - "  OPA:        {{ 'OK - Healthy, ' + ((opa_policies.json.result | default([])) | length | string) + ' policies loaded' if opa_health.status == 200 else 'FAILED' }}"
          - "  DNS:        OK - all records resolve"
          - "  Kerberos:   OK - admin ticket obtained"
          - "============================================="
EOF

ansible-playbook -i /tmp/inventory /tmp/zta-setup.yml

tee /etc/httpd/conf.d/ipa-rewrite.conf << IPA
# VERSION 7 - DO NOT REMOVE THIS LINE
RequestHeader set Host central.zta.lab 
RequestHeader set Referer https://central.zta.lab/ipa/ui/
RewriteEngine on

# Rewrite for plugin index, make it like it's a static file
RewriteRule ^/ipa/ui/js/freeipa/plugins.js$    /ipa/wsgi/plugins.py [PT]

RewriteCond %{HTTP_HOST}    ^ipa-ca.example.local$ [NC]
RewriteCond %{REQUEST_URI}  !^/ipa/crl
RewriteCond %{REQUEST_URI}  !^/(ca|kra|pki|acme)
IPA
systemctl reload httpd

#git clone https://github.com/nmartins0611/zta-aap-workshop.git

tee /tmp/integrate.yml << EOF
---
# integrate.yml — Wire up IdM ↔ OPA and issue IdM-signed certificates
#
# Run AFTER site.yml has deployed IdM and OPA on central.zta.lab.
# This version does NOT configure Keycloak.  For the full Keycloak
# integration see integrate-keycloak.yml.
#
# Usage:
#   ansible-playbook integrate.yml
#
# Run individual phases:
#   ansible-playbook integrate.yml --tags phase1
#   ansible-playbook integrate.yml --tags phase3

- name: Integrate ZTA Lab Services
  hosts: zta_services
  become: true
  gather_facts: true

  vars:
    opa_http_port: 8181
    idm_base_dn: "dc={{ idm_domain.split('.') | join(',dc=') }}"
    idm_users_dn: "cn=users,cn=accounts,{{ idm_base_dn }}"
    idm_groups_dn: "cn=groups,cn=accounts,{{ idm_base_dn }}"
    idm_server_ip: "{{ ansible_default_ipv4.address }}"
    idm_service_certs:
      - hostname: "wazuh.{{ idm_domain }}"
        cert_dir: /opt/certs/wazuh
      - hostname: "aap.{{ idm_domain }}"
        cert_dir: /opt/certs/aap

  tasks:
    # ═══════════════════════════════════════════════════════════════════
    # Phase 1 — Verify core services are running before integration
    # ═══════════════════════════════════════════════════════════════════

    - name: "Phase 1 | Verify IdM is running"
      command: ipactl status
      register: idm_status
      changed_when: false
      failed_when: "'RUNNING' not in idm_status.stdout"
      tags: [phase1, prerequisites]

    - name: "Phase 1 | Verify OPA container is running"
      command: podman ps --filter name={{ opa_container_name }} --format "{{ '{{' }}.Status{{ '}}' }}"
      register: opa_status
      changed_when: false
      failed_when: "'Up' not in opa_status.stdout"
      tags: [phase1, prerequisites]

    # - name: "Phase 1 | Install python3-requests (needed for uri module)"
    #   dnf:
    #     name: python3-requests
    #     state: present
    #   tags: [phase1, prerequisites]

    # ═══════════════════════════════════════════════════════════════════
    # Phase 2 — Create IdM test users and groups
    # ═══════════════════════════════════════════════════════════════════

    - name: "Phase 2 | Obtain Kerberos TGT"
      shell: echo '{{ idm_admin_password }}' | kinit admin
      changed_when: false
      no_log: true
      tags: [phase2, idm-users]

    - name: "Phase 2 | Create test user (ztauser) in IdM"
      command: >
        ipa user-add ztauser
        --first=ZTA --last=User
        --password
      args:
        stdin: "{{ idm_admin_password }}\n{{ idm_admin_password }}"
      register: test_user
      changed_when: test_user.rc == 0
      failed_when: false
      tags: [phase2, idm-users]

    - name: "Phase 2 | Create zta-admins group in IdM"
      command: ipa group-add zta-admins --desc="ZTA Lab Administrators"
      register: zta_group
      changed_when: zta_group.rc == 0
      failed_when: false
      tags: [phase2, idm-users]

    - name: "Phase 2 | Add ztauser to zta-admins group"
      command: ipa group-add-member zta-admins --users=ztauser
      register: group_member
      changed_when: group_member.rc == 0
      failed_when: false
      tags: [phase2, idm-users]

    # ═══════════════════════════════════════════════════════════════════
    # Phase 3 — Deploy OPA base policies and health check
    # ═══════════════════════════════════════════════════════════════════

    - name: "Phase 3 | Ensure OPA policy directory exists"
      file:
        path: "{{ opa_policy_dir }}"
        state: directory
        mode: '0755'
      tags: [phase3, opa-policies]

    - name: "Phase 3 | Deploy workshop OPA policies"
      copy:
        src: "{{ item }}"
        dest: "{{ opa_policy_dir }}/{{ item | basename }}"
        owner: root
        group: root
        mode: '0644'
      loop:
        - opa-policies/zta_base.rego
        - opa-policies/patching.rego
        - opa-policies/network.rego
        - opa-policies/db_access.rego
      register: opa_workshop_policies
      tags: [phase3, opa-policies]

    - name: "Phase 3 | Deploy OPA identity-based authz policy"
      copy:
        dest: "{{ opa_policy_dir }}/zta_authz.rego"
        content: |
          package zta.authz

          import rego.v1

          default allow := false

          # Identity-based authorization using IdM groups.
          # Accepts input.user and input.groups (populated by AAP/caller).

          allow if {
            input.user != ""
            "zta-admins" in input.groups
          }

          decision := {
            "allow": allow,
            "user": input.user,
            "groups": input.groups,
          } if {
            input.user
          }

          decision := {
            "allow": false,
            "reason": "missing user identity",
          } if {
            not input.user
          }
        owner: root
        group: root
        mode: '0644'
      register: opa_authz_policy
      tags: [phase3, opa-policies]

    - name: "Phase 3 | Deploy health check policy"
      copy:
        dest: "{{ opa_policy_dir }}/health.rego"
        content: |
          package system

          import rego.v1

          main := {
            "status": "healthy",
            "version": "1.0",
            "services": ["idm", "opa"],
          }
        owner: root
        group: root
        mode: '0644'
      tags: [phase3, opa-policies]

    - name: "Phase 3 | Restart OPA to load new policies"
      command: podman restart {{ opa_container_name }}
      when: opa_workshop_policies.changed or opa_authz_policy.changed
      tags: [phase3, opa-policies]

    - name: "Phase 3 | Wait for OPA to come back"
      uri:
        url: "http://localhost:{{ opa_http_port }}/health"
        method: GET
      register: opa_health
      until: opa_health.status == 200
      retries: 10
      delay: 3
      tags: [phase3, opa-policies]

    # ═══════════════════════════════════════════════════════════════════
    # Phase 4 — Request IdM-signed certificates for external services
    # ═══════════════════════════════════════════════════════════════════

    - name: "Phase 4 | Create certificate directories"
      file:
        path: "{{ item.cert_dir }}"
        state: directory
        mode: '0755'
      loop: "{{ idm_service_certs }}"
      tags: [phase4, certificates]

    - name: "Phase 4 | Add DNS entries for external services"
      command: >
        ipa dnsrecord-add {{ idm_domain }} {{ item.hostname.split('.')[0] }}
        --a-rec={{ idm_server_ip }}
      loop: "{{ idm_service_certs }}"
      register: dns_add
      changed_when: dns_add.rc == 0
      failed_when: false
      tags: [phase4, certificates]

    - name: "Phase 4 | Request certificates from IdM CA"
      command: >
        ipa-getcert request
        -f {{ item.cert_dir }}/server.crt
        -k {{ item.cert_dir }}/server.key
        -N CN={{ item.hostname }}
        -D {{ item.hostname }}
        -K HTTP/{{ item.hostname }}@{{ idm_realm }}
      loop: "{{ idm_service_certs }}"
      register: cert_request
      changed_when: "'New signing request' in cert_request.stdout"
      failed_when: false
      tags: [phase4, certificates]

    - name: "Phase 4 | Wait for certificate issuance"
      shell: |
        for i in $(seq 1 30); do
          status=$(ipa-getcert list -f {{ item.cert_dir }}/server.crt 2>/dev/null | grep 'status:' | head -1)
          if echo "$status" | grep -q 'MONITORING'; then
            echo "ISSUED"
            exit 0
          fi
          sleep 2
        done
        echo "TIMEOUT"
      loop: "{{ idm_service_certs }}"
      register: cert_wait
      changed_when: false
      failed_when: "'TIMEOUT' in cert_wait.stdout"
      tags: [phase4, certificates]

    - name: "Phase 4 | Set certificate permissions"
      file:
        path: "{{ item.0.cert_dir }}/{{ item.1 }}"
        mode: '0644'
      loop: "{{ idm_service_certs | product(['server.crt', 'server.key']) | list }}"
      loop_control:
        label: "{{ item.0.cert_dir }}/{{ item.1 }}"
      tags: [phase4, certificates]

    - name: "Phase 4 | Copy IdM CA root cert alongside each service cert"
      copy:
        src: /etc/ipa/ca.crt
        dest: "{{ item.cert_dir }}/ca.crt"
        remote_src: true
        mode: '0644'
      loop: "{{ idm_service_certs }}"
      tags: [phase4, certificates]

    # ═══════════════════════════════════════════════════════════════════
    # Phase 5 — End-to-end validation and summary
    # ═══════════════════════════════════════════════════════════════════

    - name: "Phase 5 | Test OPA health endpoint"
      uri:
        url: "http://localhost:{{ opa_http_port }}/health"
        method: GET
        status_code: 200
      register: opa_final_health
      tags: [phase5, validation]

    - name: "Phase 5 | Test OPA authz decision (zta-admins user)"
      uri:
        url: "http://localhost:{{ opa_http_port }}/v1/data/zta/authz/decision"
        method: POST
        body_format: json
        body:
          input:
            user: ztauser
            groups:
              - zta-admins
        status_code: [200]
      register: opa_allow_decision
      tags: [phase5, validation]

    - name: "Phase 5 | Test OPA authz decision (unauthorised user)"
      uri:
        url: "http://localhost:{{ opa_http_port }}/v1/data/zta/authz/decision"
        method: POST
        body_format: json
        body:
          input:
            user: nobody
            groups:
              - viewers
        status_code: [200]
      register: opa_deny_decision
      tags: [phase5, validation]

    - name: "Phase 5 | Display OPA test results"
      debug:
        msg:
          - "OPA health:       {{ 'OK' if opa_final_health.status == 200 else 'FAILED' }}"
          - "Allow (ztauser):  {{ opa_allow_decision.json.result }}"
          - "Deny  (nobody):   {{ opa_deny_decision.json.result }}"
      tags: [phase5, validation]

    - name: "Phase 5 | List issued certificates"
      command: ipa-getcert list
      register: cert_list
      changed_when: false
      tags: [phase5, validation]

    - name: "Phase 5 | Summary"
      debug:
        msg: |
          ╔══════════════════════════════════════════════════════════╗
          ║          ZTA Lab Integration Complete                   ║
          ╠══════════════════════════════════════════════════════════╣
          ║                                                        ║
          ║  IdM (Identity Provider)                               ║
          ║    Domain:   {{ idm_domain | ljust(39) }}║
          ║    Realm:    {{ idm_realm | ljust(39) }}║
          ║    Test user: ztauser (group: zta-admins)              ║
          ║                                                        ║
          ║  OPA (Policy Decision Point)                           ║
          ║    Endpoint:  http://localhost:{{ opa_http_port | string | ljust(24) }}║
          ║    Policies:  zta_authz, patching, network, db_access  ║
          ║    Health:    {{ 'OK' | ljust(39) if opa_final_health.status == 200 else 'FAILED' | ljust(39) }}║
          ║                                                        ║
          ║  IdM-Signed Certificates                               ║
          {% for svc in idm_service_certs %}
          ║    {{ (svc.hostname + ': ' + svc.cert_dir + '/') | ljust(52) }}║
          {% endfor %}
          ║                                                        ║
          ║  Test User                                             ║
          ║    Username: ztauser                                   ║
          ║    Password: {{ idm_admin_password | ljust(39) }}║
          ║    Groups:   zta-admins                                ║
          ║                                                        ║
          ║  Keycloak: not configured by this playbook             ║
          ║    Run integrate-keycloak.yml when ready                ║
          ║                                                        ║
          ╚══════════════════════════════════════════════════════════╝
      tags: [phase5, validation]

EOF
