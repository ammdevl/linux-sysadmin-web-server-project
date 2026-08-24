## Linux SysAdmin Web Server Project

[![MIT License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![GitHub](https://img.shields.io/badge/GitHub-ammdevl-181717?logo=github)](https://github.com/ammdevl)
[![GitHub issues](https://img.shields.io/github/issues/ammdevl/project-name.svg)](https://github.com/ammdevl/project-name/issues)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](http://makeapullrequest.com)

> **Project Status:** 🔵 **Implementation Phase** — *Proposal approved by all members (2026-08-21).*
> *Deployment follows [SERVER_SETUP.md](SERVER_SETUP.md). See [spec.md](spec.md) for the approved specification.*

## Table of Contents

- [About](#about)
- [Repository Structure](#repository-structure)
- [Tech Stack & Tools](#tech-stack--tools)
- [Architecture](#architecture)
- [Getting Started](#getting-started)
  - [Prerequisites](#prerequisites)
  - [Installation](#installation)
- [Documentation](#documentation)
- [Group Members](#group-members)
- [Contributing](#contributing)
- [License](#license)

## About

A secure Apache2 web server hosting a self-paced course website ([lfs-101-notes](https://github.com/ammdevl/lfs-101-notes), a Next.js application) on a VMware virtual machine — built as an academic Linux system administration project.

The project applies lecture concepts in a real-world scenario:

- **User & group management** — dedicated `sysadmin` (sudo) and `dev` (deployment) accounts instead of a shared root workflow
- **File permissions** — least-privilege ownership of `/var/www/app`, web server cannot modify its own document root
- **Service hardening** — key-only SSH, UFW firewall, fail2ban, hidden server version
- **TLS everywhere** — HTTP→HTTPS redirect with a self-signed certificate for IP-only access

## Repository Structure

```bash
.
├── LICENSE
├── MEMBER_SETUP.md          # One-time tooling setup for group members
├── SERVER_SETUP.md          # Full web server deployment guide (Apache2 + Next.js)
├── README.md
├── spec.md                  # Approved project specification
├── project-proposals/       # Member proposals & submission guide
│   ├── HOW-TO-SUBMIT.md
│   ├── _TEMPLATE.md
│   └── ...
└── script/
    ├── member-setup.sh      # Automates MEMBER_SETUP.md
    └── server-setup.sh      # Server provisioning (in progress)
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

**Group members (workstation setup):**

```bash
git clone https://github.com/<your-github-username>/project-name.git
cd project-name/script
chmod +x member-setup.sh
./member-setup.sh
```

See [MEMBER_SETUP.md](MEMBER_SETUP.md) for details.

**Server deployment (VM):**

Follow the step-by-step guide in [SERVER_SETUP.md](SERVER_SETUP.md) — it covers network configuration, SSH hardening, user/group creation, Apache2, PM2, SSL, firewall, and fail2ban.

## Documentation

| Document | Purpose |
| --- | --- |
| [spec.md](spec.md) | Approved specification, architecture, security plan, definition of done |
| [SERVER_SETUP.md](SERVER_SETUP.md) | Complete server deployment walkthrough |
| [MEMBER_SETUP.md](MEMBER_SETUP.md) | Developer workstation tooling & Git configuration |
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
