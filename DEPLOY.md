# Deployment & Operations Guide

Day-to-day operational procedures for the web server. For initial setup, see [SERVER_SETUP.md](SERVER_SETUP.md).

## Table of Contents

1. [Deploying App Updates](#1-deploying-app-updates)
2. [Adding a Team Member](#2-adding-a-team-member)
3. [Removing a Team Member](#3-removing-a-team-member)
4. [Rotating SSL Certificates](#4-rotating-ssl-certificates)
5. [Backup & Recovery](#5-backup--recovery)
6. [Monitoring & Health Checks](#6-monitoring--health-checks)
7. [Troubleshooting Runbook](#7-troubleshooting-runbook)

---

## 1. Deploying App Updates

The app ([lfs-101-notes](https://github.com/ammdevl/lfs-101-notes)) is a Next.js static export. Updates require pulling the latest code, rebuilding, and restarting PM2.

### Via SSH (manual)

```bash
# SSH into the VM
ssh <deploy-user>@<vm-ip>

# Pull latest code
cd /var/www/app
git pull origin main

# Rebuild
npm install --no-audit --no-fund
npm run build

# Restart PM2
pm2 restart nextjs

# Verify
curl -I http://127.0.0.1:3000    # expect 200
curl -skI https://<vm-ip>         # expect 200
```

### Health check after deploy

```bash
curl -sk https://<vm-ip>/health
# Should return: {"status":"ok",...}
```

---

## 2. Adding a Team Member

### Step 1: Generate SSH key (on their host machine)

```bash
ssh-keygen -t ed25519 -C "their-email@example.com"
```

### Step 2: Copy key to the VM

```bash
ssh-copy-id <new-user>@<vm-ip>
```

### Step 3: Create the user account (on the VM, as sysadmin)

```bash
# For sysadmin role:
sudo useradd -m -s /bin/bash -G sysadmin <username>
sudo usermod -aG sudo <username>
sudo passwd <username>

# For dev role:
sudo useradd -m -s /bin/bash -G dev <username>
sudo passwd <username>
```

### Step 4: Verify

```bash
# From their host machine:
ssh <username>@<vm-ip>
# Should NOT ask for a password
groups <username>
```

### Step 5: Update the repository

Add their username to `SYSADMIN_USERS` or `DEV_USERS` in `script/server-setup.sh`.

---

## 3. Removing a Team Member

### SSH Key Revocation

```bash
# On the VM, remove their key from authorized_keys
sudo nano /home/<username>/.ssh/authorized_keys
# Delete the line containing their public key
```

### Lock the Account

```bash
# Lock the account (preserves home directory and files)
sudo usermod -L <username>

# Or fully remove the account
sudo userdel -r <username>
```

### Verify

```bash
# From their host machine (should fail):
ssh <username>@<vm-ip>
# Expected: Permission denied (publickey).
```

---

## 4. Rotating SSL Certificates

The self-signed certificate expires after 365 days. Check expiration:

```bash
openssl x509 -in /etc/ssl/certs/selfsigned.crt -noout -dates
```

### Regenerate (self-signed)

```bash
sudo openssl req -x509 -nodes -days 365 \
    -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -keyout /etc/ssl/private/selfsigned.key \
    -out /etc/ssl/certs/selfsigned.crt \
    -subj "/CN=<vm-ip>"

sudo systemctl restart apache2
```

### Switch to Let's Encrypt (if you have a domain)

```bash
sudo apt install certbot python3-certbot-apache -y
sudo certbot --apache -d your-domain.com
sudo systemctl status certbot.timer
```

---

## 5. Backup & Recovery

### What's backed up

The automated backup (`/usr/local/bin/backup-server.sh`) runs daily at 2:37 AM and stores:

| Content | Location in backup |
|---|---|
| Apache vhost + config | `apache-config-YYYY-MM-DD.tar.gz` |
| SSL certificate + key | `ssl-certs-YYYY-MM-DD.tar.gz` |
| SSH hardening config | `ssh-hardening-YYYY-MM-DD.conf` |
| fail2ban jail config | `fail2ban-jail-YYYY-MM-DD.local` |
| PM2 process list | `pm2-dump-YYYY-MM-DD.json` |
| App source (no node_modules) | `app-source-YYYY-MM-DD.tar.gz` |

Backups are stored in `/var/backups/server/` with 30-day retention.

### Manual backup

```bash
sudo /usr/local/bin/backup-server.sh
ls -la /var/backups/server/
```

### Restore from backup

```bash
cd /var/backups/server

# Restore Apache config
sudo tar xzf apache-config-2026-09-01.tar.gz -C /

# Restore SSL certs
sudo tar xzf ssl-certs-2026-09-01.tar.gz -C /

# Restore app source
sudo tar xzf app-source-2026-09-01.tar.gz -C /var/www/

# Rebuild and restart
cd /var/www/app
npm install && npm run build
pm2 restart nextjs
sudo systemctl restart apache2
```

---

## 6. Monitoring & Health Checks

### Health endpoint

```bash
curl -sk https://<vm-ip>/health
# Returns: {"status":"ok","service":"web-server","timestamp":"..."}
```

### Service status

```bash
# All services
sudo systemctl is-active apache2        # active
sudo systemctl is-active fail2ban       # active
sudo -H -u <deploy-user> pm2 status     # nextjs: online

# Firewall
sudo ufw status

# Fail2ban bans
sudo fail2ban-client status sshd
```

### Log monitoring

```bash
# Apache errors
sudo tail -f /var/log/apache2/app-error.log

# Apache access
sudo tail -f /var/log/apache2/app-access.log

# PM2 logs
sudo -H -u <deploy-user> pm2 logs nextjs

# System auth (SSH attempts)
sudo tail -f /var/log/auth.log
```

---

## 7. Troubleshooting Runbook

### App returns 503

```bash
# 1. Check if PM2 is running
sudo -H -u <deploy-user> pm2 status

# 2. Check if port 3000 is listening
ss -tlnp | grep 3000

# 3. Check PM2 logs
sudo -H -u <deploy-user> pm2 logs nextjs --lines 30

# 4. Restart if needed
sudo -H -u <deploy-user> pm2 restart nextjs
```

### Apache won't start

```bash
# 1. Test config
sudo apache2ctl configtest

# 2. Check error log
sudo tail -20 /var/log/apache2/error.log

# 3. Check if port 80/443 is in use
sudo ss -tlnp | grep -E ':80|:443'
```

### SSH lockout recovery

If you're locked out of SSH (e.g., after enabling key-only auth without copying your key):

1. Open the VM console from VMware Workstation (not SSH)
2. Log in with the password you set during setup
3. Fix the issue:
   ```bash
   # Re-enable password auth temporarily
   sudo sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config.d/99-hardening.conf
   sudo systemctl restart ssh
   ```
4. Copy your SSH key from your host machine:
   ```bash
   ssh-copy-id <user>@<vm-ip>
   ```
5. Re-enable hardening:
   ```bash
   sudo sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config.d/99-hardening.conf
   sudo systemctl restart ssh
   ```

### Fail2ban banned the wrong IP

```bash
# Check current bans
sudo fail2ban-client status sshd

# Unban a specific IP
sudo fail2ban-client set sshd unbanip <ip-address>
```

### Disk space issues

```bash
# Check disk usage
df -h

# Find large files
sudo du -sh /var/log/* | sort -rh | head -10

# Clean old logs
sudo journalctl --vacuum-time=7d

# Check backup size
du -sh /var/backups/server/
```
