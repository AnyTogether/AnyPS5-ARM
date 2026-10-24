# 5. Data model

Tables are grouped by topic here; in the migrations, `themes` is created before `profiles`, which refers to it.

PostgreSQL 17. IDs are UUIDv7 (time-ordered, so indexes stay compact and IDs sort by creation).
Times are `timestamptz`. Text that users search is indexed with `pg_trgm`. Every table has
`created_at`; tables that change have `updated_at`.

## Accounts and profiles

```sql
create table accounts (
  id            uuid primary key,
  email         citext unique,              -- verified email (from the provider or an email code); may be null
  role          text not null default 'user',-- user | moderator | admin
  status        text not null default 'active', -- active | suspended | deleting
  delete_after  timestamptz,                 -- set by DELETE /me, 14 days later
  created_at    timestamptz not null default now()
);

create table identities (                    -- the ways in: Apple, Google, Discord, email
  account_id uuid references accounts on delete cascade,
  provider   text not null,                  -- apple | google | discord | email
  subject    text not null,                  -- the provider's user ID
  primary key (provider, subject)
);

create table sessions (
  id            uuid primary key,
  account_id    uuid not null references accounts on delete cascade,
  client        text not null,               -- launcher-macos | launcher-windows | launcher-linux | phone | web
  device_name   text,
  refresh_hash  bytea not null,              -- sha256 of the current refresh token
  previous_hash bytea,                       -- the one before, to detect reuse
  last_seen_at  timestamptz,
  revoked_at    timestamptz,
  created_at    timestamptz not null default now()
);

create table sign_in_requests (              -- email codes, phone hand-offs, device codes; short-lived
  id           uuid primary key,
  kind         text not null,                 -- email | handoff | device
  email        citext,                        -- for email codes
  code_hash    bytea,                         -- the 6-digit code or the magic link token, hashed
  account_id   uuid references accounts,      -- for hand-offs: whose phones are asked
  device_name  text,
  approved_at  timestamptz,
  attempts     int not null default 0,
  expires_at   timestamptz not null
);

create table device_codes (                  -- RFC 8628 fallback, short-lived (also mirrored in Valkey)
  device_code_hash bytea primary key,
  user_code    text unique not null,          -- e.g. K7Q-2MX, no 0/O/1/I
  client       text not null,
  device_name  text,
  approved_by  uuid references accounts,
  expires_at   timestamptz not null
);

create table profiles (
  account_id   uuid primary key references accounts on delete cascade,
  handle       citext unique not null,
  handle_changed_at timestamptz,
  display_name text not null,
  bio          text check (length(bio) <= 160),
  country      char(2),
  avatar_key   text,                          -- R2 key prefix; sizes are derived
  theme_id     uuid references themes,
  showcase     jsonb not null default '[]',   -- up to six {kind, ref}
  privacy      jsonb not null default '{}',   -- per item: everyone | friends | me
  stats        jsonb not null default '{}'    -- games, hours, trophies, platinums (worker)
);
create index profiles_handle_trgm on profiles using gin (handle gin_trgm_ops);
create index profiles_name_trgm on profiles using gin (display_name gin_trgm_ops);

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
  names      jsonb not null,                 -- {"en": "Hollow Knight: Silksong", "tr": ...}
  icon_key   text,
  taught_by  uuid references accounts,
  locked     boolean not null default false  -- a moderator fixed it; launchers cannot change it
);
create index games_name_trgm on games using gin ((names->>'en') gin_trgm_ops);

create table play_sessions (
  id         uuid primary key,               -- made by the launcher (idempotent)
  account_id uuid not null references accounts on delete cascade,
  title_id   text not null references games,
  device_id  uuid references devices,
  started_at timestamptz not null,
  ended_at   timestamptz not null check (ended_at > started_at),
  exit       text                            -- normal | crashed | killed (the launcher's diagnosis)
);
create index play_sessions_user_game on play_sessions (account_id, title_id, started_at desc);

create table library (                       -- per user per game, kept by the worker
  account_id  uuid references accounts on delete cascade,
  title_id    text references games,
  first_played_at timestamptz,
  last_played_at  timestamptz,
  seconds_played  bigint not null default 0,
  trophies_earned int not null default 0,
  trophies_total  int,
  points          int not null default 0,     -- bronze 15, silver 30, gold 90, platinum 300
  primary key (account_id, title_id)
);

create table trophy_sets (
  title_id  text references games,
  set_hash  text,                            -- hash of the game's trophy file
  primary key (title_id, set_hash)
);

create table trophies (
  title_id  text,
  set_hash  text,
  trophy_id int,
  grade     text not null,                   -- bronze | silver | gold | platinum
  hidden    boolean not null default false,
  texts     jsonb not null,                  -- {"en": {"name":..., "detail":...}, "tr": ...}
  icon_key  text,
  earned_count int not null default 0,       -- worker
  rarity    real,                            -- earned_count / players of the game, worker
  primary key (title_id, set_hash, trophy_id),
  foreign key (title_id, set_hash) references trophy_sets
);

create table earned_trophies (
  account_id uuid references accounts on delete cascade,
  title_id   text,
  set_hash   text,
  trophy_id  int,
  earned_at  timestamptz not null,
  flagged    boolean not null default false,  -- impossible patterns, off leaderboards
  primary key (account_id, title_id, trophy_id),
  foreign key (title_id, set_hash, trophy_id) references trophies
);
create index earned_by_game on earned_trophies (title_id, trophy_id);

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
  note       text check (length(note) <= 500),
  created_at timestamptz not null default now()
);
```

