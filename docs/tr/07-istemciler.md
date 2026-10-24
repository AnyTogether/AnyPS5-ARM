# 7. İstemciler

Üç kapı. Launcher ve telefon uygulaması AnyPS5-ARM içinde, web sitesi ise AnyTogether deposunda
yaşar.

## 7.1 Launcher (macOS, Swift)

### Yeni kod

`tools/macos/launcher/Sources/AnyPS5Core/Together/` (test edilebilir, arayüz yok):

| Dosya | Görevi |
|---|---|
| `TogetherClient.swift` | `/v1`'e HTTP çağrıları, aynı anda tek bir yenileme işlemiyle token yenileme, problem ayrıntısı hataları, `AnyTogether-Client` başlığı |
| `TogetherAuth.swift` | cihaz bağlama (RFC 8628): kod iste, yokla, yenileme token'ını Keychain'e kaydet |
| `TogetherSocket.swift` | anlık iletişim gateway'i: hello, çevrimiçi durumu taşıyan heartbeat'ler, resume, artan bekleme süreleriyle yeniden bağlanma (1, 2, 4 … 30 sn, jitter ile) |
| `TogetherOutbox.swift` | oturumlar, kupalar, katalog kayıtları ve raporlar için SQLite'ta (`Application Support/AnyPS5/Together/outbox.sqlite`) yalnızca ekleme yapılan bir kuyruk; çevrimiçiyken gruplar hâlinde gönderir, tür başına sırayı korur, hiçbir şeyi atmaz |
| `TogetherModels.swift` | OpenAPI belgesinden üretilen tipler |
| `TrophySync.swift` | launcher'ın `TrophySet`'ini kupa seti yüklemelerine ve kazanılan kupalara dönüştürür |
| `SessionRecorder.swift` | oyun başlangıç/bitişlerini (Discord ve kayıt senkronizasyonu için zaten izleniyor) oturumlara dönüştürür |
| `PartyVoice.swift` | LiveKit Swift SDK: parti odasına katılma, mikrofon, sessize alma, bas-konuş, konuşma olayları |
| `SharePlay.swift` | `RemotePlay`'in karelerini ve sesini LiveKit'e yayımlar; veri kanalından gelen kumanda paketlerini bir `RemoteServer` köprü yuvasına aktarır |

Uygulama hedefi (`Sources/AnyPS5/`):

