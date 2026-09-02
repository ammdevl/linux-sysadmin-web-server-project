#!/usr/bin/env bash

# =============================================================================
# Linux System Administration - Server Setup Script
# Target: Ubuntu 24.04 LTS on VMware (works on 22.04+)
# Run:    ./server-setup.sh [OPTIONS]  (from a sudo-capable admin account)
#
# Options:
#   --dry-run     Print what would be done without making changes
#   --verbose     Show full command output (default: suppressed)
#   --help        Show usage information
#
# Automates SERVER_SETUP.md:
#   system update -> network (static IP) -> SSH hardening -> Tailscale ->
#   users/groups -> web directory -> Apache2 (TLS + static serving) ->
#   Node.js/PM2 -> Next.js deploy -> UFW -> fail2ban -> backup -> verification
#
# Optional steps prompt before making changes. Env overrides:
#   VM_IP, NET_IFACE, NET_CIDR, NET_GW, APP_DIR, REPO_URL, DEPLOY_USER
#
# NOTE: This script is not fully idempotent. While most steps safely skip
# already-completed work, re-running after a partial failure may require
# manual cleanup (e.g., removing a partially-written Apache vhost or
# Netplan config). If the script fails midway, review the error, clean up
# the affected config, then re-run.
# =============================================================================

set -euo pipefail

# --- CLI Flags ---
DRY_RUN=false
VERBOSE=false

print_usage() {
    cat <<USAGE
Usage: $(basename "$0") [OPTIONS]

Options:
  --dry-run     Print what would be done without making changes
  --verbose     Show full command output (default: suppressed)
  --help        Show this help message

Environment variables:
  VM_IP         Override detected VM IP address
  NET_IFACE     Network interface (default: ens33)
  NET_CIDR      Static IP in CIDR notation (default: 192.168.10.3/24)
  NET_GW        Default gateway (default: 192.168.10.2)
  APP_DIR       Application directory (default: /var/www/app)
  REPO_URL      Git repository URL to clone
  DEPLOY_USER   User account for deployment (default: agmyintmyat)
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)  DRY_RUN=true; shift ;;
        --verbose)  VERBOSE=true; shift ;;
        --help)     print_usage; exit 0 ;;
        *)          echo "Unknown option: $1"; print_usage; exit 1 ;;
    esac
done

# --- Ctrl+C Handler ---
abort_install() {
    echo ""
    echo -e "  ${RED}! Setup aborted by user.${RESET}"
    echo ""
    exit 1
}
trap abort_install SIGINT SIGTERM

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# --- Logging Helpers ---
ok()    { echo -e "  ${GREEN}✓${RESET} $1"; }
info()  { echo -e "  ${CYAN}>${RESET} $1"; }
warn()  { echo -e "  ${YELLOW}!${RESET} $1"; }
fail()  { echo -e "  ${RED}✗ Error:${RESET} $1"; exit 1; }

run() {
    # Execute a command, respecting --dry-run and --verbose flags
    if $DRY_RUN; then
        echo -e "  ${DIM}[dry-run] $*${RESET}"
        return 0
    fi
    if $VERBOSE; then
        "$@"
    else
        "$@" > /dev/null 2>&1
    fi
}

section_header() {
    echo ""
    echo -e "  ${BLUE}------------------------------------------------------------${RESET}"
    echo -e "  ${BOLD}  $1${RESET}"
    echo -e "  ${BLUE}------------------------------------------------------------${RESET}"
}

confirm() {
    local answer
    read -rp "  $1 [y/N]: " answer
    [[ "$answer" =~ ^[Yy]$ ]]
}

print_banner() {
    local ubuntu_ver
    ubuntu_ver=$(lsb_release -rs 2>/dev/null || echo 'unknown')
    local border="------------------------------------------------------------"
    echo ""
    echo -e "  ${CYAN}+${border}+${RESET}"
    echo -e "  ${CYAN}|${RESET}  ${BOLD}Web Server Automated Setup${RESET}"
    echo -e "  ${CYAN}|${RESET}  ${DIM}Target: Ubuntu ${ubuntu_ver} (VMware VM)${RESET}"
    if $DRY_RUN; then
        echo -e "  ${CYAN}|${RESET}  ${YELLOW}${BOLD}MODE: DRY RUN (no changes will be made)${RESET}"
    fi
    echo -e "  ${CYAN}+${border}+${RESET}"
}

