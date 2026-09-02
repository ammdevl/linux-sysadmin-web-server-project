# Troubleshooting

Known issues and fixes encountered during deployment. Every fix here was verified on a live VMware Ubuntu 24.04 VM.

## Quick Reference

| Symptom | Section | TL;DR |
| --- | --- | --- |
| `Invalid command 'SSLEngine'` | [Apache SSL](#1-invalid-command-sslenge) | `sudo a2enmod ssl` |
| `503 Service Unavailable` | [Backend down](#2-503-service-unavailable-backend-down) | PM2 not running or crashed |
| AH00558 FQDN warning | [FQDN warning](#3-ah00558-fqdn-warning) | Add `ServerName` to global config |
| HTTP redirect loop / no cert | [Redirect before cert](#4-http-redirect-before-certificate-exists) | Generate self-signed cert **before** writing vhost |
| `pm2 startup` fails for deployer | [PM2 sudo](#5-pm2-startup-sudo-required) | Run from admin account, not deployer |
| No `backend/` directory | [Static export](#6-no-backend-directory--static-export) | Repo root has no `backend/`; run npm from root |
| `next start` fails | [Next start vs serve](#7-next-start-fails-with-static-export) | Use `serve`, not `next start` |
| Let's Encrypt refuses bare IP | [Certbot IP](#8-lets-encrypt-refuses-bare-ip) | Use self-signed cert instead |
| Server version exposed | [ServerTokens](#9-server-version-exposed-in-headers) | Set in `/etc/apache2/conf-available/security.conf` |

## 1. Invalid command 'SSLEngine'

**Symptom:**
```
AH00526: Syntax error on line X of /etc/apache2/sites-available/app.conf
Invalid command 'SSLEngine', perhaps misspelled or defined by a module
not included in the server configuration
```
`sudo apache2ctl configtest` fails; Apache won't start.

**Root cause:** `mod_ssl` is installed but **disabled** on Ubuntu by default. The vhost uses `SSLEngine on` which requires the `ssl` module.

**Fix:**
```bash
sudo a2enmod ssl
sudo apache2ctl configtest
sudo systemctl restart apache2
```

**Prevention:** [SERVER_SETUP.md](../SERVER_SETUP.md) §7 now includes `sudo a2enmod ssl` in the module list.

## 2. 503 Service Unavailable (Backend Down)

**Symptom:** Apache is running, `curl http://<vm-ip>` returns 301 (redirect), `curl -kI https://<vm-ip>` returns:
```
HTTP/1.1 503 Service Unavailable
```

**Root cause:** Apache is working but the Next.js app is not listening on port 3000. `ProxyPass / http://127.0.0.1:3000/` has nothing to connect to.

**Diagnose:**
```bash
# Check if anything is on port 3000
ss -tlnp | grep 3000

# Check PM2 status (as deployer)
sudo -H -u agmyintmyat pm2 status
sudo -H -u agmyintmyat pm2 logs nextjs --lines 30

# Check Apache error log
sudo tail -5 /var/log/apache2/app-error.log
```

**Common causes:**

| PM2 status | Meaning | Fix |
| --- | --- | --- |
| `[empty]` | Process never started | `pm2 start serve --name nextjs -- /var/www/app/out` |
| `errored` | App crashed on start | `pm2 logs nextjs` — check for missing `.env`, build failure, wrong directory |
| `stopped` | Manually stopped | `pm2 restart nextjs` |
| `online` but no response | Port conflict or wrong host | `ss -tlnp | grep 3000` — check binding |

**Fix sequence:**
```bash
# 1. Ensure build completed
cd /var/www/app
ls out/index.html          # must exist (static export)

# 2. Start/restart PM2
sudo -H -u agmyintmyat bash -c "pm2 restart nextjs || pm2 start serve --name 'nextjs' -- /var/www/app/out"

# 3. Verify locally before touching Apache
curl -I http://127.0.0.1:3000    # must return HTTP 200

# 4. Confirm Apache can reach it
curl -kI https://127.0.0.1        # must return HTTP 200 (not 503)
```

**Prevention:** The server-setup.sh script verifies port 3000 responds before completing — a 503 at runtime means the script's PM2 step failed.

## 3. AH00558 FQDN Warning

**Symptom:**
```
AH00558: apache2: Could not reliably determine the server's fully
qualified domain name, using 127.0.1.1
```
Appears on every `apache2ctl`, `systemctl restart apache2`, etc.

**Root cause:** Apache has no `ServerName` set at the global config level.

**Fix:**
```bash
echo "ServerName <vm-ip>" | sudo tee /etc/apache2/conf-available/servername.conf
sudo a2enconf servername
sudo systemctl restart apache2
```

Replace `<vm-ip>` with your actual VM IP (e.g., `192.168.10.3`).

**Prevention:** [SERVER_SETUP.md](../SERVER_SETUP.md) §7 includes this step ("Suppress the FQDN Warning").

## 4. HTTP Redirect Before Certificate Exists

**Symptom:** After writing the vhost (§7 step 3) and enabling the site, `sudo systemctl restart apache2` fails with:
```
[SSL: ERR_NO_SUCH_FILE] certificate file not found
```

**Root cause:** The :443 vhost references SSL certificate files (`/etc/ssl/certs/selfsigned.crt`) that don't exist yet. The HTTP vhost also forces a redirect to HTTPS (`RewriteRule ^ https://...`) — creating a redirect to a broken endpoint.

**Fix:** Generate the self-signed certificate **before** creating the vhost:

```bash
# 1. Generate cert (BEFORE writing app.conf)
sudo openssl req -x509 -nodes -days 365 \
    -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -keyout /etc/ssl/private/selfsigned.key \
    -out /etc/ssl/certs/selfsigned.crt \
    -subj "/CN=<vm-ip>"

# 2. NOW write the vhost (cert files exist, Apache will load)
sudo nano /etc/apache2/sites-available/app.conf

# 3. Test and restart
sudo apache2ctl configtest
sudo systemctl restart apache2
```

**Prevention:** [SERVER_SETUP.md](../SERVER_SETUP.md) §7 generates the cert in the "Generate a Self-Signed Certificate" subsection, which comes **before** the "Create Virtual Host Configuration" subsection.

## 5. PM2 Startup — Sudo Required

**Symptom:** Running `pm2 startup` prints a `sudo env PATH=...` command, but executing it as the deployer fails:
```
sudo: agmyintmyat is not in the sudoers file
```

**Root cause:** `pm2 startup` installs a systemd unit in `/etc/systemd/system/`, which requires root. The deployer account has no sudo by design (least privilege).

**Fix:** Run the printed command from a **sysadmin** account:

```bash
# Step 1: Save the process list (as deployer)
pm2 save

# Step 2: Get the startup command (as deployer)
pm2 startup
# Copy the printed sudo command (don't run it)

# Step 3: Exit to admin
exit

# Step 4: Run it as admin
sudo env PATH=$PATH:/usr/bin /usr/lib/node_modules/pm2/bin/pm2 startup \
    systemd -u agmyintmyat --hp /home/agmyintmyat

# Step 5: Verify
systemctl status pm2-agmyintmyat
```

The systemd unit runs PM2 **as** `agmyintmyat` on boot — the deployer never needs sudo.

**Prevention:** [SERVER_SETUP.md](../SERVER_SETUP.md) §8 steps 5-6 now show this explicitly. The `server-setup.sh` script handles it automatically.

## 6. No `backend/` Directory — Static Export

**Symptom:**
```bash
cd /var/www/app/backend
bash: cd: backend: No such file or directory
```

**Root cause:** The app repository ([lfs-101-notes](https://github.com/ammdevl/lfs-101-notes)) has its Next.js project at the **repo root**, not in a `backend/` subdirectory.

**Fix:** Run npm commands from the repo root:

```bash
cd /var/www/app    # NOT /var/www/app/backend
npm install
npm run build
```

The app uses `output: "export"` in `next.config.js` — the build produces static files in `./out/`, not a server-rendered application.

**Prevention:** [SERVER_SETUP.md](../SERVER_SETUP.md) §8 steps 3-4 specify "from the repo root `/var/www/app` — there is no `backend/` subdirectory."

## 7. `next start` Fails with Static Export

**Symptom:**
```bash
next start
Error: "next start" does not work with "output: "export"" configuration.
Use "serve" or "npx serve out" instead.
```

**Root cause:** The app's `next.config.js` sets `output: "export"`. The `next start` command is for server-rendered apps only.

**Fix:** Install `serve` globally and run it directly with PM2:

```bash
npm install -g serve
pm2 start serve --name "nextjs" -- /var/www/app/out
# Serves the static build from ./out on port 3000
```

Do not try to use `next start` directly.

## 8. Let's Encrypt Refuses Bare IP

**Symptom:**
```bash
sudo certbot --apache -d 192.168.10.3
Certbot failed to authenticate some domains
```

**Root cause:** Let's Encrypt cannot issue certificates for bare IP addresses — only for registered domain names. This is a policy restriction, not a technical error.

**Fix for IP-only access:** Use the self-signed certificate already generated in §7:
```bash
sudo openssl req -x509 -nodes -days 365 \
    -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -keyout /etc/ssl/private/selfsigned.key \
    -out /etc/ssl/certs/selfsigned.crt \
    -subj "/CN=<vm-ip>"
```

Browsers will show a trust warning — this is expected for self-signed certificates. Click through or add the cert to the browser's trust store.

**Fix if you have a domain:** Use Certbot with the domain name instead:
```bash
sudo certbot --apache -d your-domain.com
```
Then update `ServerName` in `app.conf` to the domain.

## 9. Server Version Exposed in Headers

**Symptom:** `curl -sI https://<vm-ip>` reveals:
```
Server: Apache/2.4.58 (Ubuntu)
```

**Root cause:** `ServerTokens` and `ServerSignature` are set to their defaults (`OS` and `On`).

**Fix:** These are **server-context directives** — they belong in global config, not inside a `<VirtualHost>` block:

```bash
sudo sed -i 's/^ServerTokens .*/ServerTokens Prod/; s/^ServerSignature .*/ServerSignature Off/' \
    /etc/apache2/conf-available/security.conf
sudo systemctl restart apache2
```

After the fix, response headers should show only:
```
Server: Apache
```

**Prevention:** [SERVER_SETUP.md](../SERVER_SETUP.md) §7 "Hide Server Version (Global Config)" covers this. The `server-setup.sh` script sets both automatically.

## Appendix: Verification Checklist

Run after any change to confirm the full stack is operational:

```bash
# Backend alive?
curl -I http://127.0.0.1:3000                    # expect 200

# HTTP redirect?
curl -I http://<vm-ip>                            # expect 301 → https://

# HTTPS working?
curl -kI https://<vm-ip>                          # expect 200 (accept self-signed)

# Version hidden?
curl -skI https://<vm-ip> | grep -i "server:"    # expect "Server: Apache"

# Services running?
sudo systemctl is-active apache2                  # expect "active"
sudo systemctl is-active fail2ban                 # expect "active"
sudo -H -u agmyintmyat pm2 status                 # expect "nextjs" online

# Firewall?
sudo ufw status                                   # expect Status: active, 22/80/443 allowed
```
