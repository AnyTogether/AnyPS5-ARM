# 2. Architecture

## The idea in two lines

**Players talk to each other directly.** Voice, share play video and the friend's pad go
peer-to-peer between the players' own machines, encrypted, without passing through our server.
**The server only introduces them and keeps what must be kept:** accounts, profiles, trophies,
friends, messages for people who are offline, and a relay for the few connections that cannot go
direct.

## The picture

```mermaid
flowchart LR
    subgraph Players
        L1[Launcher<br/>macOS · Swift]
        L2[Launcher<br/>Windows / Linux · Rust]
        P[AnyPS5 Remote<br/>iOS / Android · Flutter]
        W[Browser]
    end

    subgraph Cloudflare
        CF[anytogether.kodla.agency<br/>DNS, TLS, CDN, WAF]
        R2[(R2 files<br/>anytogether-cdn.kodla.agency)]
    end

    subgraph "Our server"
        WEB[web · Next.js]
        API[api · TypeScript, Hono<br/>/api/v1]
        RT[realtime gateway<br/>/rt · WebSocket<br/>presence, messages, signalling]
        WK[worker · jobs]
        PG[(PostgreSQL)]
        VK[(Valkey)]
        TURN[STUN / TURN relay<br/>anytogether-relay.kodla.agency<br/>coturn]
    end

    L1 & L2 & P & W -- HTTPS / WSS --> CF --> WEB & API & RT
    API --> PG & VK
    RT --> VK & PG
    WK --> PG & VK
    API -. presigned URLs .-> R2

    L1 <== "WebRTC, direct (P2P)<br/>voice · share play · pad" ==> P
    L2 <== "WebRTC, direct (P2P)" ==> W
    L1 <== "WebRTC, direct (P2P)" ==> L2
    L1 -. "only if direct fails" .-> TURN
```

Everything that needs a server goes to **one hostname**, `anytogether.kodla.agency`, behind
Cloudflare: the website at `/`, the API at `/api/v1`, the realtime gateway at `/rt`. Media goes
**player to player** with WebRTC. Only when two players' networks cannot reach each other (strict
NATs, some mobile and office networks, typically 10-20 % of pairs) does it go through our TURN
relay, still encrypted end to end.

## Hostnames (one level under kodla.agency only)

Cloudflare's free certificate covers `kodla.agency` and `*.kodla.agency`, one level deep; a name
like `api.anytogether.kodla.agency` would need a paid certificate and is harder to remember. So
everything lives on one hostname, split by path, plus two siblings that cannot share it:

