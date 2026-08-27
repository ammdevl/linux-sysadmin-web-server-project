# Web Server — Linux SysAdmin Project Proposal

**Approved by:** @All Members

**Date of Submission:** 2026-08-21

**Target Environment:** Ubuntu 24.04 LTS

## Gist

A secure Apache2 web server hosting a self-paced course Next.js application on a VMware virtual machine, with proper user/group management, file permissions, and SSL/TLS encryption.

## Story

A training center needs a self-paced course website where students can access learning materials and track their progress — all hosted on a VMware virtual machine. Without proper Linux administration, the app runs as root with wide-open permissions — anyone on the server can read, modify, or delete critical files. By applying user and group management, the sysadmin creates dedicated accounts for deployment and administration, restricts file access to the right people, and hardens the server so only authorized users can manage the site.

## Why

- Deploys the Next.js app on a real VMware virtual machine, making it accessible on the network.
- Applies lecture concepts — user accounts, groups, and file permissions — in a real-world scenario.
- Ensures least-privilege access: the web server process, the deployer, and the admin each have their own restricted permissions.

## Why Not

- No domain registration — access is via the VM's IP address only.
- No load balancing or clustering — single VM for learning purposes.
- No containerization (Docker/Podman) — bare-metal setup to understand the underlying services.
- No CMS or database — the site is a standalone Next.js application.
- No CI/CD pipeline — deployment is done manually via SSH for direct learning.

## Tech Spec

- **OS / Distro:** Ubuntu 24.04 LTS (VMware Virtual Machine)
- **Core Services & Packages:**
  - `apache2` — web server and reverse proxy
  - `libapache2-mod-proxy-http` — Apache reverse proxy module
  - `nodejs` + `npm` — runtime for Next.js
  - `certbot` + `python3-certbot-apache` — SSL/TLS certificate management
  - `ufw` — firewall
  - `fail2ban` — intrusion prevention, bans IPs after repeated failed attempts
  - `tailscale` — secure tunnel between host and VM, WireGuard-based VPN
- **User & Group Management:**
  - `sysadmin` group — full sudo access for server administration
  - `dev` group — deployment access, owns and manages web files
  - Apache runs under `www-data` (system default, not customized)
  - Default accounts (`root` excluded) locked or removed
- **File & Directory Permissions:**
  - `/var/www/app/` — owned by `deployer:dev`, `775` directories, `664` files
  - `dev` group has read/write access to web files
  - `sysadmin` group has full access to all server configs
  - SSH keys restricted — no password login, key-only authentication
  - Sensitive config files (`.env`, SSL keys) readable only by root or `sysadmin` group
  - Web server cannot write to its own document root (defense against compromise)
- **Automation / Config:**
  - Bash script for server setup, user creation, permission configuration, and Apache setup
  - Config templates stored in the repository for consistent deployments
- **Architecture / Flow:**
  ```
  Production Access (Browser):
      Client → HTTPS (<vm-ip>:443) → Apache2 (TLS termination)
          → Reverse Proxy (ProxyPass) → Next.js (port 3000)

  Admin Access (Host → VM via Tailscale):
      Host Machine ←→ Tailscale (WireGuard) ←→ VMware VM
          SSH (22) → deployer user → git pull → build → restart
  ```
  - Production access: `https://<vm-ip>` (direct, no Tailscale)
  - Admin/development access: via Tailscale tunnel (SSH, deployment)
  - Tailscale is used only for sysadmin and dev configuration — not for end-user production traffic
  - Next.js runs on `localhost:3000` managed by PM2 as dedicated user
  - Apache proxies all requests to the Node.js process
  - All file operations logged and permission-restricted

## Security & Backup Plan

- Tailscale provides encrypted tunnel for admin access only — production traffic does not go through Tailscale.
- UFW allows only SSH (22), HTTP (80), and HTTPS (443) — all other ports blocked.
- SSH hardened: key-only auth, root login disabled, port changed from default.
- fail2ban monitors SSH and Apache logs — auto-bans IPs after 5 failed attempts for 1 hour.
- Apache configured with `ServerTokens Prod` and `ServerSignature Off` to hide version info.
- Dedicated system user for Next.js process — not running as root.
- File permissions enforce least-privilege — web server cannot modify its own files.
- SSL hardened with TLS 1.2/1.3 only, strong cipher suites, and HSTS headers.
- `.env` and config files readable only by their dedicated owner.
- Regular backups of config and app source to the repository.

## Definition of Done

- [x] Tailscale is installed and host can reach VM for admin access (`tailscale status`).
- [x] VM is accessible via SSH over Tailscale with key-only authentication (no password login).
- [x] `sysadmin` and `dev` groups created with appropriate members.
- [x] Dedicated `developers` (in `dev`) and `admins` (in `sysadmin`) users created.
- [x] Root login is disabled over SSH.
- [x] Apache2 installs and starts without errors (`systemctl status apache2` shows active).
- [x] Next.js app builds and runs on `localhost:3000` as a dedicated non-root user.
- [x] `curl http://<tailscale-ip>` returns the Next.js page via Apache reverse proxy.
- [x] HTTPS works — `curl -I https://<tailscale-ip>` returns `200` with valid certificate.
- [x] HTTP-to-HTTPS redirect is in place.
- [x] File permissions are correct — `ls -la /var/www/app/` shows proper ownership.
- [x] Web server process cannot write to its own document root.
- [x] Firewall blocks all ports except 22, 80, and 443.
- [x] fail2ban is active and monitoring SSH and Apache (`fail2ban-client status`).
- [x] Server version info is hidden in HTTP response headers.
- [x] Apache starts on boot (`systemctl enable apache2`).
- [x] Next.js starts on boot via PM2 (`pm2 startup` + `pm2 save`).

## Key References & Documentation

- [Ubuntu Server Guide](https://ubuntu.com/server/docs)
- [Apache2 Documentation](https://httpd.apache.org/docs/2.4/)
- [Apache mod_proxy Documentation](https://httpd.apache.org/docs/2.4/mod/mod_proxy.html)
- [Next.js Deployment Guide](https://nextjs.org/docs/deploying)
- [Ubuntu UFW Guide](https://help.ubuntu.com/community/UFW)
- [Fail2ban Documentation](https://github.com/fail2ban/fail2ban)
- [Tailscale Documentation](https://tailscale.com/kb/)
- [PM2 Documentation](https://pm2.keymetrics.io/docs/usage/quick-start/)
- [Netplan Documentation](https://netplan.io/)
- [Linux File Permissions Guide](https://www.linuxfoundation.org/blog/linux-file-permissions)
