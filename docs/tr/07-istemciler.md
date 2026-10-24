# 7. İstemciler

Dört kapı: macOS'taki launcher (AnyPS5-ARM, Swift), Windows ve Linux'taki launcher
([AnyPS5-Desktop](https://github.com/utkuhalis/AnyPS5-Desktop), Flutter), telefon uygulaması
(Flutter, AnyPS5-ARM'ın `mobile/` dizininde) ve web sitesi (AnyTogether deposunda). Her biri tam
teşekküllü bir AnyTogether istemcisidir; hiçbiri ikinci sınıf değildir.
[Platformlar](12-platformlar.md) her platformun neyi farklı yaptığını listeler.

2026-10-24 itibarıyla durum. "Sonraki sürüm", AnyPS5-ARM'ın `main` dalında olup henüz sürüme girmemiş
demektir (son sürüm v0.2.13-arm).

| | Giriş | Arkadaşlar | Profiller | Oynama süresi, kupalar | Mesajlar | Partiler, ses | Arkadaşın oyununa katılma |
|---|---|---|---|---|---|---|---|
| macOS launcher'ı | sürümde (0.2.13) | sürümde | sonraki sürüm | sürümde | sonraki sürüm | sonraki sürüm | sonraki sürüm |
| Telefon uygulaması | sürümde (1.9.1) | sonraki sürüm | - | - | sonraki sürüm | sonraki sürüm | - |
| Web sitesi | yapıldı | yapıldı | yapıldı | profillerde gösteriliyor | yapıldı | yapıldı | - |
| AnyPS5-Desktop | planlandı | planlandı | planlandı | planlandı | planlandı | planlandı | planlandı |

Her istemci, birinin kendi kurduğu başka bir AnyTogether sunucusuna da yönlendirilebilir (macOS
launcher'ı ve telefon: sonraki sürüm; launcher eşleşmiş telefona hangi sunucuyu kullandığını söyler).

## 7.1 macOS launcher'ı (Swift)

### Kod

`tools/macos/launcher/Sources/AnyPS5Core/Together/` (test edilebilir, arayüz içermez), yapıldı:

| Dosya | Görevi |
|---|---|
| `TogetherClient.swift` | kimin giriş yaptığı; `/api/v1`'e HTTP çağrıları, aynı anda yalnızca tek bir yenileme isteğiyle token yenileme, problem-details hataları, `AnyTogether-Client` başlığı; e-posta kodu, telefondan devir ve cihaz koduyla giriş; yenileme token'ı Keychain'de |
| `TogetherServer.swift` | launcher'ın hangi AnyTogether ile konuştuğu: varsayılan olarak AnyTogether'ın kendisi, Ayarlar'dan bir başkası (yalnızca https; bu Mac için http) ya da `ANYTOGETHER_URL` |
| `TogetherSocket.swift` | anlık iletişim gateway'i: hello, çevrimiçi durumunu taşıyan heartbeat'ler, resume, artan bekleme süreleriyle yeniden bağlanma |
| `TogetherSync.swift` | oyun oturumları ve kazanılmış kupalarıyla kupa setleri; diskte bir giden kutusunda tutulur ve sunucunun istediği sırayla (bu Mac kaydedilir, oyun öğretilir, set yüklenir, ardından oturumlar ve kupalar), her biri bir kez gönderilir; oynarken kazanılan bir kupa anında gider |
| `TogetherAccount.swift`, `TogetherProfile.swift` | kendi profilin, başkalarının profilleri, gizlilik |
| `TogetherFriends.swift` | şu an ne yaptıklarıyla arkadaşlar, istekler, engellemeler |
| `TogetherMessages.swift` | konuşmalar ve mesajlar |
| `TogetherParties.swift` | partiler: bir liderle ve sürerken bir sesli çağrıyla en fazla sekiz arkadaş |
| `TogetherCalls.swift` | çağrılar, API'den gelen ICE sunucuları, soket üzerinden WebRTC sinyalleşmesi |
| `TogetherGameSessions.swift` | arkadaşın oyununa katılmak için oyun oturumları |

Uygulama hedefi (`Sources/AnyPS5/`):

| Ekran | Nedir | Durum |
|---|---|---|
| Ayarlar → AnyTogether | e-posta koduyla ya da eşleşmiş telefonla ("Telefonumla giriş yap") giriş, çıkış; adın, biyografin, ülken, kullanıcı adın ve kimin neyi gördüğü; "Arkadaşlarım oyunuma katılabilsin"; Sunucu satırı | giriş sürümde; gerisi sonraki sürüm |
| Arkadaşlar paneli | çevrimiçi durumu ve oyunlarıyla liste; istekler; kullanıcı adıyla ekleme; her arkadaş için: profil, mesaj, partiye davet, katılınabilir bir oyun için **<arkadaş> ile oyna** | sürümde; profiller, mesajlar, partiler, birlikte oynama sonraki sürüm |
| Profil görünümü | kendi kartın ve arkadaşlarınınki: avatar, ad, kullanıcı adı, biyografi; oyunlar, saatler, kupalar ve puanlar; oynama süresi ve ilerlemeyle oyunlar; nadirlikleriyle son kupalar | sonraki sürüm |
| Mesajlar | konuşmalar ve sohbet görünümü | sonraki sürüm |
| Parti paneli | üyeler, davetler, lider işlemleri, **ses**: mikrofonu açıp kapama, ⌥V ile bas-konuş (genel bir tuş, oyunun üstünde de çalışır), konuşanın çevresinde bir halka, üst çubuktaki parti düğmesinde de | sonraki sürüm |
| Oyun davetleri | bir arkadaşın oyununa davetler için kartlar ve bildirimler, Reddet seçeneğiyle | sonraki sürüm |
| Apple, Google, Discord ile giriş | API'nin zaten doğruladığı sağlayıcılar için düğmeler | planlandı |
| Akış paneli, AnyTogether'da Tema Hub'ı, oyun sayfası, share play | | planlandı |

Ses, uygulamada lisansıyla birlikte taşınan Google'ın WebRTC'sini (hazır derlenmiş `stasel/WebRTC`
paketi, BSD-3-Clause, arm64 ve x86_64) kullanır. Uygulamada mikrofon kullanım metni vardır ve
Developer ID imzası, hardened runtime altında ona ses girişi yetkisini verir.

Katılmaya izin verilmiş bir oyun çalışırken launcher onun için bir oyun oturumu açar (oyun, oyun
sürümü, motor derlemesi) ve motorun çevrimiçi köprüsü için oturumu, kullanıcıyı ve rolünü yazar;
`ANYPS5_TOGETHER_SESSION` oyuna bunun yerini söyler (bkz.
[Anlık iletişim](06-anlik-ses-birlikte-oynama.md) 6.7). Köprünün kendisi `online-play` branch'inde,
varsayılan olarak kapalı.

### Launcher için kurallar

- **Hiçbir şey oynamayı engellemez.** Her çağrı zaman aşımlı ve asenkrondur; başarısızlıklar giden
  kutusuna gider ya da sessiz bir durum göstergesiyle bildirilir, asla modal pencereyle değil.
- **Giriş yapmadan da deneyim eksiksizdir.** Hiçbir AnyTogether öğesi rahatsız edecek şekilde görünmez;
  Ayarlar → AnyTogether'da bir satır, güncellemeden sonraki ilk açılışta bir kart ("Yeni: AnyTogether",
  tek basışla kalıcı olarak kapatılır).
- **İzinler kullanıldığı anda istenir**: mikrofon sese ilk katılışta, ekran kaydı ilk share play'de
  (Remote Play/Clips zaten istiyor).
- **Testler** telefon sunucusununkiler gibi: süreç içinde sahte bir API ve gateway; giden kutusu
  çevrimdışı/çevrimiçi geçişlerine karşı test edilir; senkronizasyon gerçek API'ye karşı da test edilir.
- **İmzalama**: sürüm derlemeleri Developer ID ile imzalanır; bu, mikrofon ve ekran kaydı izinlerini
  güncellemelerden sonra da korur.

## 7.2 Windows ve Linux launcher'ı (AnyPS5-Desktop)

[AnyPS5-Desktop](https://github.com/utkuhalis/AnyPS5-Desktop), launcher'ın Windows ve Linux portudur;
Flutter ile yazılmış, herkese açık (GPL-2.0) bir proje: aynı PS5 tarzı ana ekran, kütüphane, kilit
açma, kontroller, kupalar, kayıtlar ve telefon kumandası. AnyTogether'a, diğer istemcilerin
kullandığı aynı API ve gateway üzerinden kendisi bağlanır; sunucuda macOS'a özgü hiçbir şey yok.
Durum: launcher geliştiriliyor; AnyTogether kısmı planlandı. Telefon uygulaması gibi Dart olduğu için
telefonun AnyTogether istemcisinin (`mobile/lib/together/`) çoğunu paylaşabilir: REST ve token yenileme,
soket, arkadaşlar, mesajlar, `flutter_webrtc` ile partiler ve ses.

Launcher'ın platformundan ihtiyaç duydukları:

| İhtiyaç | Windows | Linux |
|---|---|---|
| Güvenli token deposu | Credential Manager | Secret Service (GNOME Keyring, KWallet) |
| Sağlayıcılarla giriş | varsayılan tarayıcı ve bir loopback yönlendirmesi (`127.0.0.1:<random port>`, RFC 8252) | aynı |
| Yankı gidermeli mikrofon | WebRTC'nin ses işleme altyapısı | WebRTC'nin ses işleme altyapısı (PipeWire/PulseAudio girişi) |
| Bas-konuş tuşu | `RegisterHotKey` | masaüstünün genel kısayol portalı |
| Kupalar, oyun oturumları | launcher'ın zaten oyun başına okuduğu şekilde | aynı |
| Oyun yakalama (share play) | Windows.Graphics.Capture (oyun penceresi) | xdg-desktop-portal üzerinden PipeWire ekran yayını (kullanıcıya bir kez sorar) |
| Oyun sesi (share play) | WASAPI process loopback (yalnızca oyunun süreci) | oyunun düğümünün PipeWire akışı |
| Düşük gecikmeli H.264 (share play) | Media Foundation donanım MFT'si ya da doğrudan NVENC / AMF / Quick Sync | VA-API (Intel, AMD) ya da NVENC |

Ekranlar macOS launcher'ınınkilerle (7.1) aynıdır; launcher'ın kendi PS5 tarzı arayüzünde, ortak hata
kodlarından ve olay adlarından alınan aynı metinlerle (İngilizce, Türkçe).

Telefon uygulaması (7.3) bu launcher'la da macOS'takiyle olduğu gibi çalışır: AnyPS5-Desktop telefon
protokolünü (WebSocket 47700 portunda eşleştirme, UDP ile kumanda, kablo yolları) zaten konuşuyor;
protokol [Platformlar](12-platformlar.md) 12.4'te yazılı.

## 7.3 Telefon uygulaması (Flutter)

### Kod

`mobile/lib/together/`, yapıldı: `together_account.dart` (e-posta koduyla ya da devir üzerinden Mac'in
hesabıyla giriş, Mac'in devir isteğini onaylama, başka bir sunucu), `together_socket.dart` (giriş
yapılmışken çevrimiçi olan anlık iletişim soketi), `together_hub.dart`, `people.dart`, `friends.dart`,
`messages.dart`, `parties.dart` ve `voice.dart`, `voice_mesh.dart` ve `voice_webrtc.dart` içinde ses
(`flutter_webrtc`, relay kimlik bilgileri süreleri dolmadan yenilenir).

### Ekranlar

| Ekran | Nedir | Durum |
|---|---|---|
| Hesap | bir e-posta kodu ya da tek dokunuşla Mac'in hesabı; ilk giriş hesabı oluşturur | sürümde (1.9.1) |
| Onay | bir launcher istediğinde (devir) "<Mac/PC adı> cihazında oturum açılsın mı?": tek dokunuş | sürümde |
| Arkadaşlar | ana ekrandaki bir kişiler düğmesinden | sonraki sürüm |
| Mesajlar | konuşmaların yanında | sonraki sürüm |
| Parti | üyeler, davetler, ses | sonraki sürüm |
| Mesajlar, davetler, arkadaşlık istekleri için anlık bildirimler | | planlandı |
| Akış, profiller, share play izleyicisi | | planlandı |

### Telefon için kurallar

- Yerel ağ üzerindeki kumanda tam olarak olduğu gibi kalır; telefon ile bilgisayar bir aradayken
  AnyTogether asla aralarına girmez.
- Anlık bildirim (planlandı): APNs (iOS) ve FCM (Android) token'ları oturum başına kaydedilir;
  bildirimler yalnızca ID'leri ve kısa bir metni taşır; içerik açıldığında çekilir.
- Pil: gateway soketi arka planda kapatılır (anlık bildirimler devralır), uygulamaya dönüldüğünde açılır.

## 7.4 Web sitesi (Next.js)

| Sayfa | Yol | Durum |
|---|---|---|
| Açılış sayfası | `/` | yapıldı |
| Giriş (e-posta kodu ya da bağlantısı, passkey; ilk seferde hesap oluşturulur) | `/login`, `/login/email` | yapıldı |
| Bir launcher'ın cihaz kodunu onaylama | `/link` | yapıldı |
| Oyunlar, oynama süresi ve kupalarla profil (herkese açık, SSR); oradan birini şikâyet etme | `/u/<handle>` | yapıldı; Open Graph görseli planlandı |
| Arkadaşlar, mesajlar, sesli parti (giriş yapılmışken) | `/friends`, `/messages`, `/party` | yapıldı |
| Ayarlar: profil, avatar, gizlilik, passkey'ler, giriş yapılmış cihazlar, her yerden çıkış, verilerimi indir, hesabı sil | `/settings` | yapıldı |
| Oyun sayfası | `/g/<title id>` | planlandı |
| Akış | `/feed` | planlandı |
| Theme Hub | `/themes`, `/themes/<id>` | planlandı |
| Liderlik tabloları | `/leaderboards` | planlandı |
| İndirmeler | `/download` | planlandı |
| Kurallar, gizlilik politikası, kullanım koşulları, KVKK aydınlatma metni | `/rules`, `/privacy`, `/terms`, `/kvkk` | planlandı |

Görünüm, coming-soon sayfasını (koyu, `#07080c`, mavi/mor/turkuaz vurgular, Space Grotesk ve JetBrains
Mono) ve launcher'ın konsol tarzını izler. Varsayılan dil İngilizce, Türkçe bir seçiciyle. Tarayıcı hiç
token tutmaz: sitenin sunucusu token'ları HttpOnly çerezlerde saklar ve sayfa gateway soketini açarken
API'den tek kullanımlık bir bilet ister.

## 7.5 Ortak parçalar

- **Türler**: bugün her istemci kendi türlerini `packages/shared` içindeki Zod şemalarına göre yazar;
  Swift ve Dart türlerinin bir OpenAPI belgesinden üretilmesi planlandı.
- **Metinler**: hata `code`'ları ve olay adları her istemcide çevrilir (İngilizce, Türkçe).
- **Telefon protokolü** (eşleştirme, kumanda, kablo, AnyTogether devri) ve **kumanda paketi** tek bir
  yerde tanımlanır; böylece macOS launcher'ı, AnyPS5-Desktop ve telefon uygulaması birlikte çalışabilir.
- **Görseller**: AnyTogether işareti (favicon'daki iki halka) launcher'da, telefonda ve web'de.