| Hostname | Through Cloudflare's proxy | What answers |
|---|---|---|
| `anytogether.kodla.agency` | yes | `/` website, `/api/v1/...` API, `/rt` realtime gateway (WebSocket), `/.well-known/...` |
| `anytogether-cdn.kodla.agency` | yes | Cloudflare R2: avatars, theme files and previews, download mirrors |
| `anytogether-relay.kodla.agency` | **no** (DNS only; UDP can't be proxied) | STUN and TURN: UDP/TCP 3478, TLS 5349 |

On the server, the reverse proxy routes by path: `/api` to the API, `/rt` to the gateway, the rest
to the website (each its own application in its own container).

## What goes where

| Traffic | Path | Why |
|---|---|---|
| Sign-in, profiles, trophies, library, friends, themes | client → server (HTTPS) | must be stored and shared |
| Presence (who is online, what they play) | client ↔ gateway (WSS) | friends must learn it even when you are not connected to them |
| Messages | client ↔ gateway, stored in PostgreSQL | must reach people who are offline and every device of theirs |
| WebRTC signalling (offers, answers, ICE candidates) | client ↔ gateway ↔ client | the introduction; a few kilobytes per call |
| **Voice** | **player ↔ player** (WebRTC, Opus) | lowest delay, no server bandwidth |
| **Share play video and game sound** | **host → viewer** (WebRTC, H.264 + Opus) | lowest delay; a 720p60 stream is ~8 Mbit/s that our server never carries |
| **The friend's pad** | **viewer → host** (WebRTC data channel) | every millisecond counts |
| Relay when direct is impossible | player ↔ TURN ↔ player | so it always works; the relay sees only encrypted packets |

## The services on our server

### api (TypeScript, Hono on Node 22)

The one place that changes stored data; stateless. TypeScript because the website is TypeScript
too, so schemas (Zod) are written once and the OpenAPI document generated from them gives typed
clients in **Swift** (macOS launcher), **Dart** (phone), **TypeScript** (web), and in any language
another launcher uses (the Windows/Linux port, in Rust). Hono because it is small, web-standard and portable (Node today, Bun or
Cloudflare Workers later). Drizzle with reviewed SQL migrations. Errors as RFC 9457 problem
details with stable codes every client translates.

### realtime gateway (same codebase, own process)

One WebSocket per signed-in client. Carries presence heartbeats and changes, message delivery,
notifications, and **WebRTC signalling**: when Ayşe calls Utku, her offer goes to the gateway,
which forwards it to Utku's devices; answers and ICE candidates come back the same way. Holds no
state of its own: presence in Valkey, events between gateway processes over Valkey pub/sub.

### worker (same codebase, own process)

pg-boss jobs inside PostgreSQL: trophy rarity, leaderboards, mail (sign-in codes), push
notifications (APNs, FCM), image resizing and checks, account deletion after the grace period.

### web (Next.js)

Public profiles and game pages server-rendered (fast, shareable, link previews); the signed-in
app (friends, messages, parties with voice in the browser, share play viewer, Theme Hub,
downloads, leaderboards, settings) in the browser. It uses the same API as everyone.

### PostgreSQL 17, Valkey 8

PostgreSQL holds everything that must last. Valkey holds what may vanish: presence (60 s expiry),
pub/sub, rate limits, short-lived sign-in codes, the last minutes of events for reconnects.

### coturn (STUN and TURN)

STUN tells each player its public address so two players can punch through their routers to each
other (ICE). TURN relays the media when that fails. Credentials are short-lived (issued per call
by the API, HMAC-based, valid 12 hours). TURN only ever sees DTLS-SRTP encrypted media: it cannot
hear or see anything.

### Optional later: an SFU

For a party of 8 people all talking, peer-to-peer means each sends 7 audio streams (7 × 32
kbit/s ≈ 0.2 Mbit/s, fine). For share play to many viewers, peer-to-peer means the host uploads
one video per viewer (3 viewers ≈ 24 Mbit/s up, too much for many homes). Only then is a
forwarding server (an SFU such as LiveKit) worth running. It is a later, optional add-on: the
default is direct.

## Technology choices

| Need | Choice | Why |
|---|---|---|
| API and gateway | TypeScript, Node 22, Hono | one language with the web, shared schemas |
| Database | PostgreSQL 17 + Drizzle | all we need in one engine; SQL migrations |
| Jobs | pg-boss | queue inside PostgreSQL |
| Temporary state | Valkey 8 | Redis-compatible, open licence |
| Peer-to-peer media | **WebRTC** | built for exactly this: NAT traversal (ICE/STUN/TURN), encryption (DTLS-SRTP), Opus voice, low-latency video, data channels, in every browser and with libraries for every platform |
| WebRTC per platform | macOS: Google's WebRTC framework (Swift package); Windows/Linux: `webrtc-rs` (pure Rust) or LiveKit's `libwebrtc` Rust bindings; phone: `flutter_webrtc`; web: the browser | each launcher in its own language |
| Relay | coturn | the standard TURN server |
| Website | Next.js | SSR for public pages |
| Files | Cloudflare R2 | S3 API, no egress fees |
| Sign-in | OpenID Connect (Apple, Google, Discord) + passwordless email codes; passkeys later | one tap, nothing to remember (see [API](04-api.md)) |
| Push | APNs, FCM HTTP v1 | direct, no middleman |
| Errors / metrics | Sentry, Prometheus + Grafana | standard |
| Deploy | our own server's container platform (git push → build → deploy) | what the server already uses |

## How a call is set up (voice or share play)

```mermaid
sequenceDiagram
    participant A as Ayşe (launcher, Windows)
    participant G as Gateway
    participant API as API
    participant U as Utku (launcher, macOS)
    A->>API: POST /api/v1/calls {party}
    API-->>A: call id, TURN credentials (12 h)
    A->>G: signal {to: Utku, offer (SDP)}
    G->>U: signal {from: Ayşe, offer}
    U->>API: (gets TURN credentials too)
    U->>G: signal {to: Ayşe, answer}
    G->>A: answer
    A-->>U: ICE candidates both ways through G
    A<<->>U: WebRTC: direct UDP if possible, TURN if not
    Note over A,U: voice / video / pad flow player to player
```

## Repository layout (the code, when it starts)

`utkuhalis/AnyTogether` (monorepo, pnpm workspaces):

```
apps/
  api/          Hono API (/api/v1)
  realtime/     WebSocket gateway: presence, messages, signalling
  worker/       pg-boss jobs
  web/          Next.js website
packages/
  shared/       Zod schemas, event and signalling types, error codes, OpenAPI
  db/           Drizzle schema and SQL migrations
clients/
  swift/        generated types for the macOS launcher (used from AnyPS5-ARM)
  dart/         generated types for the phone app
infra/
  Dockerfiles   one per app, built by the server on push
  coturn/       turnserver.conf, the relay's compose file
  backups/
docs/           this plan
```

The macOS launcher's integration lives in AnyPS5-ARM (`AnyPS5Core/Together/`), the phone app's
in `mobile/lib/together/`, the Windows/Linux launcher's in its own repository, written by its
maintainer from the published contracts. See [Clients](07-clients.md) and [Platforms](12-platforms.md).

## Scale

| Stage | Accounts / online | Server |
|---|---|---|
| Launch | 5,000 / 500 | our existing server, shared: AnyTogether within ~3 GB with memory limits; media is peer-to-peer |
| Growing | 50,000 / 5,000 | the same, plus more TURN bandwidth |
| Large | more | more gateway/API processes (stateless), TURN on a second machine, a read replica |

Because media is direct, the server's load is small: requests, sockets and the relay for the
pairs that need it. The relay is the only part whose bandwidth grows with use.
