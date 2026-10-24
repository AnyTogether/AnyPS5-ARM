# 5. Veri modeli

Tablolar burada konularına göre gruplanmıştır; migration'larda `themes`, kendisine başvuran `profiles` tablosundan önce oluşturulur.

PostgreSQL 17. ID'ler UUIDv7'dir (zamana göre sıralı olduğu için indeksler kompakt kalır ve ID'ler oluşturulma sırasına göre dizilir).
Zamanlar `timestamptz` türündedir. Kullanıcıların arama yaptığı metinler `pg_trgm` ile indekslenir. Her tabloda
`created_at` bulunur; değişen tablolarda ayrıca `updated_at` vardır.

## Hesaplar ve profiller

```sql
create table accounts (
  id            uuid primary key,
  email         citext unique,              -- doğrulanmış e-posta (sağlayıcıdan ya da e-posta kodundan); boş olabilir
  role          text not null default 'user',-- user | moderator | admin
  status        text not null default 'active', -- active | suspended | deleting
  delete_after  timestamptz,                 -- DELETE /me ile ayarlanır, 14 gün sonrası
  created_at    timestamptz not null default now()
);

create table identities (                    -- giriş yolları: Apple, Google, Discord, e-posta
  account_id uuid references accounts on delete cascade,
  provider   text not null,                  -- apple | google | discord | email
  subject    text not null,                  -- sağlayıcıdaki kullanıcı ID'si
  primary key (provider, subject)
);

create table sessions (
  id            uuid primary key,
  account_id    uuid not null references accounts on delete cascade,
  client        text not null,               -- launcher-macos | launcher-windows | launcher-linux | phone | web
  device_name   text,
  refresh_hash  bytea not null,              -- geçerli yenileme token'ının sha256'sı
  previous_hash bytea,                       -- bir öncekininki, yeniden kullanımı yakalamak için
  last_seen_at  timestamptz,
  revoked_at    timestamptz,
  created_at    timestamptz not null default now()
);

create table sign_in_requests (              -- e-posta kodları, telefona devretmeler, cihaz kodları; kısa ömürlü
  id           uuid primary key,
  kind         text not null,                 -- email | handoff | device
  email        citext,                        -- e-posta kodları için
  code_hash    bytea,                         -- 6 haneli kod ya da sihirli bağlantı token'ı, hash'lenmiş
  account_id   uuid references accounts,      -- telefona devretmelerde: kimin telefonlarına sorulacağı
  device_name  text,
  approved_at  timestamptz,
  attempts     int not null default 0,
  expires_at   timestamptz not null
);

create table device_codes (                  -- RFC 8628 yedek yolu, kısa ömürlü (Valkey'de de bir kopyası tutulur)
  device_code_hash bytea primary key,
  user_code    text unique not null,          -- örn. K7Q-2MX, 0/O/1/I içermez
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
  avatar_key   text,                          -- R2 anahtar öneki; boyutlar buradan türetilir
  theme_id     uuid references themes,
  showcase     jsonb not null default '[]',   -- en fazla altı {kind, ref}
  privacy      jsonb not null default '{}',   -- öğe başına: everyone | friends | me
  stats        jsonb not null default '{}'    -- oyunlar, saatler, kupalar, platinler (worker)
);
create index profiles_handle_trgm on profiles using gin (handle gin_trgm_ops);
create index profiles_name_trgm on profiles using gin (display_name gin_trgm_ops);

create table devices (                       -- kullanıcının bilgisayarları, launcher'ın rastgele ID'siyle
  id         uuid primary key,
  account_id uuid not null references accounts on delete cascade,
  platform   text not null,                  -- macos | windows | linux
  name       text not null,                  -- "Utku's MacBook Pro", "Gaming PC"
  model      text,                           -- Mac15,9 / CPU ve GPU özeti
  last_seen_at timestamptz
);
```

## Oyunlar, oturumlar, kupalar

```sql
create table games (                         -- katalog, title ID başına bir satır
  title_id   text primary key check (title_id ~ '^[A-Z]{4}[0-9]{5}$'),
  names      jsonb not null,                 -- {"en": "Hollow Knight: Silksong", "tr": ...}
  icon_key   text,
  taught_by  uuid references accounts,
  locked     boolean not null default false  -- bir moderatör sabitlemiştir; launcher'lar değiştiremez
);
create index games_name_trgm on games using gin ((names->>'en') gin_trgm_ops);

create table play_sessions (
  id         uuid primary key,               -- launcher tarafından üretilir (idempotent)
  account_id uuid not null references accounts on delete cascade,
  title_id   text not null references games,
  device_id  uuid references devices,
  started_at timestamptz not null,
  ended_at   timestamptz not null check (ended_at > started_at),
  exit       text                            -- normal | crashed | killed (launcher'ın teşhisi)
);
create index play_sessions_user_game on play_sessions (account_id, title_id, started_at desc);

create table library (                       -- kullanıcı ve oyun başına, worker tarafından tutulur
  account_id  uuid references accounts on delete cascade,
  title_id    text references games,
  first_played_at timestamptz,
  last_played_at  timestamptz,
  seconds_played  bigint not null default 0,
  trophies_earned int not null default 0,
  trophies_total  int,
  points          int not null default 0,     -- bronz 15, gümüş 30, altın 90, platin 300
  primary key (account_id, title_id)
);

create table trophy_sets (
  title_id  text references games,
  set_hash  text,                            -- oyunun kupa dosyasının hash'i
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
  rarity    real,                            -- earned_count / oyunun oyuncu sayısı, worker
  primary key (title_id, set_hash, trophy_id),
  foreign key (title_id, set_hash) references trophy_sets
);

create table earned_trophies (
  account_id uuid references accounts on delete cascade,
  title_id   text,
  set_hash   text,
  trophy_id  int,
  earned_at  timestamptz not null,
  flagged    boolean not null default false,  -- imkânsız örüntüler, liderlik tablolarından çıkarılır
  primary key (account_id, title_id, trophy_id),
  foreign key (title_id, set_hash, trophy_id) references trophies
);
create index earned_by_game on earned_trophies (title_id, trophy_id);

create table compatibility_reports (
  id         uuid primary key,
  account_id uuid references accounts on delete set null,
  title_id   text references games,
  verdict    text not null,                  -- nothing | menus | playable | perfect
  engine     text not null,                  -- örn. 0.2.13-arm
  platform   text not null,                  -- macos | windows | linux
  machine    text, os text,                  -- Mac modeli ya da CPU/GPU; işletim sistemi ve sürümü
  fps_avg    real,
  exit       text,
  note       text check (length(note) <= 500),
  created_at timestamptz not null default now()
);
```

## Sosyal

```sql
create table friendships (                   -- her çift için bir satır, user_a < user_b
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
  folded_into uuid references activities     -- bir saat içinde kazanılan birden çok kupa tek kayıtta birleşir
);
create index activities_actor on activities (actor_id, id desc);

create table activity_likes (activity_id uuid references activities on delete cascade, account_id uuid, primary key (activity_id, account_id));
create table activity_comments (id uuid primary key, activity_id uuid references activities on delete cascade, account_id uuid, text text not null);
```

## Mesajlar ve partiler

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
  seq        bigint not null,                -- conversations.last_seq + 1, aynı transaction içinde
  id         uuid not null unique,           -- istemcinin UUIDv7'si, yeniden denemeler için
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
create table calls (                         -- API tarafından kurulur; medyanın kendisi eşten eşe (P2P) akar
  id         uuid primary key,
  party_id   uuid references parties on delete set null,
  started_by uuid references accounts on delete set null,
  started_at timestamptz not null default now(),
  ended_at   timestamptz
);
create table call_quality (                  -- görüşme bittiğinde katılımcı başına bir satır
  call_id    uuid references calls on delete cascade,
  account_id uuid references accounts on delete set null,
  path       text not null,                  -- direct | relay-udp | relay-tls
  rtt_ms     real, loss real, glass_to_glass_ms real,
  share_play boolean not null default false
);

create table party_members (party_id uuid references parties on delete cascade, account_id uuid references accounts on delete cascade, joined_at timestamptz not null default now(), primary key (party_id, account_id));
```

## Temalar, sürümler, moderasyon

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

## Valkey'de (geçici)

| Anahtar | Değer | Süre |
|---|---|---|
| `presence:<user>` | hash: durum, title_id, başlangıç zamanı, cihazlar | 60 sn, heartbeat'lerle yenilenir |
| `events:<user>` | `resume` için son olayların stream'i | 5 dk'ya kırpılır |
| `rl:<scope>:<id>` | hız sınırı sayaçları | pencere süresi |
| `lb:<board>:<period>` | puana göre sıralı kullanıcı ID'leri kümesi (sorted set) | 10 dk'da bir yeniden oluşturulur |
| `devcode:<user_code>` | cihaz kodu durumu | 10 dk |

## Sayım

- **Oynama süresi**: oturumlar geldiğinde worker `ended_at - started_at` farkını `library` tablosuna
  ekler (oturumlar önce ID'ye göre tekilleştirilir; böylece yeniden gönderilen bir paket asla iki kez sayılmaz).
- **Nadirlik**: değişen her oyun için kupa başına `earned_count` (`earned_by_game` indeksini kullanan,
  `earned_trophies` üzerinde bir `count(*)`) ve `players` = oyunun `library` tablosundaki satır sayısı; `rarity = earned /
  players`. Oyun başına en sık 10 dakikada bir.
- **Puanlar**: bronz 15, gümüş 30, altın 90, platin 300; toplamı `library.points` alanına ve
  profilin `stats` alanına yazılır.

## Verilerin saklanması

| Veri | Saklama süresi |
|---|---|
| Hesap ve profil | silinene kadar (talepten 14 gün sonra) |
| Oturumlar, kupalar, kütüphane | hesap silinene kadar |
| Mesajlar | yazarı silene ya da hesap silinene kadar; silinen mesajların içeriği anında boşaltılır |
| Uyumluluk raporları | hesap silindiğinde anonimleştirilir (hesap alanı null yapılır) |
| İptal edilmiş oturumlar | 30 gün |
| Denetim kaydı | 1 yıl |
| Yedekler | 30 gün (gecelik); dolayısıyla bir silme işlemi 30 gün sonra yedeklerde de tamamlanmış olur |
