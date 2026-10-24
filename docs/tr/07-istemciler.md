# 7. İstemciler

Dört kapı: macOS'taki launcher (AnyPS5-ARM, Swift), Windows ve Linux'taki launcher
([AnyPS5 Desktop](https://github.com/utkuhalis/AnyPS5-Desktop), Flutter), telefon uygulaması
(Flutter, AnyPS5-ARM'ın `mobile/` dizininde) ve web sitesi (AnyTogether deposunda). Her biri tam
teşekküllü bir AnyTogether istemcisidir; hiçbiri ikinci sınıf değildir.
[Platformlar](12-platformlar.md) her platformun neyi farklı yaptığını listeler.

2026-10-25 itibarıyla durum: AnyPS5-ARM 0.2.15 (macOS launcher'ı), telefon uygulaması 1.11.0 ve AnyPS5
Desktop 0.1.1 sürümde; web sitesi yapıldıkça yayına giriyor. Aşağıda yapıldı olarak işaretlenen her şey
bu sürümlerde.

| | Giriş | Arkadaşlar | Profiller | Oynama süresi, kupalar | Mesajlar | Partiler, ses, görüşmeler | Arkadaşın oyununa katılma | Aktivite, liderlik tabloları, bildirimler | Share play | Tema Hub'ı | Uyumluluk |
|---|---|---|---|---|---|---|---|---|---|---|---|
| macOS launcher'ı | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | host olur, izler, birlikte oynar | ✓ (listeler, kurar, paylaşır) | ✓ (oturumdan sonra sorar) |
| Telefon uygulaması | ✓ | ✓ | ✓ (kendininkini düzenler) | - | ✓ | ✓ | - | ✓ | izler, birlikte oynar | launcher'ın temasını giyer | - |
| Web sitesi | ✓ (passkey'lerle) | ✓ | ✓ | profillerde | ✓ | ✓ | - | ✓ (tarayıcı bildirimleriyle) | izler, birlikte oynar | ✓ | ✓ |
| AnyPS5 Desktop | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | planlandı | planlandı | planlandı | planlandı |

Oyuncu bulma (oyuncu arama panosu, Şu an canlı, kişiler, oyun sayfaları) ve yönetici sayfası şimdilik
yalnızca web sitesinde. Her istemci, birinin kendi kurduğu başka bir AnyTogether sunucusuna da
yönlendirilebilir (launcher eşleşmiş telefona hangi sunucuyu kullandığını söyler).

## 7.0 Birlikte test edildi

Her istemci kendi sahte sunucusuna karşı, hepsi birlikte de tek bir gerçek yerel sisteme karşı test
edilir (AnyTogether deposunda `e2e/`): her istemcinin deposundaki bir sürücü istemcinin gerçek kodunu
çalıştırır, web sitesi de headless Chrome'da gerçek sayfaları üzerinden yürütülür. Son çalıştırma
2026-10-24, bütün kontroller geçti:

| Senaryo | macOS launcher'ı | Telefon | AnyPS5 Desktop | Web sitesi |
|---|---|---|---|---|
| 1 Giriş: e-posta kodları; telefon → Mac, Mac → telefon, telefon → AnyPS5 Desktop devri; web sitesinde onaylanan cihaz kodları | ✓ | ✓ | ✓ | ✓ |
| 2 Arkadaşlar: web sitesinde kabul edilen bir istek; diğerlerinde çevrimiçi durumu; arkadaşlıktan çıkarma; engelleme | ✓ | ✓ | ✓ | ✓ |
| 3 Mesajlar: canlı okunmamış rozeti ve okundu bilgisiyle birebir mesaj; dört kişilik bir grup, yazıyor bilgisi, okunmamış sayıları | ✓ | ✓ | ✓ | ✓ |
| 4 Partiler: web sitesinde başlatılır, üç uygulama katılır, liderlik devredilir, bir üye çıkarılır | ✓ | ✓ | ✓ | ✓ |
| 5 Görüşmeler: parti sesi ve birebir görüşme, gateway üzerinden sinyalleşme, relay kimlik bilgileri, iki yönde mikrofon kapatma | ✓ | ✓ | yapıldı, henüz testte değil | ✓ |
| 6 Senkronizasyon: web sitesinin profilinde, liderlik tablosunda ve akışında oynama süresi ve kupalar; gizliliğin bunları gizlemesi | ✓ | - | ✓ | ✓ |
| 7 Oyun oturumları: host Mac'tir, AnyPS5 Desktop sürüm kontrolünden sonra katılır, özellikler ve sinyaller | ✓ | - | ✓ | - |

Share play, Tema Hub'ı, bildirimler ve oyuncu bulma henüz istemciler arası testte değil; share play
launcher'da host ve izleyici tek bir süreçte çalıştırılarak test ediliyor.

## 7.1 macOS launcher'ı (Swift)

### Kod

`tools/macos/launcher/Sources/AnyPS5Core/Together/` (test edilebilir, arayüz içermez), yapıldı:

| Dosya | Görevi |
|---|---|
| `TogetherClient.swift` | kimin giriş yaptığı; `/api/v1`'e HTTP çağrıları, aynı anda yalnızca tek bir yenileme isteğiyle token yenileme, problem-details hataları, `AnyTogether-Client` başlığı; e-posta kodu, telefondan devir ve cihaz koduyla giriş; yenileme token'ı Keychain'de |
| `TogetherServer.swift` | launcher'ın hangi AnyTogether ile konuştuğu: varsayılan olarak AnyTogether'ın kendisi, Ayarlar'dan bir başkası (yalnızca https; bu Mac için http) ya da `ANYTOGETHER_URL` |
| `TogetherSocket.swift` | anlık iletişim gateway'i: hello, çevrimiçi durumunu taşıyan heartbeat'ler, resume, artan bekleme süreleriyle yeniden bağlanma |
| `TogetherSync.swift` | oyun oturumları ve kazanılmış kupalarıyla kupa setleri; diskte bir giden kutusunda tutulur ve sunucunun istediği sırayla, her biri bir kez gönderilir; oynarken kazanılan bir kupa anında gider |
| `TogetherAccount.swift`, `TogetherProfile.swift` | kendi profilin, başkalarının profilleri, gizlilik |
| `TogetherFriends.swift` | şu an ne yaptıklarıyla arkadaşlar, istekler, engellemeler |
| `TogetherMessages.swift` | konuşmalar, gruplar, yazıyor bilgisi |
| `TogetherParties.swift`, `TogetherCalls.swift` | sesli görüşmeleriyle partiler, birebir görüşmeler, mikrofon kapatma, ICE sunucuları, sinyalleşme |
| `TogetherGameSessions.swift` | arkadaşın oyununa katılmak için oyun oturumları |
| `TogetherSharePlay.swift` | share play'in çağrıları ve sinyalleri, ve yalnızca 2-4. kumandayı tutan bir izleyicinin oyuna ulaşmasına izin veren kumanda yönlendiricisi |
| `TogetherFeed.swift`, `TogetherLeaderboards.swift`, `TogetherNotifications.swift` | aktivite akışı ve tepkiler, liderlik tabloları, bildirimler |
| `TogetherThemes.swift`, `TogetherCompat.swift` | Tema Hub'ı, uyumluluk raporları ve kararları |

`Sources/AnyPS5SharePlay/` share play'in WebRTC kısmını tutar: `SharePlayHost` (izleyici başına bir H.264
izi, "audio" ve "pad" veri kanalları), `SharePlayWatcher` ve `SharePlaySpeaker` (izleyici tarafı).

### Ekranlar

| Ekran | Nedir |
|---|---|
| Ayarlar → AnyTogether | e-posta koduyla, web sitesinin cihaz koduyla ya da eşleşmiş telefonla giriş, çıkış; adın, biyografin, ülken, kullanıcı adın ve kimin neyi gördüğü; "Arkadaşlarım oyunuma katılabilsin"; Sunucu satırı |
| Arkadaşlar paneli | çevrimiçi durumu ve oyunlarıyla liste; istekler; kullanıcı adıyla ekleme; her arkadaş için: profil, mesaj, görüşme, partiye davet, katılınabilir bir oyun için **<arkadaş> ile oyna**, bir share play için **İzle**; bir oyun çalışırken **Birlikte oyna** |
| Profil görünümü | kendi kartın ve arkadaşlarınınki: oyunlar, saatler, kupalar ve puanlar, nadirlikleriyle son kupalar, son aktiviteler |
| Etkinlikler | arkadaşların kupaları, ilk oynayışları, uzun oturumları ve dönüm noktaları, tepkilerle |
| Sıralama | genel kupa puanları, bir oyunun puanları, oynama süresi ya da tamamlama; arkadaşlar ya da herkes; senin sıran |
| Bildirimler | üst çubukta okunmamış sayısıyla bir zil, liste, yeniler için kısa bir bildirim |
| Mesajlar | konuşmalar, gruplar, yazıyor bilgisi |
| Parti paneli | üyeler, davetler, lider işlemleri, **ses**: mikrofonu açıp kapama, ⌥V ile bas-konuş (genel bir tuş, oyunun üstünde de çalışır), konuşanın çevresinde bir halka |
| Share play (host) | kimlerin izlediği, her birinin bağlantısı (doğrudan ya da relay üzerinden, gidiş-dönüş süresi, görüntü boyutu ve kare hızı), **…, N. oyuncu olsun**, kumandayı geri alma, birini çıkarma, davet, "Arkadaşlar davetsiz girebilir", "En çok izleyici", **Birlikte oynamayı durdur** |
| Share play (izleyici) | arkadaşın oyunu sesiyle birlikte tam ekran; arkadaş bir kumanda verdiğinde kumanda onun 2-4. oyuncusu olur; PS düğmesi çıkar |
| Temalar | AnyTogether'daki Hub (bir sunucuda yokken GitHub klasörü), giriş yapılmışken **Hub'da paylaş**, `anyps5://theme/<id>` bağlantıları |
| … nasıl çalıştı? | oturumdan sonra tek dokunuşla bir uyumluluk raporu; oyunun bilgilerinde topluluğun kararı |
| Apple, Google, Discord ile giriş | planlandı |

Ses ve share play, uygulamada lisansıyla birlikte taşınan Google'ın WebRTC'sini (hazır derlenmiş
`stasel/WebRTC` paketi, BSD-3-Clause) kullanır. Uygulamada mikrofon kullanım metni vardır; share play,
Remote Play ve klipler ekran kaydı iznini bir kez ister.

Katılmaya izin verilmiş bir oyun çalışırken launcher onun için bir oyun oturumu açar (oyun, oyun
sürümü, motor derlemesi) ve motorun çevrimiçi köprüsü için oturumu, kullanıcıyı ve rolünü yazar;
`ANYPS5_TOGETHER_SESSION` oyuna bunun yerini söyler (bkz.
[Anlık iletişim](06-anlik-ses-birlikte-oynama.md) 6.7). Köprünün kendisi `online-play` branch'inde,
varsayılan olarak kapalı.

### AnyTogether'ın yanında: motorlar ve çökme raporları

AnyTogether'a ait olmayan ama bir oyunu raporlayan herkes için önemli iki launcher özelliği:

- **Motor seçici** (Ayarlar → Motor ve oyun başına): AnyPS5-ARM sürümlerine eklenen motor derlemeleri
  (`AnyPS5-toolkit-macos-<version>.zip`) tarihleri ve notlarıyla listelenir, ilerleme göstergesiyle
  indirilir, GitHub'ın SHA-256'sına ve kendi manifestlerine karşı kontrol edilir (her kilit açmadan önce
  yeniden) ve Application Support'ta yan yana tutulur; biri bütün oyunlar ya da tek bir oyun için
  seçilir. Kendi derlemenin bulunduğu bir klasör de kullanılabilir. Seçilenden farklı bir motorla kilidi
  açılmış bir oyun **Güncelle ve Oyna** seçeneğini sunar; kayıtlar ve kupalar kalır. Motor sürümü her
  uyumluluk raporuyla ve her oyun oturumuyla (sürüm kontrolü) birlikte gider.
- **Çökme raporları**: bir oyun bir hatayla, bir çökmeyle ya da penceresi görünmeden durduğunda launcher
  macOS'un çökme raporu için birkaç saniye bekler ve bir panel açar: anlaşılır bir dille neden, Mac,
  motor, günlüğün sonu. **Raporu Dışa Aktar** günlüğü, çökme raporunu, son kilit açmanın çıktısını ve
  oyunun ayarlarını tek bir dosyaya kaydeder; **Sorun Bildir** neyin paylaşılacağını gösterir ve önceden
  doldurulmuş bir GitHub issue'su açar (AnyPS5-ARM'ınkini ya da upstream motorun formunu). Önce ev
  klasörü, adlar, e-posta adresleri ve AnyTogether token'ları çıkarılır. **Ayrıntılı Günlük (İz)** ve
  tek seferlik **Ayrıntılı Günlükle Oyna**, zor bir hata için daha fazlasını kaydeder.

### Launcher için kurallar

- **Hiçbir şey oynamayı engellemez.** Her çağrı zaman aşımlı ve asenkrondur; başarısızlıklar giden
  kutusuna gider ya da sessiz bir durum göstergesiyle bildirilir, asla modal pencereyle değil.
- **Giriş yapmadan da deneyim eksiksizdir.** Hiçbir AnyTogether öğesi rahatsız edecek şekilde görünmez;
  Ayarlar → AnyTogether'da bir satır.
- **İzinler kullanıldığı anda istenir**: mikrofon sese ilk katılışta, ekran kaydı ilk share play'de
  (Remote Play ve klipler zaten istiyor).
- **Testler** telefon sunucusununkiler gibi: süreç içinde sahte bir API ve gateway; giden kutusu
  çevrimdışı/çevrimiçi geçişlerine karşı test edilir; istemciler arası test gerçek sunucuya karşı.
- **İmzalama**: sürüm derlemeleri Developer ID ile imzalanır; bu, mikrofon ve ekran kaydı izinlerini
  güncellemelerden sonra da korur.

## 7.2 Windows ve Linux launcher'ı (AnyPS5 Desktop)

[AnyPS5 Desktop](https://github.com/utkuhalis/AnyPS5-Desktop), launcher'ın Windows ve Linux portudur;
Flutter ile yazılmış, herkese açık (GPL-2.0) bir proje: aynı PS5 tarzı ana ekran, kütüphane, kilit
açma, kontroller, kupalar, kayıtlar ve telefon kumandası. AnyTogether'a, diğer istemcilerin
kullandığı aynı API ve gateway üzerinden kendisi bağlanır; sunucuda macOS'a özgü hiçbir şey yok. 0.1.1
erken bir önizleme.

**Kurulum**: bir Windows kurulum programı (Inno Setup, `AnyPS5-Desktop-Setup-<version>-x64.exe`:
varsayılan olarak kullanıcı başına, yönetici izni gerekmez, Başlat menüsü kısayolu, bir kaldırma
programı, yükseltmeden önce çalışan launcher kapatılır) ya da taşınabilir bir zip; Linux'ta Ubuntu
22.04'te derlenmiş bir AppImage, bir `.deb` (`/opt/anyps5-desktop`) ya da bir tar.gz. Derlemeler henüz
kod imzalı değil, bu yüzden SmartScreen uyarı verebilir.

**Motor kendini indirir**: ilk açılışın son adımı **AnyPS5 motorunu indir** seçeneğini sunar. Launcher
upstream [AnyPS5](https://github.com/boykopovar/AnyPS5)'in son sürümünü okur, sistem için relinker'ı ve
sistem kütüphanelerini indirir (kaldığı yerden devam edebilir, her dosya GitHub'ın yayımladığı SHA-256'ya
karşı kontrol edilir; SHA-256'sı olmayan bir dosya yalnızca ikinci, açık bir seçimle), hiçbir adın ya da
bağlantının klasörün dışına çıkmasına izin vermeden açar ve her sürüm için bir klasör tutar. Ayarlar →
AnyPS5 Motoru kullanılan motoru gösterir, güncellemeleri denetler, sürümleri listeler, diğerlerini siler
ya da kendi klasörünü kullanır. Daha yeni bir motor çıktığında kurulu oyunlar **Güncelle ve Oyna**
seçeneğini sunar. Oyun oturumu sürüm kontrolünün karşılaştırdığı, oyunun kurulduğu motor derlemesidir.

AnyTogether kısmı (`lib/core/together/`), yapıldı ve sürümde:

| Kısım | Ne yapar |
|---|---|
| Giriş | bir e-posta kodu, web sitesinde onaylanan bir kod (passkey'ler ve web sitesinin diğer giriş yolları orada çalışır) ya da tek dokunuşla eşleşmiş telefon, iki yönde de; Ayarlar'da başka bir sunucu ya da `ANYTOGETHER_URL` |
| Canlı | gateway soketi, çevrimiçi durumu (bir oyun çalışırken, oyun ID'siyle birlikte oyunda), arkadaşlar |
| Senkronizasyon | diskteki bir giden kutusu (`Together/outbox.json`) üzerinden oyun oturumları ve kupalar: çevrimdışıyken hiçbir şey kaybolmaz, hiçbir şey iki kez sayılmaz |
| Arkadaşlar, mesajlar, parti | istekler, kullanıcı adıyla ekleme, her arkadaşın ne oynadığı; bir kumandanın gönderebileceği hızlı yanıtlarla ve iki yönde yazıyor bilgisiyle konuşmalar; sesli partiler |
| Ses | `flutter_webrtc` üzerinden web sitesinin protokolü, konuşma için ayarlanmış Opus; oyunun üstünde de çalışan bir konuşma tuşu (varsayılanı V): Windows'ta `GetAsyncKeyState`, X11'de `XQueryKeymap` |
| Profiller | kendininki ve bir arkadaşınki: oynama süresi ve kupa ilerlemesiyle oyunlar, nadirlikleriyle son kupalar |
| Arkadaşın oyununa katılma | bir oyun çalışırken bir oyun oturumu; Katıl, oyunun kurulu olduğunu, oyun sürümünü ve motor derlemesini kontrol eder, katılır ve oyunu başlatır; motorun çevrimiçi köprüsü için oturum `Together/game-session.json` içinde |
| Token'lar | Windows: geçerli kullanıcı için DPAPI ile mühürlenmiş bir dosya; Linux: bir anahtarlık yanıt verirse `secret-tool` üzerinden Secret Service, yoksa 0700 bir klasörde 0600 bir dosya |

Planlandı: share play (host ve izleyici), akış, liderlik tabloları, bildirimler, Tema Hub'ı, uyumluluk
raporları, tarayıcı üzerinden sağlayıcılarla giriş. Launcher'ın share play için platformundan ihtiyaç
duydukları:

| İhtiyaç | Windows | Linux |
|---|---|---|
| Oyun yakalama | Windows.Graphics.Capture (oyun penceresi) | xdg-desktop-portal üzerinden PipeWire ekran yayını (kullanıcıya bir kez sorar) |
| Oyun sesi | WASAPI process loopback (yalnızca oyunun süreci) | oyunun düğümünün PipeWire akışı |
| Düşük gecikmeli H.264 | Media Foundation donanım MFT'si ya da doğrudan NVENC / AMF / Quick Sync | VA-API (Intel, AMD) ya da NVENC |

Telefon uygulaması (7.3) bu launcher'la da macOS'takiyle olduğu gibi çalışır: AnyPS5 Desktop telefon
protokolünü (WebSocket 47700 portunda eşleştirme, UDP ile kumanda, kablo yolları) konuşur; protokol
[Platformlar](12-platformlar.md) 12.4'te yazılı. Kumandanın oyuna ulaşması motorun uzak kumanda
köprüsünü gerektirir; bu köprü bugün motorda yalnızca POSIX'te var (Linux çalışıyor; Windows için bir
Winsock portu AnyPS5-ARM'ın `remotepad-winsock` branch'inde).

## 7.3 Telefon uygulaması (Flutter)

### Kod

`mobile/lib/together/`, yapıldı: `together_account.dart` (e-posta koduyla ya da devir üzerinden Mac'in
hesabıyla giriş, bir launcher'ın devir isteğini onaylama, başka bir sunucu), `together_socket.dart`,
`together_hub.dart`, `people.dart`, `friends.dart`, `profiles.dart`, `messages.dart`, `groups.dart`,
`typing.dart`, `parties.dart`, `calls.dart`, `voice.dart`, `voice_mesh.dart` ve `voice_webrtc.dart`
içinde ses, `feed.dart` ve `activity.dart`, `leaderboards.dart`, `notifications.dart`, ve
`share_play.dart` ile `share_play_webrtc.dart` içinde share play (`flutter_webrtc`, relay kimlik
bilgileri süreleri dolmadan yenilenir).

### Ekranlar (1.11.0)

| Ekran | Nedir |
|---|---|
| Hesap | bir e-posta kodu ya da tek dokunuşla Mac'in hesabı; profilini ve resmini düzenleme |
| Onay | bir launcher istediğinde (devir) "<Mac/PC adı> cihazında oturum açılsın mı?": tek dokunuş |
| Arkadaşlar | çevrimiçi durumu, istekler, profiller; yakında bir bilgisayar olmadan da açılır |
| Mesajlar | konuşmalar ve gruplar, yazıyor bilgisi |
| Parti ve görüşmeler | üyeler, davetler, ses; bir arkadaşla birebir görüşmeler, herkesin gördüğü mikrofon kapatma |
| Etkinlikler, Sıralama | tepkilerle akış; genel ve oyun başına tablolar |
| Bildirimler | zil ve listesi |
| Share play | Arkadaşlar'dan ya da bir davetten **İzle**: görüntü yalnızca alan bir WebRTC bağlantısında, ses Remote Play'in hoparlöründen; host bir kumanda verdiğinde Remote Play kumandası görüntünün üstüne gelir ve titreşim ve ışık çubuğuyla onun 2-4. oyuncusu olarak oynar; kimin oyunu, hangi oyuncu, gidiş-dönüş süresi, fps ve yükseklik gösteren bir etiket |
| Mesajlar, davetler, arkadaşlık istekleri için anlık bildirimler | planlandı |

### Telefon için kurallar

- Yerel ağ üzerindeki kumanda tam olarak olduğu gibi kalır; telefon ile bilgisayar bir aradayken
  AnyTogether asla aralarına girmez.
- Anlık bildirim (planlandı): APNs (iOS) ve FCM (Android) token'ları oturum başına kaydedilir;
  bildirimler yalnızca ID'leri ve kısa bir metni taşır; içerik açıldığında çekilir.
- Pil: gateway soketi arka planda kapatılır (anlık bildirimler var olduğunda onlar devralır), uygulamaya
  dönüldüğünde açılır.

## 7.4 Web sitesi (Next.js)

Aksi belirtilmedikçe hepsi yapıldı.

| Sayfa | Yol |
|---|---|
| Ana sayfa: AnyTogether nedir; giriş yapılmışken tepkilerle arkadaşların akışı | `/` |
| Giriş (e-posta kodu ya da bağlantısı, passkey; ilk seferde hesap oluşturulur) | `/login`, `/login/email` |
| Bir launcher'ın cihaz kodunu onaylama | `/link` |
| Oyunlar, oynama süresi, kupalar ve son aktivitelerle profil (herkese açık, SSR); oradan birini şikâyet etme | `/u/<handle>` |
| Arkadaşlar, mesajlar ve gruplar, sesli parti; her sayfadan bir arkadaşa görüşme | `/friends`, `/messages`, `/party` |
| Bir arkadaşın share play'ini izleme ve kumanda verildiğinde bir kumandayla ya da klavyeyle birlikte oynama | `/watch/<id>` |
| Oyuncu bul: oyuncu arama panosu; herkese açık partiler ve share play'lerle Şu an canlı; kişiler | `/find`, `/find/live`, `/find/people` |
| Oyun sayfası: şu an kimin oynadığı, ilanlar, herkese açık partiler ve share play'ler, en iyi oyuncular, nasıl çalıştığı, temalar | `/games/<title id>` |
| Liderlik tabloları | `/leaderboards` |
| Tema Hub'ı, bir tema, tema paylaşma, temaların | `/themes`, `/themes/<id>`, `/themes/new`, `/themes/mine` |
| Uyumluluk listesi ve bir oyunun raporları; rapor gönderme | `/compatibility`, `/compatibility/<title id>` |
| İndirmeler: macOS launcher'ı, telefon uygulaması, AnyPS5 Desktop, son sürümlerinden | `/download` |
| Bildirimler ve cihaz başına açılan tarayıcı bildirimleri | `/notifications` |
| Ayarlar: profil, avatar, gizlilik, keşif, bildirimler ve e-posta özeti, passkey'ler, giriş yapılmış cihazlar, her yerden çıkış, verilerimi indir, hesabı sil | `/settings` |
| Moderatör sayfası: kararlarıyla şikâyetler, hesaplar, yasaklamalar, denetim günlüğü (yalnızca yöneticiler; diğerleri "bulunamadı" alır) | `/admin` |
| Kurallar, gizlilik politikası, kullanım koşulları, KVKK aydınlatma metni | planlandı |
| Profiller ve oyun sayfaları için Open Graph görselleri | planlandı |

Görünüm launcher'ın konsol tarzını (koyu, mavi/mor/turkuaz vurgular, Space Grotesk ve JetBrains Mono)
izler, telefonlarda da. Varsayılan dil İngilizce, Türkçe bir seçiciyle. Tarayıcı hiç token tutmaz:
sitenin sunucusu token'ları HttpOnly çerezlerde saklar ve sayfa gateway soketini açarken API'den tek
kullanımlık bir bilet ister. Her sayfa güvenlik başlıkları taşır (çerçeve içine alınamaz, sıkı bir
referrer politikası, mikrofon yalnızca sitenin kendisi için) ve sitenin kendi yolları başka sitelerin
sayfalarından gönderilen değişiklikleri reddeder.

## 7.5 Ortak parçalar

- **Türler**: bugün her istemci kendi türlerini `packages/shared` içindeki Zod şemalarına göre yazar;
  Swift ve Dart türlerinin bir OpenAPI belgesinden üretilmesi planlandı.
- **Metinler**: hata `code`'ları ve olay adları her istemcide çevrilir (İngilizce, Türkçe).
- **Telefon protokolü** (eşleştirme, kumanda, kablo, AnyTogether devri) ve **kumanda paketi** tek bir
  yerde tanımlanır; böylece macOS launcher'ı, AnyPS5 Desktop, telefon uygulaması ve share play'in
  kumanda kanalı birlikte çalışabilir.
- **Görseller**: AnyTogether işareti (favicon'daki iki halka) launcher'da, telefonda ve web'de.
