# ADR-004: Next.js Static Export over Server-Side Rendering

**Status:** Accepted  
**Date:** 2026-08-21

## Context

The Next.js application ([lfs-101-notes](https://github.com/ammdevl/lfs-101-notes)) is a self-paced course website with static content (markdown notes, no user accounts, no API routes). Next.js supports both SSR (server-side rendering) and static export.

## Decision

Use **static export** (`output: "export"` in `next.config.js`) with Apache serving static files directly.

## Rationale

- **No server-side logic:** The site is pure content — no authentication, no databases, no API routes. SSR provides no benefit.
- **Performance:** Static files served directly from Apache's document root are faster than proxying through Node.js.
- **Simplicity:** A static export eliminates the need for a running Node.js process in production (though PM2 is kept for the lab exercise).
- **Security:** No server-side code means no server-side vulnerabilities. The attack surface is limited to Apache serving files.
- **Resource efficiency:** Static files use minimal CPU and memory compared to SSR.

## Consequences

- Content updates require a rebuild (`npm run build`) and deploy — no dynamic content at request time.
- Client-side routing uses `FallbackResource /index.html` in Apache, which handles SPA navigation correctly.
- The `out/` directory contains all pre-rendered HTML, CSS, and JavaScript files.
