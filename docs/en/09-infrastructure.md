# 9. Infrastructure

## 9.1 Where it runs

On **our existing server**, as one more Coolify project beside the others:

| | Today (read by the server-control session, 2026-10-24) |
|---|---|
| Machine | Hetzner Cloud, Falkenstein (fsn1, eu-central), 16 vCPU AMD EPYC Genoa, 30 GiB RAM, 601 GB disk (281 GB free) |
| OS | Ubuntu 22.04 LTS |
| Network | public IPv4 only (142.132.181.43), 20 TB/month included, ~1 TB/month used |
| Runs | Docker, **Coolify v4**, Traefik as reverse proxy (80/443, HTTP/3), ~100 containers, 30+ sites; per-app PostgreSQL and Redis resources |
| DNS | `kodla.agency` on Cloudflare; `anytogether.kodla.agency` → this server, proxied, served today by a "coming soon" nginx app in Coolify project "AnyTogether" |
| Deploy | Coolify: GitHub repo with deploy key and webhook, build from Dockerfile on push |

**The server is shared**, and on 19 October it ran out of memory because of parallel Next.js
builds. So AnyTogether is planned **small and capped**:

| Container | Memory limit | CPU limit | Notes |
|---|---|---|---|
| web (Next.js, standalone output) | 512 MB | 1 | built once per deploy (Coolify builds one at a time) |
| api | 384 MB | 1 | one replica at start |
| realtime | 384 MB | 1 | tens of thousands of idle sockets fit |
| worker | 256 MB | 0.5 | |
| postgres (Coolify resource, 17) | 1 GB | 2 | `shared_buffers=256MB`, `max_connections=50` |
| valkey (Coolify resource) | 128 MB | 0.5 | `maxmemory 96mb`, `allkeys-lru`, no persistence |
| coturn | 256 MB | 1 | host network for UDP |
| **Total** | **≈ 3 GB** | | well inside what is free (~9 GiB available today) |

A Next.js build takes another 2-3 GB while it runs; Coolify builds one app at a time on this
server, so that peak never overlaps another build.

Because voice, share play and pads go peer-to-peer, the server never carries media except for
the pairs that need the relay.

## 9.2 Coolify layout

Project **AnyTogether** (already exists), environments `production` and `staging`:

| Coolify resource | Source | Domain / route |
|---|---|---|
| `web` | repo `utkuhalis/AnyTogether`, `apps/web/Dockerfile` | `anytogether.kodla.agency` (path `/`) |
| `api` | same repo, `apps/api/Dockerfile` | `anytogether.kodla.agency/api` (Traefik `PathPrefix(/api)`) |
| `realtime` | same repo, `apps/realtime/Dockerfile` | `anytogether.kodla.agency/rt` (WebSocket) |
| `worker` | same repo, `apps/worker/Dockerfile` | none |
| `postgres` | Coolify PostgreSQL 17 resource | internal network only |
| `valkey` | Coolify Redis/Valkey resource | internal network only |
| `coturn` | Docker Compose resource, `network_mode: host` | `anytogether-relay.kodla.agency` (DNS only) |
| staging | the same apps from the `staging` branch | `anytogether-staging.kodla.agency` |

The "coming soon" app is replaced by `web` when the first version is ready.

## 9.3 Cloudflare

- DNS (all one level under `kodla.agency`, so the existing certificates cover them):
  - `anytogether` → 142.132.181.43, **proxied** (already).
  - `anytogether-cdn` → R2 public bucket custom domain, proxied.
  - `anytogether-relay` → 142.132.181.43, **DNS only** (grey): STUN/TURN over UDP cannot be proxied.
  - `anytogether-staging` → 142.132.181.43, proxied.
- SSL Full (strict); Traefik already gets Let's Encrypt certificates by DNS-01 through Cloudflare.
  coturn's TLS port (5349) uses its own Let's Encrypt certificate for `anytogether-relay` (DNS-01,
  renewed by a small certbot container, coturn reloaded on renewal).
- WAF managed rules; edge rate limits on `/api/v1/auth/*`; bot fight mode on the website paths,
  not on `/api` (launchers are not browsers).
