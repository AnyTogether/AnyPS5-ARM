# 4. API

Temel adres: `https://api.anytogether.kodla.agency/v1`. Giriş ve çıkış JSON, UTF-8; zamanlar UTC'de
RFC 3339 biçiminde, kimlikler UUIDv7 dizesi (zamana göre sıralanabilir). Hatalar RFC 9457 problem
ayrıntısı biçimindedir:

```json
{ "type": "https://anytogether.kodla.agency/errors/handle-taken",
  "title": "That handle is taken", "status": 409, "code": "handle_taken" }
```

İstemciler `code` alanını kendi dillerine çevirir (launcher ve telefon zaten İngilizce ve Türkçe
destekliyor). API, OpenAPI 3.1 belgesini `/v1/openapi.json` adresinde yayımlar; Swift ve Dart
tipleri bu belgeden üretilir.

İstemciden gelen her istek `AnyTogether-Client: launcher/0.2.13 (macOS 26.6; Mac15,9)` başlığını
taşır (ya da `phone/1.10.0 (iOS 27.0)`, `web/…`). API, güvenli kullanılamayacak kadar eski bir
istemciyi `426 Upgrade Required` ve launcher'ın "AnyTogether'ı kullanmak için AnyPS5'i güncelleyin"
olarak gösterdiği bir `code` ile reddedebilir.

## 4.1 Giriş ve oturumlar

Üç giriş yolu, tek hesap:

