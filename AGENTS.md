# AGENTS.md — linux-terminal-tools

Server management scripts and tools for mail.eksneks.com (IP: 81.17.98.31).

---

## Server overview

| Component | Detail |
|-----------|--------|
| Host | mail.eksneks.com |
| IP | 81.17.98.31 |
| Web server | nginx |
| Cache | Varnish (port 6081) |
| PHP | PHP-FPM 8.3 (socket: /var/run/php/php8.3-fpm.sock) |
| Database | MySQL (admin: root via socket, app user: missiria) |
| Mail | Postfix + Dovecot |
| SSL | Let's Encrypt / certbot |

---

## Directory layout

```
/var/www/
  MISSIRIA/
    eksit/          — IPTV WordPress sites
    apps/
      shark-app/    — Next.js
      leader-app/   — NestJS API + Next.js front
  AI/editor/        — AI editor app (Next.js)
  GEO/              — Geo/tracking (fox-track-service-nextjs)
  IT/dashboard-app/ — IT dashboard

/etc/nginx/
  sites-available/  — config files (one per domain)
  sites-enabled/    — symlinks to active configs

/etc/letsencrypt/live/<domain>/
  fullchain.pem
  privkey.pem

/home/missiria/linux-terminal-tools/batches/
  autopilot.sh      — main site launcher batch
```

---

## Nginx architecture patterns

### Standard (no Varnish)
```
:80  → PHP-FPM (or 301 → HTTPS)
:443 SSL → PHP-FPM
```

### Varnish (when ENABLE_VARNISH=y)
```
:8080         → PHP-FPM (backend, not public)
:80           → 301 HTTPS redirect
:443 SSL      → Varnish :6081 (front door)
Varnish :6081 → nginx :8080
```

---

## autopilot.sh — site launcher

**Path:** /home/missiria/linux-terminal-tools/batches/autopilot.sh
**Run as:** root

Phase 1 collects all inputs interactively, Phase 2 executes silently.

### What it does (in order)
1. **Files** — create web root or rsync from source domain
2. **Nginx** — write nginx config; falls back to HTTP-only if SSL cert missing
3. **Certbot** — `certbot --nginx --non-interactive --agree-tos -m <email>` using `EMAIL_PREFIX@DOMAIN`
4. **Database** — create MySQL DB + user, or clone from source
5. **Email** — create postfix virtual mailbox + dovecot passwdfile entry
6. **Varnish** — write Varnish nginx config (checks certs exist before writing SSL block)
7. **Audit** — DNS, nginx, SSL, HTTP, DB, email status report

### Key variables
| Variable | Default | Description |
|----------|---------|-------------|
| MODE | — | `new` or `copy` |
| DOMAIN | — | Target domain (no www.) |
| WEB_ROOT | — | Absolute path to web root |
| EMAIL_PREFIX | contact | Email user prefix; also used as certbot contact |
| PHP_VER | 8.3 | PHP-FPM version |
| ENABLE_VARNISH | n | `y` to enable Varnish architecture |
| SKIP_CERTBOT | n | `y` to skip SSL (dev/local) |
| DB_USER | missiria | MySQL app user |
| MYSQL_ADMIN_USER | root | MySQL admin user |

### Environment overrides
```bash
DB_USER=missiria DB_PASS=xxx MYSQL_ADMIN_PASS=yyy ./autopilot.sh
```

---

## Common operations

### Re-issue SSL cert (chicken-and-egg fix)
When nginx config already has SSL cert paths but cert doesn't exist:
```bash
# 1. Temporarily disable SSL server block in sites-available/<domain>
# 2. Add plain port-80 server block
nginx -t && systemctl reload nginx

# 3. Issue cert
certbot --nginx -d domain.com -d www.domain.com \
  --non-interactive --agree-tos -m contact@domain.com

# 4. Verify certbot wrote SSL to correct block (not 8080 backend)
# 5. If Varnish: restore proper 8080+443 config
nginx -t && systemctl reload nginx
```

### Add new domain
```bash
bash /home/missiria/linux-terminal-tools/batches/autopilot.sh
# → select "new" mode
```

### Clone domain
```bash
bash /home/missiria/linux-terminal-tools/batches/autopilot.sh
# → select "copy" mode, provide source domain
```

### Check cert expiry
```bash
certbot certificates
```

### Reload nginx safely
```bash
nginx -t && systemctl reload nginx
```

---

## Known gotchas

- **Certbot injects SSL into first matching server block** — when multiple blocks exist for same domain, it may inject into wrong one (e.g. the 8080 backend block). Always verify after certbot runs.
- **Varnish + SKIP_CERTBOT** — if SSL skipped, exec_varnish writes HTTP-only config. Run certbot manually and then re-run exec_varnish or manually write the SSL 443 block.
- **wp-config.php proxy headers** — Varnish setup injects `HTTP_X_FORWARDED_PROTO` and `HTTP_X_FORWARDED_HOST` handling into wp-config.php automatically.
- **MySQL admin auth** — root connects via socket by default (no password). Set MYSQL_ADMIN_PASS env if socket auth not available.
- **PHP-FPM socket** — autopilot auto-detects first available socket if php8.3-fpm.sock missing.
