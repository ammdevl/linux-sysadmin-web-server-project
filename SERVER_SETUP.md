# Web Server Manual Setup Guide

Step-by-step guide to set up an Apache2 + Next.js web server on a VMware Ubuntu 24.04 LTS virtual machine.

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Network Configuration](#2-network-configuration)
3. [SSH Setup](#3-ssh-setup)
4. [Tailscale Setup (Admin Access)](#4-tailscale-setup-admin-access)
5. [User & Group Management](#5-user--group-management)
6. [File & Directory Permissions](#6-file--directory-permissions)
7. [Apache2 Installation & Configuration](#7-apache2-installation--configuration)
8. [Node.js & Next.js Setup](#8-nodejs--nextjs-setup)
9. [SSL/TLS with Certbot](#9-ssltls-with-certbot)
10. [Firewall (UFW)](#10-firewall-ufw)
11. [Fail2ban](#11-fail2ban)
12. [Backup](#12-backup)
13. [Verification](#13-verification)

## 1. Prerequisites

Before starting, ensure you have:

- **VMware Workstation / Fusion** installed on your host machine
- **Ubuntu 24.04 LTS ISO** downloaded
- **Host machine** with internet access
- **sudo / root privileges** on the VM

### Create the Virtual Machine

1. Open VMware → Create a New Virtual Machine
2. Select **Ubuntu 24.04 LTS** ISO
3. Allocate resources:
   - **CPU:** 2+ cores
   - **RAM:** 4 GB minimum
   - **Disk:** 40 GB+
   - **Network:** NAT (we'll configure static IP later)
4. Complete the installation and boot into Ubuntu

### Update the System

After the first boot, update the system and install prerequisite packages:

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y git curl openssl
```

> `git` is needed to clone the app repository in §8. `curl` and `openssl` are used for Tailscale installation and certificate generation.

## 2. Network Configuration

### Assign a Static IP Address

The VM needs a static IP so services remain reachable after reboots.

1. Open Netplan configuration:
    ```bash
    sudo cp /etc/netplan/50-cloud-init.yaml /etc/netplan/50-cloud-init.yaml.bak
    sudo nano /etc/netplan/50-cloud-init.yaml
    ```

2. Replace the contents with:
    ```yaml
    network:
      version: 2
      ethernets:
        ens33:
          dhcp4: false
          addresses:
            - 192.168.10.3/24
          routes:
            - to: default
              via: 192.168.10.2
          nameservers:
            addresses: [8.8.8.8, 8.8.4.4]
    ```

    > **Note:** Adjust `ens33`, `192.168.10.3`, and `192.168.10.2` to match your VMware network setup. Check your interface name with `ip a`.

3. Test and apply:
    ```bash
    sudo netplan try        # tests config (reverts after 120s if not confirmed)
    sudo netplan apply      # applies permanently
    ip a                    # verify static IP
    ```

## 3. SSH Setup

### Install OpenSSH Server (on VM)

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install openssh-server -y
```

### Verify SSH is Running

```bash
sudo systemctl status ssh
```

### Connect from Host Machine

**Linux / macOS:**
```bash
ssh <username>@192.168.10.3
```

**Windows (PowerShell):**
```powershell
ssh <username>@192.168.10.3
```

### Set Up Key-Based Authentication

1. On your **host machine**, generate an SSH key pair:
    ```bash
    ssh-keygen -t ed25519 -C "your-email@example.com"
    ```
    Press Enter to accept defaults (or set a passphrase for extra security).

2. Copy the public key to the VM:
    ```bash
    ssh-copy-id <username>@192.168.10.3
    ```

3. Test key-based login (should NOT ask for password):
    ```bash
    ssh <username>@192.168.10.3
    ```

### Team Key Distribution

Each team member must add their own SSH key to the VM before password authentication is disabled. Repeat the following **on each member's host machine**:

1. Generate a key pair (skip if you already have one):
    ```bash
    ssh-keygen -t ed25519 -C "your-email@example.com"
    ```

2. Copy the public key to the VM:
    ```bash
    ssh-copy-id <username>@192.168.10.3
    ```

3. Verify you can log in without a password:
    ```bash
    ssh <username>@192.168.10.3
    ```

> **Important:** Complete this for every team member **before** proceeding to the next step. Once password authentication is disabled, there is no way to add keys remotely — you would need console access from VMware.

### Disable Password Authentication and Root Login (on VM)

> **Security:** Root login is disabled to prevent direct remote access to the root account. All administration is done through regular users with `sudo`.

1. Open SSH config:
    ```bash
    sudo nano /etc/ssh/sshd_config
    ```

2. Find and change these lines:
    ```
    PasswordAuthentication no
    PermitRootLogin no
    AllowGroups sysadmin dev
    ```

3. Restart SSH:
    ```bash
    sudo systemctl restart ssh
    ```

## 4. Tailscale Setup (Admin Access)

Tailscale provides a secure tunnel between your host machine and the VM for administration purposes only. Production traffic does **not** go through Tailscale.

### Install Tailscale on VM

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

Follow the authentication URL to link the VM to your Tailscale account.

### Install Tailscale on Host Machine

Download and install from [tailscale.com/download](https://tailscale.com/download). Sign in with the same account.

### Verify Tunnel

1. On host, check Tailscale status:
    ```bash
    tailscale status
    ```

2. Ping the VM via Tailscale:
    ```bash
    ping <tailscale-ip>
    ```

3. SSH via Tailscale:
    ```bash
    ssh <username>@<tailscale-ip>
    ```

> **Note:** Tailscale is used only for sysadmin and dev configuration. The website is accessed via the VM's static IP directly.

## 5. User & Group Management

### Create Groups

```bash
sudo groupadd sysadmin
sudo groupadd dev
```

### Create Users

```bash
# Admin user (sysadmin group, sudo access)
sudo useradd -m -s /bin/bash -G sysadmin mgkhant
sudo useradd -m -s /bin/bash -G sysadmin agmyintmyatag
sudo useradd -m -s /bin/bash -G sysadmin gonyaungwin
sudo useradd -m -s /bin/bash -G sysadmin agkhantkyaw
sudo useradd -m -s /bin/bash -G sysadmin santhiritun

# Deployer users (dev group) — agmyintmyat is the primary deployer
sudo useradd -m -s /bin/bash -G dev kghtutthaw
sudo useradd -m -s /bin/bash -G dev hanlinhtun
sudo useradd -m -s /bin/bash -G dev shoonlaeaung
sudo useradd -m -s /bin/bash -G dev agmyintmyat
```

### Set Passwords

If you used [server-setup.sh](script/server-setup.sh), it prompts for each new user's password interactively (input hidden, Enter skips and leaves the account locked). For classroom demos on the isolated lab VM, `12345678` is used as the shared convention — never reuse it outside the lab.

For manual setup, run `passwd` for every account:

```bash
sudo passwd mgkhant
sudo passwd agmyintmyatag
sudo passwd gonyaungwin
sudo passwd agkhantkyaw
sudo passwd santhiritun
sudo passwd kghtutthaw
sudo passwd hanlinhtun
sudo passwd shoonlaeaung
sudo passwd agmyintmyat
```

### Grant sudo to sysadmin and dev Groups

```bash
sudo usermod -aG sudo mgkhant
sudo usermod -aG sudo agmyintmyatag
sudo usermod -aG sudo gonyaungwin
sudo usermod -aG sudo agkhantkyaw
sudo usermod -aG sudo santhiritun
```

### Verify Groups

```bash
groups mgkhant        # should show: mgkhant sysadmin
groups agmyintmyat    # should show: agmyintmyat dev (primary deployer)
```

### Lock Unused Default Accounts

```bash
sudo usermod -L <unused-default-user>
```

## 6. File & Directory Permissions

### Create Web Directory

```bash
sudo mkdir -p /var/www/app
```

### Set Ownership

```bash
sudo chown -R agmyintmyat:dev /var/www/app
```

### Set Permissions

```bash
# Directories: 775 (owner+group read/write/execute)
sudo chmod 775 /var/www/app

# Files: 664 (owner+group read/write, others read)
sudo chmod -R 664 /var/www/app/*
```

### Verify Permissions

```bash
ls -la /var/www/app/
# Expected: drwxrwxr-x agmyintmyat dev
```

### Protect Sensitive Files

If the application uses a `.env` file (e.g., for API keys or secrets), restrict it to the owner:

```bash
sudo chown agmyintmyat:dev /var/www/app/.env
sudo chmod 600 /var/www/app/.env
```

> **Note:** The [lfs-101-notes](https://github.com/ammdevl/lfs-101-notes) app is a static export and does not use a `.env` file at runtime — this step only applies if your app requires one.

## 7. Apache2 Installation & Configuration

### Install Apache2

```bash
sudo apt install apache2 -y
```

### Enable Required Modules

```bash
sudo a2enmod proxy
sudo a2enmod proxy_http
sudo a2enmod rewrite
sudo a2enmod headers
sudo a2enmod ssl
```

### Generate a Self-Signed Certificate

> Access is via the VM IP address only, and Let's Encrypt cannot issue certificates for bare IPs — so a self-signed certificate is used by default. Browsers will show a one-time trust warning; this is expected.

Generate the certificate **before** creating the VirtualHost so Apache passes `configtest` on the first try. ECDSA (P-256) is used instead of RSA for stronger security and faster handshakes:

```bash
sudo openssl req -x509 -nodes -days 365 \
    -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -keyout /etc/ssl/private/selfsigned.key \
    -out /etc/ssl/certs/selfsigned.crt \
    -subj "/CN=<vm-ip>"
```

### Create Virtual Host Configuration

```bash
sudo nano /etc/apache2/sites-available/app.conf
```

Add the following:
```apache
<VirtualHost *:80>
    ServerName <vm-ip>

    # Redirect all HTTP to HTTPS
    RewriteEngine On
    RewriteCond %{HTTPS} off
    RewriteRule ^ https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]
</VirtualHost>

<VirtualHost *:443>
    ServerName <vm-ip>

    # SSL Configuration (self-signed ECDSA certificate generated above)
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
    Alias /_next/static/ /var/www/app/out/_next/static/

    # All other requests proxied to Node.js (PM2)
    ProxyPreserveHost On
    ProxyPass / http://127.0.0.1:3000/
    ProxyPassReverse / http://127.0.0.1:3000/

    # Health check endpoint (returns 200 without hitting Node.js)
    ProxyPass /health !
    Alias /health /var/www/app/out/health.html

    # Logs
    ErrorLog ${APACHE_LOG_DIR}/app-error.log
    CustomLog ${APACHE_LOG_DIR}/app-access.log combined
</VirtualHost>
```

> **Note:** Replace `<vm-ip>` with your actual VM IP address. The certificate paths point to the self-signed pair generated above.

### Enable the Site

```bash
sudo a2ensite app.conf
sudo a2dissite 000-default.conf
```

### Hide Server Version (Global Config)

> `ServerTokens` and `ServerSignature` are server-context directives — placing them inside a `<VirtualHost>` block breaks `configtest`. They belong in `/etc/apache2/conf-available/security.conf`.

Verify these values in `/etc/apache2/conf-available/security.conf`:

```
ServerTokens Prod
ServerSignature Off
```

### Suppress the FQDN Warning

Prevents `AH00558: Could not reliably determine the server's fully qualified domain name` from appearing on every Apache command:

```bash
echo "ServerName <vm-ip>" | sudo tee /etc/apache2/conf-available/servername.conf
sudo a2enconf servername
```

### Test and Restart

```bash
sudo apache2ctl configtest
sudo systemctl restart apache2
sudo systemctl enable apache2
```

## 8. Node.js & Next.js Setup

### Install Node.js (System-Wide via NodeSource)

> **Important:** Do NOT use NVM for server setups — it installs per-user in `~/.nvm/` and won't be available to other users (like `deployer`). Use NodeSource for system-wide access.

```bash
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
sudo apt install -y nodejs
```

Verify:
```bash
node -v
npm -v
```

### Install PM2

PM2 is a process manager for Node.js that handles auto-restarts, log rotation, and startup on boot.

```bash
sudo npm install -g pm2
```

> **Important:** Install PM2 as root (with `sudo`) **before** switching to the deployer user in the next step. A global install ensures PM2 is available in all users' PATH.

### Deploy the Next.js App

1. Switch to deployer user:
    ```bash
    su agmyintmyat
    ```

2. Clone the project:
    ```bash
    cd /var/www
    git clone https://github.com/ammdevl/lfs-101-notes.git app
    cd app
    ```

3. Install dependencies and build (from the repo root `/var/www/app`):
    ```bash
    npm install
    npm run build
    ```
    > This app is a static export (`output: "export"` in `next.config.js`) — the build produces plain HTML/CSS/JS in `./out`.

4. Start the app with PM2 (from the repo root `/var/www/app`):
    ```bash
    npm install -g serve
    pm2 start serve --name "nextjs" -- /var/www/app/out
    ```
    > This serves the static build from `./out` on port 3000. Do NOT use `next start` — it fails with a static export (`output: "export"`) configuration. Installing `serve` globally avoids `npx` downloading it on every cold start.

5. Save PM2 process list and get the startup command:
    ```bash
    pm2 save
    pm2 startup
    ```
    > PM2 prints a `sudo env PATH=...` command. **Do not run it as the deployer** — `dev` users have no sudo by design. Just copy it, then move to the next step.

6. Exit back to admin:
    ```bash
    exit
    ```

    > Now paste the `sudo env PATH=...` command PM2 printed in previous state.

### Verify PM2

```bash
pm2 status          # should show "nextjs" as online
pm2 logs nextjs     # check application logs (crash reasons appear here)
curl -I http://127.0.0.1:3000    # should return HTTP 200 from the Next.js page
```

> **Note:** The app runs from the repo root `/var/www/app` — all `npm` commands (install, build, start) are executed in this directory. Verify `curl -I http://127.0.0.1:3000` returns 200 **before** troubleshooting Apache; a 503 from Apache means this backend is down.

### PM2 Useful Commands

```bash
pm2 restart nextjs          # restart the app
pm2 stop nextjs             # stop the app
pm2 delete nextjs           # remove the app
pm2 logs nextjs             # view logs
pm2 monit                   # real-time monitoring dashboard
```

## 9. SSL/TLS with Certbot

> **Optional — requires a domain.** Skip this section for IP-only access: the VM already uses a self-signed certificate (Section 7), and Let's Encrypt cannot issue certificates for bare IPs.

### Install Certbot

```bash
sudo apt install certbot python3-certbot-apache -y
```

### Obtain Certificate

```bash
sudo certbot --apache -d <your-domain>
```

Certbot obtains the certificate and rewrites `app.conf` automatically. Then update `ServerName` in `/etc/apache2/sites-available/app.conf` from `<vm-ip>` to `<your-domain>` and swap the self-signed certificate lines for the Let's Encrypt paths Certbot reports.

### Auto-Renewal (for Let's Encrypt only)

```bash
sudo systemctl status certbot.timer
sudo certbot renew --dry-run
```

## 10. Firewall (UFW)

### Install and Enable

```bash
sudo apt install ufw -y
```

### Set Rules

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
```

### Enable Firewall

```bash
sudo ufw enable
```

### Verify

```bash
sudo ufw status verbose
```

---

## 11. Fail2ban

### Install

```bash
sudo apt install fail2ban -y
```

### Configure

```bash
sudo nano /etc/fail2ban/jail.local
```

Add:
```ini
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
```

### Start and Enable

```bash
sudo systemctl start fail2ban
sudo systemctl enable fail2ban
```

### Verify

```bash
sudo fail2ban-client status
sudo fail2ban-client status sshd
```

## 12. Backup

Configure automated daily backups of server configs, SSL certs, and app source:

```bash
sudo tee /usr/local/bin/backup-server.sh > /dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
BACKUP_DIR="/var/backups/server"
DATE=$(date +%Y-%m-%d)
KEEP_DAYS=30
mkdir -p "$BACKUP_DIR"
tar czf "$BACKUP_DIR/apache-config-$DATE.tar.gz" /etc/apache2/sites-available/ /etc/apache2/conf-available/ /etc/logrotate.d/apache2-app 2>/dev/null
tar czf "$BACKUP_DIR/ssl-certs-$DATE.tar.gz" /etc/ssl/certs/selfsigned.crt /etc/ssl/private/selfsigned.key 2>/dev/null
cp /etc/ssh/sshd_config "$BACKUP_DIR/ssh-hardening-$DATE.conf" 2>/dev/null || true
cp /etc/fail2ban/jail.local "$BACKUP_DIR/fail2ban-jail-$DATE.local" 2>/dev/null || true
sudo -H -u agmyintmyat pm2 save --force 2>/dev/null || true
cp /home/agmyintmyat/.pm2/dump.pm2 "$BACKUP_DIR/pm2-dump-$DATE.json" 2>/dev/null || true
if [[ -d /var/www/app/.git ]]; then
    tar czf "$BACKUP_DIR/app-source-$DATE.tar.gz" \
        --exclude='node_modules' --exclude='.next' \
        -C /var/www app 2>/dev/null
fi
find "$BACKUP_DIR" -name "*.tar.gz" -mtime +$KEEP_DAYS -delete 2>/dev/null || true
find "$BACKUP_DIR" -name "*.conf" -mtime +$KEEP_DAYS -delete 2>/dev/null || true
find "$BACKUP_DIR" -name "*.local" -mtime +$KEEP_DAYS -delete 2>/dev/null || true
find "$BACKUP_DIR" -name "*.json" -mtime +$KEEP_DAYS -delete 2>/dev/null || true
EOF
sudo chmod +x /usr/local/bin/backup-server.sh
```

Schedule daily execution:

```bash
echo '37 2 * * * root /usr/local/bin/backup-server.sh >> /var/log/server-backup.log 2>&1' | sudo tee /etc/cron.d/server-backup
```

Run the initial backup:

```bash
sudo /usr/local/bin/backup-server.sh
ls -la /var/backups/server/
```

## 13. Verification

Run these checks to confirm everything works:

### Services

```bash
sudo systemctl status apache2
sudo systemctl is-active fail2ban
sudo -H -u agmyintmyat pm2 status
```

### HTTP → HTTPS Redirect

```bash
curl -I http://<vm-ip>
# Should return: HTTP/1.1 301 Moved Permanently
#                Location: https://<vm-ip>/
```

### HTTPS Serving

```bash
curl -skI https://<vm-ip>
# Should return: HTTP/1.1 200 OK
```

### Health Check Endpoint

```bash
curl -sk https://<vm-ip>/health
# Should return: HTML page with "Service OK"
```

### Static Assets (served directly by Apache)

```bash
curl -skI https://<vm-ip>/_next/static/
# Should return: HTTP/1.1 200 OK (Apache serving from disk)
```

### Server Version Hidden

```bash
curl -skI https://<vm-ip> | grep -i server
# Should return: Server: Apache (no version number)
```

### Tailscale (Admin Access)

```bash
tailscale status
ping <tailscale-ip>
ssh <username>@<tailscale-ip>
```

### File Permissions

```bash
ls -la /var/www/app/
# Expected: drwxrwxr-x agmyintmyat dev
```

### Firewall

```bash
sudo ufw status verbose
# Status: active, only 22/tcp, 80/tcp, 443/tcp allowed
```

### Fail2ban

```bash
sudo fail2ban-client status
sudo fail2ban-client status sshd
```

To verify fail2ban is actually banning, attempt 6 failed SSH logins from another machine. The IP should be banned after the 5th failure:

```bash
sudo fail2ban-client status sshd
# Should show at least 1 banned IP under "Currently banned"
```

### Boot Persistence

After a reboot, verify services start automatically:

```bash
sudo systemctl is-enabled apache2    # should return: enabled
sudo systemctl is-enabled fail2ban   # should return: enabled
sudo systemctl is-enabled pm2-agmyintmyat  # should return: enabled
```

### SSH Hardening

```bash
grep AllowGroups /etc/ssh/sshd_config
# Should return: AllowGroups sysadmin dev
```

### Backup

```bash
test -d /var/backups/server && echo "Backup directory exists"
ls -lt /var/backups/server/ | head -5
```

---

## Reference

1. [Netplan Configuration](https://netplan.io/)
2. [SSH Key-Based Authentication](https://www.digitalocean.com/community/tutorials/how-to-configure-ssh-key-based-authentication-on-a-linux-server)
3. [Tailscale Documentation](https://tailscale.com/kb/)
4. [Apache2 Virtual Hosts](https://ubuntu.com/tutorials/install-and-configure-apache)
5. [UFW Firewall Guide](https://help.ubuntu.com/community/UFW)
6. [Fail2ban Setup](https://www.digitalocean.com/community/tutorials/how-to-protect-ssh-with-fail2ban-on-ubuntu-20-04)
7. [Node.js Installation](https://nodejs.org/en/download)
8. [Certbot Apache Plugin](https://certbot.eff.org/instructions?ws=apache&os=ubuntunoble)
9. [Linux File Permissions](https://www.linuxfoundation.org/blog/linux-file-permissions)
10. [Ubuntu User Management](https://ubuntu.com/server/docs/user-management)