1. **E-posta ve parola** (web'de ve telefonda): parola Argon2id ile özetlenir
   (m=64 MB, t=3, p=1); hesabın başkaları tarafından bulunabilmesi için e-posta önce 6 haneli bir
   kodla doğrulanır.
2. Web'de ve telefonda **Sign in with Apple** ve **Discord** (OAuth 2.0 / OpenID Connect);
   doğrulanmış e-posta üzerinden ya da ayarlardan mevcut bir hesaba bağlanır.
3. Launcher için (ve TV'ler ya da klavyesi olmayan her cihaz için) **cihaz bağlama**: OAuth 2.0
   Device Authorization Grant, RFC 8628. Launcher bir kod ve bir QR gösterir; kullanıcı telefondan
   ya da web'den onaylar. Launcher ile yerel ağ üzerinden zaten eşleşmiş olan telefon uygulaması
   tek dokunuşla onaylayabilir.

| Yöntem | Yol | Ne yapar |
|---|---|---|
| POST | `/auth/register` | e-posta, parola, kullanıcı adı → doğrulama kodu gönderir |
| POST | `/auth/verify-email` | kod → hesap doğrulanır |
| POST | `/auth/login` | e-posta, parola → token'lar |
| POST | `/auth/oauth/{apple,discord}` | sağlayıcının kodu ya da ID token'ı → token'lar |
| POST | `/auth/device` | istemci, cihaz adı → `device_code`, `user_code`, `verification_uri`, `interval` |
| POST | `/auth/device/approve` | (giriş yapılmış) `user_code` → o cihazı onaylar |
| POST | `/auth/token` | `grant_type=device_code` ya da `refresh_token` → token'lar |
| POST | `/auth/logout` | bu oturumu iptal eder |
| GET | `/auth/sessions` | hesabın giriş yapılmış cihazları |
| DELETE | `/auth/sessions/{id}` | bir cihazın oturumunu kapatır |
| POST | `/auth/password/forgot`, `/auth/password/reset` | e-postayla kod gönderir, yeni parola belirler |

**Token'lar.** Erişim token'ı; kullanıcı kimliğini, oturum kimliğini ve yetki kapsamlarını taşıyan
bir JWT'dir (EdDSA, 15 dakika). Yenileme token'ı rastgele 256 bitlik bir dizedir, yalnızca SHA-256
özeti olarak saklanır, 60 gün geçerlidir ve **her kullanımda yenilenir**; eski bir token'ın yeniden
kullanılması tüm oturumu iptal eder (hırsızlık tespiti). Launcher yenileme token'ını macOS
Keychain'de, telefon iOS Keychain'de ya da Android Keystore destekli depolamada, web ise HttpOnly,
Secure, SameSite=Lax bir çerezde tutar.

## 4.2 Ben, profiller ve ayarlar

| Yöntem | Yol | Ne yapar |
|---|---|---|
| GET | `/me` | hesap, profil, ayarlar, sayılar |
| PATCH | `/me/profile` | görünen ad, biyografi, ülke, vitrin, profil teması |
| PATCH | `/me/handle` | yeni kullanıcı adı (30 günde bir) |
| POST | `/me/avatar` | → önceden imzalanmış R2 yükleme URL'si; ardından dosya `PUT` edilir; ardından `POST /me/avatar/confirm` |
| PATCH | `/me/privacy` | öğe başına görünürlük (bkz. Özellikler 3.5) |
| PATCH | `/me/notifications` | hangi anlık bildirimlerin ve e-postaların gönderileceği |
| POST | `/me/export` | tam veri dışa aktarımını kuyruğa alır (e-postayla gelen bağlantıdan zip), KVKK/GDPR |
| DELETE | `/me` | hesabı siler (fikir değiştirmek için 14 gün) |
| GET | `/users/{handle}` | bir profil, isteyenin görmesine izin verildiği kadarıyla |
| GET | `/users/search?q=` | kullanıcıları kullanıcı adına ya da isme göre bulur (trigram), yalnızca doğrulanmış hesaplar |

## 4.3 Oyunlar, oturumlar ve kupalar

| Yöntem | Yol | Ne yapar |
|---|---|---|
| PUT | `/games/{title_id}` | kataloğa bir oyunu tanıtır: dil başına adlar, ikon yükleme URL'si (yalnızca oyun bilinmiyorsa ya da isteyen güvenilir biriyse) |
| GET | `/games/{title_id}` | katalog kaydı, topluluk uyumluluğu, nadirlik özeti |
| POST | `/me/sessions` | oturum grubu `{id, title_id, mac_id, started_at, ended_at, exit}` |
| GET | `/users/{handle}/library` | oyunlar, oynama süresi, son oynanma, ilerleme |
| PUT | `/trophy-sets/{title_id}/{set_hash}` | kupa seti: kimlikler, dereceler, gizli işaretleri, dil başına adlar/açıklamalar, ikon yükleme URL'leri |
| POST | `/me/trophies` | grup `{title_id, set_hash, trophy_id, earned_at}`; tekrarlar yok sayılır |
| GET | `/users/{handle}/trophies?title_id=` | kazanılan kupalar, tarihleri ve nadirlikleriyle |
| POST | `/games/{title_id}/reports` | uyumluluk raporu (isteğe bağlı), bkz. Özellikler 3.7 |

**Gruplama ve idempotency.** Launcher'ın giden kutusu en fazla 200 öğelik gruplar gönderir. Her öğe
istemcinin ürettiği bir UUIDv7 taşır; sunucu bunu saklar ve ikinci kopyayı yok sayar, böylece bir
grup zaman aşımından sonra çift sayım olmadan yeniden gönderilebilir. Yanıt, her öğe için `stored`,
`duplicate` ya da bir kodla birlikte `rejected` döndürür.

## 4.4 Arkadaşlar, çevrimiçi durumu, aktivite

| Yöntem | Yol | Ne yapar |
|---|---|---|
| GET | `/me/friends` | arkadaşlar, çevrimiçi durumlarıyla |
| POST | `/me/friends/requests` | `{handle}` ya da `{qr_token}` → istek |
| GET | `/me/friends/requests` | gelen ve giden istekler |
| POST | `/me/friends/requests/{id}/accept` / `decline` | |
| DELETE | `/me/friends/{user_id}` | arkadaşlıktan çıkarır |
| POST | `/me/blocks` / DELETE `/me/blocks/{user_id}` | engeller, engeli kaldırır |
| GET | `/me/feed?before=` | arkadaşların aktiviteleri, en yeniden eskiye, sayfa başına 30 |
| POST | `/activities/{id}/like` / DELETE | |
| POST | `/activities/{id}/comments` | |
| GET | `/me/qr` | arkadaş ekleme QR'ı için kısa ömürlü bir token |

Çevrimiçi durumu REST üzerinden ayarlanmaz; anlık iletişim soketi üzerinden taşınır (4.7).

## 4.5 Mesajlar

| Yöntem | Yol | Ne yapar |
|---|---|---|
| GET | `/me/conversations` | sohbetler, son mesaj ve okunmamış sayısıyla |
| POST | `/conversations` | `{members: [...], title?}` → birebir (2 kişi, yeniden kullanılır) ya da grup |
| GET | `/conversations/{id}/messages?after=&before=&limit=` | geçmiş, mesaj sırasına göre |
| POST | `/conversations/{id}/messages` | `{client_id, text?, attachments?, reply_to?}` |
| PATCH / DELETE | `/conversations/{id}/messages/{seq}` | kendi mesajını düzenler (15 dk) ya da siler |
| POST | `/conversations/{id}/read` | `{up_to_seq}` |
| POST | `/conversations/{id}/attachments` | → önceden imzalanmış yükleme URL'si |
| POST | `/messages/{id}/report` | |

## 4.6 Partiler, ses, Share play

| Yöntem | Yol | Ne yapar |
|---|---|---|
| POST | `/parties` | `{privacy}` → parti (isteyen kişi sahibi olur) |
| GET | `/parties/{id}` | üyeler, ne oynadıkları, Share play durumu |
| POST | `/parties/{id}/invites` | `{user_ids}` |
| POST | `/parties/{id}/join` / `leave` | |
| POST | `/parties/{id}/voice-token` | → LiveKit URL'si ve oda token'ı (ses yayınlama/abone olma) |
| POST | `/parties/{id}/share-play` | ev sahibi paylaşımı başlatır → video yayınlayabilen bir token; üyeler izleyici token'ı alır |
| POST | `/parties/{id}/share-play/controller` | `{user_id, slot}` bir üyeye kumanda yuvası verir ya da geri alır |
| DELETE | `/parties/{id}/share-play` | durdurur |

Oda token'ları tam olarak gereken izinleri taşır: izleyiciler abone olabilir; `pad` konusuna veri
ise yalnızca ev sahibi onlara bir yuva verdiyse gönderebilir. İzin değiştiğinde token yeniden
verilir.

## 4.7 Anlık iletişim gateway'i

`wss://rt.anytogether.kodla.agency/v1/socket`. İstemci erişim token'ını URL'de değil ilk çerçevede
gönderir (böylece token hiçbir zaman loglara düşmez):

```json
{ "op": "hello", "token": "<access token>", "client": "launcher/0.2.13", "resume": "<last event id>" }
```

Sunucu `{"op":"ready","session":"…","heartbeat":25}` ile yanıt verir ve ardından olayları gönderir:

```json
{ "op": "event", "id": "01J…", "type": "message.created", "data": { … } }
```

İstemci her 25 sn'de bir (ve çevrimiçi durumu değiştiğinde hemen)
`{"op":"heartbeat","presence":{"state":"in_game","title_id":"PPSA01234","since":"…"}}` gönderir.
Art arda iki heartbeat kaçırılırsa soket kapanır ve çevrimiçi durumu sona erer. Yeniden bağlanırken
son olay kimliğiyle gönderilen `resume`, son 5 dakikada kaçırılanları yeniden oynatır (kullanıcı
başına bir Valkey stream'inde tutulur); daha eski boşluklar REST çağrılarıyla doldurulur.

| Olay | Ne zaman |
|---|---|
| `presence.updated` | bir arkadaşın durumu ya da oyunu değişti |
| `friend.request`, `friend.accepted`, `friend.removed` | |
| `message.created`, `message.updated`, `message.deleted`, `conversation.read`, `typing` | |
| `party.invite`, `party.updated`, `party.member_joined`, `party.member_left`, `party.ended` | |
| `share_play.started`, `share_play.controller_changed`, `share_play.stopped` | |
| `activity.created` | akış için bir arkadaşın aktivitesi |
| `trophy.rarity_changed` | sahip olduğun bir kupa bir nadirlik etiketinin sınırını geçti |
| `account.signed_out` | bu oturum başka bir yerden iptal edildi |

## 4.8 Temalar, indirmeler, liderlik tabloları

| Yöntem | Yol | Ne yapar |
|---|---|---|
| GET | `/themes?sort=new\|popular\|liked&q=&cursor=` | Hub |
| GET | `/themes/{id}` | ayrıntılar, sürümler, hazırlayan |
| POST | `/themes` | yüklemeyi başlatır → önceden imzalanmış URL; ardından `POST /themes/{id}/publish` |
| POST | `/themes/{id}/versions` | temanın yeni bir sürümü |
| POST / DELETE | `/themes/{id}/like` | |
| GET | `/releases/latest?product=launcher\|phone` | sürüm, notlar, URL, SHA-256 |
| GET | `/leaderboards/{board}?scope=global\|friends&period=all\|month\|week` | sıralamalar, seninkiyle birlikte |
| GET | `/games/{title_id}/leaderboard` | oyun başına |

## 4.9 Sınırlar

Hesap başına (kimlik doğrulaması olmayan çağrılar için de Cloudflare'de IP başına):

| Ne | Sınır |
|---|---|
| Giriş denemeleri | hesap başına 15 dk'da 10, IP başına 30 |
| Mesajlar | dakikada 30, günde 1000 |
| Arkadaşlık istekleri | günde 50 |
| Yüklemeler | avatar 5 MB, görsel 10 MB, tema 300 MB (launcher'ın kendi sınırı) |
| Gruplar | 200 öğe, 1 MB |

Bir sınırın aşılması `Retry-After` ile birlikte `429` döndürür.

## 4.10 Sürümleme

`/v1` uyumlu kalır: yalnızca alan eklenir. Uyumu bozan bir değişiklik `/v2`'ye gider ve `/v1`,
`/v2`'ye geçen launcher sürümünden sonra en az altı ay çalışmaya devam eder.
