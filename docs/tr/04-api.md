# 4. API

Temel adres: `https://anytogether.kodla.agency/api/v1` (her şey için tek hostname; bkz. [Mimari](02-mimari.md)); kendi kurulan bir AnyTogether aynı yolları kendi hostname'inde yanıtlar. Giriş ve çıkış JSON, UTF-8; alan adları camelCase (`titleId`, `startedAt`), zamanlar UTC'de RFC 3339,
ID'ler UUIDv7 string'leri (zamana göre sıralanabilir). Hatalar RFC 9457 problem details biçimindedir:

```json
{ "type": "https://anytogether.kodla.agency/errors/handle-taken",
  "title": "That handle is taken", "status": 409, "code": "handle_taken" }
```

İstemciler `code` alanını kendi dillerine çevirir (launcher ve telefon zaten İngilizce ve Türkçe
içeriyor). Kod herkese açık ([github.com/utkuhalis/AnyTogether](https://github.com/utkuhalis/AnyTogether)):
bugün sözleşme `packages/shared` içindeki Zod şemalarıdır. Onlardan üretilecek, `/api/v1/openapi.json`
adresinde yayınlanacak bir OpenAPI 3.1 belgesi ve Swift, Dart ve TypeScript tipleri planlandı.

İstemciden gelen her istek, istemciyi ve platformu belirten `AnyTogether-Client` başlığını taşır:
`launcher-macos/0.2.13 (macOS 26.6; Mac15,9)`, `launcher-windows/0.3.0 (Windows 11 24H2)`,
`launcher-linux/0.3.0 (Fedora 41; KDE)`, `phone/1.10.0 (iOS 27.0)`, `web/…`. API bunu giriş yapmış
her cihazla birlikte kaydeder. Güvenli olamayacak kadar eski bir istemciyi `426 Upgrade Required` ile
(`upgrade_required` kodu, "AnyTogether'ı kullanmak için AnyPS5'i güncelle" olarak gösterilir) reddetmek planlandı.

Aşağıdaki her tablo neyin **yapıldığını** (2026-10-24'teki kodda) ve neyin **planlandığını** gösterir.

## 4.1 Giriş: tek dokunuş, kayıt formu yok

**Kayıt adımı da şifre de yoktur.** İlk giriş hesabı oluşturur; kullanıcı adı ve görünen ad
sağlayıcıdan ya da e-posta adresinden alınır (sonradan düzenlenebilir); sağlayıcıda varsa avatar da
alınır.

| Giriş yolu | Nerede | Kullanıcı ne yapar | Durum |
|---|---|---|---|
| **E-posta kodu** | her yerde | e-postayı yaz, ardından postadaki 6 haneli kodu gir (ya da içindeki bağlantıya tıkla); akılda tutulacak bir şey yok | yapıldı: web, macOS launcher'ı, telefon |
| **Passkey** | web sitesi (Touch ID, Windows Hello, bir telefon, bir parola yöneticisi) | giriş yaptıktan sonra Ayarlar'dan bir tane ekle; sonraki girişlerde hiç e-posta gerekmez | yapıldı: web |
| **Telefondan** | telefon uygulaması eşleşmiş ve giriş yapmış her launcher, ve tersi | launcher sorar, telefon "<Mac/PC adı> için giriş yapılsın mı?" der, tek dokunuş | yapıldı: macOS launcher'ı ve telefon |
| **Cihaz kodu** (yedek) | elinin altında tarayıcı olmayan bir launcher | launcher bir kod ve bir QR gösterir; web'de `/link` adresinde onaylanır | API'de ve web'de yapıldı |
| **Apple ile devam et** | macOS launcher'ı (yerel sayfa, Touch ID), iPhone (yerel), web | tek dokunuş | API yapıldı (sunucuya istemci ID'leri verilene kadar kapalı); düğmeler planlandı |
| **Google ile devam et** | her launcher (sistem tarayıcısı), Android (yerel Credential Manager), web | Google'da zaten oturum açıksa tek dokunuş | aynısı |
| **Discord ile devam et** | her launcher (sistem tarayıcısı), telefon, web | Discord'da zaten oturum açıksa tek dokunuş | aynısı |

**Launcher'lar sağlayıcıları nasıl kullanacak**: RFC 8252'nin yerel uygulamalar için istediği gibi,
sistem tarayıcısında PKCE ile OAuth 2.0. macOS, `ASWebAuthenticationSession` (tarayıcının
oturumlarını paylaşan bir sayfa; böylece Google ya da Discord genellikle tek tıktır) ve Apple için
`ASAuthorizationAppleIDProvider` kullanır; Windows ve Linux varsayılan tarayıcıyı açar ve sonucu bir
loopback yönlendirmesiyle alır (`http://127.0.0.1:<random port>/callback`). Telefon yerel Apple,
Google ve Discord akışlarını kullanır. Hepsi API'mizde son bulur: API, Apple'ın ve Google'ın ID
token'larını onların anahtarlarına ve bizim istemci ID'lerimize göre doğrular, Discord'un kodunu
(PKCE verifier ile) kullanıcı bilgisine çevirir ve kendi token'larımızı verir.

**Telefondan devir**, telefonla launcher'ın zaten paylaştığı yerel bağlantı üzerinden yürür (telefon
protokolü, [Platformlar](12-platformlar.md) 12.4): giriş yapmak isteyen taraf API'de bir devir başlatır
ve ID'sini bir `togetherHandoff` mesajıyla gönderir; giriş yapmış olan diğer taraf API'de onaylar ve
`togetherHandoffAnswer` ile yanıt verir; soran tarafın `/auth/token` yoklaması token'larını alır.
Eşleşmiş bir telefon giriş yapmış bir launcher'a sorduğunda anında onaylanır.

| Metot | Yol | Ne yapar | Durum |
|---|---|---|---|
| POST | `/auth/email/start` | `{email}` → 6 haneli bir kod ve bir bağlantı gönderir (10 dk geçerli) | yapıldı |
| POST | `/auth/email/verify` | `{email, code}` ya da `{email, link}` → token'lar; ilk kullanımda hesabı oluşturur | yapıldı |
| POST | `/auth/passkey/start` | → `navigator.credentials.get()` için `{challengeId, options}` (keşfedilebilir, 5 dk geçerli) | yapıldı |
| POST | `/auth/passkey/finish` | `{challengeId, response, deviceName?}` → token'lar | yapıldı |
| GET | `/auth/passkeys` | passkey'lerin (ad, senkronize olup olmadığı, eklenme, son kullanım) ve üst sınır, 10 | yapıldı |
| POST | `/auth/passkeys/start` | (giriş yapmış) → `navigator.credentials.create()` için seçenekler | yapıldı |
| POST | `/auth/passkeys` | (giriş yapmış) `{response, name?}` → yeni passkey | yapıldı |
| DELETE | `/auth/passkeys/{id}` | birini kaldır | yapıldı |
| POST | `/auth/oidc/{apple,google,discord}` | Apple, Google: `{idToken, nonce?}`; Discord: `{code, codeVerifier, redirectUri}` → token'lar; ilk kullanımda hesabı oluşturur | yapıldı |
| POST | `/auth/handoff/start` | (soran) `{deviceName}` → `{handoffId, secret, expiresIn}` (5 dk) | yapıldı |
| POST | `/auth/handoff/{id}/approve` | (giriş yapmış) → onaylar | yapıldı |
| POST | `/auth/device` | (yedek) `{deviceName}` → `deviceCode`, `userCode` (`XXXX-XXXX`), `verificationUri`, `expiresIn`, `interval` (RFC 8628) | yapıldı |
| POST | `/auth/device/approve` | (giriş yapmış) `{userCode}` → onaylar | yapıldı |
| POST | `/auth/token` | `{grantType: "refresh_token", refreshToken}`, `{grantType: "device_code", deviceCode}` ya da `{grantType: "handoff", handoffId, secret}` → token'lar; onaylanana kadar `authorization_pending` | yapıldı |
| POST | `/auth/logout` | bu oturumu iptal eder | yapıldı |
| GET | `/auth/sessions` | giriş yapmış cihazlar, bu cihaz işaretli | yapıldı |
| DELETE | `/auth/sessions` | her yerden çıkış; `?keep=current` bu cihazı tutar | yapıldı |
| DELETE | `/auth/sessions/{id}` | bir cihazın oturumunu kapat | yapıldı |
| GET | `/.well-known/jwks.json` | erişim token'larının genel anahtarı (gateway kullanır) | yapıldı |
| GET | `/auth/providers` | bu istemcinin sunabileceği giriş yolları | planlandı |
| POST | `/me/identities/{provider}` | başka bir giriş yolu bağla (tek hesapta Apple + Discord) | planlandı |

**Token'lar.** Erişim token'ı: kullanıcıyı ve oturumu belirten bir JWT (EdDSA, Ed25519, 15 dakika).
Yenileme token'ı: 256 rastgele bit, yalnızca SHA-256 hash'i olarak saklanır, 90 gün geçerlidir ve **her
kullanımda yenilenir**; eski bir token'ı yeniden kullanmak oturumu iptal eder (`refresh_reused`).
Platformun güvenli deposunda tutulur: macOS Keychain, Windows Credential Manager, Linux'ta Secret
Service (GNOME Keyring, KWallet), iOS Keychain, Android Keystore; web'de ise HttpOnly, Secure,
SameSite=Lax bir çerezde, yani tarayıcının kendisi hiçbir zaman token tutmaz.

**Passkey'ler.** Web sitesinin hostname'i (relying party) için WebAuthn keşfedilebilir kimlik
bilgileri; böylece tarayıcı e-posta sormadan onları önerir. Passkey'in içindeki kullanıcı tanıtıcısı
hesabın 16 baytlık ID'sidir; asla bir e-posta ya da kullanıcı adı değildir. Hesap başına en fazla 10.
Yasaklı bir hesap her yerde olduğu gibi burada da reddedilir; silinmeyi bekleyen bir hesaba giriş
yapmak onu korur.

## 4.2 Ben, profiller ve ayarlar

| Metot | Yol | Ne yapar | Durum |
|---|---|---|---|
| GET | `/me` | hesap, profil, gizlilik | yapıldı |
| PATCH | `/me/profile` | `displayName`, `bio` (160), `country`; adlar ve biyografiler bağlantı içeremez | yapıldı |
| PATCH | `/me/profile` | vitrin, profil teması | planlandı |
| PATCH | `/me/handle` | yeni kullanıcı adı (30 günde bir; eskisi 30 gün boyunca sana ayrılır ve hâlâ profile götürür) | yapıldı |
| PUT | `/me/avatar` | görselin kendisi (PNG ya da JPEG, 5 MB'a kadar) → meta verisi olmadan 256 px JPEG olarak yeniden kodlanır | yapıldı |
| DELETE | `/me/avatar` | kaldır | yapıldı |
| GET | `/avatars/{hash}.jpg` | baytlarının hash'iyle bir avatar (bir yıl önbelleğe alınır) | yapıldı |
| PATCH | `/me/privacy` | bölüm başına: `library`, `trophies`, `friends`, `presence`, `search`; her biri `everyone`, `friends` ya da `nobody` (bkz. Özellikler 3.5) | yapıldı |
| GET | `/me/export` | tüm verilerin tek bir JSON dosyası olarak, anında (KVKK/GDPR) | yapıldı |
| POST | `/me/deletion` | silmeyi onaylamak için 6 haneli bir kod gönderir; e-postası olmayan bir hesap kullanıcı adıyla onaylar | yapıldı |
| DELETE | `/me` | `{code}` ya da `{handle}` → hesap 14 gün sonra silinir; o zamana kadar giriş yapmak onu korur | yapıldı |
| GET | `/users/{handle}` | soranın görebileceği haliyle bir profil | yapıldı |
| GET | `/users/{handle}/friends` | gizliliği izin veriyorsa arkadaşları | yapıldı |
| GET | `/users/search?q=` | kullanıcı adına ya da ada göre kişi bul (`search` ayarı izin verenler) | yapıldı |
| PATCH | `/me/notifications` | hangi anlık bildirimler ve e-posta bildirimleri | planlandı |

## 4.3 Oyunlar, oturumlar ve kupalar

| Metot | Yol | Ne yapar | Durum |
|---|---|---|---|
| POST | `/me/devices` | bir bilgisayarı kaydet: `{id, platform, name, model?}` (launcher'ın kendi rastgele ID'si) | yapıldı |
| PUT | `/games/{titleId}` | kataloğa bir oyun öğret: dil başına adlar, ikon (bir moderatör kilitlediyse reddedilir) | yapıldı |
| GET | `/games/{titleId}` | katalog kaydı, kaç oyuncusu olduğu, kupa setleri | yapıldı |
| POST | `/me/sessions` | oturum grubu `{id, titleId, deviceId, startedAt, endedAt, exit?}` | yapıldı |
| GET | `/users/{handle}/library` | oyunlar, oynama süresi, son oynama, ilerleme | yapıldı |
| PUT | `/trophy-sets/{titleId}/{setHash}` | kupa seti: ID'ler, dereceler, gizli işaretleri, dil başına adlar ve açıklamalar | yapıldı |
| POST | `/me/trophies` | grup `{titleId, setHash, trophyId, earnedAt}`; tekrarlar yok sayılır; arkadaşlar `trophy.earned` alır | yapıldı |
| GET | `/users/{handle}/trophies?titleId=` | tarihleri ve nadirlikleriyle kazanılmış kupalar | yapıldı |
| POST | `/games/{titleId}/reports` | uyumluluk raporu (isteğe bağlı), bkz. Özellikler 3.7 | planlandı |

**Gruplama ve idempotency.** Launcher en fazla 200 öğelik gruplar gönderir. Oturumlar istemcinin
ürettiği bir UUID taşır, kupalar da hesap, oyun ve kupaya göre anahtarlanır; böylece bir grup zaman
aşımından sonra çift sayılmadan yeniden gönderilebilir. Yanıt her öğe için `stored`, `duplicate` ya da
bir kodla (`unknown_device`, `unknown_trophy` gibi) `rejected` listeler.

## 4.4 Arkadaşlar, çevrimiçi durumu, aktivite

| Metot | Yol | Ne yapar | Durum |
|---|---|---|---|
| GET | `/me/friends` | çevrimiçi durumlarıyla arkadaşlar | yapıldı |
| POST | `/me/friends/requests` | `{handle}` → istek (o sana zaten istek attıysa anında kabul edilir) | yapıldı |
| GET | `/me/friends/requests` | gelen ve giden | yapıldı |
| POST | `/me/friends/requests/{userId}/accept` / `decline` | | yapıldı |
| DELETE | `/me/friends/{userId}` | arkadaşlıktan çıkar | yapıldı |
| POST | `/me/blocks` / DELETE `/me/blocks/{userId}` | engelle, engeli kaldır | yapıldı |
| POST | `/me/friends/requests` | kısa ömürlü bir token için `GET /me/qr` ile birlikte `{qrToken}` | planlandı |
| GET | `/me/feed?before=` | arkadaşların aktivitesi, en yeniden eskiye, sayfa başına 30 | planlandı |
| POST / DELETE | `/activities/{id}/like`, POST `/activities/{id}/comments` | | planlandı |

Çevrimiçi durumu REST üzerinden ayarlanmaz; gerçek zamanlı soket üzerinden taşınır (4.7).

## 4.5 Mesajlar ve şikâyetler

Konuşmalar arkadaşlar arasındadır.

| Metot | Yol | Ne yapar | Durum |
|---|---|---|---|
| GET | `/me/conversations` | son mesajları ve okunmamış sayılarıyla konuşmalar | yapıldı |
| GET | `/me/conversations/unread` | rozet için toplam okunmamış | yapıldı |
| POST | `/conversations` | `{members, title?, group?}` → birebir (2 kişi, bir kez açılır ve yeniden kullanılır) ya da grup (en fazla 32) | yapıldı |
| GET / PATCH | `/conversations/{id}` | bir konuşma; grubu yeniden adlandır | yapıldı |
| POST | `/conversations/{id}/members` / DELETE `/conversations/{id}/members/{userId}` | gruba ekle; birini çıkar ya da ayrıl | yapıldı |
| GET | `/conversations/{id}/messages?after=&before=&limit=` | mesaj sırasına göre geçmiş (sayfa başına en fazla 100) | yapıldı |
| POST | `/conversations/{id}/messages` | `{clientId, text, replyTo?}`; metin en fazla 4000 karakter | yapıldı |
| PATCH / DELETE | `/conversations/{id}/messages/{seq}` | mesajını düzenle (15 dk) ya da sil | yapıldı |
| POST | `/conversations/{id}/read` | `{upToSeq}` | yapıldı |
| POST | `/reports` | `{targetKind: "user" \| "message", targetId, reason, note?}`; şikâyet edilen mesajın metni moderatörler için saklanır | yapıldı |
| POST | `/conversations/{id}/attachments` | → bir görsel için yükleme URL'si | planlandı |

## 4.6 Partiler, çağrılar, oyun oturumları, share play

Ses eşten eşedir (bkz. [Anlık iletişim](06-anlik-ses-birlikte-oynama.md)); API yalnızca çağrıları kurar
ve relay kimlik bilgilerini dağıtır. Oyun oturumları, arkadaşın oyununa katılmanın ve çevrimiçi
oyunun sunucu tarafıdır.

| Metot | Yol | Ne yapar | Durum |
|---|---|---|---|
| POST | `/parties` | `{privacy: "invite" \| "friends"}` → parti; soran lider olur (ve varsa başka partiden ayrılır) | yapıldı |
| GET | `/me/party` | içinde olduğum parti ve beni bekleyen davetler | yapıldı |
| GET / PATCH | `/parties/{id}` | üyeler, ne oynadıkları, çağrı; gizliliği değiştir (lider) | yapıldı |
| POST | `/parties/{id}/invites` | `{userIds}` (arkadaşlar) | yapıldı |
| POST | `/parties/{id}/join` / `decline` / `leave` | en fazla 8 üye | yapıldı |
| POST | `/parties/{id}/kick` / `leader` | `{userId}`: lider birini çıkarır ya da liderliği devreder | yapıldı |
| POST | `/calls` | `{partyId}` (partinin sesi) ya da `{userId}` (bir arkadaş) → çağrı, ICE sunucuları (STUN, 12 saat geçerli kimlik bilgileriyle TURN) | yapıldı |
| GET | `/calls/{id}` | içinde kim var, hangi cihazda | yapıldı |
| POST | `/calls/{id}/answer` / `decline` / `leave` | sana gelen bir çağrı, bu cihazda yanıtlandı; parti çağrısı son ses ayrılınca biter | yapıldı |
| GET | `/ice-servers` | süren bir çağrı için taze TURN kimlik bilgileri | yapıldı |
| POST | `/game-sessions` | `{titleId, gameVersion, engineBuild, capacity (2-16), joinable, properties (≤ 4 KB)}` → soranın yayıncı olduğu oturum | yapıldı |
| GET | `/me/game-session` | içinde oynadığım oturum ve beni bekleyen davetler | yapıldı |
| GET / PATCH / DELETE | `/game-sessions/{id}` | gör (oyuncular, davet edilenler ve katılınabilirken yayıncının arkadaşları); kapasiteyi, katılınabilirliği, özellikleri değiştir; bitir (yayıncı) | yapıldı |
| POST | `/game-sessions/{id}/invites` | `{userIds}` (arkadaşlar) | yapıldı |
| POST | `/game-sessions/{id}/join` | `{gameVersion, engineBuild}`; başka bir sürüm ya da derleme `version_mismatch`, dolu bir oturum `full` ile reddedilir | yapıldı |
| POST | `/game-sessions/{id}/decline` / `leave` | yayıncının ayrılması oturumu bitirir | yapıldı |
| POST / DELETE | `/calls/{id}/share-play` | yayıncı paylaşmayı başlatır ya da durdurur; üyelere bildirilir. Yalnızca izleme: hiçbir endpoint kontrolü bir izleyiciye vermez | planlandı |
| POST | `/calls/{id}/quality` | istemcinin sondaki raporu: doğrudan mı relay'li mi, gidiş-dönüş, kayıp, ekrandan ekrana örnekler | planlandı |

Offer'lar, answer'lar ve ICE adaylarının kendileri gateway üzerinden taşınır (`signal`, 4.7).

## 4.7 Gerçek zamanlı gateway

`wss://anytogether.kodla.agency/rt`. Yapıldı. İstemci kim olduğunu ilk çerçevede söyler (URL'de
değil; böylece asla loglara düşmez): launcher'lar ve telefon erişim token'larıyla, web sitesinin
tarayıcısı ise hiç token tutmadığı için sitenin sunucusunun istediği tek kullanımlık bir biletle
(`POST /realtime/ticket`, 30 sn geçerli):

```json
{ "op": "hello", "token": "<access token>", "client": "launcher-windows/0.3.0", "resume": "<last event id>" }
```

Sunucu `{"op":"ready","session":"…","heartbeat":25}` ile yanıt verir ve ardından olayları gönderir:

```json
{ "op": "event", "id": "…", "type": "message.created", "data": { … } }
```

İstemci her 25 sn'de bir (ve çevrimiçi durumu değiştiğinde hemen)
`{"op":"heartbeat","presence":{"state":"in_game","titleId":"PPSA01234","since":"…"}}` gönderir. İki heartbeat
kaçırmak soketi kapatır ve çevrimiçi durumunun süresi dolar. Yeniden bağlanırken son olay ID'siyle
`resume`, son 5 dakikada kaçırılanları yeniden oynatır (kullanıcı başına bir Valkey stream'inde
tutulur); daha eski boşluklar REST çağrılarıyla doldurulur. Kapanış kodları: 4001 merhaba yok ya da
hatalı, 4003 oturum kapatıldı, 4008 heartbeat yok, 4029 çok fazla çerçeve.

| Olay | Ne zaman | Durum |
|---|---|---|
| `presence.updated` | bir arkadaşın durumu ya da oyunu değişti; partisi ve katılınabilir oyun oturumu da | yapıldı |
| `friend.request`, `friend.accepted`, `friend.removed` | | yapıldı |
| `trophy.earned` | bir arkadaş kupa kazandı (gizli bir kupa adı olmadan) | yapıldı |
| `message.created`, `message.updated`, `message.deleted`, `conversation.read`, `conversation.updated` | | yapıldı |
| `party.invite`, `party.updated`, `party.member_joined`, `party.member_left`, `party.ended` | | yapıldı |
| `call.ringing`, `call.answered`, `call.joined`, `call.left`, `call.ended` | sana gelen bir çağrı; başka bir cihazda yanıtlandı; biri partinin sesine girdi ya da çıktı; bitti | yapıldı |
| `signal` | bir çağrı eşinden WebRTC offer, answer, ICE adayı, bye ya da renegotiate (aktarılır, asla saklanmaz) | yapıldı |
| `game_session.invite`, `game_session.updated`, `game_session.ended` | | yapıldı |
| `account.signed_out` | bu oturum başka bir yerden iptal edildi | yapıldı |
| `typing` | | planlandı |
| `share_play.started`, `share_play.stopped` | | planlandı |
| `activity.created` | akış için bir arkadaşın aktivitesi | planlandı |
| `trophy.rarity_changed` | sahip olduğun bir kupa bir nadirlik etiketini geçti | planlandı |

`auth.handoff` ortak tiplerde var; devrin kendisi telefonun yerel bağlantısından geçtiği için (4.1)
gateway bugün onu göndermiyor.

## 4.8 Temalar, indirmeler, liderlik tabloları

Hepsi planlandı.

| Metot | Yol | Ne yapar |
|---|---|---|
| GET | `/themes?sort=new\|popular\|liked&q=&cursor=` | Hub |
| GET | `/themes/{id}` | ayrıntılar, sürümler, yapan |
| POST | `/themes` | bir yükleme başlat → yükleme URL'si; ardından `POST /themes/{id}/publish` |
| POST | `/themes/{id}/versions` | temanın yeni bir sürümü |
| POST / DELETE | `/themes/{id}/like` | |
| GET | `/releases/latest?product=launcher\|phone` | sürüm, notlar, URL, SHA-256 |
| GET | `/leaderboards/{board}?scope=global\|friends&period=all\|month\|week` | seninki dahil sıralamalar |
| GET | `/games/{titleId}/leaderboard` | oyun başına |

## 4.9 Sınırlar

Adres başına ve hesap başına, Valkey'de sayılır (yapıldı):

| Ne | Sınır |
|---|---|
| Her istek | adres başına dakikada 600, hesap başına dakikada 300 |
| Giriş | adres başına 15 dakikada 30 deneme (istenen ve denenen kodlar, sağlayıcılar, passkey'ler, devirler); e-posta kodları: adres başına saatte 5, 10 yanlış deneme kodu bitirir |
| Token çağrıları | adres başına 10 dakikada 300 (yenilemeler, cihaz kodu yoklamaları; 4 sn'den sık bir yoklama `slow_down` alır) |
| Mesajlar | dakikada 30, günde 1000 |
| Arkadaşlık istekleri | günde 50 |
| Aramalar | dakikada 120 |
| Şikâyetler | günde 20 |
| Profil değişiklikleri | saatte 30; avatarlar saatte 10, her biri 5 MB |
| Başlatılan çağrılar | saatte 60; açılan oyun oturumları: saatte 120 |
| Eklenen passkey'ler | saatte 20 |
| Gruplar | 200 öğe |

Bir sınırı aşmak `Retry-After` ile `429` döndürür. Gateway'de: 10 saniyede 30 çerçeve, bir çağrının
kurulumu için 10 saniyede 300 sinyal.

## 4.10 Sürümleme

`/v1` uyumlu kalır: alanlar yalnızca eklenir. Geriye dönük uyumsuz bir değişiklik `/v2`'ye gider ve `/v1`,
`/v2`'ye geçen launcher sürümünden sonra en az altı ay çalışmaya devam eder.
