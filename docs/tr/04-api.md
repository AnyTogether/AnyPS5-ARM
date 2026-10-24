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
`launcher-macos/0.2.15 (macOS 26.6; Mac15,9)`, `launcher-windows/0.1.1 (Windows 11 24H2)`,
`launcher-linux/0.1.1 (Fedora 41; KDE)`, `phone/1.11.0 (iOS 27.0)`, `web/…`. API bunu giriş yapmış
her cihazla birlikte kaydeder. Güvenli olamayacak kadar eski bir istemciyi `426 Upgrade Required` ile
(`upgrade_required` kodu, "AnyTogether'ı kullanmak için AnyPS5'i güncelle" olarak gösterilir) reddetmek planlandı.

Aşağıdaki her tablo neyin **yapıldığını** (2026-10-25'teki kodda) ve neyin **planlandığını** gösterir.

## 4.1 Giriş: tek dokunuş, kayıt formu yok

**Kayıt adımı da şifre de yoktur.** İlk giriş hesabı oluşturur; kullanıcı adı ve görünen ad
sağlayıcıdan ya da e-posta adresinden alınır (sonradan düzenlenebilir); sağlayıcıda varsa avatar da
alınır.

| Giriş yolu | Nerede | Kullanıcı ne yapar | Durum |
|---|---|---|---|
| **E-posta kodu** | her yerde | e-postayı yaz, ardından postadaki 6 haneli kodu gir (ya da içindeki bağlantıya tıkla); akılda tutulacak bir şey yok | yapıldı: web, iki launcher, telefon |
| **Passkey** | web sitesi (Touch ID, Windows Hello, bir telefon, bir parola yöneticisi) | giriş yaptıktan sonra Ayarlar'dan bir tane ekle; sonraki girişlerde hiç e-posta gerekmez | yapıldı: web |
| **Telefondan** | telefon uygulaması eşleşmiş ve giriş yapmış her launcher, ve tersi | launcher sorar, telefon "<Mac/PC adı> için giriş yapılsın mı?" der, tek dokunuş | yapıldı: iki launcher ve telefon |
| **Cihaz kodu** | elinin altında tarayıcı olan bir launcher: passkey'ler ve web sitesinin diğer giriş yolları orada çalışır | launcher bir kod gösterir ve `/link` adresini açar; orada onaylanır | yapıldı: API, web, iki launcher |
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
| GET / PATCH | `/me/discovery` | `{discoverable, languages}`: "<oyun> oynayanlar" listesinde, önerilerde ve oyun sayfalarında görünmek (`null` kütüphane ayarını izler) ve oynadığın en fazla 5 dil | yapıldı |
| GET | `/me/export` | tüm verilerin tek bir JSON dosyası olarak, anında (KVKK/GDPR); konuşmalar ve gönderdiğin şikâyetler dahil | yapıldı |
| POST | `/me/deletion` | silmeyi onaylamak için 6 haneli bir kod gönderir; e-postası olmayan bir hesap kullanıcı adıyla onaylar | yapıldı |
| DELETE | `/me` | `{code}` ya da `{handle}` → hesap 14 gün sonra silinir; o zamana kadar giriş yapmak onu korur | yapıldı |
| GET | `/users/{handle}` | soranın görebileceği haliyle bir profil | yapıldı |
| GET | `/users/{handle}/friends` | gizliliği izin veriyorsa arkadaşları | yapıldı |
| GET | `/users/search?q=` | kullanıcı adına ya da ada göre kişi bul (`search` ayarı izin verenler) | yapıldı |

## 4.3 Oyunlar, oturumlar ve kupalar

| Metot | Yol | Ne yapar | Durum |
|---|---|---|---|
| POST | `/me/devices` | bir bilgisayarı kaydet: `{id, platform, name, model?}` (launcher'ın kendi rastgele ID'si) | yapıldı |
| PUT | `/games/{titleId}` | kataloğa bir oyun öğret: dil başına adlar, ikon (bir moderatör kilitlediyse reddedilir; ikon URL'si yalnızca operatörün listelediği bir hosttan) | yapıldı |
| GET | `/games/{titleId}` | katalog kaydı, kaç oyuncusu olduğu, kupa setleri | yapıldı |
| POST | `/me/sessions` | oturum grubu `{id, titleId, deviceId, startedAt, endedAt, exit?}` | yapıldı |
| GET | `/users/{handle}/library` | oyunlar, oynama süresi, son oynama, ilerleme | yapıldı |
| PUT | `/trophy-sets/{titleId}/{setHash}` | kupa seti: ID'ler, dereceler, gizli işaretleri, dil başına adlar ve açıklamalar | yapıldı |
| POST | `/me/trophies` | grup `{titleId, setHash, trophyId, earnedAt}`; tekrarlar yok sayılır; arkadaşlar `trophy.earned` alır | yapıldı |
| GET | `/users/{handle}/trophies?titleId=` | tarihleri ve nadirlikleriyle kazanılmış kupalar | yapıldı |

**Gruplama ve idempotency.** Launcher en fazla 200 öğelik gruplar gönderir. Oturumlar istemcinin
ürettiği bir UUID taşır, kupalar da hesap, oyun ve kupaya göre anahtarlanır; böylece bir grup zaman
aşımından sonra çift sayılmadan yeniden gönderilebilir. Yanıt her öğe için `stored`, `duplicate` ya da
bir kodla (`unknown_device`, `unknown_trophy` gibi) `rejected` listeler.

## 4.4 Arkadaşlar, çevrimiçi durumu, aktivite, liderlik tabloları

| Metot | Yol | Ne yapar | Durum |
|---|---|---|---|
| GET | `/me/friends` | çevrimiçi durumlarıyla arkadaşlar | yapıldı |
| POST | `/me/friends/requests` | `{handle}` → istek (o sana zaten istek attıysa anında kabul edilir) | yapıldı |
| GET | `/me/friends/requests` | gelen ve giden | yapıldı |
| POST | `/me/friends/requests/{userId}/accept` / `decline` | | yapıldı |
| DELETE | `/me/friends/{userId}` | arkadaşlıktan çıkar | yapıldı |
| POST | `/me/blocks` / DELETE `/me/blocks/{userId}` | engelle, engeli kaldır | yapıldı |
| GET | `/me/feed?before=&limit=` | arkadaşların aktivitesi, en yeniden eskiye, sayfa başına 30 (en fazla 50) | yapıldı |
| GET | `/users/{handle}/activity?before=` | bir kişinin aktivitesi, soranın görebileceği haliyle | yapıldı |
| PUT / DELETE | `/activities/{id}/reaction` | `{reaction: "fire" \| "clap" \| "wow" \| "heart"}`, öğe başına kişi başına bir tane | yapıldı |
| GET | `/leaderboards/points?scope=friends\|global` | toplam kupa puanı: en fazla 100 kayıt, senin sıran ve değerin, çevrendeki kişiler, toplam | yapıldı |
| GET | `/games/{titleId}/leaderboard?by=points\|time\|completion&scope=` | tek bir oyunun tablosu | yapıldı |
| GET | `/leaderboards/games` | tablosu seçilebilecek oyunlar: önce seninkiler, sonra en çok oynananlar | yapıldı |
| POST | `/me/friends/requests` | kısa ömürlü bir token için `GET /me/qr` ile birlikte `{qrToken}` | planlandı |
| GET | `/leaderboards/...?period=month\|week` | bu ayın ve bu haftanın tabloları | planlandı |

Çevrimiçi durumu REST üzerinden ayarlanmaz; gerçek zamanlı soket üzerinden taşınır (4.8).

## 4.5 Mesajlar, bildirimler ve şikâyetler

Konuşmalar arkadaşlar arasındadır.

| Metot | Yol | Ne yapar | Durum |
|---|---|---|---|
| GET | `/me/conversations` | son mesajları ve okunmamış sayılarıyla konuşmalar | yapıldı |
| GET | `/me/conversations/unread` | rozet için toplam okunmamış | yapıldı |
| POST | `/conversations` | `{members, title?, group?}` → birebir (2 kişi, bir kez açılır ve yeniden kullanılır) ya da grup (en fazla 32) | yapıldı |
| GET / PATCH | `/conversations/{id}` | bir konuşma; grubu yeniden adlandır | yapıldı |
| POST | `/conversations/{id}/members` / DELETE `/conversations/{id}/members/{userId}` | gruba ekle; birini çıkar ya da ayrıl | yapıldı |
| GET | `/conversations/{id}/messages?after=&before=&limit=` | mesaj sırasına göre geçmiş (sayfa başına en fazla 100) | yapıldı |
| POST | `/conversations/{id}/messages` | `{clientId, text, replyTo?}`; metin en fazla 4000 karakter, engel listesindeki bir alan adına bağlantı yok (`link_blocked`) | yapıldı |
| PATCH / DELETE | `/conversations/{id}/messages/{seq}` | mesajını düzenle (15 dk) ya da sil | yapıldı |
| POST | `/conversations/{id}/read` | `{upToSeq}` | yapıldı |
| GET | `/me/notifications?before=` | bildirimler, en yeniden eskiye, sayfa başına 30 | yapıldı |
| GET | `/me/notifications/unread` | zil için okunmamış sayısı | yapıldı |
| POST | `/me/notifications/read-all`, `/me/notifications/{id}/read` | okundu olarak işaretle; kişinin diğer cihazları da bunu duyar | yapıldı |
| GET / PATCH | `/me/notifications/settings` | her türü aç ya da kapat, e-posta özeti (`digest`); yanıt ayrıca bu sunucunun anlık bildirim gönderip göndermediğini VAPID anahtarıyla birlikte söyler | yapıldı |
| POST / DELETE | `/me/push` | bu tarayıcının anlık bildirim aboneliği (`PushSubscription.toJSON()` ve bir dil), tarayıcının girişine bağlı | yapıldı |
| POST | `/reports` | `{targetKind: "user" \| "message" \| "theme" \| "lfg", targetId, reason, note?}`; şikâyet edilen şey (bir mesajın metni, bir ilanın notu, bir temanın adı ve sürümü) moderatörler için saklanır | yapıldı |
| POST | `/conversations/{id}/attachments` | → bir görsel için yükleme URL'si | planlandı |

## 4.6 Partiler, çağrılar, oyun oturumları, share play

Ses ve share play (birlikte oynama) eşten eşedir (bkz. [Anlık iletişim](06-anlik-ses-birlikte-oynama.md));
API yalnızca onları kurar ve relay kimlik bilgilerini dağıtır. Oyun oturumları, arkadaşın oyununa
katılmanın ve çevrimiçi oyunun sunucu tarafıdır.

| Metot | Yol | Ne yapar | Durum |
|---|---|---|---|
| POST | `/parties` | `{privacy: "invite" \| "friends", public?}` → parti; soran lider olur (ve varsa başka partiden ayrılır) | yapıldı |
| GET | `/me/party` | içinde olduğum parti ve beni bekleyen davetler | yapıldı |
| GET / PATCH | `/parties/{id}` | üyeler, ne oynadıkları, çağrı; gizliliği ya da herkese açık listelemeyi `{join: "request" \| "open", titleId?, language?}` veya `null` olarak değiştir (lider) | yapıldı |
| POST | `/parties/{id}/invites` | `{userIds}` (arkadaşlar) | yapıldı |
| POST | `/parties/{id}/join` / `decline` / `leave` | en fazla 8 üye | yapıldı |
| POST | `/parties/{id}/kick` / `leader` | `{userId}`: lider birini çıkarır ya da liderliği devreder | yapıldı |
| GET | `/parties/public?titleId=&language=` | soranın görebileceği, herkese açık listelenen partiler | yapıldı |
| POST | `/parties/{id}/requests`, DELETE `/parties/{id}/requests/me` | "istekle" listelenen bir partiye katılmak iste ya da isteği geri al | yapıldı |
| POST | `/parties/{id}/requests/{userId}/accept` / `decline` | lider yanıt verir; evet bir davettir | yapıldı |
| POST | `/calls` | `{partyId}` (partinin sesi) ya da `{userId}` (bir arkadaş) → çağrı, ICE sunucuları (STUN, 12 saat geçerli kimlik bilgileriyle TURN) | yapıldı |
| GET | `/calls/{id}` | içinde kim var, hangi cihazda, kim sessizde | yapıldı |
| POST | `/calls/{id}/answer` / `decline` / `leave` | sana gelen bir çağrı, bu cihazda yanıtlandı; parti çağrısı son ses ayrılınca biter | yapıldı |
| POST | `/calls/{id}/mute` | `{muted}`: diğerleri bunu görür | yapıldı |
| GET | `/ice-servers` | süren bir çağrı için taze TURN kimlik bilgileri | yapıldı |
| POST | `/game-sessions` | `{titleId, gameVersion, engineBuild, capacity (2-16), joinable, properties (≤ 4 KB)}` → soranın yayıncı olduğu oturum | yapıldı |
| GET | `/me/game-session` | içinde oynadığım oturum ve beni bekleyen davetler | yapıldı |
| GET / PATCH / DELETE | `/game-sessions/{id}` | gör (oyuncular, davet edilenler ve katılınabilirken yayıncının arkadaşları); kapasiteyi, katılınabilirliği, özellikleri değiştir; bitir (yayıncı) | yapıldı |
| PUT | `/game-sessions/{id}/members/me` | `{properties}` (≤ 2 KB): bu oyuncunun kendi özellikleri, oynadığı cihazla birlikte | yapıldı |
| GET | `/game-sessions/{id}/ice-servers` | oturumun oyuncuları için relay kimlik bilgileri | yapıldı |
| POST | `/game-sessions/{id}/invites` | `{userIds}` (arkadaşlar) | yapıldı |
| POST | `/game-sessions/{id}/join` | `{gameVersion, engineBuild}`; başka bir sürüm ya da derleme `version_mismatch`, dolu bir oturum `full` ile reddedilir | yapıldı |
| POST | `/game-sessions/{id}/decline` / `leave` | yayıncının ayrılması oturumu bitirir | yapıldı |
| POST | `/share-plays` | `{titleId, title?, open (friends walk in, default true), maxViewers (1-4, default 2), public?}` (`open`: arkadaşlar davetsiz girebilir) → bu cihazın yayıncı olduğu share play ve ICE sunucuları; yayıncının önceki share play'i biter | yapıldı |
| GET | `/me/share-play` | yayıncısı olduğum share play, izlediğim share play ve beni bekleyen davetler | yapıldı |
| GET / PATCH / DELETE | `/share-plays/{id}` | gör (kumandalarıyla izleyiciler; yayıncı için davet edilenler ve istekler de); oyunu, `open`, `maxViewers` ve herkese açık listelemeyi değiştir; durdur (yayıncı) | yapıldı |
| POST | `/share-plays/{id}/invites` / `decline` | yayıncı arkadaşlarını davet eder; davet edilen reddeder | yapıldı |
| POST | `/share-plays/{id}/join` | bu cihazda izle → share play ve ICE sunucuları; yeniden katılmak koltuğu buraya taşır ve kumandayı korur; dolu bir share play `full` ile reddedilir | yapıldı |
| POST | `/share-plays/{id}/leave` | izlemeyi bırak | yapıldı |
| PUT | `/share-plays/{id}/viewers/{userId}/slot` | `{slot: 2 \| 3 \| 4 \| null}`: yayıncı bir izleyiciye kumanda verir ya da geri alır; izleyici başına bir kumanda, kumanda başına bir izleyici. 1. oyuncu asla verilmez: o yayıncınındır | yapıldı |
| DELETE | `/share-plays/{id}/viewers/{userId}` | yayıncı bir izleyiciyi çıkarır; ancak yeniden davet edilirse geri gelebilir | yapıldı |
| GET | `/share-plays/{id}/ice-servers` | yayıncı ya da bir izleyici için taze relay kimlik bilgileri | yapıldı |
| GET | `/share-plays/public?titleId=&language=&live=1` | herkese açık listelenen share play'ler; `live=1` yalnızca "Şu an canlı" altındakileri bırakır | yapıldı |
| POST | `/share-plays/{id}/requests`, DELETE `/share-plays/{id}/requests/me` | "istekle" listelenen bir share play'e katılmak iste ya da isteği geri al | yapıldı |
| POST | `/share-plays/{id}/requests/{userId}/accept` / `decline` | yayıncı yanıt verir; evet bir davettir | yapıldı |
| POST | `/calls/{id}/quality` | istemcinin sondaki raporu: doğrudan mı relay'li mi, gidiş-dönüş, kayıp, ekrandan ekrana örnekler | planlandı |

Offer'lar, answer'lar ve ICE adaylarının kendileri gateway üzerinden taşınır (`signal`, 4.8).

## 4.7 Oyuncu bulma

Bunların herhangi birinde kimin görüneceği engellere (iki yönde de) ve her kişinin gizlilik ayarlarına uyar.

| Metot | Yol | Ne yapar | Durum |
|---|---|---|---|
| GET | `/lfg?titleId=&purpose=&language=&now=1&before=` | oyuncu arama panosu, en yeniden eskiye; `now=1` yarım saat içinde başlayacakları bırakır | yapıldı |
| GET | `/lfg/games` | açık ilanı olan oyunlar | yapıldı |
| GET | `/me/lfg` | ilanlarım ve kimlerin katılmak istediği; katılmak istediğim ilanlar | yapıldı |
| POST | `/lfg` | `{titleId, purpose: "coop" \| "online" \| "party" \| "trophies", startsAt?, languages (1-3), region?, slots, note? (140), expiresAt?}`; co-op'ta 3 oyunculuk, diğerlerinde 7 oyunculuk daha yer var; en fazla 3 açık ilan | yapıldı |
| GET / DELETE | `/lfg/{id}` | bir ilan; kapat (ilan sahibi) | yapıldı |
| POST | `/lfg/{id}/requests`, DELETE `/lfg/{id}/requests/me` | "Ben varım" ya da geri al | yapıldı |
| POST | `/lfg/{id}/requests/{userId}/accept` / `decline` | ilan sahibi yanıt verir; evet, oyuncuyu ilan sahibinin share play'ine (co-op) ya da partisine davet eder ve bir yeri doldurur | yapıldı |
| GET | `/discover/players?titleId=` | bir oyunu oynayan ve kütüphanesini gösteren kişiler | yapıldı |
| GET | `/discover/suggestions` | tanıyor olabileceğin kişiler: ortak arkadaşlar, ikinizin de oynadığı oyunlar, ortak bir dil | yapıldı |
| GET | `/games/{titleId}/hub` | bir oyunun sayfası: şu an kimin oynadığı, açık ilanlar, herkese açık partiler ve share play'ler, oyunu gösteren oyuncular | yapıldı |

## 4.8 Gerçek zamanlı gateway

`wss://anytogether.kodla.agency/rt`. Yapıldı. İstemci kim olduğunu ilk çerçevede söyler (URL'de
değil; böylece asla loglara düşmez): launcher'lar ve telefon erişim token'larıyla, web sitesinin
tarayıcısı ise hiç token tutmadığı için sitenin sunucusunun istediği tek kullanımlık bir biletle
(`POST /realtime/ticket`, 30 sn geçerli):

```json
{ "op": "hello", "token": "<access token>", "client": "launcher-windows/0.1.1", "resume": "<last event id>" }
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
hatalı, 4003 oturum kapatıldı, 4008 heartbeat yok, 4029 çok fazla çerçeve ya da sinyal. Bir kullanıcı
tek bir gateway sürecinde 20 soket tutabilir.

İstemcinin heartbeat'ler dışında gönderdikleri:

| Çerçeve | Ne yapar |
|---|---|
| `{"op":"signal","to":…,"device":…,"call" \| "session" \| "share":…,"kind":…,"data":…}` | aynı çağrının bir üyesine, aynı oyun oturumunun bir oyuncusuna ya da bir share play'in yayıncısıyla bir izleyicisi arasında (asla izleyiciden izleyiciye değil) WebRTC sinyalleşmesi; aktarılır, asla saklanmaz |
| `{"op":"typing","conversation":…}` | konuşmanın diğer üyelerine "yazıyorum", en fazla iki saniyede bir |
| `{"op":"watch","topics":["lfg","discover:PPSA01234",…]}` | bu soketin izlediği herkese açık konular (en fazla 8): pano, herkese açık listeler, tümü ya da tek bir oyununki |

| Olay | Ne zaman | Durum |
|---|---|---|
| `presence.updated` | bir arkadaşın durumu ya da oyunu değişti; partisi, katılınabilir oyun oturumu ve share play'i de | yapıldı |
| `friend.request`, `friend.accepted`, `friend.removed` | | yapıldı |
| `trophy.earned` | bir arkadaş kupa kazandı (gizli bir kupa adı olmadan) | yapıldı |
| `feed.item` | bir arkadaşın aktivite öğesi; yeni ya da içine yeni kupalar katılmış | yapıldı |
| `message.created`, `message.updated`, `message.deleted`, `conversation.read`, `conversation.updated`, `typing` | | yapıldı |
| `notification`, `notification.read` | yeni okunmamış sayısıyla yeni bir bildirim; bir cihazda okundu | yapıldı |
| `party.invite`, `party.updated`, `party.member_joined`, `party.member_left`, `party.ended` | | yapıldı |
| `party.request`, `party.request_cancelled`, `party.request_answered` | herkese açık bir partiye katılma isteği | yapıldı |
| `call.ringing`, `call.answered`, `call.joined`, `call.left`, `call.updated`, `call.ended` | sana gelen bir çağrı; başka bir cihazda yanıtlandı; biri partinin sesine girdi ya da çıktı; sessize alındı; bitti | yapıldı |
| `signal` | bir çağrı eşinden WebRTC offer, answer, ICE adayı, bye ya da renegotiate | yapıldı |
| `game_session.invite`, `game_session.updated`, `game_session.ended`, `game_session.signal` | | yapıldı |
| `share_play.invite`, `share_play.updated`, `share_play.ended`, `share_play.signal` | davet edildin; biri geldi ya da gitti, bir kumanda verildi ya da geri alındı; durduruldu ya da çıkarıldın; yayıncıyla sinyalleşme | yapıldı |
| `share_play.request`, `share_play.request_cancelled`, `share_play.request_answered` | herkese açık bir share play'e katılma isteği | yapıldı |
| `lfg.request`, `lfg.request_cancelled`, `lfg.answered` | biri ilanına katılmak istiyor; ilan sahibi yanıt verdi | yapıldı |
| `lfg.changed`, `discover.changed` | izlenen bir konuda: bir ilan ya da herkese açık bir parti veya share play geldi, değişti ya da gitti (listeyi yeniden oku) | yapıldı |
| `account.signed_out` | bu oturum başka bir yerden iptal edildi | yapıldı |
| `trophy.rarity_changed` | sahip olduğun bir kupa bir nadirlik etiketini geçti | planlandı |

`auth.handoff` ortak tiplerde var; devrin kendisi telefonun yerel bağlantısından geçtiği için (4.1)
gateway bugün onu göndermiyor.

## 4.9 Temalar, uyumluluk, indirmeler, yönetim

| Metot | Yol | Ne yapar | Durum |
|---|---|---|---|
| GET | `/themes?sort=new\|popular\|liked&q=&author=&cursor=&limit=` | Hub: yayınlanmış temalar, sayfa başına 24 (en fazla 60) | yapıldı |
| GET | `/hub/themes.json` | eski launcher'ların okuduğu dizin (GitHub klasörünün biçimi): Hub adreslerini `/api/v1/hub/` olarak ayarla | yapıldı |
| GET | `/themes/{id}`, `/me/themes` | bir tema (sürümler, yapan, beğeniler, senin beğenin); durumları ne olursa olsun kendi temaların | yapıldı |
| GET | `/themes/{id}/preview.webp`, `/thumb.webp` | görselleri (`?v=<version>` ile kalıcı olarak önbelleğe alınır) | yapıldı |
| GET | `/themes/{id}/download` | `X-Theme-Version` ve `X-Theme-SHA256` ile `.anyps5theme` dosyası | yapıldı |
| POST | `/themes` | multipart: tema dosyası (50 MB'a kadar) ve dosyada yoksa bir önizleme görseli (8 MB'a kadar); hemen yayınlanır | yapıldı |
| POST | `/themes/{id}/versions` | temanın bir sonraki sürümü, aynı şekilde | yapıldı |
| PATCH / DELETE | `/themes/{id}` | yeniden adlandır ya da açıklama yaz; sil (yapan) | yapıldı |
| PUT / DELETE | `/themes/{id}/like` | | yapıldı |
| GET | `/compat?q=&platform=&status=&cursor=` | uyumluluk listesi: platform başına kararlarıyla oyunlar (herkes) | yapıldı |
| GET | `/compat/{titleId}` | tek bir oyun: kararlar ve raporlar | yapıldı |
| POST | `/compat/reports` | `{titleId, name?, platform, status: "nothing" \| "boots" \| "menus" \| "ingame" \| "playable", launcherVersion, engineVersion?, machine?, os?, fpsAvg?, gameVersion?, note?}` | yapıldı |
| DELETE | `/compat/reports/{id}` | raporunu sil | yapıldı |
| GET | `/releases` | AnyPS5-ARM'ın (macOS, telefon) ve AnyPS5-Desktop'ın son sürümü | yapıldı |
| GET | `/releases/latest?product=launcher\|phone\|phone-ios\|desktop` | sürüm, etiket, notlar, sayfa, ana dosyanın URL'si, boyutu ve SHA-256'sı | yapıldı |
| GET | `/admin/reports?status=open\|actioned\|dismissed\|all&before=` | şikâyet kuyruğu; neyin şikâyet edildiği ve ne sıklıkla (yalnızca yöneticiler) | yapıldı |
| POST | `/admin/reports/{id}` | `{action: "dismiss" \| "warn" \| "ban" \| "remove_message" \| "reset_avatar" \| "reset_bio" \| "remove_post", days?, reason?}`; bir işlem aynı şey hakkındaki tüm açık şikâyetleri kapatır | yapıldı |
| POST | `/admin/lfg/{id}/remove` | bir ilanı şikâyet olmadan panodan kaldır | yapıldı |
| GET | `/admin/users?q=` | kullanıcı adı, e-posta (hash'i, hesabı olmayan bir adrese konmuş yasakları da bulur) ya da ID ile bir hesap: oturumlar, yasaklar, şikâyetler | yapıldı |
| POST | `/admin/users/{id}/ban`, GET `/admin/bans`, POST `/admin/bans/{id}/lift` | yasaklar | yapıldı |
| GET | `/admin/audit` | denetim kaydı | yapıldı |

Yönetim yolları hesabın rolünü her istekte kontrol eder. Yönetici rolünü vermek ve geri almak, bir
temayı göstermek, gizlemek ya da incelemeye almak API'nin yanındaki komut satırı aracıyla yapılır
(`admin grant`, `admin revoke`, `admin theme <id> show|hide|review`).

## 4.10 Sınırlar

Adres başına ve hesap başına, Valkey'de sayılır (yapıldı):

| Ne | Sınır |
|---|---|
| Her istek | adres başına dakikada 600, hesap başına dakikada 300; bir gövde en fazla 8 MB (tema yüklemesi 50 MB) |
| Giriş | adres başına 15 dakikada 30 deneme (istenen ve denenen kodlar, sağlayıcılar, passkey'ler, devirler); e-posta kodları: adres başına saatte 5, kod başına 10 deneme (atomik olarak sayılır), adres başına günde 30 yanlış kod |
| Token çağrıları | adres başına 10 dakikada 300 (yenilemeler, cihaz kodu yoklamaları; 4 sn'den sık bir yoklama `slow_down` alır) |
| Mesajlar | dakikada 30, günde 1000 |
| Arkadaşlık istekleri | günde 50 |
| Aramalar | dakikada 120; keşif listeleri dakikada 60 |
| Şikâyetler | günde 20 |
| Profil değişiklikleri | saatte 30; avatarlar saatte 10, her biri 5 MB |
| Başlatılan çağrılar | saatte 60; açılan oyun oturumları: saatte 120; başlatılan share play'ler: saatte 60 |
| Tepkiler | saatte 300 |
| Temalar | günde 20 paylaşma ya da güncelleme; beğeniler saatte 300 |
| Uyumluluk raporları | günde 60 |
| Oyuncu arama | günde 10 ilan (yeni bir hesap için 2); yabancıların ilanlarına, partilerine ve share play'lerine katılma isteği saatte 60 (yeni bir hesap için 10) |
| Eklenen passkey'ler | saatte 20 |
| Gruplar | 200 öğe |

Yeni hesap, bir günden yeni olan ya da az kupası olan hesaptır. Bir sınırı aşmak `Retry-After` ile
`429` döndürür. Gateway'de: 10 saniyede 30 çerçeve, bir çağrının kurulumu için 10 saniyede 300 sinyal.

## 4.11 Sürümleme

`/v1` uyumlu kalır: alanlar yalnızca eklenir. Geriye dönük uyumsuz bir değişiklik `/v2`'ye gider ve `/v1`,
`/v2`'ye geçen launcher sürümünden sonra en az altı ay çalışmaya devam eder.
