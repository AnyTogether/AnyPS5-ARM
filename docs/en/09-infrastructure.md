# 9. Infrastructure

## 9.1 Where it runs

On **our own server**, as one more project beside the ones already running there. The server's
details (address, provider, size, what else runs on it) are deliberately **not** in this public
plan; they live in the private infrastructure notes of the AnyTogether repository.

The server is shared with other sites, so AnyTogether is planned **small and capped**:

| Container | Memory limit | CPU limit | Notes |
|---|---|---|---|
| web (Next.js, standalone output) | 512 MB | 1 | built once per deploy; builds run one at a time |
| api | 384 MB | 1 | one replica at start |
| realtime | 384 MB | 1 | tens of thousands of idle sockets fit |
| worker | 256 MB | 0.5 | |
| postgres 17 | 1 GB | 2 | `shared_buffers=256MB`, `max_connections=50` |
| valkey | 128 MB | 0.5 | `maxmemory 96mb`, `allkeys-lru`, no persistence |
| coturn | 256 MB | 1 | host network for UDP |
| **Total** | **≈ 3 GB** | | |

A Next.js build takes another 2-3 GB while it runs; builds run one at a time, so that peak never
overlaps another build.

Because voice, share play and pads go peer-to-peer, the server never carries media except for
the pairs that need the relay.

## 9.2 Applications

| Application | Source | Route |
|---|---|---|
| `web` | repo `utkuhalis/AnyTogether`, `apps/web/Dockerfile` | `anytogether.kodla.agency/` |
| `api` | same repo, `apps/api/Dockerfile` | `anytogether.kodla.agency/api` |
| `realtime` | same repo, `apps/realtime/Dockerfile` | `anytogether.kodla.agency/rt` (WebSocket) |
| `worker` | same repo, `apps/worker/Dockerfile` | none |
| `postgres`, `valkey` | managed database resources | internal network only |
| `coturn` | container with host networking | `anytogether-relay.kodla.agency` (DNS only) |
| staging | the same apps from the `staging` branch | `anytogether-staging.kodla.agency` |

The server's reverse proxy routes by path; the "coming soon" page is replaced by `web` when the
first version is ready.

## 9.3 Cloudflare

- DNS (all one level under `kodla.agency`, so the existing certificates cover them):
  - `anytogether` → the server, **proxied** (already).
  - `anytogether-cdn` → R2 public bucket custom domain, proxied.
  - `anytogether-relay` → **DNS only** (grey): STUN/TURN over UDP cannot be proxied, so this
    name shows the address it points to. It should point to an address of its own (a separate
    IP or a small separate machine), never to the address of the web origin, which stays hidden
    behind Cloudflare.
  - `anytogether-staging` → the server, proxied.
- SSL Full (strict); the origin gets Let's Encrypt certificates by DNS-01 through Cloudflare.
- The origin accepts web traffic **only from Cloudflare's address ranges**, so it cannot be reached
  around Cloudflare even if its address is known.
  coturn's TLS port (5349) uses its own Let's Encrypt certificate for `anytogether-relay` (DNS-01,
  renewed by a small certbot container, coturn reloaded on renewal).
- WAF managed rules; edge rate limits on `/api/v1/auth/*`; bot fight mode on the website paths,
  not on `/api` (launchers are not browsers).
- Cache: public profile pages 60 s with stale-while-revalidate; R2 files long.
- R2 buckets: `anytogether-files` (private), `anytogether-cdn` (public), `anytogether-backups`
  (private, 30-day lifecycle). The server's Cloudflare API token may not have R2 rights; creating
  the buckets and attaching `anytogether-cdn` as the public bucket's custom domain may be done by
  Utku in the Cloudflare dashboard.

## 9.4 Firewall

Only the relay needs ports of its own, opened with Utku's approval:

| Port | Protocol | For |
|---|---|---|
| 3478 | UDP and TCP | STUN and TURN |
| 5349 | TCP | TURN over TLS (networks that block UDP) |
| 49160-49360 | UDP | TURN relay ports (200 ports ≈ 100 relayed calls at once; widened if needed) |

Everything else stays behind the reverse proxy on 443.

## 9.5 coturn

```
listening-port=3478
tls-listening-port=5349
min-port=49160
max-port=49360
external-ip=<the relay's public address>
realm=anytogether.kodla.agency
use-auth-secret
static-auth-secret=<from the environment>   # the API issues time-limited credentials from it
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

The denied private ranges stop the relay from being used to reach the server's internal
networks. Credentials are the standard TURN REST scheme (username = expiry:user id, password =
HMAC of it), valid 12 hours.

## 9.6 Deploy

- Push to `main` of `utkuhalis/AnyTogether` → the server builds and deploys each changed app
  (webhook, one build at a time).
- GitHub Actions only checks: typecheck, lint, tests against PostgreSQL and Valkey service
  containers, migration check. Only what passed is deployed (branch protection on `main`).
- Migrations run as the API container starts (`drizzle-kit migrate` before the server), always
  backward compatible with the version still running (expand, deploy, contract).
- Health checks in each Dockerfile so the proxy only routes to a ready container.

## 9.7 Backups and recovery

- Scheduled PostgreSQL backups, daily, to the R2 backups bucket (S3-compatible), encrypted; kept
  30 days.
- A monthly restore test into the staging database.
- R2 versioning on the files bucket.
- Goals: RPO 24 h at launch (daily dumps), 5 min once WAL archiving (wal-g to R2) is added;
  RTO 1 h.

## 9.8 Monitoring

- Container health checks and notifications from the server's platform.
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
| Server | €0 extra (our existing server) |
| Traffic | inside what the server includes; relayed calls only |
| Cloudflare (free plan), R2 (a few GB, no egress fees) | ~€0-1 |
| Mail for sign-in codes (Resend free tier or kodla.agency SMTP) | €0 |
| Apple Developer (already paid: APNs, Developer ID signing) | €0 extra |
| **Total** | **≈ €0-1** |

If relayed share play ever grows large, coturn moves to a small machine of its own.