# --- Configuration ---
REPO_URL="${REPO_URL:-https://github.com/ammdevl/lfs-101-notes.git}"
DEPLOY_USER="${DEPLOY_USER:-agmyintmyat}"
APP_DIR="${APP_DIR:-/var/www/app}"

SYSADMIN_USERS=(mgkhant agmyintmyatag gonyaungwin agkhantkyaw santhiritun)
DEV_USERS=(kghtutthaw hanlinhtun shoonlaeaung agmyintmyat)

# --- Preflight Checks ---
check_root_or_sudo() {
    if [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
        fail "Run this script from an account with sudo privileges."
    fi
}

check_ubuntu() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        [[ "$ID" == "ubuntu" ]] || fail "This script is designed for Ubuntu only. Detected: $PRETTY_NAME"
    else
        fail "Cannot detect OS. /etc/os-release not found."
    fi
    ok "OS detected: $PRETTY_NAME"
}

detect_vm_ip() {
    ip -4 route get 1.1.1.1 2>/dev/null | grep -oP 'src \K[0-9.]+' | head -1
}

# --- Step 1: System Update ---
system_update() {
    section_header "Step 1/12  System Update"
    info "apt-get update && upgrade..."
    run sudo apt-get update -qq
    run sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq
    run sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git curl openssl
    ok "System packages up to date (git, curl, openssl ensured)"
}

# --- Step 2: Network (Static IP via Netplan) ---
configure_network() {
    section_header "Step 2/12  Network Configuration"

    if ! confirm "Configure a static IP via Netplan now? (skip if already configured)"; then
        warn "Skipped network configuration"
        return
    fi

    local iface cidr gateway
    read -rp "  Interface name      [${NET_IFACE:-ens33}]: " iface
    iface=${iface:-${NET_IFACE:-ens33}}
    read -rp "  Static IP (CIDR)    [${NET_CIDR:-192.168.10.3/24}]: " cidr
    cidr=${cidr:-${NET_CIDR:-192.168.10.3/24}}
    read -rp "  Default gateway     [${NET_GW:-192.168.10.2}]: " gateway
    gateway=${gateway:-${NET_GW:-192.168.10.2}}

    run sudo cp /etc/netplan/50-cloud-init.yaml /etc/netplan/50-cloud-init.yaml.bak

    # Write config to 50-cloud-init.yaml
    run sudo tee /etc/netplan/50-cloud-init.yaml > /dev/null <<EOF
network:
  version: 2
  ethernets:
    ${iface}:
      dhcp4: false
      addresses:
        - ${cidr}
      routes:
        - to: default
          via: ${gateway}
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
EOF

    # Validate Netplan config before applying
    if ! $DRY_RUN; then
        if ! sudo netplan try 2>/dev/null; then
            fail "Netplan config validation failed — check interface name and CIDR"
        fi
        ok "Netplan config validated"
    fi

    run sudo netplan apply
    ok "Static IP applied: $(ip -4 addr show "$iface" | grep -oP '(?<=inet\s)[0-9./]+')"
    warn "If you changed the IP, reconnect SSH using the new address."
}

# --- Step 3: SSH Hardening ---
setup_ssh() {
    section_header "Step 3/12  SSH Setup & Hardening"

    run sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq openssh-server
    run sudo systemctl enable --now ssh
    ok "OpenSSH server installed and running"

    if ! confirm "Harden SSH? (key-only auth, root login disabled, AllowGroups restricted)"; then
        warn "Skipped SSH hardening — do this after copying your SSH key (ssh-copy-id)"
        return
    fi

    local sudo_user home_dir
    sudo_user="${SUDO_USER:-$USER}"
    home_dir=$(eval echo "~${sudo_user}")
    if [[ ! -s "${home_dir}/.ssh/authorized_keys" ]]; then
        warn "No authorized_keys found for $sudo_user — hardening may lock you out!"
        confirm "Continue anyway?" || { warn "Skipped SSH hardening"; return; }
    fi

    run sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
    run sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
    run sudo bash -c 'grep -q "^AllowGroups" /etc/ssh/sshd_config || echo "AllowGroups sysadmin dev" >> /etc/ssh/sshd_config'
    run sudo sshd -t
    run sudo systemctl restart ssh
    ok "SSH hardened: key-only auth, root login disabled, AllowGroups=sysadmin,dev"
}

