# ADR-002: PM2 over systemd for Node.js Process Management

**Status:** Accepted  
**Date:** 2026-08-21

## Context

The Next.js application needs a process manager to handle auto-restarts, log management, and boot persistence. Options include PM2, systemd user units, or running directly.

## Decision

Use **PM2** as the process manager for the Node.js application.

## Rationale

- **Simplicity:** `pm2 start serve --name nextjs -- /var/www/app/out` is a single command. Systemd unit files require writing, enabling, and debugging service definitions.
- **Log management:** PM2 provides `pm2 logs`, `pm2 monit`, and built-in log rotation out of the box.
- **Ecosystem:** PM2 is the standard process manager for Node.js applications, with extensive documentation and community support.
- **Boot persistence:** `pm2 startup` generates a systemd unit automatically — we get systemd integration without writing unit files manually.

## Consequences

- PM2 adds a Node.js dependency (installed via npm) — acceptable since Node.js is already required for the app.
- PM2 runs as a user-level daemon, not a system service — the `pm2 startup` command bridges this gap by creating a systemd unit.
