# 5. Veri modeli

PostgreSQL 17. ID'ler UUIDv7'dir (zamana göre sıralı olduğu için indeksler kompakt kalır ve ID'ler oluşturulma sırasına göre dizilir).
Zamanlar `timestamptz` türündedir. Her tabloda `created_at` bulunur.

Aşağıdaki tablolar **yapılmış** olanlardır; 2026-10-24'te
[`packages/db/src/schema.ts`](https://github.com/utkuhalis/AnyTogether/blob/main/packages/db/src/schema.ts)
içindeki Drizzle şemasının tanımladığı gibi, burada SQL olarak ve kısaltılarak yazıldı (`created_at` ve
indekslerin çoğu atlandı). **Planlanan** tablolar onlardan sonra gelir.

## Hesaplar ve giriş

```sql
create table accounts (
  id            uuid primary key,
  email         citext unique,              -- sağlayıcıdan ya da e-posta kodundan; boş olabilir
  role          text not null default 'user',-- user | moderator | admin
  status        text not null default 'active', -- active | banned | deleting
  delete_after  timestamptz                  -- DELETE /me ile ayarlanır, 14 gün sonrası
);

create table identities (                    -- giriş yolları
  account_id uuid not null references accounts on delete cascade,
  provider   text not null,                  -- apple | google | discord | email
  subject    text not null,                  -- sağlayıcıdaki kullanıcı ID'si; e-posta için adresin kendisi
  primary key (provider, subject)
);

create table sessions (                      -- giriş yapmış bir cihaz
  id            uuid primary key,
  account_id    uuid not null references accounts on delete cascade,
  client        text not null,               -- launcher-macos | launcher-windows | launcher-linux | phone | web
  device_name   text,
  refresh_hash  bytea not null,              -- geçerli yenileme token'ının sha256'sı
  previous_hash bytea,                       -- bir öncekininki, yeniden kullanımı yakalamak için
  expires_at    timestamptz not null,        -- 90 gün
  last_seen_at  timestamptz,
  revoked_at    timestamptz
);

create table passkeys (                      -- WebAuthn keşfedilebilir kimlik bilgileri, hesap başına en fazla 10
  id           text primary key,             -- doğrulayıcının kimlik bilgisi ID'si
  account_id   uuid not null references accounts on delete cascade,
  name         text not null check (length(name) <= 60),
  public_key   bytea not null,               -- COSE, tarayıcının gönderdiği gibi
  counter      bigint not null default 0,    -- senkronize passkey'lerin çoğu hep 0 gönderir
  transports   jsonb not null default '[]',
  device_type  text not null,                -- singleDevice | multiDevice (senkronize)
  backed_up    boolean not null default false,
  last_used_at timestamptz
);

create table sign_in_requests (              -- e-posta kodları, telefondan devirler, cihaz kodları; kısa ömürlü
  id           uuid primary key,
  kind         text not null check (kind in ('email', 'handoff', 'device')),
  email        citext,                        -- e-posta kodları için
  code_hash    bytea,                         -- 6 haneli kod, hash'lenmiş
  link_hash    bytea,                         -- postadaki bağlantının token'ı, hash'lenmiş
  secret_hash  bytea,                         -- devir sırrı ya da cihaz kodu, hash'lenmiş
  user_code    text unique,                   -- cihaz kodları: XXXX-XXXX, 0/O/1/I yok
  client       text,
  device_name  text,
  approved_by  uuid references accounts on delete cascade,
  attempts     int not null default 0,
  last_polled_at timestamptz,
  consumed_at  timestamptz,
  expires_at   timestamptz not null
);
```

Passkey challenge'ları (5 dakika), gateway biletleri (30 saniye) ve hesap silme kodları (10 dakika)
tablolarda değil, Valkey'de durur.

## Profiller ve cihazlar

```sql
create table profiles (
  account_id   uuid primary key references accounts on delete cascade,
  handle       citext unique not null,
  handle_changed_at timestamptz,
  display_name text not null,
  bio          text check (length(bio) <= 160),
  country      text,
  avatar_url   text,                          -- /api/v1/avatars/<hash>.jpg ya da sağlayıcının resmi
  privacy      jsonb not null default '{}',   -- library, trophies, friends, presence, search: everyone | friends | nobody
  stats        jsonb not null default '{}'    -- planlandı: oyunlar, saatler, kupalar, platinler
);

create table handle_history (                -- bırakılmış bir kullanıcı adı, son sahibi için 30 gün tutulur
  handle      citext primary key,
  account_id  uuid not null references accounts on delete cascade,
  released_at timestamptz not null default now()
);

create table avatars (                       -- meta verisiz 256 px JPEG; yalnızca güncel olan tutulur
  hash       text primary key,               -- baytların hash'i; böylece bir görselin URL'si hiç değişmez
  account_id uuid not null references accounts on delete cascade,
  bytes      bytea not null
);

create table devices (                       -- launcher'ın rastgele ID'siyle kullanıcının bilgisayarları
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
  names      jsonb not null default '{}',    -- {"en": "Hollow Knight: Silksong", "tr": ...}; taslak satırda boş
  icon_url   text,
  taught_by  uuid references accounts on delete set null,
  locked     boolean not null default false  -- bir moderatör düzeltti; launcher'lar değiştiremez
);

create table play_sessions (
  id         uuid primary key,               -- launcher tarafından üretilir (idempotent)
  account_id uuid not null references accounts on delete cascade,
  title_id   text not null references games,
  device_id  uuid references devices on delete set null,
  started_at timestamptz not null,
  ended_at   timestamptz not null check (ended_at > started_at),
  exit       text                            -- normal | crashed | killed (launcher'ın teşhisi)
);
create index on play_sessions (account_id, title_id, started_at desc);

create table library (                       -- kullanıcı ve oyun başına; oturum ya da kupa geldikçe yeniden hesaplanır
  account_id  uuid not null references accounts on delete cascade,
  title_id    text not null references games,
  first_played_at timestamptz,
  last_played_at  timestamptz,
  seconds_played  bigint not null default 0,
  trophies_earned int not null default 0,
  trophies_total  int,
  points          int not null default 0,     -- bronz 15, gümüş 30, altın 90, platin 300
  primary key (account_id, title_id)
);

create table trophy_sets (
  title_id  text not null references games,
  set_hash  text not null,                   -- oyunun kupa dosyasının hash'i
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
  rarity    real,                            -- earned_count / oyunun oyuncuları, 0..1
  primary key (title_id, set_hash, trophy_id),
  foreign key (title_id, set_hash) references trophy_sets
);

create table earned_trophies (
  account_id uuid not null references accounts on delete cascade,
  title_id   text not null,
  set_hash   text not null,
  trophy_id  int not null,
  earned_at  timestamptz not null,
  flagged    boolean not null default false,  -- imkânsız örüntüler, liderlik tablolarının dışında (işaretleme planlandı)
  primary key (account_id, title_id, trophy_id),
  foreign key (title_id, set_hash, trophy_id) references trophies
);
create index earned_by_game on earned_trophies (title_id, trophy_id);
```

Kupa ikonları henüz saklanmıyor.

## Sosyal ve moderasyon

```sql
create table friendships (                   -- çift başına bir satır, user_a < user_b
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
  target_kind text not null,                 -- user | message (ileride activity, theme, game_name)
  target_id   text not null,
  reason      text not null,                 -- spam | harassment | hate | sexual | impersonation | cheating | piracy | other
  note        text check (length(note) <= 500),
  snapshot    jsonb,                         -- şikâyet edilen mesajın o anki hali; yazarı silse de tutulur
  status      text not null default 'open',  -- open | actioned | dismissed
  handled_by  text,
  handled_at  timestamptz
);
-- şikâyet eden ve hedef başına tek açık şikâyet

create table bans (                          -- bir hesaba, bir e-postaya (yalnızca SHA-256'sı tutulur) ya da ikisine
  id         uuid primary key,
  account_id uuid references accounts on delete set null,
  email_hash bytea,
  reason     text,
  created_by text,
  expires_at timestamptz,                    -- null: kaldırılana kadar
  lifted_at  timestamptz
);

create table audit_log (id uuid primary key, actor_id uuid, action text not null, target text, data jsonb);
```

## Mesajlar

```sql
create table conversations (
  id         uuid primary key,
  kind       text not null check (kind in ('direct', 'group')),
  title      text,
  direct_key text unique,                    -- "küçük:büyük" kullanıcı ID'si; bir çiftin tek birebir konuşması olur
  created_by uuid references accounts on delete set null,
  last_seq   bigint not null default 0,
  updated_at timestamptz not null default now(), -- son mesaj ya da değişiklik, listeyi sıralamak için
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
  seq        bigint not null,                -- conversations.last_seq + 1, aynı transaction içinde
  id         uuid not null unique,           -- istemcinin UUID'si, yeniden denemeler için
  author_id  uuid references accounts on delete set null,
  text       text check (length(text) <= 4000),
  attachments jsonb not null default '[]',   -- yüklemeler gelene kadar boş kalır
  reply_to   bigint,
  edited_at  timestamptz,
  deleted_at timestamptz,                    -- silinen bir mesaj anında boşaltılır
  primary key (conversation_id, seq)
);
```

## Partiler, çağrılar, oyun oturumları

```sql
create table parties (                       -- en fazla sekiz kişi
  id        uuid primary key,
  leader_id uuid references accounts on delete set null,
  privacy   text not null default 'invite' check (privacy in ('invite', 'friends')),
  ended_at  timestamptz
);
create table party_members (                 -- biri aynı anda tek bir partide olabilir
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

create table calls (                         -- API kurar; medyanın kendisi eşten eşedir
  id          uuid primary key,
  party_id    uuid references parties on delete set null,
  started_by  uuid references accounts on delete set null,
  callee_id   uuid references accounts on delete set null, -- iki arkadaş arasındaki bir çağrı
  started_at  timestamptz not null default now(),
  answered_at timestamptz,
  ended_at    timestamptz
);
-- parti başına tek açık çağrı

create table game_sessions (                 -- bir launcher'ın arkadaşları katılsın diye açtığı oyun; yayıncı başına tek açık
  id           uuid primary key,
  host_id      uuid not null references accounts on delete cascade,
  title_id     text not null references games,
  game_version text not null,                -- "01.000.002", launcher'ın okuduğu gibi
  engine_build text not null,                -- yalnızca aynı derlemenin kendisiyle konuşabileceğine güvenilir
  capacity     int not null check (capacity between 2 and 16),
  joinable     boolean not null default true,
  properties   jsonb not null default '{}',  -- en fazla 4 KB, launcher'ların belirlediği
  ended_at     timestamptz
);
create table game_session_players (          -- yayıncı dahil; biri aynı anda tek bir oturumda oynar
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

Bir çağrıda kimin sinyal gönderebileceği ve şu an kimin içinde olduğu `calls` tablosunda değil, Valkey'de tutulur.

## Planlanan tablolar

```sql
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
  note       text check (length(note) <= 500)
);

create table activities (
  id         uuid primary key,
  actor_id   uuid not null references accounts on delete cascade,
  kind       text not null,                  -- trophy | platinum | new_game | long_session | completed | clip | theme | joined
  payload    jsonb not null,
  visibility text not null,                  -- everyone | friends
  folded_into uuid references activities     -- bir saat içindeki birkaç kupa tek öğe olur
);
create index activities_actor on activities (actor_id, id desc);
create table activity_likes (activity_id uuid references activities on delete cascade, account_id uuid, primary key (activity_id, account_id));
create table activity_comments (id uuid primary key, activity_id uuid references activities on delete cascade, account_id uuid, text text not null);

create table call_quality (                  -- bir çağrının sonunda katılımcı başına bir satır
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

Mevcut tablolarda da planlananlar: `profiles.theme_id` ve `showcase`, bir partinin çağrısında
`share_play` durumu (kim yayınlıyor, ne zamandan beri; kontrolcü yuvası yok, share play yalnızca
izlemedir), partiler için bağlantıyla gizlilik.

## Valkey'de (geçici)

| Anahtar | Değer | Süre |
|---|---|---|
| `presence:<user>:<session>` | bir cihazın durumu, title ID'si, başlangıç zamanı | 60 sn, heartbeat'lerle yenilenir |
| `presence:<user>` | kullanıcının cihazları üzerinden birleştirilmiş çevrimiçi durumu, parti ve oyun oturumuyla | 70 sn |
| `presence-extra:<user>` | çevrimiçi durumunda gösterilen parti ve katılınabilir oyun oturumu | sürdükleri sürece |
| `presence-hidden:<user>` | kullanıcının çevrimiçi durumu hiç kimseye görünmezken ayarlıdır | ayarlı olduğu sürece |
| `friends:<user>` | gateway'in çevrimiçi durumu dağıtımı için kullanıcının arkadaşları | API tarafından tutulur |
| `events:<user>` | `resume` için son olayların stream'i | 5 dk'ya kırpılır |
| `user:<user>` | gateway'in dinlediği pub/sub kanalı | - |
| `call:<id>:members`, `call:<id>:in` | bir çağrıda kimin sinyal gönderebileceği; kimin hangi cihazda içinde olduğu | 12 saat |
| `rt-ticket:<hash>` | web sitesi için tek kullanımlık gateway bileti | 30 sn |
| `passkey:register:<user>`, `passkey:signin:<id>` | bir passkey challenge'ı | 5 dk |
| `revoked:<session>` | kapatılmış bir oturum; API ve gateway reddeder | erişim token'ının ömrü |
| `rl:<name>:<who>:<window>` | hız sınırı sayaçları | pencere süresi |
| `lb:<board>:<period>` | puana göre sıralı kullanıcı ID'leri kümesi (planlandı) | 10 dk'da bir yeniden oluşturulur |

## Sayım

- **Oynama süresi**: oturumlar geldiğinde, dokundukları oyunların kütüphane satırları oturumlardan
  yeniden hesaplanır (oturumlar önce ID'ye göre tekilleştirilir; böylece yeniden gönderilen bir paket asla iki kez sayılmaz).
- **Nadirlik**: bir oyun için kupalar geldiğinde, kupa başına `earned_count` (`earned_by_game` indeksini
  kullanan, `earned_trophies` üzerinde bir `count(*)`) ve `players` = oyunun `library` tablosundaki satır
  sayısı; `rarity = earned / players`. Etiketler: yaygın > %50, az yaygın %20-50, nadir %5-20, çok nadir
  %1-5, ultra nadir < %1.
- **Puanlar**: bronz 15, gümüş 30, altın 90, platin 300; toplamı `library.points` alanına yazılır;
  profilin `stats` alanı planlandı.

## Verilerin saklanması

| Veri | Saklama süresi |
|---|---|
| Hesap ve profil | silinene kadar (talepten 14 gün sonra); 14 gün dolunca saatlik temizlikte silinir |
| Oturumlar, kupalar, kütüphane | hesap silinene kadar |
| Mesajlar | yazarı silene ya da hesap silinene kadar; silinen mesajların içeriği anında boşaltılır |
| Şikâyet edilen mesajlar | metinleri moderatörler için şikâyette kalır |
| Uyumluluk raporları (planlandı) | hesap silindiğinde anonimleştirilir (hesap alanı null yapılır) |
| Denetim kaydı | 1 yıl |
| Yedekler | 30 gün (gecelik); dolayısıyla bir silme işlemi 30 gün sonra yedeklerde de tamamlanmış olur |