# --- Step 4: Tailscale (Admin Access) ---
setup_tailscale() {
    section_header "Step 4/12  Tailscale (Optional Admin Tunnel)"
    if ! confirm "Install Tailscale? (secure admin/deployment tunnel, not required for production traffic)"; then
        warn "Skipped Tailscale"
        return
    fi
    if command -v tailscale > /dev/null; then
        ok "Tailscale already installed"
    else
        run curl -fsSL https://tailscale.com/install.sh | sh
        ok "Tailscale installed"
    fi
    info "Starting authentication — follow the printed URL..."
    sudo tailscale up || warn "Tailscale auth not completed — run 'sudo tailscale up' later"
}

# --- Interactive Password Setup ---
set_password() {
    local u="$1" pass confirm
    while true; do
        echo ""
        read -srp "  Enter password for ${BOLD}$u${RESET} (Enter skips): " pass; echo ""
        [[ -z "$pass" ]] && { warn "$u left locked (no password set)"; return; }
        read -srp "  Confirm password for $u: " confirm; echo ""
        [[ "$pass" == "$confirm" ]] && break
        warn "Passwords do not match — try again"
    done
    echo "$u:$pass" | sudo chpasswd > /dev/null 2>&1 \
        && ok "Password set for $u" \
        || fail "Failed to set password for $u"
}