| Ekran | Nedir |
|---|---|
| Üst çubuk | profil çipi durum noktalı bir avatara dönüşür; çevrimiçi sayısını gösteren bir Arkadaşlar düğmesi; okunmamış sayısını gösteren bir Mesajlar düğmesi |
| Giriş paneli | "AnyTogether'a giriş yap": kod, bir QR, "Bu Mac'te aç" (web'deki bağlama sayfasını açar) |
| Profil katmanı | kendi kartın (kendi temanla), ad/biyografi/avatar/vitrin düzenleme, gizlilik |
| Arkadaşlar paneli | çevrimiçi durumları ve oyunlarıyla liste; istekler; kullanıcı adı ya da QR ile ekleme; her arkadaş için: profil, mesaj, partiye davet |
| Mesajlar paneli | sohbetler ve bir sohbet görünümü; kumandayla kullanılabilir (ekran klavyesi macOS'un klavyesidir; kumanda kullanan biri hazır yanıtlar gönderebilir) |
| Parti kartı | kenarda yüzen bir kart: üyeler, konuşma halkaları, sessize alma, bas-konuş ipucu, Share play düğmesi; oyunun üzerinde küçük bir katman olarak kalır (kupa bildirimi gibi) |
| Akış paneli | arkadaşların aktiviteleri |
| Tema Hub'ı | mevcut Temalar ekranı AnyTogether'ın dizinini okur; "Hub'da paylaş" yükleme yapar |
| Oyun sayfası | oyunu oynayan arkadaşlar, kupalarda nadirlik, topluluk uyumluluğu, oturumdan sonra "Nasıl çalıştı?" sorusu (isteğe bağlı) |

### Launcher için kurallar

- **Hiçbir şey oyunu engellemez.** Her çağrı zaman aşımlı ve asenkrondur; hatalar giden kutusuna
  gider ya da modal pencere yerine sessiz bir durum olarak gösterilir.
- **Giriş yapmadan da deneyim eksiksizdir.** Hiçbir AnyTogether öğesi rahatsız edecek şekilde
  görünmez; Ayarlar → AnyTogether'da bir satır, güncellemeden sonraki ilk açılışta bir kart
  ("Yeni: AnyTogether", tek basışla kalıcı olarak kapatılır).
- **İzinler kullanılacağı an istenir**: mikrofon ilk parti sesli sohbetinde, ekran kaydı ilk Share
  play'de (Remote Play/Klipler tarafından zaten isteniyor).
- **Testler** telefon sunucusununkiler gibi: süreç içinde sahte bir API ve gateway; giden kutusu
  çevrimdışı/çevrimiçi geçişlerine karşı, cihaz bağlama sahte bir onayla test edilir.
- **İmzalama**: mikrofon ve ekran kaydı izinlerinin güncellemeler arasında korunması için sürüm
  derlemelerinin sabit bir imzası (Developer ID Application) olmalı, bkz. açık sorular.

## 7.2 Telefon uygulaması (Flutter)

### Yeni kod

`mobile/lib/together/`: `together_client.dart`, `together_socket.dart`, `auth.dart` (e-posta,
Apple, Discord; cihaz bağlama onayı), `party_voice.dart` (LiveKit Flutter), `share_play_view.dart`.

### Ekranlar

| Ekran | Nedir |
|---|---|
| Hesap | giriş yap / kayıt ol; ya da "Launcher'ın hesabını kullan": launcher ile eşleşmiş telefon, launcher'dan telefon için bir oturumu onaylamasını ister (parola yazılmaz) |
| Onay | launcher'ın QR'ını taramak ya da kodunu yazmak Mac'i tek dokunuşla onaylar |
| Arkadaşlar, Mesajlar, Akış | mevcut launcher modunun yanında sekmeler; mesajlar, davetler ve arkadaşlık istekleri için anlık bildirimler |
| Parti | üyeler, ses (telefon kumanda olarak kullanılırken sesi de taşıyabilir), Share play izleyicisi |
| Share play izleyicisi | yayın tam ekranda, kumanda onun üzerinde; bugün Remote Play'de görüntünün üzerindeki kumandanın aynısı; her yerden çalışır |
| Profil | kendi kartın ve başkalarınınki |

### Telefon için kurallar

- Yerel ağ üzerinden kumanda olduğu gibi kalır; telefon ve Mac yan yanayken AnyTogether asla
  araya girmez.
- Anlık bildirim: APNs (iOS) ve FCM (Android) token'ları oturum başına kaydedilir; bildirimler
  yalnızca kimlikleri ve kısa bir metni taşır; içerik açıldığında çekilir.
- Pil: gateway soketi arka planda kapatılır (yerine anlık bildirimler geçer), uygulama öne
  geldiğinde yeniden açılır.

## 7.3 Web sitesi (Next.js)

| Sayfa | Yol |
|---|---|
| Açılış sayfası ("Çok yakında"nın yerini alır) | `/` |
| Giriş / kayıt / cihaz bağlama | `/login`, `/signup`, `/link` |
| Profil (herkese açık, SSR, Open Graph görseli) | `/u/<handle>` |
| Bir profilin kütüphanesi, kupaları | `/u/<handle>/games`, `/u/<handle>/trophies/<title id>` |
| Oyun sayfası | `/g/<title id>` |
| Arkadaşlar, mesajlar, akış, parti (giriş yapılmış) | `/friends`, `/messages`, `/feed`, `/party/<id>` |
| Tema Hub'ı | `/themes`, `/themes/<id>` |
| Liderlik tabloları | `/leaderboards` |
| İndirmeler | `/download` |
| Ayarlar, gizlilik, veri dışa aktarımı, hesap silme | `/settings/...` |
| Kurallar, gizlilik politikası, kullanım koşulları, KVKK aydınlatma metni | `/rules`, `/privacy`, `/terms`, `/kvkk` |

Görünüm "çok yakında" sayfasını (koyu, `#07080c`, mavi/mor/turkuaz vurgular, Space Grotesk ve
JetBrains Mono) ve launcher'ın konsol stilini izler. Giriş yapmış bir kullanıcının kendi sayfaları
onun profil temasıyla görünür. İngilizce ve Türkçe; tarayıcı diline göre seçilir, bir anahtarla
değiştirilebilir.

## 7.4 Ortak parçalar

- **Tipler**: OpenAPI belgesinden Swift (swift-openapi-generator) ve Dart (openapi-generator
  dart-dio ya da küçük, elle yazılmış bir üretici) için üretilir; böylece üç istemci aynı dili konuşur.
- **Metinler**: hata `code`'ları ve olay adları her istemcide çevrilir (İngilizce, Türkçe).
- **Görseller**: AnyTogether logosu (favicon'daki iki halka) launcher'da, telefonda ve web'de
  kullanılır.