- Cache: public profile pages 60 s with stale-while-revalidate; R2 files long.
- R2 buckets: `anytogether-files` (private), `anytogether-cdn` (public), `anytogether-backups`
  (private, 30-day lifecycle). The server's Cloudflare API token may not have R2 rights; creating
  the buckets and attaching `anytogether-cdn` as the public bucket's custom domain may be done by
  Utku in the Cloudflare dashboard.

## 9.4 Firewall (to be opened with Utku's approval)

Today ufw drops everything not allowed, and no relay port is open. Needed for the relay only:

| Port | Protocol | For |
|---|---|---|
| 3478 | UDP and TCP | STUN and TURN |
| 5349 | TCP | TURN over TLS (networks that block UDP) |
| 49160-49360 | UDP | TURN relay ports (200 ports ≈ 100 relayed calls at once; widened if needed) |

Docker's published ports bypass ufw, so coturn runs with host networking and these rules are
set explicitly in ufw (and in the Hetzner Cloud Firewall, if one is attached to the server:
Utku checks the Hetzner console). Everything else stays behind Traefik on 443.

## 9.5 coturn

```
listening-port=3478
tls-listening-port=5349
min-port=49160
max-port=49360
external-ip=142.132.181.43
realm=anytogether.kodla.agency
use-auth-secret
static-auth-secret=<from Coolify env>   # the API issues time-limited credentials from it
cert=/certs/anytogether-relay/fullchain.pem
pkey=/certs/anytogether-relay/privkey.pem
no-cli
no-multicast-peers
denied-peer-ip=10.0.0.0-10.255.255.255
denied-peer-ip=172.16.0.0-172.31.255.255
denied-peer-ip=192.168.0.0-192.168.255.255
total-quota=200
user-quota=4
max-bps=2000000                         # 2 MB/s per allocation (~16 Mbit/s), enough for 720p60
```

The denied private ranges stop the relay from being used to reach the server's internal Docker
networks. Credentials are the standard TURN REST scheme (username = expiry:user id, password =
HMAC of it), valid 12 hours.

## 9.6 Deploy

- Push to `main` of `utkuhalis/AnyTogether` → Coolify builds and deploys each changed app
  (webhook, one build at a time on this server).
- GitHub Actions only checks: typecheck, lint, tests against PostgreSQL and Valkey service
  containers, migration check. Coolify deploys only what passed (branch protection on `main`).
- Migrations run as the API container starts (`drizzle-kit migrate` before the server), always
  backward compatible with the version still running (expand, deploy, contract).
- Health checks in each Dockerfile so Traefik only routes to a ready container.

## 9.7 Backups and recovery

- Coolify's scheduled PostgreSQL backups, daily, to the R2 backups bucket (S3-compatible
  destination in Coolify), encrypted; kept 30 days.
- A monthly restore test into the staging database.
- R2 versioning on the files bucket.
- Goals: RPO 24 h at launch (daily dumps), 5 min once WAL archiving (wal-g to R2) is added;
  RTO 1 h.

## 9.8 Monitoring

- Coolify's own container health and notifications.
- Uptime checks (Uptime Kuma, already common on such servers, or Cloudflare health checks): the
  website, `/api/v1/health`, the gateway (WebSocket handshake), STUN on the relay.
- Metrics: API and gateway expose Prometheus metrics; coturn's Prometheus exporter (allocations,
  bytes relayed).
- Errors: Sentry (API, web, launchers with opt-in crash reports, phone app).
- Clients report call quality (direct or relayed, round trip, loss, glass-to-glass samples),
  aggregated, no content. The share of relayed calls tells us how much TURN bandwidth to expect.

## 9.9 Costs

| Item | Per month |
|---|---|
| Server | €0 extra (existing Hetzner machine) |
| Traffic | inside the 20 TB included; relayed calls only |
| Cloudflare (free plan), R2 (a few GB, no egress fees) | ~€0-1 |
| Mail for sign-in codes (Resend free tier or kodla.agency SMTP) | €0 |
| Apple Developer (already paid: APNs, Developer ID signing) | €0 extra |
| **Total** | **≈ €0-1** |

If relayed share play ever grows large, coturn moves to a cheap Hetzner machine of its own
(20 TB included there too).
