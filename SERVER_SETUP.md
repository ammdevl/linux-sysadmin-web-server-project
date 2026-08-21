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
12. [Verification](#12-verification)

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
            - 192.168.10.5/24
          routes:
            - to: default
              via: 192.168.10.2
          nameservers:
            addresses: [8.8.8.8, 8.8.4.4]
    ```

    > **Note:** Adjust `ens33`, `192.168.10.5`, and `192.168.10.2` to match your VMware network setup. Check your interface name with `ip a`.

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
ssh <username>@192.168.10.5
```

**Windows (PowerShell):**
```powershell
ssh <username>@192.168.10.5
```

### Set Up Key-Based Authentication

1. On your **host machine**, generate an SSH key pair:
    ```bash
    ssh-keygen -t ed25519 -C "your-email@example.com"
    ```
    Press Enter to accept defaults (or set a passphrase for extra security).

2. Copy the public key to the VM:
    ```bash
    ssh-copy-id <username>@192.168.10.5
    ```

3. Test key-based login (should NOT ask for password):
    ```bash
    ssh <username>@192.168.10.5
    ```

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
sudo useradd -m -s /bin/bash -G sysadmin aungkhantkyaw
sudo useradd -m -s /bin/bash -G sysadmin santhiritun

# Deployer user (dev group, for deployment)
sudo useradd -m -s /bin/bash -G dev kghtutthaw
sudo useradd -m -s /bin/bash -G dev hanlinhtun
sudo useradd -m -s /bin/bash -G dev shoonlaeaung
sudo useradd -m -s /bin/bash -G dev agmyintmyat
```

### Set Passwords

```bash
sudo passwd mgkhant
sudo passwd agmyintmyatag
sudo passwd gonyaungwin
sudo passwd aungkhantkyaw
sudo passwd santhiritun
sudo passwd kghtutthaw
sudo passwd hanlinhtun
sudo passwd shoonlaeaung
sudo passwd agmyintmyat
```

### Grant sudo to sysadmin Group

```bash
echo "%sysadmin ALL=(ALL:ALL) ALL" | sudo tee /etc/sudoers.d/sysadmin
```

### Verify Groups

```bash
groups mgkhant      # should show: mgkhant sysadmin
groups kghtutthaw   # should show: kghtutthaw dev
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
sudo chown -R kghtutthaw:dev /var/www/app
```

### Set Permissions

```bash
# Directories: 775 (owner+group read/write/execute)
sudo find /var/www/app -type d -exec chmod 775 {} \;

# Files: 664 (owner+group read/write, others read)
sudo find /var/www/app -type f -exec chmod 664 {} \;
```

### Verify Permissions

```bash
ls -la /var/www/app/
# Expected: drwxrwxr-x kghtutthaw dev
```

### Protect Sensitive Files

```bash
# If .env exists, restrict to owner only
sudo chown kghtutthaw:dev /var/www/app/.env
sudo chmod 600 /var/www/app/.env
```

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

    # SSL Configuration (Certbot will populate these)
    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/<vm-ip>/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/<vm-ip>/privkey.pem

    # Security headers
    Header always set Strict-Transport-Security "max-age=63072000; includeSubDomains"
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-Frame-Options "SAMEORIGIN"

    # Hide server version
    ServerTokens Prod
    ServerSignature Off

    # Reverse proxy to Next.js
    ProxyPreserveHost On
    ProxyPass / http://127.0.0.1:3000/
    ProxyPassReverse / http://127.0.0.1:3000/

    # Static assets served directly by Apache (optional performance boost)
    # ProxyPass /_next/static/ !
    # Alias /_next/static/ /var/www/app/.next/static/

    # Logs
    ErrorLog ${APACHE_LOG_DIR}/app-error.log
    CustomLog ${APACHE_LOG_DIR}/app-access.log combined
</VirtualHost>
```

> **Note:** Replace `<vm-ip>` with your actual VM IP address. SSL paths will be updated after Certbot runs.

### Enable the Site

```bash
sudo a2ensite app.conf
sudo a2dissite 000-default.conf
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

### Deploy the Next.js App

1. Switch to deployer user:
    ```bash
    su - kghtutthaw
    ```

2. Clone the project:
    ```bash
    cd /var/www
    git clone https://github.com/ammdevl/lfs-101-notes.git app
    cd app
    ```

3. Install dependencies and build (from `app/backend` directory):
    ```bash
    cd backend
    npm install
    npm run build
    ```

4. Start the app with PM2 (from `app/backend` directory):
    ```bash
    pm2 start npm --name "nextjs" -- start
    ```

5. Save PM2 process list and set up startup:
    ```bash
    pm2 save
    pm2 startup
    ```
    > PM2 will output a command starting with `sudo env PATH=...`. **Copy and run that exact command** to finalize startup configuration.

6. Exit back to admin:
    ```bash
    exit
    ```

### Verify PM2

```bash
pm2 status          # should show "nextjs" as online
pm2 logs nextjs     # check application logs
curl http://127.0.0.1:3000    # should return the Next.js page
```

> **Note:** The app runs from `/var/www/app/backend` — all `npm` commands (install, build, start) are executed in this directory.

### PM2 Useful Commands

```bash
pm2 restart nextjs          # restart the app
pm2 stop nextjs             # stop the app
pm2 delete nextjs           # remove the app
pm2 logs nextjs             # view logs
pm2 monit                   # real-time monitoring dashboard
```

## 9. SSL/TLS with Certbot

### Install Certbot

```bash
sudo apt install certbot python3-certbot-apache -y
```

### Obtain Certificate

```bash
sudo certbot --apache -d <vm-ip>
```

> **Note:** For IP-based certificates, Let's Encrypt may not issue certificates for bare IPs. If so, use a self-signed certificate instead (see below).

### Self-Signed Certificate (Fallback for IP Access)

```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ssl/private/selfsigned.key \
    -out /etc/ssl/certs/selfsigned.crt \
    -subj "/CN=<vm-ip>"
```

Then update the VirtualHost to use these paths:
```apache
SSLCertificateFile /etc/ssl/certs/selfsigned.crt
SSLCertificateKeyFile /etc/ssl/private/selfsigned.key
```

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

## 12. Verification

Run these checks to confirm everything works:

```bash
# Services are running
sudo systemctl status apache2
pm2 status
sudo systemctl status fail2ban

# Website responds via HTTP (should redirect to HTTPS)
curl -I http://<vm-ip>

# Website responds via HTTPS
curl -I https://<vm-ip>

# Tailscale tunnel works (admin access)
tailscale status
ping <tailscale-ip>

# SSH works over Tailscale
ssh deployer@<tailscale-ip>

# File permissions are correct
ls -la /var/www/app/

# Firewall is active
sudo ufw status

# Fail2ban is active
sudo fail2ban-client status

# Server version is hidden
curl -sI https://<vm-ip> | grep -i server
# Should return: Server: Apache
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
