# 7. İstemciler

Dört kapı: macOS'taki launcher (AnyPS5-ARM, Swift), Windows ve Linux'taki launcher (Rust portu),
telefon uygulaması (Flutter, AnyPS5-ARM'ın `mobile/` dizininde) ve web sitesi (AnyTogether
deposunda). Her biri tam teşekküllü bir AnyTogether istemcisidir; hiçbiri ikinci sınıf değildir.
[Platformlar](12-platformlar.md) her platformun neyi farklı yaptığını listeler.

## 7.1 macOS launcher'ı (Swift)

### Yeni kod

`tools/macos/launcher/Sources/AnyPS5Core/Together/` (test edilebilir, arayüz içermez):

| Dosya | Görevi |
|---|---|
| `TogetherClient.swift` | `/v1`'e HTTP çağrıları, aynı anda yalnızca tek bir yenileme isteğiyle token yenileme, problem-details hataları, `AnyTogether-Client` başlığı |
| `TogetherAuth.swift` | tek dokunuşla giriş: Apple (`ASAuthorizationAppleIDProvider`), Google ve Discord (PKCE ile `ASWebAuthenticationSession`), e-posta kodu, eşleştirilmiş telefona devretme, yedek yol olarak cihaz kodu; yenileme token'ı Keychain'de |
| `TogetherSocket.swift` | anlık iletişim gateway'i: hello, çevrimiçi durumunu taşıyan heartbeat'ler, resume, artan bekleme süreleriyle yeniden bağlanma (1, 2, 4 … 30 sn, rastgele sapmayla) |
| `TogetherOutbox.swift` | oturumlar, kupalar, katalog girdileri ve raporlar için SQLite'ta (`Application Support/AnyPS5/Together/outbox.sqlite`) yalnızca ekleme yapılan bir kuyruk; çevrimiçiyken toplu gönderir, tür başına sırayı korur, hiçbir şeyi atmaz |
| `TogetherModels.swift` | OpenAPI belgesinden üretilen türler |
| `TrophySync.swift` | launcher'ın `TrophySet` yapısını kupa seti yüklemelerine ve kazanılan kupalara dönüştürür |
| `SessionRecorder.swift` | oyunun başlayıp bitmesini (Discord ve kayıt senkronizasyonu için zaten izleniyor) oturumlara dönüştürür |
| `TogetherCall.swift` | WebRTC (Swift paketi olarak Google'ın WebRTC framework'ü): parti üyesi başına peer connection, `TogetherSocket` üzerinden sinyalleşme, API'den gelen ICE sunucuları, yol ve kalite raporlama |
| `PartyVoice.swift` | mikrofon kanalı (Apple ses işleme), sessize alma, bas-konuş, konuşma seviyeleri |
| `SharePlay.swift` | `RemotePlay`'in ScreenCaptureKit karelerini WebRTC'nin H.264 kodlayıcısına (VideoToolbox, `StreamEncoder` ile aynı düşük gecikme ayarları), oyun sesini de Opus olarak iletir; `pad` veri kanalından gelen kumanda paketlerini bir `RemoteServer` köprü yuvasına aktarır |

Uygulama hedefi (`Sources/AnyPS5/`):

| Ekran | Nedir |
|---|---|
| Üst çubuk | profil çipi, durum noktalı avatara dönüşür; çevrimiçi sayısını gösteren bir Arkadaşlar düğmesi; okunmamış sayısını gösteren bir Mesajlar düğmesi |
| Giriş paneli | "Apple / Google / Discord ile devam et", "Telefonumu kullan" (telefon uygulaması eşleştirilmiş ve giriş yapılmışsa), "Bana kod gönder"; cihaz kodu yalnızca yedek yol olarak |
| Profil katmanı | kendi kartın (temanla birlikte), ad/biyografi/avatar/vitrin düzenleme, gizlilik |
| Arkadaşlar paneli | çevrimiçi durumu ve oyunlarıyla liste; istekler; kullanıcı adıyla ya da QR ile ekleme; her arkadaş için: profil, mesaj, partiye davet |
| Mesajlar paneli | konuşmalar ve sohbet görünümü, kumandayla kullanılabilir (ekran klavyesi macOS'unkidir; kumanda kullanan biri hazır yanıtlar gönderebilir) |
| Parti kartı | yanda yüzen bir kart: üyeler, konuşma halkaları, sessize alma, bas-konuş ipucu, Share play (birlikte oynama) düğmesi; oyun sırasında küçük bir katman olarak üstte kalır (kupa bildirimi gibi) |
| Akış paneli | arkadaşların aktivitesi |
| Theme Hub | mevcut Temalar ekranı AnyTogether'ın dizinini okur; "Hub'da paylaş" yükleme yapar |
| Oyun sayfası | oyunu oynayan arkadaşlar, kupalarda nadirlik, topluluk uyumluluğu, oturum sonrasında "Nasıl çalıştı?" sorusu (isteğe bağlı) |

### Launcher için kurallar

- **Hiçbir şey oynamayı engellemez.** Her çağrı zaman aşımlı ve asenkrondur; başarısızlıklar giden
  kutusuna gider ya da sessiz bir durum göstergesiyle bildirilir, asla modal pencereyle değil.
- **Giriş yapmadan da deneyim eksiksizdir.** Hiçbir AnyTogether öğesi rahatsız edecek şekilde görünmez;
  Ayarlar → AnyTogether'da bir satır, güncellemeden sonraki ilk açılışta bir kart ("Yeni: AnyTogether",
  tek basışla kalıcı olarak kapatılır).
