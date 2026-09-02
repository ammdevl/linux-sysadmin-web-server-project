# System Architecture

Reference document describing how all components fit together. For step-by-step setup, see [SERVER_SETUP.md](../SERVER_SETUP.md).

## Component Stack

```
┌─────────────────────────────────────────────────┐
│                  VMware VM                      │
│            Ubuntu 24.04 LTS                     │
│                                                 │
│  ┌──────────┐  ┌──────────────────────────────┐ │
│  │ Apache2  │  │ Static files (disk)          │ │
│  │ :80/:443 │──│ /var/www/app/out/            | │
│  │ TLS +    │  │/_next/static/ served directly│ │
│  │ proxy +  │  └──────────────────────────────┘ │
│  │ static   │  ┌──────┐  ┌──────┐  ┌────────┐   │
│  │ serving  │──│ PM2  │──│ Node │──│ serve  │   │
│  └──────────┘  │      │  │      │  │ :3000  │   │
│                │      │  │      │  │ dynamic│   │
│  ┌──────┐      └──────┘  └──────┘  └────────┘   │
│  │ UFW  │  ┌────────┐  ┌───────────┐            │
│  │      │  │fail2ban│  │ Tailscale │            │
│  └──────┘  └────────┘  └───────────┘            │
└─────────────────────────────────────────────────┘
```

| Layer | Component | Purpose |
| --- | --- | --- |
| Web server | Apache2 | TLS termination, HTTP→HTTPS redirect, static file serving, reverse proxy |
| Static files | Apache2 `Alias` | Serves `_next/static/` directly from disk (bypasses Node.js) |
| Process manager | PM2 | Auto-restart, boot persistence, log management |
| Application | Node.js + `serve` | Serves dynamic routes on port 3000 (proxied by Apache) |
| Build tool | Next.js (`npm run build`) | Static HTML/CSS/JS output to `./out/` (`output: "export"`) |
| Health check | Apache `Alias` | `/health` endpoint returns status without hitting Node.js |
| Firewall | UFW | Allows only 22/tcp, 80/tcp, 443/tcp |
| Intrusion prevention | fail2ban | Auto-bans IPs after 5 failed SSH/Apache auth attempts (1 hour) |
| Backup | cron + tar | Daily backup of configs, SSL certs, app source (30-day retention) |
| Admin tunnel | Tailscale | WireGuard-based VPN for SSH access from host only |

## Traffic Flow

### Production (browser → VM)

```
Client (browser)
    │
    │  https://<vm-ip>:443
    ▼
Apache2 (:443)  ── TLS termination (self-signed ECDSA cert)
    │
    ├── /_next/static/*  ── Alias ──▶ /var/www/app/out/_next/static/ (disk)
    │
    ├── /health  ── Alias ──▶ /var/www/app/out/health.json (disk)
    │
    └── /*  ── ProxyPass ──▶ PM2 → serve (:3000)
```

1. Browser sends HTTPS request to `<vm-ip>:443`
2. Apache2 terminates TLS using the self-signed ECDSA certificate
3. For `_next/static/` requests: Apache serves files directly from disk (fast, no Node.js)
4. For `/health` requests: Apache serves the health check JSON from disk
5. All other requests: Apache proxies to `127.0.0.1:3000` where `serve` (PM2) responds
5. Response flows back through Apache to the client

HTTP requests on port 80 are automatically redirected to HTTPS (301).

### Administration (host → VM)

```
Host machine
    │
    │  Tailscale (WireGuard tunnel)
    ▼
VM Tailscale interface
    │
    │  ssh <user>@<tailscale-ip>
    ▼
SSH (22)  ── key-only auth, password disabled
    │
    │  su - agmyintmyat (deployer)
    ▼
git pull → npm install → npm run build → pm2 restart
```

1. Admin connects via Tailscale VPN (not over public internet)
2. SSH with key-based authentication (no passwords)
3. Switch to deployer user (`agmyintmyat`, `dev` group)
4. Pull latest code, rebuild, restart PM2 process

**Tailscale is NOT used for production traffic** — clients access the VM directly via its IP address.

## Network Topology

```
┌──────────────┐      ┌───────────────────────┐      ┌──────────────┐
│ Client       │      │   VMware NAT Network  │      │ Host Machine │
│ (browser)    │      │   192.168.10.0/24     │      │ (admin)      │
│              │      │                       │      │              │
│  ──────────────────────────────────────▶    │      │  Tailscale   │
│  https://192.168.10.3:443                   │      │  ─ WireGuard │
└──────────────┘      │                       └──────────────┘
                      │  Gateway: 192.168.10.2
                      │  VM IP:   192.168.10.3 (static, Netplan)
                      │  DNS:     8.8.8.8, 8.8.4.4
                      └───────────────────────┘
```

- **VM static IP:** configured via Netplan (`/etc/netplan/90-static.yaml`)
- **VMware NAT:** VM is reachable from the host machine on the VMnet8 network
- **External access:** clients on the same LAN or routed network can reach `<vm-ip>` directly
- **Tailscale:** independent encrypted tunnel for administration only; does not affect production routing

## Security Model

### Users & Groups

```
Group: sysadmin (sudo ALL)
├── mgkhant
├── agmyintmyatag
├── gonyaungwin
├── agkhantkyaw
└── santhiritun

Group: dev (deployment only)
├── kghtutthaw
├── hanlinhtun
├── shoonlaeaung
└── agmyintmyat ← primary deployer
```

- `sysadmin` members have full sudo access for server management
- `dev` members have no sudo; they deploy by running PM2 as themselves
- Apache runs as `www-data` (system default) — not in any custom group
- No passwords for accounts until set via `passwd` (lab convention: `12345678`)

