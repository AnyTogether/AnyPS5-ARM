# 5. Data model

PostgreSQL 17. IDs are UUIDv7 (time-ordered, so indexes stay compact and IDs sort by creation).
Times are `timestamptz`. Every table has `created_at`.

The tables below are the ones **built**, as the Drizzle schema in
[`packages/db/src/schema.ts`](https://github.com/utkuhalis/AnyTogether/blob/main/packages/db/src/schema.ts)
defines them on 2026-10-24, written here as SQL and shortened (`created_at` and most indexes left
out). The **planned** tables come after them.

## Accounts and sign-in

```sql
create table accounts (
  id            uuid primary key,
  email         citext unique,              -- from the provider or an email code; may be null
  role          text not null default 'user',-- user | moderator | admin
  status        text not null default 'active', -- active | banned | deleting
  delete_after  timestamptz                  -- set by DELETE /me, 14 days later
);

create table identities (                    -- the ways in
  account_id uuid not null references accounts on delete cascade,
  provider   text not null,                  -- apple | google | discord | email
  subject    text not null,                  -- the provider's user ID; for email, the address
  primary key (provider, subject)
);

create table sessions (                      -- a signed-in device
  id            uuid primary key,
  account_id    uuid not null references accounts on delete cascade,
  client        text not null,               -- launcher-macos | launcher-windows | launcher-linux | phone | web
  device_name   text,
  refresh_hash  bytea not null,              -- sha256 of the current refresh token
  previous_hash bytea,                       -- the one before, to detect reuse
  expires_at    timestamptz not null,        -- 90 days
  last_seen_at  timestamptz,
  revoked_at    timestamptz
);

create table passkeys (                      -- WebAuthn discoverable credentials, at most 10 per account
  id           text primary key,             -- the authenticator's credential ID
  account_id   uuid not null references accounts on delete cascade,
  name         text not null check (length(name) <= 60),
  public_key   bytea not null,               -- COSE, as the browser sent it
  counter      bigint not null default 0,    -- most synced passkeys always send 0
  transports   jsonb not null default '[]',
  device_type  text not null,                -- singleDevice | multiDevice (synced)
  backed_up    boolean not null default false,
  last_used_at timestamptz
);

create table sign_in_requests (              -- email codes, phone hand-offs, device codes; short-lived
  id           uuid primary key,
  kind         text not null check (kind in ('email', 'handoff', 'device')),
  email        citext,                        -- for email codes
  code_hash    bytea,                         -- the 6-digit code, hashed
  link_hash    bytea,                         -- the mail's link token, hashed
  secret_hash  bytea,                         -- the hand-off secret or the device code, hashed
  user_code    text unique,                   -- device codes: XXXX-XXXX, no 0/O/1/I
  client       text,
  device_name  text,
  approved_by  uuid references accounts on delete cascade,
  attempts     int not null default 0,
  last_polled_at timestamptz,
  consumed_at  timestamptz,
  expires_at   timestamptz not null
);
```

Passkey challenges (5 minutes), gateway tickets (30 seconds) and account-deletion codes (10
minutes) live in Valkey, not in tables.

## Profiles and devices

```sql
create table profiles (
  account_id   uuid primary key references accounts on delete cascade,
  handle       citext unique not null,
  handle_changed_at timestamptz,
  display_name text not null,
  bio          text check (length(bio) <= 160),
  country      text,
  avatar_url   text,                          -- /api/v1/avatars/<hash>.jpg, or the provider's picture
  privacy      jsonb not null default '{}',   -- library, trophies, friends, presence, search: everyone | friends | nobody
  stats        jsonb not null default '{}'    -- planned: games, hours, trophies, platinums
);

create table handle_history (                -- a given-up handle, held for its last owner for 30 days
  handle      citext primary key,
  account_id  uuid not null references accounts on delete cascade,
  released_at timestamptz not null default now()
);

create table avatars (                       -- 256 px JPEG without metadata; only the current one is kept
  hash       text primary key,               -- of the bytes, so the URL never changes for one image
  account_id uuid not null references accounts on delete cascade,
  bytes      bytea not null
);

create table devices (                       -- a user's computers, by the launcher's random ID
  id         uuid primary key,
  account_id uuid not null references accounts on delete cascade,
  platform   text not null,                  -- macos | windows | linux
  name       text not null,                  -- "Utku's MacBook Pro", "Gaming PC"
  model      text,                           -- Mac15,9 / CPU and GPU summary
  last_seen_at timestamptz
);
```

## Games, sessions, trophies

```sql
create table games (                         -- the catalogue, one row per title ID
  title_id   text primary key check (title_id ~ '^[A-Z]{4}[0-9]{5}$'),
  names      jsonb not null default '{}',    -- {"en": "Hollow Knight: Silksong", "tr": ...}; empty for a stub
  icon_url   text,
  taught_by  uuid references accounts on delete set null,
  locked     boolean not null default false  -- a moderator fixed it; launchers cannot change it
);

create table play_sessions (
  id         uuid primary key,               -- made by the launcher (idempotent)
  account_id uuid not null references accounts on delete cascade,
  title_id   text not null references games,
  device_id  uuid references devices on delete set null,
  started_at timestamptz not null,
  ended_at   timestamptz not null check (ended_at > started_at),
  exit       text                            -- normal | crashed | killed (the launcher's diagnosis)
);
create index on play_sessions (account_id, title_id, started_at desc);

create table library (                       -- per user per game, worked out again when sessions or trophies arrive
  account_id  uuid not null references accounts on delete cascade,
  title_id    text not null references games,
  first_played_at timestamptz,
  last_played_at  timestamptz,
  seconds_played  bigint not null default 0,
  trophies_earned int not null default 0,
  trophies_total  int,
  points          int not null default 0,     -- bronze 15, silver 30, gold 90, platinum 300
  primary key (account_id, title_id)
);

create table trophy_sets (
  title_id  text not null references games,
  set_hash  text not null,                   -- hash of the game's trophy file
  taught_by uuid references accounts on delete set null,
  primary key (title_id, set_hash)
);

create table trophies (
  title_id  text not null,
  set_hash  text not null,
  trophy_id int not null,
  grade     text not null check (grade in ('bronze', 'silver', 'gold', 'platinum')),
  hidden    boolean not null default false,
  texts     jsonb not null,                  -- {"en": {"name":..., "detail":...}, "tr": ...}
  earned_count int not null default 0,
  rarity    real,                            -- earned_count / players of the game, 0..1
  primary key (title_id, set_hash, trophy_id),
  foreign key (title_id, set_hash) references trophy_sets
);

create table earned_trophies (
  account_id uuid not null references accounts on delete cascade,
  title_id   text not null,
  set_hash   text not null,
  trophy_id  int not null,
  earned_at  timestamptz not null,
  flagged    boolean not null default false,  -- impossible patterns, off leaderboards (flagging planned)
  primary key (account_id, title_id, trophy_id),
  foreign key (title_id, set_hash, trophy_id) references trophies
);
create index earned_by_game on earned_trophies (title_id, trophy_id);
```

Trophy icons are not stored yet.

## Social and moderation

```sql
create table friendships (                   -- one row per pair, user_a < user_b
  user_a   uuid not null references accounts on delete cascade,
  user_b   uuid not null references accounts on delete cascade,
  state    text not null check (state in ('pending', 'accepted')),
  asked_by uuid not null,
  accepted_at timestamptz,
  primary key (user_a, user_b),
  check (user_a < user_b)
);

create table blocks (
  blocker uuid not null references accounts on delete cascade,
  blocked uuid not null references accounts on delete cascade,
  primary key (blocker, blocked)
);

create table reports (
  id          uuid primary key,
  reporter_id uuid references accounts on delete set null,
  target_kind text not null,                 -- user | message (later activity, theme, game_name)
  target_id   text not null,
  reason      text not null,                 -- spam | harassment | hate | sexual | impersonation | cheating | piracy | other
  note        text check (length(note) <= 500),
  snapshot    jsonb,                         -- a reported message as it was, kept even if its author deletes it
  status      text not null default 'open',  -- open | actioned | dismissed
  handled_by  text,
  handled_at  timestamptz
);
-- one open report per reporter and target

create table bans (                          -- on an account, on an email (kept only as its SHA-256), or both
  id         uuid primary key,
  account_id uuid references accounts on delete set null,
  email_hash bytea,
  reason     text,
  created_by text,
  expires_at timestamptz,                    -- null: until lifted
  lifted_at  timestamptz
);

create table audit_log (id uuid primary key, actor_id uuid, action text not null, target text, data jsonb);
```

## Messages

```sql
create table conversations (
  id         uuid primary key,
  kind       text not null check (kind in ('direct', 'group')),
  title      text,
  direct_key text unique,                    -- "smaller:larger" user ID, so a pair has one direct conversation
  created_by uuid references accounts on delete set null,
  last_seq   bigint not null default 0,
  updated_at timestamptz not null default now(), -- the last message or change, for ordering the list
  check ((kind = 'direct') = (direct_key is not null))
);

create table conversation_members (
  conversation_id uuid not null references conversations on delete cascade,
  account_id uuid not null references accounts on delete cascade,
  read_seq   bigint not null default 0,
  muted      boolean not null default false,
  joined_at  timestamptz not null default now(),
  primary key (conversation_id, account_id)
);

create table messages (
  conversation_id uuid not null references conversations on delete cascade,
  seq        bigint not null,                -- conversations.last_seq + 1, in the same transaction
  id         uuid not null unique,           -- the client's UUID, for retries
  author_id  uuid references accounts on delete set null,
  text       text check (length(text) <= 4000),
  attachments jsonb not null default '[]',   -- stays empty until uploads exist
  reply_to   bigint,
  edited_at  timestamptz,
  deleted_at timestamptz,                    -- a deleted message is emptied at once
  primary key (conversation_id, seq)
);
```

## Parties, calls, game sessions

```sql
create table parties (                       -- at most eight people
  id        uuid primary key,
  leader_id uuid references accounts on delete set null,
  privacy   text not null default 'invite' check (privacy in ('invite', 'friends')),
  ended_at  timestamptz
);
create table party_members (                 -- someone is in one party at a time
  party_id   uuid not null references parties on delete cascade,
  account_id uuid not null unique references accounts on delete cascade,
  joined_at  timestamptz not null default now(),
  primary key (party_id, account_id)
);
create table party_invites (
  party_id   uuid not null references parties on delete cascade,
  account_id uuid not null references accounts on delete cascade,
  invited_by uuid references accounts on delete set null,
  primary key (party_id, account_id)
);

create table calls (                         -- set up by the API; the media itself is peer-to-peer
  id          uuid primary key,
  party_id    uuid references parties on delete set null,
  started_by  uuid references accounts on delete set null,
  callee_id   uuid references accounts on delete set null, -- a call between two friends
  started_at  timestamptz not null default now(),
  answered_at timestamptz,
  ended_at    timestamptz
);
-- one open call per party

create table game_sessions (                 -- a game a launcher hosts for friends to join; one open per host
  id           uuid primary key,
  host_id      uuid not null references accounts on delete cascade,
  title_id     text not null references games,
  game_version text not null,                -- "01.000.002", as the launcher reads it
  engine_build text not null,                -- only the same build can be relied on to talk to itself
  capacity     int not null check (capacity between 2 and 16),
  joinable     boolean not null default true,
  properties   jsonb not null default '{}',  -- up to 4 KB, defined by the launchers
  ended_at     timestamptz
);
create table game_session_players (          -- the host included; someone plays in one session at a time
  session_id uuid not null references game_sessions on delete cascade,
  account_id uuid not null unique references accounts on delete cascade,
  joined_at  timestamptz not null default now(),
  primary key (session_id, account_id)
);
create table game_session_invites (
  session_id uuid not null references game_sessions on delete cascade,
  account_id uuid not null references accounts on delete cascade,
  invited_by uuid references accounts on delete set null,
  primary key (session_id, account_id)
);
```

Who may signal in a call and who is in it now are kept in Valkey, not in `calls`.

## Planned tables

```sql
create table compatibility_reports (
  id         uuid primary key,
  account_id uuid references accounts on delete set null,
  title_id   text references games,
  verdict    text not null,                  -- nothing | menus | playable | perfect
  engine     text not null,                  -- e.g. 0.2.13-arm
  platform   text not null,                  -- macos | windows | linux
  machine    text, os text,                  -- Mac model or CPU/GPU; OS and version
  fps_avg    real,
  exit       text,
  note       text check (length(note) <= 500)
);

create table activities (
  id         uuid primary key,
  actor_id   uuid not null references accounts on delete cascade,
  kind       text not null,                  -- trophy | platinum | new_game | long_session | completed | clip | theme | joined
  payload    jsonb not null,
  visibility text not null,                  -- everyone | friends
  folded_into uuid references activities     -- several trophies in an hour become one
);
create index activities_actor on activities (actor_id, id desc);
create table activity_likes (activity_id uuid references activities on delete cascade, account_id uuid, primary key (activity_id, account_id));
create table activity_comments (id uuid primary key, activity_id uuid references activities on delete cascade, account_id uuid, text text not null);

create table call_quality (                  -- one row per participant at the end of a call
  call_id    uuid references calls on delete cascade,
  account_id uuid references accounts on delete set null,
  path       text not null,                  -- direct | relay-udp | relay-tls
  rtt_ms     real, loss real, glass_to_glass_ms real,
  share_play boolean not null default false
);

create table themes (
  id        uuid primary key,
  maker_id  uuid references accounts on delete set null,
  name      text not null,
  status    text not null default 'review',  -- review | published | removed
  likes     int not null default 0,
  installs  int not null default 0,
  current_version int not null default 1
);
create table theme_versions (theme_id uuid references themes on delete cascade, version int, file_key text not null, preview_key text, design jsonb not null, primary key (theme_id, version));
create table theme_likes (theme_id uuid references themes on delete cascade, account_id uuid, primary key (theme_id, account_id));

create table releases (product text, version text, notes text, url text, sha256 text, published_at timestamptz, primary key (product, version));
```

Also planned on existing tables: `profiles.theme_id` and `showcase`, a `share_play` state on a
party's call (who hosts, since when; there is no controller slot, share play is watch only),
link privacy for parties.

## In Valkey (temporary)

| Key | Value | Expiry |
|---|---|---|
| `presence:<user>:<session>` | one device's state, title ID, since | 60 s, renewed by heartbeats |
| `presence:<user>` | the user's presence merged over their devices, with party and game session | 70 s |
| `presence-extra:<user>` | the party and the joinable game session shown in presence | while they last |
| `presence-hidden:<user>` | set while the user's presence is visible to nobody | while set |
| `friends:<user>` | the user's friends, for the gateway's presence fan-out | kept by the API |
| `events:<user>` | stream of the last events, for `resume` | trimmed to 5 min |
| `user:<user>` | the pub/sub channel the gateway listens on | - |
| `call:<id>:members`, `call:<id>:in` | who may signal in a call; who is in it, on which device | 12 h |
| `rt-ticket:<hash>` | a one-time gateway ticket for the website | 30 s |
| `passkey:register:<user>`, `passkey:signin:<id>` | a passkey challenge | 5 min |
| `revoked:<session>` | a signed-out session, refused by the API and the gateway | the access token's life |
| `rl:<name>:<who>:<window>` | rate-limit counters | the window |
| `lb:<board>:<period>` | sorted set of user IDs by score (planned) | rebuilt every 10 min |

## Counting

- **Play time**: when sessions arrive, the library rows of the games they touch are worked out
  again from the sessions (deduplicated by ID first, so a resent batch never counts twice).
- **Rarity**: when trophies for a game arrive, `earned_count` per trophy (a `count(*)` over
  `earned_trophies` using `earned_by_game`) and `players` = rows in `library` for the game;
  `rarity = earned / players`. Labels: common > 50 %, uncommon 20-50 %, rare 5-20 %, very rare
  1-5 %, ultra rare < 1 %.
- **Points**: bronze 15, silver 30, gold 90, platinum 300, summed into `library.points`; the
  profile's `stats` are planned.

## Keeping data

| Data | Kept |
|---|---|
| Account and profile | until deleted (14 days after asking); purged every hour once the 14 days are over |
| Sessions, trophies, library | until the account is deleted |
| Messages | until deleted by the author or the account is deleted; deleted messages are emptied at once |
| Reported messages | their text stays in the report for the moderators |
| Compatibility reports (planned) | anonymised (account set null) when the account is deleted |
| Audit log | 1 year |
| Backups | 30 days (nightly), so a deletion is complete in backups after 30 days |