- **İzinler kullanıldığı anda istenir**: mikrofon ilk parti sesinde, ekran kaydı ilk share play'de
  (Remote Play/Clips zaten istiyor).
- **Testler** telefon sunucusununkiler gibi: süreç içinde sahte bir API ve gateway; giden kutusu
  çevrimdışı/çevrimiçi geçişlerine karşı test edilir; cihaz bağlama sahte bir onayla test edilir.
- **İmzalama**: mikrofon ve ekran kaydı izinlerinin güncellemelerden sonra da korunması için sürüm
  derlemelerinin sabit bir imzaya (Developer ID Application) ihtiyacı var, bkz. açık sorular.

## 7.2 Windows ve Linux launcher'ı (Rust)

Bu launcher'ın Windows ve Linux portu Rust ile yazılıyor. AnyTogether'a, yayımladığımız bir Rust
crate'i olan `anytogether` üzerinden erişir (MIT ya da Apache-2.0, böylece her launcher kullanabilir);
crate, AnyTogether deposunda `clients/rust` altında tutulur:

| Modül | Görevi |
|---|---|
| `api` | OpenAPI belgesinden üretilen tipli REST istemcisi (`reqwest`, `serde`), token yenileme |
| `auth` | varsayılan tarayıcıda PKCE ve loopback yönlendirmesiyle (`127.0.0.1:<random port>`, RFC 8252) Apple, Google, Discord; e-posta kodu; telefona devretme; yedek yol olarak cihaz kodu; token'lar Windows Credential Manager'da ya da Linux Secret Service'te (`keyring` crate'i) |
| `socket` | anlık iletişim gateway'i (`tokio-tungstenite`): hello, heartbeat'ler, resume, tipli bir akış olarak olaylar |
| `outbox` | macOS launcher'ındakiyle aynı, yalnızca ekleme yapılan kuyruk; SQLite'ta (`rusqlite`), oturumlar, kupalar, katalog girdileri ve raporlar için |
| `call` | `webrtc-rs` (saf Rust) ya da LiveKit'in `libwebrtc` bağlamalarıyla (Google'ın WebRTC'si, donanım codec'leriyle) WebRTC peer connection'ları, `socket` üzerinden sinyalleşme |
| `share_play` | launcher'ın yakalama katmanından kodlanmış H.264 karelerini ve PCM sesi alır; `pad` veri kanalından gelen kumanda paketlerini bir callback'e teslim eder |

Launcher'ın kendisinin sağladıkları (crate'te değil, platform kodunda):

| İhtiyaç | Windows | Linux |
|---|---|---|
| Oyun yakalama | Windows.Graphics.Capture (oyun penceresi) | xdg-desktop-portal üzerinden PipeWire ekran yayını (kullanıcıya bir kez sorar) |
| Oyun sesi | WASAPI process loopback (yalnızca oyunun süreci) | oyunun düğümünün PipeWire akışı |
| Düşük gecikmeli H.264 | Media Foundation donanım MFT'si ya da doğrudan NVENC / AMF / Quick Sync | VA-API (Intel, AMD) ya da NVENC |
| Yankı gidermeli mikrofon | WebRTC'nin ses işleme altyapısı | WebRTC'nin ses işleme altyapısı (PipeWire/PulseAudio girişi) |
| Arkadaştan gelen kumanda | motorun uzak kumanda köprüsü (`ANYPS5_REMOTE_PAD_2…4`) | aynı |
| Kupalar, oyun oturumları | launcher'ın zaten oyun başına okuduğu şekilde | aynı |
| Bas-konuş tuşu | `RegisterHotKey` | masaüstünün genel kısayol portalı |

Ekranlar macOS launcher'ınınkilerle (7.1) aynıdır; launcher'ın kendi PS5 tarzı arayüzünde, ortak hata
kodlarından ve olay adlarından alınan aynı metinlerle (İngilizce, Türkçe).