## Social

```sql
create table friendships (                   -- one row per pair, user_a < user_b
  user_a uuid references accounts on delete cascade,
  user_b uuid references accounts on delete cascade,
  state  text not null,                      -- pending | accepted
  asked_by uuid not null,
  created_at timestamptz not null default now(),
  accepted_at timestamptz,
  primary key (user_a, user_b),
  check (user_a < user_b)
);

create table blocks (
  blocker uuid references accounts on delete cascade,
  blocked uuid references accounts on delete cascade,
  primary key (blocker, blocked)
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
```

## Messages and parties

```sql
create table conversations (
  id      uuid primary key,
  kind    text not null,                     -- direct | group | party
  title   text,
  last_seq bigint not null default 0,
  party_id uuid
);

create table conversation_members (
  conversation_id uuid references conversations on delete cascade,
  account_id uuid references accounts on delete cascade,
  read_seq   bigint not null default 0,
  muted      boolean not null default false,
  primary key (conversation_id, account_id)
);

create table messages (
  conversation_id uuid references conversations on delete cascade,
  seq        bigint not null,                -- conversations.last_seq + 1, in the same transaction
  id         uuid not null unique,           -- the client's UUIDv7, for retries
  author_id  uuid references accounts on delete set null,
  text       text check (length(text) <= 4000),
  attachments jsonb not null default '[]',
  reply_to   bigint,
  edited_at  timestamptz,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  primary key (conversation_id, seq)
);

create table parties (
  id       uuid primary key,
  owner_id uuid references accounts,
  privacy  text not null default 'invite',   -- invite | friends | link
  link_token text unique,
  share_play jsonb,                          -- {host, started_at, slots: {"2": user_id}}
  ended_at timestamptz
);
create table calls (                         -- set up by the API; the media itself is peer-to-peer
  id         uuid primary key,
  party_id   uuid references parties on delete set null,
  started_by uuid references accounts on delete set null,
  started_at timestamptz not null default now(),
  ended_at   timestamptz
);
create table call_quality (                  -- one row per participant at the end of a call
  call_id    uuid references calls on delete cascade,
  account_id uuid references accounts on delete set null,
  path       text not null,                  -- direct | relay-udp | relay-tls
  rtt_ms     real, loss real, glass_to_glass_ms real,
  share_play boolean not null default false
);

create table party_members (party_id uuid references parties on delete cascade, account_id uuid references accounts on delete cascade, joined_at timestamptz not null default now(), primary key (party_id, account_id));
```

## Themes, releases, moderation

```sql
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

create table reports (
  id uuid primary key, reporter_id uuid references accounts on delete set null,
  target_kind text not null,                 -- user | message | theme | activity | game_name
  target_id text not null, reason text not null, note text,
  status text not null default 'open',       -- open | actioned | dismissed
  handled_by uuid, handled_at timestamptz
);

create table audit_log (id uuid primary key, actor_id uuid, action text not null, target text, data jsonb, created_at timestamptz not null default now());
```

## In Valkey (temporary)

| Key | Value | Expiry |
|---|---|---|
| `presence:<user>` | hash: state, title_id, since, devices | 60 s, renewed by heartbeats |
| `events:<user>` | stream of the last events, for `resume` | trimmed to 5 min |
| `rl:<scope>:<id>` | rate-limit counters | the window |
| `lb:<board>:<period>` | sorted set of user IDs by score | rebuilt every 10 min |
| `devcode:<user_code>` | device code state | 10 min |

## Counting

- **Play time**: when sessions arrive, the worker adds `ended_at - started_at` to `library`
  (sessions are deduplicated by ID first, so a resent batch never counts twice).
- **Rarity**: per changed game, `earned_count` per trophy (a `count(*)` over `earned_trophies`
  using `earned_by_game`) and `players` = rows in `library` for the game; `rarity = earned /
  players`. At most every 10 minutes per game.
- **Points**: bronze 15, silver 30, gold 90, platinum 300, summed into `library.points` and the
  profile's `stats`.

## Keeping data

| Data | Kept |
|---|---|
| Account and profile | until deleted (14 days after asking) |
| Sessions, trophies, library | until the account is deleted |
| Messages | until deleted by the author or the account is deleted; deleted messages are emptied at once |
| Compatibility reports | anonymised (account set null) when the account is deleted |
| Revoked sessions | 30 days |
| Audit log | 1 year |
| Backups | 30 days (nightly), so a deletion is complete in backups after 30 days |