### File Permissions

| Path | Owner | Group | Dir perms | File perms | Purpose |
| --- | --- | --- | --- | --- | --- |
| `/var/www/app/` | `agmyintmyat` | `dev` | 775 | 664 | Web app root |
| `/etc/ssl/private/selfsigned.key` | `root` | `root` | — | 600 | TLS private key |
| `/etc/ssl/certs/selfsigned.crt` | `root` | `root` | — | 644 | TLS certificate |
| `/etc/ssh/sshd_config.d/99-hardening.conf` | `root` | `root` | — | 644 | SSH config overrides |
| `/etc/fail2ban/jail.local` | `root` | `root` | — | 644 | Fail2ban config |
| `/etc/apache2/sites-available/app.conf` | `root` | `root` | — | 644 | Apache vhost |

**Key principle:** Apache (`www-data`) can read the web files but cannot write to them — defense against a compromised web server.

### SSH Hardening

| Setting | Value | File |
| --- | --- | --- |
| `PasswordAuthentication` | `no` | `/etc/ssh/sshd_config.d/99-hardening.conf` |
| `PermitRootLogin` | `no` | `/etc/ssh/sshd_config.d/99-hardening.conf` |
| `AllowGroups` | `sysadmin dev` | `/etc/ssh/sshd_config.d/99-hardening.conf` |
| Authentication | Key-based only | SSH key pair on host |

### Firewall Rules (UFW)

| Port | Protocol | Action | Purpose |
| --- | --- | --- | --- |
| 22 | TCP | ALLOW | SSH access |
| 80 | TCP | ALLOW | HTTP (redirects to HTTPS) |
| 443 | TCP | ALLOW | HTTPS |
| All others | — | DENY | Blocked by default |

### Intrusion Prevention (fail2ban)

| Jail | Max retries | Ban time | Log watched |
| --- | --- | --- | --- |
| `sshd` | 5 | 1 hour | `/var/log/auth.log` |
| `apache-auth` | 5 | 1 hour | `/var/log/apache2/app-error.log` |

## File & Directory Layout

### On the VM

```
/var/www/app/                     # app root (owned by agmyintmyat:dev)
├── out/                          # static export output (npm run build)
│   ├── index.html                # entry point
│   └── ...                       # HTML, CSS, JS, assets
├── pages/                        # Next.js source pages
├── components/                   # React components
├── styles/                       # CSS/SCSS
├── public/                       # static assets
├── next.config.js                # output: "export" + trailingSlash
├── package.json                  # scripts: start → serve out
├── package-lock.json
└── .pm2/                         # PM2 state (managed by PM2)

/etc/apache2/
├── sites-available/
│   └── app.conf                  # VirtualHost *:80 + *:443
├── sites-enabled/
│   └── app.conf                  # symlink
├── conf-available/
│   ├── security.conf             # ServerTokens Prod, ServerSignature Off
│   └── servername.conf           # ServerName <vm-ip> (suppresses AH00558)
└── mods-enabled/
    ├── proxy.load                # mod_proxy
    ├── proxy_http.load           # mod_proxy_http
    ├── rewrite.load              # mod_rewrite
    ├── headers.load              # mod_headers
    └── ssl.load                  # mod_ssl

/etc/ssl/
├── certs/selfsigned.crt          # self-signed ECDSA TLS certificate
└── private/selfsigned.key        # TLS private key (600)

/etc/ssh/sshd_config.d/
└── 99-hardening.conf             # PasswordAuthentication no, PermitRootLogin no, AllowGroups

/etc/fail2ban/
└── jail.local                    # SSH + Apache auth jails

/etc/logrotate.d/
└── apache2-app                   # Log rotation for app-access.log, app-error.log

/etc/cron.d/
└── server-backup                 # Daily backup at 2:37 AM

/usr/local/bin/
└── backup-server.sh              # Backup script (configs, certs, app source)

/var/backups/server/              # Backup storage (30-day retention)

/etc/systemd/system/
└── pm2-agmyintmyat.service       # PM2 boot service (runs as deployer)
```

### PM2 Process State

```
/home/agmyintmyat/.pm2/
├── dump.pm2                      # saved process list (pm2 save)
├── pm2.pid                       # daemon PID
└── logs/                         # application logs
    ├── nextjs-out.log            # stdout
    └── nextjs-error.log          # stderr
```

## Boot Sequence

On VM startup, the following services start automatically:

```
1. systemd
   ├── sshd (OpenSSH server)
   ├── apache2 (web server + reverse proxy)
   ├── pm2-agmyintmyat.service (PM2 daemon, runs as agmyintmyat)
   │   └── restores saved process list → serve /var/www/app/out → port 3000
   ├── ufw (firewall)
   ├── fail2ban (intrusion prevention)
   └── tailscale (admin tunnel, if configured)

2. Apache is ready → client can reach :80 and :443
3. PM2 restores processes → port 3000 listening
4. Full chain operational: HTTPS :443 → ProxyPass → :3000
```

### Port Map

| Port | Service | Binding | Access |
| --- | --- | --- | --- |
| 22 | SSH (sshd) | 0.0.0.0 | Key-only auth, AllowGroups=sysadmin,dev |
| 80 | Apache2 | 0.0.0.0 | HTTP → 301 redirect to HTTPS |
| 443 | Apache2 | 0.0.0.0 | TLS (ECDSA) + static files + reverse proxy |
| 3000 | PM2 / `serve` | 127.0.0.1 | Localhost only (Apache proxies dynamic routes) |

Port 3000 is only accessible from localhost — external clients reach it exclusively through Apache on :443. Static assets (`_next/static/`) and the health check endpoint are served directly by Apache from disk.