Telefon uygulaması (7.3), launcher telefon protokolünü (WebSocket 47700 portunda eşleştirme, UDP ile
kumanda, kablo yolları) konuştuğu anda bu launcher'la da macOS'takiyle olduğu gibi çalışır. Bu protokol,
yalnızca belgeye bakılarak uygulanabilsin diye [Platformlar](12-platformlar.md) bölümünde yazılı olarak
tanımlanmıştır.

## 7.3 Telefon uygulaması (Flutter)

### Yeni kod

`mobile/lib/together/`: `together_client.dart`, `together_socket.dart`, `auth.dart` (yerel olarak Apple,
Google, Discord; e-posta kodu; bir launcher'ın devretme isteğini ya da cihaz kodunu onaylama), `call.dart`
(`flutter_webrtc`), `share_play_view.dart`.

### Ekranlar

| Ekran | Nedir |
|---|---|
| Hesap | tek dokunuş: Apple, Google ya da Discord veya bir e-posta kodu; ilk giriş hesabı oluşturur |
| Onay | bir launcher istediğinde (telefona devretme) "<Mac/PC adı> cihazında oturum açılsın mı?" ya da yedek QR'ını tara: tek dokunuş |
| Arkadaşlar, Mesajlar, Akış | mevcut launcher modunun yanında sekmeler; mesajlar, davetler ve arkadaşlık istekleri için anlık bildirimler |
| Parti | üyeler, ses (telefon kumanda olurken sesi de taşıyabilir), share play izleyicisi |
| Share play izleyicisi | akış tam ekran, kumanda üzerinde; bugün Remote Play'de kumandanın görüntünün üzerinde durmasıyla aynı; her yerden çalışır |
| Profil | kendi kartın ve başkalarınınki |

### Telefon için kurallar

- Yerel ağ üzerindeki kumanda tam olarak olduğu gibi kalır; telefon ile bilgisayar bir aradayken
  AnyTogether asla aralarına girmez.
- Anlık bildirim: APNs (iOS) ve FCM (Android) token'ları oturum başına kaydedilir; bildirimler yalnızca
  ID'leri ve kısa bir metni taşır; içerik açıldığında çekilir.
- Pil: gateway soketi arka planda kapatılır (anlık bildirimler devralır), uygulamaya dönüldüğünde açılır.

## 7.4 Web sitesi (Next.js)

| Sayfa | Yol |
|---|---|
| Açılış sayfası ("Coming soon"ın yerine) | `/` |
| Giriş (tek dokunuş; ilk seferde hesap oluşturulur), bir launcher'ı onaylama | `/login`, `/link` |
| Profil (herkese açık, SSR, Open Graph görseli) | `/u/<handle>` |
| Bir profilin kütüphanesi ve kupaları | `/u/<handle>/games`, `/u/<handle>/trophies/<title id>` |
| Oyun sayfası | `/g/<title id>` |
| Arkadaşlar, mesajlar, akış, parti (giriş yapılmışken) | `/friends`, `/messages`, `/feed`, `/party/<id>` |
| Theme Hub | `/themes`, `/themes/<id>` |
| Liderlik tabloları | `/leaderboards` |
| İndirmeler | `/download` |
| Ayarlar, gizlilik, veri dışa aktarma, hesabı silme | `/settings/...` |
| Kurallar, gizlilik politikası, kullanım koşulları, KVKK aydınlatma metni | `/rules`, `/privacy`, `/terms`, `/kvkk` |

Görünüm, coming-soon sayfasını (koyu, `#07080c`, mavi/mor/turkuaz vurgular, Space Grotesk ve JetBrains
Mono) ve launcher'ın konsol tarzını izler. Giriş yapmış kullanıcının kendi sayfaları profil temasını taşır.
İngilizce ve Türkçe; tarayıcının diline göre ve bir anahtarla değiştirilebilir.

## 7.5 Ortak parçalar

- **Türler**: Swift (swift-openapi-generator), Rust (progenitor ya da openapi-generator), Dart ve
  TypeScript için OpenAPI belgesinden üretilir; böylece dört istemci aynı dili konuşur.
- **Metinler**: hata `code`'ları ve olay adları her istemcide çevrilir (İngilizce, Türkçe).
- **Telefon protokolü** (eşleştirme, kumanda, kablo) ve **kumanda paketi** tek bir yerde tanımlanır;
  böylece macOS ve Windows/Linux launcher'ları ile telefon uygulaması birlikte çalışabilir.
- **Görseller**: AnyTogether işareti (favicon'daki iki halka) launcher'da, telefonda ve web'de.
