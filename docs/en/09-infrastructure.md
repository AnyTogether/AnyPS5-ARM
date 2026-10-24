# 9. Infrastructure

## 9.1 Where it runs

Start on **one server** (the one we already have, if it fits; otherwise a VPS):

| Resource | Start | Why |
|---|---|---|
| CPU | 4 vCPU | API, gateway, worker, web, PostgreSQL, LiveKit together |
| RAM | 8 GB (16 GB comfortable) | PostgreSQL buffers, Next.js, LiveKit |
| Disk | 160 GB NVMe | database and logs; files live in R2 |
| Network | 1 Gbit/s, generous traffic | share play is bandwidth: 1 Gbit/s ≈ 100 viewers of 720p60 |
| OS | Ubuntu 24.04 LTS or Debian 12 | |
| Location | close to most players (Istanbul or Frankfurt) | voice and share play delay |

When share play grows, LiveKit moves first to its own machine with more bandwidth; everything
else stays.

## 9.2 Docker Compose

```yaml
services:
  caddy:      # TLS at the origin (Cloudflare origin cert), reverse proxy to web/api/rt
  web:        # Next.js, port 3000
  api:        # Hono, port 8080, 2 replicas
  realtime:   # gateway, port 8081
  worker:     # pg-boss jobs
  postgres:   # 17, volume on NVMe, tuned shared_buffers=2GB
  valkey:     # 8, no persistence needed (appendonly no)
  livekit:    # host networking for UDP 50000-60000, 7880 (WSS behind Caddy), 7881 TCP
  coturn:     # optional if LiveKit's TURN is used; 3478 UDP/TCP, 5349 TLS
  backup:     # nightly pg_dump | age | upload to R2
  uptime:     # Uptime Kuma, checks every service
```

Firewall (ufw/nftables): 443 only from Cloudflare's ranges (web, api, rt, cdn); 7880 WSS and
UDP 50000-60000, TCP 7881, 3478, 5349 open to all for LiveKit/TURN; SSH by key only from known
addresses.

## 9.3 Cloudflare

- DNS: `anytogether`, `api.anytogether`, `rt.anytogether`, `cdn.anytogether` proxied (orange);
  `live.anytogether`, `turn.anytogether` DNS only (grey).
- SSL mode Full (strict) with an origin certificate; Authenticated Origin Pulls on.
- WAF managed rules; rate limiting at the edge for `/v1/auth/*`; bot fight mode on the web, not on
  the API (the launcher is not a browser).
- Cache: public profile pages cached for 60 s with stale-while-revalidate; `cdn` cached long.
- R2 buckets: `anytogether-files` (private), `anytogether-cdn` (public through `cdn.`),
  `anytogether-backups` (private, lifecycle 30 days).
- WebSockets on `rt.` (supported on proxied hostnames).

## 9.4 Deploy

- **CI (GitHub Actions)** on every push: typecheck, lint, unit tests, API tests against a real
  PostgreSQL and Valkey in services, migration check (applies on a copy of the previous schema),
  build Docker images, push to GitHub Container Registry.
- **CD**: on a tag `vX.Y.Z`, an action connects over SSH and runs
  `docker compose pull && docker compose up -d` with zero-downtime for api/web (two replicas,
  Caddy health checks); migrations run first as a one-off job and must be backward compatible with
  the running code (expand, deploy, contract).
- **Staging**: the same compose on a smaller machine or a second project on the same one, at
  `staging.anytogether.kodla.agency`, used by test builds of the launcher and phone app.

## 9.5 Backups and recovery

- PostgreSQL: nightly `pg_dump -Fc`, encrypted with `age`, uploaded to R2 (kept 30 days); WAL
  archiving with `wal-g` to R2 for point-in-time recovery (to the minute) once there are real
  users.
- A restore is tested monthly on staging (a script that restores the latest dump and runs the API
  tests against it).
- R2 has object versioning on the files bucket.
- Recovery goals: RPO 5 minutes (with WAL), RTO 1 hour.

## 9.6 Monitoring

- **Uptime Kuma**: HTTP checks of web, api, rt (WebSocket), LiveKit, TURN, every minute; alerts by
  mail and Telegram/Discord.
- **Prometheus + Grafana**: request rates and latencies (API), sockets (gateway), job queue depth
  (worker), PostgreSQL (postgres_exporter), LiveKit (its own `/metrics`: rooms, participants,
  packet loss, bandwidth), host metrics (node_exporter).
- **Logs**: JSON logs from every service to Loki (or simply `docker logs` with rotation at the
  start); no message texts, no tokens in logs.
- **Errors**: Sentry SDKs in API, web, launcher (opt-in crash reports), phone app.
- **Clients report** voice and share play quality (round trip, loss, glass-to-glass samples) to a
  metrics endpoint, aggregated, no content.

## 9.7 Costs (rough, per month)

| Item | Start |
|---|---|
| Server (4 vCPU, 16 GB, 1 Gbit/s, Frankfurt/Istanbul) | €20-60 (or €0 on our existing server) |
| Cloudflare (free plan; Pro €20 if WAF rules need it) | €0-20 |
| R2 (10 GB stored, egress free) | < €1 |
| Mail (Resend free tier or own SMTP) | €0 |
| Apple Developer (APNs, signing, maybe App Store) | ~€8 (€99/year) |
| Domain | already kodla.agency |
| **Total** | **€0-90** |

Bandwidth is the cost that grows with share play; LiveKit on a bandwidth-friendly host (Hetzner
includes 20 TB) keeps it flat.