# --- Step 5: Users & Groups ---
create_users() {
    section_header "Step 5/12  User & Group Management"

    getent group sysadmin > /dev/null || sudo groupadd sysadmin
    getent group dev     > /dev/null || sudo groupadd dev
    ok "Groups ready: sysadmin, dev"

    local u
    local new_users=()
    for u in "${SYSADMIN_USERS[@]}"; do
        if ! id -u "$u" > /dev/null 2>&1; then
            sudo useradd -m -s /bin/bash -G sysadmin "$u"
            info "created sysadmin user: $u"
            new_users+=("$u")
        fi
    done
    for u in "${DEV_USERS[@]}"; do
        if ! id -u "$u" > /dev/null 2>&1; then
            sudo useradd -m -s /bin/bash -G dev "$u"
            info "created dev user: $u"
            new_users+=("$u")
        fi
    done
    ok "Users ready (${#SYSADMIN_USERS[@]} sysadmin, ${#DEV_USERS[@]} dev)"

    if [[ ${#new_users[@]} -gt 0 ]]; then
        section_header "Setting Passwords (input hidden)"
        info "Classroom demo convention: 12345678 — lab VM only, never reuse elsewhere."
        echo ""
        for u in "${new_users[@]}"; do
            set_password "$u"
        done
    fi

    for u in "${SYSADMIN_USERS[@]}"; do
        sudo usermod -aG sudo "$u"
    done
    ok "sysadmin group granted sudo via 'sudo' group"
}

# --- Step 6: Web Directory Permissions ---
prepare_web_dir() {
    section_header "Step 6/12  File & Directory Permissions"
    run sudo mkdir -p "$APP_DIR"
    run sudo chown -R "$DEPLOY_USER:dev" "$APP_DIR"
    run sudo chmod 775 "$APP_DIR"
    run sudo find "$APP_DIR" -type d -exec chmod 775 {} \;
    run sudo find "$APP_DIR" -type f -exec chmod 664 {} \;
    ok "$APP_DIR owned by $DEPLOY_USER:dev (dirs 775, files 664)"
}

# --- Step 7: Apache2 (TLS + Static Serving) ---
setup_apache() {
    section_header "Step 7/12  Apache2 Installation & Configuration"

    run sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq apache2
    run sudo a2enmod proxy proxy_http rewrite headers ssl
    ok "Apache2 installed (proxy, proxy_http, rewrite, headers, ssl enabled)"

    local vm_ip="$VM_IP"
    [[ -z "$vm_ip" ]] && vm_ip=$(detect_vm_ip)
    [[ -z "$vm_ip" ]] && vm_ip="192.168.10.3"

    # Generate ECDSA self-signed certificate (stronger and faster than RSA 2048)
    if [[ ! -f /etc/ssl/certs/selfsigned.crt ]]; then
        run sudo openssl req -x509 -nodes -days 365 \
            -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
            -keyout /etc/ssl/private/selfsigned.key \
            -out /etc/ssl/certs/selfsigned.crt \
            -subj "/CN=${vm_ip}"
        ok "Self-signed ECDSA certificate generated for ${vm_ip}"
    else
        ok "Self-signed certificate already exists"
    fi

    # Hide version (ServerTokens/ServerSignature are server-context only)
    run sudo sed -i 's/^ServerTokens .*/ServerTokens Prod/; s/^ServerSignature .*/ServerSignature Off/' \
        /etc/apache2/conf-available/security.conf
    echo "ServerName ${vm_ip}" | sudo tee /etc/apache2/conf-available/servername.conf > /dev/null
    run sudo a2enconf servername
    ok "Version hidden, FQDN warning suppressed"

    # Serve static files directly from Apache (no Node.js needed for static export)
    # Dynamic content is still proxied to PM2 on port 3000
    run sudo tee /etc/apache2/sites-available/app.conf > /dev/null <<EOF
<VirtualHost *:80>
    ServerName ${vm_ip}

    # Redirect all HTTP to HTTPS
    RewriteEngine On
    RewriteCond %{HTTPS} off
    RewriteRule ^ https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]
</VirtualHost>

<VirtualHost *:443>
    ServerName ${vm_ip}

    # SSL Configuration (self-signed ECDSA certificate)
    SSLEngine on
    SSLCertificateFile /etc/ssl/certs/selfsigned.crt
    SSLCertificateKeyFile /etc/ssl/private/selfsigned.key

    # Security headers (requires mod_headers)
    Header always set Strict-Transport-Security "max-age=63072000; includeSubDomains"
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-Frame-Options "SAMEORIGIN"

    # Static files served directly by Apache (performance)
    # Skip proxy for _next/static/ — serve immutable assets from disk
    ProxyPass /_next/static/ !
    Alias /_next/static/ ${APP_DIR}/out/_next/static/

    # All other requests proxied to Node.js (PM2)
    ProxyPreserveHost On
    ProxyPass / http://127.0.0.1:3000/
    ProxyPassReverse / http://127.0.0.1:3000/

    # Health check endpoint (returns 200 without hitting Node.js)
    ProxyPass /health !
    Alias /health /var/www/app/out/health.html

    # Logs
    ErrorLog \${APACHE_LOG_DIR}/app-error.log
    CustomLog \${APACHE_LOG_DIR}/app-access.log combined
</VirtualHost>
EOF

    # Create health check endpoint file
    if ! $DRY_RUN; then
        echo '<!DOCTYPE html><html><head><title>OK</title></head><body><h1>Service OK</h1></body></html>' | \
            sudo tee "${APP_DIR}/out/health.html" > /dev/null 2>&1 || true
    fi

    run sudo a2ensite app.conf
    run sudo a2dissite 000-default.conf
    sudo apache2ctl configtest > /dev/null 2>&1 || fail "Apache config test failed — check /etc/apache2/sites-available/app.conf"
    run sudo systemctl restart apache2
    run sudo systemctl enable apache2
    ok "Site enabled, config test passed, Apache restarted"

    # Log rotation for custom app logs (default logrotate only covers access.log/error.log)
    run sudo tee /etc/logrotate.d/apache2-app > /dev/null <<'EOF'
/var/log/apache2/app-*.log {
    weekly
    missingok
    rotate 4
    compress
    delaycompress
    notifempty
    create 640 www-data adm
    sharedscripts
    postrotate
        systemctl reload apache2 > /dev/null 2>&1 || true
    endscript
}
EOF
    ok "Log rotation configured for app-access.log and app-error.log"
}

# --- Step 8: Node.js + PM2 ---
install_node() {
    section_header "Step 8/12  Node.js & PM2 Installation"

    if command -v node > /dev/null && [[ "$(node -v | cut -c2- | cut -d. -f1)" -ge 20 ]]; then
        ok "Node.js $(node -v) already installed"
    else
        run curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
        run sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nodejs
        ok "Node.js $(node -v) installed (system-wide via NodeSource)"
    fi

    if ! command -v pm2 > /dev/null; then
        run sudo npm install -g pm2
        ok "PM2 installed"
    else
        ok "PM2 already installed"
    fi
}

# --- Step 9: Deploy Next.js App ---
# Requires: DEPLOY_USER must exist (created in Step 5) and PM2 installed (Step 8).
deploy_app() {
    section_header "Step 9/12  Next.js Application Deployment"

    if [[ -f "$APP_DIR/package.json" ]]; then
        ok "App already present at $APP_DIR"
    elif [[ -n "$(ls -A "$APP_DIR" 2>/dev/null)" ]]; then
        fail "$APP_DIR is not empty and contains no package.json — resolve manually, then rerun."
    else
        info "Cloning $REPO_URL ..."
        run sudo chown "$DEPLOY_USER:dev" "$APP_DIR"
        sudo -H -u "$DEPLOY_USER" git clone "$REPO_URL" "$APP_DIR" > /dev/null 2>&1
        ok "Repository cloned"
    fi

    info "Installing dependencies and building (this may take several minutes)..."
    sudo -H -u "$DEPLOY_USER" bash -c "cd '$APP_DIR' && npm install --no-audit --no-fund > /dev/null 2>&1 && npm run build > /dev/null 2>&1" \
        || fail "npm install/build failed — run manually: cd $APP_DIR && npm install && npm run build"
    ok "Dependencies installed, static export built to out/"

    # Install 'serve' globally so PM2 can run it directly (avoids npx overhead)
    if ! command -v serve > /dev/null; then
        run sudo npm install -g serve
        ok "Installed 'serve' globally"
    fi

    info "Starting app with PM2 as $DEPLOY_USER..."
    sudo -H -u "$DEPLOY_USER" bash -c "pm2 start serve --name 'nextjs' -- '$APP_DIR/out' > /dev/null 2>&1 && pm2 save > /dev/null 2>&1" \
        || fail "PM2 start failed — check: sudo -H -u $DEPLOY_USER pm2 logs nextjs"
    sleep 3

    local pm2_bin
    pm2_bin=$(command -v pm2)
    "$pm2_bin" startup systemd -u "$DEPLOY_USER" --hp "/home/$DEPLOY_USER" > /dev/null 2>&1 \
        && ok "PM2 startup configured (app survives reboots)"

    curl -sf -o /dev/null http://127.0.0.1:3000 \
        && ok "App responding on port 3000" \
        || fail "Nothing listening on port 3000 — check: sudo -H -u $DEPLOY_USER pm2 logs nextjs"
}

# --- Step 10: Firewall ---
setup_ufw() {
    section_header "Step 10/12  Firewall (UFW)"
    if ! confirm "Enable UFW now? (allows 22, 80, 443 — blocks everything else)"; then
        warn "Skipped firewall setup"
        return
    fi
    run sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ufw
    run sudo ufw default deny incoming
    run sudo ufw default allow outgoing
    run sudo ufw allow ssh
    run sudo ufw allow 80/tcp
    run sudo ufw allow 443/tcp
    run sudo ufw --force enable
    ok "UFW active: allowing 22/tcp, 80/tcp, 443/tcp"
}

# --- Step 11: Fail2ban ---
setup_fail2ban() {
    section_header "Step 11/12  Fail2ban (Intrusion Prevention)"
    run sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq fail2ban

    run sudo tee /etc/fail2ban/jail.local > /dev/null <<'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = ssh
logpath = /var/log/auth.log

[apache-auth]
enabled = true
port = http,https
logpath = /var/log/apache2/app-error.log
EOF
    run sudo systemctl enable --now fail2ban
    ok "Fail2ban active (ban after 5 failures, 1 hour)"
}

# --- Step 12: Backup ---
setup_backup() {
    section_header "Step 12/12  Backup Configuration"

    if ! confirm "Configure automated daily backups? (backs up configs, SSL certs, and app source)"; then
        warn "Skipped backup configuration"
        return
    fi

    run sudo tee /usr/local/bin/backup-server.sh > /dev/null <<'BACKUP'
#!/usr/bin/env bash
# Daily backup of server configs, SSL certs, and app source
set -euo pipefail

BACKUP_DIR="/var/backups/server"
DATE=$(date +%Y-%m-%d)
KEEP_DAYS=30

mkdir -p "$BACKUP_DIR"

# Backup Apache configs
tar czf "$BACKUP_DIR/apache-config-$DATE.tar.gz" \
    /etc/apache2/sites-available/ \
    /etc/apache2/conf-available/ \
    /etc/logrotate.d/apache2-app 2>/dev/null

# Backup SSL certs
tar czf "$BACKUP_DIR/ssl-certs-$DATE.tar.gz" \
    /etc/ssl/certs/selfsigned.crt \
    /etc/ssl/private/selfsigned.key 2>/dev/null

# Backup SSH config
cp /etc/ssh/sshd_config "$BACKUP_DIR/ssh-hardening-$DATE.conf" 2>/dev/null || true

# Backup fail2ban config
cp /etc/fail2ban/jail.local "$BACKUP_DIR/fail2ban-jail-$DATE.local" 2>/dev/null || true

# Backup PM2 process list
sudo -H -u agmyintmyat pm2 save --force 2>/dev/null || true
cp /home/agmyintmyat/.pm2/dump.pm2 "$BACKUP_DIR/pm2-dump-$DATE.json" 2>/dev/null || true

# Backup app source (shallow clone, latest commit only)
if [[ -d /var/www/app/.git ]]; then
    tar czf "$BACKUP_DIR/app-source-$DATE.tar.gz" \
        --exclude='node_modules' --exclude='.next' \
        -C /var/www app 2>/dev/null
fi

# Cleanup old backups
find "$BACKUP_DIR" -name "*.tar.gz" -mtime +$KEEP_DAYS -delete 2>/dev/null || true
find "$BACKUP_DIR" -name "*.conf" -mtime +$KEEP_DAYS -delete 2>/dev/null || true
find "$BACKUP_DIR" -name "*.local" -mtime +$KEEP_DAYS -delete 2>/dev/null || true
find "$BACKUP_DIR" -name "*.json" -mtime +$KEEP_DAYS -delete 2>/dev/null || true
BACKUP

    run sudo chmod +x /usr/local/bin/backup-server.sh

    # Install cron job (daily at 2:37 AM — avoids :00/:30 stampede)
    run sudo tee /etc/cron.d/server-backup > /dev/null <<'CRON'
# Daily server backup at 2:37 AM
37 2 * * * root /usr/local/bin/backup-server.sh >> /var/log/server-backup.log 2>&1
CRON

    # Run initial backup
    if ! $DRY_RUN; then
        sudo /usr/local/bin/backup-server.sh > /dev/null 2>&1 || true
    fi

    ok "Daily backup configured (2:37 AM, 30-day retention)"
    info "Backups stored in /var/backups/server/"
}

# --- Final Verification ---
run_verification() {
    section_header "Verification Summary"
    local vm_ip="$VM_IP"
    [[ -z "$vm_ip" ]] && vm_ip=$(detect_vm_ip)

    local pass=0 total=0
    check() {
        total=$((total + 1))
        if eval "$2" > /dev/null 2>&1; then
            ok "$1"; pass=$((pass + 1))
        else
            warn "$1"
        fi
    }

    check "Apache2 service running"          "systemctl is-active --quiet apache2"
    check "Next.js responding on :3000"      "curl -sf http://127.0.0.1:3000"
    check "HTTP redirects to HTTPS (301)"    "curl -sI http://${vm_ip} | grep -q 301"
    check "HTTPS serves the site (200)"      "curl -skI https://127.0.0.1 | grep -q 200"
    check "Health check endpoint (200)"      "curl -sk https://127.0.0.1/health | grep -q 'OK'"
    check "Static assets served by Apache"   "curl -skI https://127.0.0.1/_next/static/ | grep -q 200"
    check "UFW firewall active"              "sudo ufw status | grep -q 'Status: active'"
    check "fail2ban service running"         "sudo systemctl is-active --quiet fail2ban"
    check "PM2 process online"               "sudo -H -u $DEPLOY_USER pm2 prettylist 2>/dev/null | grep -q '\"status\": \"online\"'"
    check "Backup directory exists"          "test -d /var/backups/server"
    check "SSH AllowGroups configured"       "grep -q 'AllowGroups' /etc/ssh/sshd_config"

    echo ""
    echo -e "  ${BOLD}Results: ${pass}/${total} checks passed${RESET}"
    echo ""
    echo -e "  ${BOLD}Next steps (manual):${RESET}"
    echo -e "  ${DIM}1. Any locked accounts:     sudo passwd <username>  (ones skipped during password prompts)${RESET}"
    echo -e "  ${DIM}2. Copy your SSH key:       ssh-copy-id <user>@${vm_ip:-<vm-ip>}  (before relying on key-only auth)${RESET}"
    echo -e "  ${DIM}3. Browse:                  https://${vm_ip:-<vm-ip>}  (accept the self-signed certificate warning)${RESET}"
    echo -e "  ${DIM}4. Health check:            https://${vm_ip:-<vm-ip>}/health${RESET}"
    echo -e "  ${DIM}5. Optional domain TLS:     see SERVER_SETUP.md Section 9 (Certbot)${RESET}"
    echo ""
}

# --- Main Entry Point ---
print_banner
check_root_or_sudo
check_ubuntu

VM_IP="${VM_IP:-$(detect_vm_ip)}"
[[ -n "$VM_IP" ]] && info "Detected VM IP: $VM_IP (override with VM_IP=... )"

confirm "Proceed with full server setup? (risky/optional steps will ask again)" \
    || { warn "Setup cancelled."; exit 0; }

system_update
configure_network
setup_ssh
setup_tailscale
create_users
prepare_web_dir
setup_apache
install_node
deploy_app
setup_ufw
setup_fail2ban
setup_backup
run_verification
