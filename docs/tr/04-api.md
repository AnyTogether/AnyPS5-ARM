# 4. API

Temel adres: `https://anytogether.kodla.agency/api/v1` (her şey için tek hostname; bkz. [Mimari](02-mimari.md)). Giriş ve çıkış JSON, UTF-8; zamanlar UTC'de RFC 3339,
ID'ler UUIDv7 string'leri (zamana göre sıralanabilir). Hatalar RFC 9457 problem details biçimindedir:

```json
{ "type": "https://anytogether.kodla.agency/errors/handle-taken",
  "title": "That handle is taken", "status": 409, "code": "handle_taken" }
```

İstemciler `code` alanını kendi dillerine çevirir (launcher ve telefon zaten İngilizce ve Türkçe
içeriyor). API, OpenAPI 3.1 belgesini `/api/v1/openapi.json` adresinde yayınlar; Swift,
Rust, Dart ve TypeScript tipleri bundan üretilir.

İstemciden gelen her istek, istemciyi ve platformu belirten `AnyTogether-Client` başlığını taşır:
`launcher-macos/0.2.13 (macOS 26.6; Mac15,9)`, `launcher-windows/0.3.0 (Windows 11 24H2)`,
`launcher-linux/0.3.0 (Fedora 41; KDE)`, `phone/1.10.0 (iOS 27.0)`, `web/…`. API, güvenli olamayacak kadar eski bir istemciyi
`426 Upgrade Required` ve launcher'ın "AnyTogether'ı kullanmak için AnyPS5'i güncelle" olarak gösterdiği bir `code` ile reddedebilir.

## 4.1 Giriş: tek dokunuş, kayıt formu yok

**Kayıt adımı da şifre de yoktur.** İlk giriş hesabı oluşturur; kullanıcı adı
ve görünen ad sağlayıcıdan alınır (sonradan düzenlenebilir); sağlayıcıda varsa avatar da
alınır.

| Giriş yolu | Nerede | Kullanıcı ne yapar |
|---|---|---|
| **Apple ile devam et** | macOS launcher'ı (yerel sayfa, Touch ID), iPhone (yerel), web | tek dokunuş |
| **Google ile devam et** | her launcher (sistem tarayıcısı), Android (yerel Credential Manager), web | Google'da zaten oturum açıksa tek dokunuş |
| **Discord ile devam et** | her launcher (sistem tarayıcısı), telefon, web | Discord'da zaten oturum açıksa tek dokunuş |
| **E-posta kodu** | her yerde | e-postayı yaz, ardından postadaki 6 haneli kodu gir (ya da içindeki bağlantıya tıkla); akılda tutulacak bir şey yok |
| **Telefondan** | telefon uygulaması eşleşmiş ve giriş yapmış her launcher | launcher sorar, telefon "<Mac/PC adı> için giriş yapılsın mı?" der, tek dokunuş |
| **Cihaz kodu** (yedek) | elinin altında tarayıcı olmayan bir launcher | launcher bir kod ve bir QR gösterir; telefonda ya da web'de onaylanır |
| Passkey'ler (ileride) | her yerde | Touch ID / Windows Hello / telefon |

**Launcher'lar bunu nasıl yapar**: RFC 8252'nin yerel uygulamalar için istediği gibi, sistem tarayıcısında PKCE ile
OAuth 2.0. macOS, `ASWebAuthenticationSession` (tarayıcının oturumlarını paylaşan bir sayfa; böylece Google
ya da Discord genellikle tek tıktır) ve Apple için `ASAuthorizationAppleIDProvider` kullanır; Windows ve Linux
varsayılan tarayıcıyı açar ve sonucu bir loopback yönlendirmesiyle alır
(`http://127.0.0.1:<random port>/callback`). Telefon yerel Apple, Google ve Discord akışlarını
kullanır. Hepsi, sağlayıcının ID token'ını (OpenID Connect) doğrulayıp kendi token'larımızı veren
API'mizde son bulur.

