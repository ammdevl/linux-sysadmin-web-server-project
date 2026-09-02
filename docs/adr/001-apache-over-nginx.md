# ADR-001: Apache2 over Nginx

**Status:** Accepted  
**Date:** 2026-08-21

## Context

The web server needs a reverse proxy for TLS termination and request forwarding. Both Apache2 and Nginx are viable options on Ubuntu 24.04 LTS.

## Decision

Use **Apache2** as the web server and reverse proxy.

## Rationale

- **Course alignment:** Apache2 is covered in the CST-311 Linux Fundamentals curriculum; Nginx is not.
- **Module ecosystem:** `mod_proxy`, `mod_ssl`, `mod_rewrite`, and `mod_headers` provide all required functionality without third-party modules.
- **Configuration style:** Apache's virtual host syntax is more readable for students learning web server configuration for the first time.
- **Ubuntu default:** Apache2 is the default web server on Ubuntu, with first-party package support and extensive documentation.

## Consequences

- Apache uses more memory per connection than Nginx — acceptable for a single-VM lab with low traffic.
- `.htaccess` support is available but not used (all config is in vhost blocks).
