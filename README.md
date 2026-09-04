## Linux SysAdmin Web Server Project

[![MIT License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![GitHub](https://img.shields.io/badge/GitHub-ammdevl-181717?logo=github)](https://github.com/ammdevl)
[![GitHub issues](https://img.shields.io/github/issues/ammdevl/linux-sysadmin-web-server-project.svg)](https://github.com/ammdevl/linux-sysadmin-web-server-project/issues)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](http://makeapullrequest.com)

A secure Apache2 web server hosting a self-paced course website ([lfs-101-notes](https://github.com/ammdevl/lfs-101-notes), a Next.js application) on a VMware virtual machine — built as an academic Linux system administration project.

## Table of Contents

- [Linux SysAdmin Web Server Project](#linux-sysadmin-web-server-project)
- [Table of Contents](#table-of-contents)
- [About](#about)
- [Repository Structure](#repository-structure)
- [Tech Stack \& Tools](#tech-stack--tools)
- [Architecture](#architecture)
- [Getting Started](#getting-started)
  - [Prerequisites](#prerequisites)
  - [Installation](#installation)
- [Documentation](#documentation)
- [Group Members](#group-members)
- [Contributing](#contributing)
- [License](#license)

## About
The project applies lecture concepts in a real-world scenario:

- **User & group management** — dedicated `sysadmin` (sudo) and `dev` (deployment) accounts instead of a shared root workflow
- **File permissions** — least-privilege ownership of `/var/www/app`, web server cannot modify its own document root
- **Service hardening** — key-only SSH, UFW firewall, fail2ban, hidden server version
- **TLS everywhere** — HTTP→HTTPS redirect with a self-signed certificate for IP-only access

## Repository Structure

```bash
.
├── LICENSE
├── SERVER_SETUP.md          # Full web server deployment guide
├── DEPLOY.md                # Deployment & operations runbook
├── README.md                # Project overview and documentation
├── spec.md                  # Approved project specification
├── src/                     # images for docs/
├── slide/                   # Presentation slides
├── .gitignore
├── docs/
│   ├── architecture.md      # System architecture & design reference
│   ├── troubleshooting.md   # Known issues & fixes from live deployment
│   └── adr/                 # Architecture Decision Records
│       ├── 001-apache-over-nginx.md
│       ├── 002-pm2-over-systemd.md
│       ├── 003-self-signed-over-lets-encrypt.md
│       └── 004-static-export-over-ssr.md
├── project-proposals/       # Member proposals & submission guide
│   ├── HOW-TO-SUBMIT.md
│   ├── _TEMPLATE.md
│   └── ...
└── script/
    └── server-setup.sh      # Automated server provisioning
```

## Tech Stack & Tools

| Category | Tool |
| --- | --- |
| OS | Ubuntu 24.04 LTS (VMware Workstation VM, static IP via Netplan) |
| Web server | Apache2 (reverse proxy, TLS termination) |
| Application | [lfs-101-notes](https://github.com/ammdevl/lfs-101-notes) — Next.js static export served via PM2 (`npx serve out`) on port 3000 |
| Process manager | PM2 (auto-restart, boot persistence) |
| SSL/TLS | Self-signed certificate (IP access); Certbot optional for domains |
| Security | UFW, fail2ban, key-only SSH, Tailscale (admin tunnel) |

## Architecture

```
Production Access (Browser):
    Client → HTTPS (<vm-ip>:443) → Apache2 (TLS termination)
        → Reverse Proxy (ProxyPass) → Next.js / serve (port 3000)

Admin Access (Host → VM via Tailscale):
    Host Machine ←→ Tailscale (WireGuard) ←→ VMware VM
        SSH (22) → deployer user → git pull → build → restart
```

Production traffic goes directly over the network via the VM's IP address; Tailscale is used only for administration and deployment.

## Getting Started

Follow these instructions to get a local copy of the project up and running for setup, testing, or development.

### Prerequisites

Before you begin, ensure you have the following installed and configured:

* **Operating System:** Linux Ubuntu 22.04 LTS or later
* **Shell:** `bash` (version 4.0 or higher)
* **Access Privileges:** `sudo` / root privileges on the target server
* **Version Control:** `git` installed locally
* **SSH Keys:** SSH key pair generated and configured for remote deployment/access
* **Node.js:** v20.9 or later (server only, installed during [SERVER_SETUP.md](SERVER_SETUP.md) §8)

### Installation

Follow the step-by-step guide in [SERVER_SETUP.md](SERVER_SETUP.md) — it covers network configuration, SSH hardening, user/group creation, Apache2, PM2, SSL, firewall, and fail2ban. An automated script (`script/server-setup.sh`) is also available to reproduce the full setup.

## Documentation

| Document | Purpose |
| --- | --- |
| [spec.md](spec.md) | Approved specification, architecture, security plan, definition of done |
| [SERVER_SETUP.md](SERVER_SETUP.md) | Complete server deployment walkthrough (step-by-step) |
| [DEPLOY.md](DEPLOY.md) | Deployment workflow, operations runbook, key revocation, backup & recovery |
| [docs/architecture.md](docs/architecture.md) | System architecture, traffic flow, security model, file layout, boot sequence |
| [docs/troubleshooting.md](docs/troubleshooting.md) | Known issues & fixes from real VM deployment |
| [docs/adr/](docs/adr/) | Architecture Decision Records (why Apache, PM2, self-signed, static export) |
| [project-proposals/](project-proposals/) | Original member proposals and submission process |

## Group Members

| No. | Name | Role |
| --- | --- | --- |
| 1 | Maung Khant | Project Leader |
| 2 | Aung Myint Myat Aung | sysadmin |
| 3 | Gon Yaung Win | sysadmin |
| 4 | Aung Khant Kyaw | sysadmin |
| 5 | San Thiri Tun | sysadmin |
| 6 | Kaung Htut Thaw | co-sysadmin |
| 7 | Han Linn Htun | co-sysadmin |
| 8 | Shoon Lae Aung | co-sysadmin |
| 9 | Aung Myint Myat | PM & Documentation |

## Contributing

While this is primarily an academic portfolio project, suggestions for improvements, bug reports, and code reviews are welcome. Please open an issue or reach out directly.

## License

This repository is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

---

<div align="center">
  <sub>Built with ❤️ during our academic journey</sub>
</div>