| Metot | Yol | Ne yapar |
|---|---|---|
| GET | `/auth/providers` | bu istemcinin sunabileceği giriş yolları |
| POST | `/auth/oidc/{apple,google,discord}` | sağlayıcının kodu (PKCE verifier ile) ya da ID token'ı → token'lar; ilk kullanımda hesabı oluşturur |
| POST | `/auth/email/start` | e-posta → 6 haneli bir kod ve bir sihirli bağlantı gönderir (10 dk geçerli) |
| POST | `/auth/email/verify` | e-posta + kod (ya da bağlantının token'ı) → token'lar |
| POST | `/auth/handoff/start` | (launcher) cihaz adı → kullanıcının giriş yapmış telefonlarına iletilen bir handoff ID'si |
| POST | `/auth/handoff/{id}/approve` | (telefon, giriş yapmış) → onaylar; launcher'ın yoklaması token'ları alır |
| POST | `/auth/device` | (yedek) → `device_code`, `user_code`, `verification_uri`, `interval` (RFC 8628) |
| POST | `/auth/device/approve` | (giriş yapmış) `user_code` → onaylar |
| POST | `/auth/token` | `grant_type=refresh_token`, `device_code` ya da `handoff` → token'lar |
| POST | `/auth/logout` | bu oturumu iptal eder |
| GET / DELETE | `/auth/sessions`, `/auth/sessions/{id}` | giriş yapmış cihazlar; birinin oturumunu kapat |
| POST | `/me/identities/{provider}` | başka bir giriş yolu bağla (tek hesapta Apple + Discord) |

**Token'lar.** Erişim token'ı: kullanıcıyı, oturumu ve kapsamları içeren bir JWT (EdDSA, 15 dakika).
Yenileme token'ı: 256 rastgele bit, yalnızca SHA-256 hash'i olarak saklanır, 90 gün geçerlidir ve **her
kullanımda yenilenir**; eski bir token'ı yeniden kullanmak oturumu iptal eder. Platformun güvenli deposunda tutulur: macOS Keychain,
Windows Credential Manager, Linux'ta Secret Service (GNOME Keyring, KWallet), iOS Keychain,
Android Keystore; web'de ise HttpOnly, Secure, SameSite=Lax bir çerezde.

## 4.2 Ben, profiller ve ayarlar

| Metot | Yol | Ne yapar |
|---|---|---|
| GET | `/me` | hesap, profil, ayarlar, sayılar |
| PATCH | `/me/profile` | görünen ad, biyografi, ülke, vitrin, profil teması |
| PATCH | `/me/handle` | yeni kullanıcı adı (30 günde bir) |
| POST | `/me/avatar` | → imzalı R2 yükleme URL'si; ardından dosyayı `PUT` et; ardından `POST /me/avatar/confirm` |
| PATCH | `/me/privacy` | öğe başına görünürlük (bkz. Özellikler 3.5) |
| PATCH | `/me/notifications` | hangi anlık bildirimler ve e-posta bildirimleri |
| POST | `/me/export` | tam veri dışa aktarımını sıraya al (e-postayla gelen bağlantıdan zip), KVKK/GDPR |
| DELETE | `/me` | hesabı sil (fikrini değiştirmek için 14 gün) |
| GET | `/users/{handle}` | bir profil, soran kişinin görebileceği haliyle |
| GET | `/users/search?q=` | kullanıcıları kullanıcı adına ya da ada göre bul (trigram), yalnızca doğrulanmış hesaplar |

## 4.3 Oyunlar, oturumlar ve kupalar

| Metot | Yol | Ne yapar |
|---|---|---|
| PUT | `/games/{title_id}` | kataloğa bir oyun öğret: dil başına adlar, ikon yükleme URL'si (yalnızca oyun bilinmiyorsa ya da soran güvenilirse) |
| GET | `/games/{title_id}` | katalog kaydı, topluluk uyumluluğu, nadirlik özeti |
| POST | `/me/sessions` | oturum grubu `{id, title_id, mac_id, started_at, ended_at, exit}` |
| GET | `/users/{handle}/library` | oyunlar, oynama süresi, son oynama, ilerleme |
| PUT | `/trophy-sets/{title_id}/{set_hash}` | kupa seti: ID'ler, dereceler, gizli bayrakları, dil başına adlar/açıklamalar, ikon yükleme URL'leri |
| POST | `/me/trophies` | grup `{title_id, set_hash, trophy_id, earned_at}`; tekrarlar yok sayılır |
| GET | `/users/{handle}/trophies?title_id=` | tarihleri ve nadirlikleriyle kazanılmış kupalar |
| POST | `/games/{title_id}/reports` | uyumluluk raporu (isteğe bağlı), bkz. Özellikler 3.7 |

**Gruplama ve idempotency.** Launcher'ın giden kutusu en fazla 200 öğelik gruplar gönderir. Her öğe
istemcinin ürettiği bir UUIDv7 taşır; sunucu bunu saklar ve ikinci kopyayı yok sayar; böylece bir grup,
zaman aşımından sonra çift sayım olmadan yeniden gönderilebilir. Yanıt her öğe için `stored`,
`duplicate` ya da bir kodla birlikte `rejected` döndürür.

## 4.4 Arkadaşlar, çevrimiçi durumu, aktivite

| Metot | Yol | Ne yapar |
|---|---|---|
| GET | `/me/friends` | çevrimiçi durumlarıyla arkadaşlar |
| POST | `/me/friends/requests` | `{handle}` ya da `{qr_token}` → istek |
| GET | `/me/friends/requests` | gelen ve giden |
| POST | `/me/friends/requests/{id}/accept` / `decline` | |
| DELETE | `/me/friends/{user_id}` | arkadaşlıktan çıkar |
| POST | `/me/blocks` / DELETE `/me/blocks/{user_id}` | engelle, engeli kaldır |
| GET | `/me/feed?before=` | arkadaşların aktivitesi, en yeniden eskiye, sayfa başına 30 |
| POST | `/activities/{id}/like` / DELETE | |
| POST | `/activities/{id}/comments` | |
| GET | `/me/qr` | arkadaş ekleme QR'ı için kısa ömürlü bir token |

Çevrimiçi durumu REST üzerinden ayarlanmaz; gerçek zamanlı soket üzerinden taşınır (4.7).

## 4.5 Mesajlar

| Metot | Yol | Ne yapar |
|---|---|---|
| GET | `/me/conversations` | son mesajı ve okunmamış sayısıyla konuşmalar |
| POST | `/conversations` | `{members: [...], title?}` → birebir (2 kişi, yeniden kullanılır) ya da grup |
| GET | `/conversations/{id}/messages?after=&before=&limit=` | mesaj sırasına göre geçmiş |
| POST | `/conversations/{id}/messages` | `{client_id, text?, attachments?, reply_to?}` |
| PATCH / DELETE | `/conversations/{id}/messages/{seq}` | mesajını düzenle (15 dk) ya da sil |
| POST | `/conversations/{id}/read` | `{up_to_seq}` |
| POST | `/conversations/{id}/attachments` | → imzalı yükleme URL'si |
| POST | `/messages/{id}/report` | |

## 4.6 Partiler, çağrılar, share play

Ses ve share play (birlikte oynama) eşten eşe (P2P) çalışır (bkz. [Anlık iletişim](06-anlik-ses-birlikte-oynama.md)); API
yalnızca çağrıları kurar ve relay (aktarma sunucusu) kimlik bilgilerini dağıtır.

| Metot | Yol | Ne yapar |
|---|---|---|
| POST | `/parties` | `{privacy}` → parti (soran kişi sahibidir) |
| GET | `/parties/{id}` | üyeler, ne oynadıkları, çağrı ve share play durumu |
| POST | `/parties/{id}/invites` | `{user_ids}` |
| POST | `/parties/{id}/join` / `leave` | |
| POST | `/calls` | `{party_id}` ya da `{user_id}` → çağrı ID'si, ICE sunucuları (STUN, 12 saat geçerli kimlik bilgileriyle TURN) |
| GET | `/ice-servers` | süren bir çağrı için taze TURN kimlik bilgileri |
| POST | `/calls/{id}/share-play` | yayıncı paylaşımı başlatır; üyelere haber verilir |
| POST | `/calls/{id}/share-play/controller` | `{user_id, slot}` bir üyeye kontrolcü yuvası ver ya da geri al |
| DELETE | `/calls/{id}/share-play` | paylaşımı durdur |
| POST | `/calls/{id}/quality` | istemcinin sondaki raporu: doğrudan mı relay üzerinden mi, gidiş-dönüş süresi, kayıp, ekrandan ekrana gecikme örnekleri |

Offer'lar, answer'lar ve ICE adaylarının kendisi gateway üzerinden taşınır (`signal`, 4.7).

## 4.7 Gerçek zamanlı gateway

`wss://anytogether.kodla.agency/rt`. İstemci erişim token'ını ilk frame'de gönderir
(URL'de değil; böylece asla loglara düşmez):

```json
{ "op": "hello", "token": "<access token>", "client": "launcher-windows/0.3.0", "resume": "<last event id>" }
```

Sunucu `{"op":"ready","session":"…","heartbeat":25}` ile yanıt verir ve ardından olayları gönderir:

```json
{ "op": "event", "id": "01J…", "type": "message.created", "data": { … } }
```

İstemci her 25 sn'de bir (ve çevrimiçi durumu değiştiğinde hemen) `{"op":"heartbeat","presence":{"state":"in_game","title_id":"PPSA01234","since":"…"}}`
gönderir. Art arda iki heartbeat'in kaçırılması soketi kapatır ve çevrimiçi durumunun süresi dolar. Yeniden bağlanırken
son olay ID'siyle `resume`, son 5 dakika içinde kaçırılanları yeniden oynatır (kullanıcı başına bir Valkey
stream'inde tutulur); daha eski boşluklar REST çağrılarıyla doldurulur.

| Olay | Ne zaman |
|---|---|
| `presence.updated` | bir arkadaşın durumu ya da oyunu değişti |
| `friend.request`, `friend.accepted`, `friend.removed` | |
| `message.created`, `message.updated`, `message.deleted`, `conversation.read`, `typing` | |
| `party.invite`, `party.updated`, `party.member_joined`, `party.member_left`, `party.ended` | |
| `call.ringing`, `call.answered`, `call.ended` | sana gelen bir çağrı, başka bir cihazda yanıtlandı, bitti |
| `signal` | bir çağrı eşinden WebRTC offer, answer, ICE adayı ya da bye (aktarılır, asla saklanmaz) |
| `share_play.started`, `share_play.controller_changed`, `share_play.stopped` | |
| `auth.handoff` | (telefon) bir launcher giriş yapılmasını istiyor |
| `activity.created` | akış için bir arkadaşın aktivitesi |
| `trophy.rarity_changed` | sahip olduğun bir kupa bir nadirlik etiketinin sınırını geçti |
| `account.signed_out` | bu oturum başka bir yerden iptal edildi |

## 4.8 Temalar, indirmeler, liderlik tabloları

| Metot | Yol | Ne yapar |
|---|---|---|
| GET | `/themes?sort=new\|popular\|liked&q=&cursor=` | Hub |
| GET | `/themes/{id}` | ayrıntılar, sürümler, yapımcı |
| POST | `/themes` | yüklemeyi başlat → imzalı URL; ardından `POST /themes/{id}/publish` |
| POST | `/themes/{id}/versions` | temanın yeni bir sürümü |
| POST / DELETE | `/themes/{id}/like` | |
| GET | `/releases/latest?product=launcher\|phone` | sürüm, notlar, URL, SHA-256 |
| GET | `/leaderboards/{board}?scope=global\|friends&period=all\|month\|week` | seninki dahil sıralamalar |
| GET | `/games/{title_id}/leaderboard` | oyun başına |

## 4.9 Sınırlar

Hesap başına (ve kimlik doğrulaması yapılmamış çağrılar için Cloudflare'de IP başına):

| Ne | Sınır |
|---|---|
| Giriş denemeleri | e-posta kodları: adres başına saatte 5 gönderim, 10 yanlış kod adresi 15 dk kilitler; IP başına 30 deneme |
| Mesajlar | dakikada 30, günde 1000 |
| Arkadaşlık istekleri | günde 50 |
| Yüklemeler | avatar 5 MB, görsel 10 MB, tema 300 MB (launcher'ın kendi sınırı) |
| Gruplar | 200 öğe, 1 MB |

Bir sınırı aşmak `Retry-After` ile birlikte `429` döndürür.

## 4.10 Sürümleme

`/v1` uyumlu kalır: alanlar yalnızca eklenir. Geriye dönük uyumluluğu bozan bir değişiklik `/v2`'ye gider ve `/v1`,
`/v2`'ye geçen launcher sürümünden sonra en az altı ay çalışmaya devam eder.
