# ADR-003: Self-Signed Certificate over Let's Encrypt

**Status:** Accepted  
**Date:** 2026-08-21

## Context

The server needs TLS encryption. Let's Encrypt provides free, trusted certificates but requires a publicly resolvable domain name. The server is accessed via a private IP address on a VMware NAT network.

## Decision

Use a **self-signed ECDSA certificate** by default. Let's Encrypt via Certbot is documented as an optional upgrade.

## Rationale

- **IP-only access:** Let's Encrypt cannot issue certificates for bare IP addresses — only for registered domain names. The VM is accessed via `192.168.10.3`, which is a private IP.
- **No domain registered:** The project scope explicitly excludes domain registration.
- **Lab environment:** A self-signed certificate is appropriate for a learning lab. Students learn the TLS configuration process without the DNS validation complexity.
- **Upgrade path:** Certbot instructions are documented in SERVER_SETUP.md §9 for anyone who adds a domain later.

## Consequences

- Browsers will show a trust warning on first visit — this is expected and documented.
- ECDSA (P-256) is used instead of RSA 2048 for stronger security and faster handshakes.
- Certificate must be manually renewed every 365 days (no auto-renewal for self-signed certs).
