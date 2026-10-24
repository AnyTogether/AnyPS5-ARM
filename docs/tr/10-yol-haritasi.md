# 10. Yol haritası

Her aşama insanların kullanabileceği bir şey çıkarır; bu, oturana kadar launcher'da bir anahtarın
arkasında durur. "Bitti", "kod yazıldı" demek değildir; listesindeki her kontrolün geçmesi demektir.

## Nerede duruyor (2026-10-24)

Kod herkese açık ve MIT lisanslı:
[github.com/utkuhalis/AnyTogether](https://github.com/utkuhalis/AnyTogether). "Sürümde", AnyPS5-ARM
v0.2.13-arm'da (telefon uygulaması 1.9.1) demektir; "sonraki sürüm", AnyPS5-ARM'ın `main` dalında olup
henüz sürüme girmemiş demektir.

| Aşama | Durum |
|---|---|
| 0 Temeller | **büyük ölçüde yapıldı.** Depo, API, gateway, web sitesi, CI. E-posta kodu ya da bağlantısıyla giriş, passkey'ler (web), telefondan devir, cihaz kodu; Apple, Google ve Discord API'de doğrulanıyor. macOS launcher'ı ve telefon giriş yapıyor (sürümde). Kalanlar: istemcilerde sağlayıcı düğmeleri, OpenAPI belgesi, staging, R2'ye yedekler, yasal sayfalar. |
| 1 Profil, kütüphane, kupalar | **büyük ölçüde yapıldı.** Profiller, kullanıcı adları, avatarlar, gizlilik; katalog, oturumlar, kütüphane, kupa setleri, nadirlik; launcher oynama süresini ve kupaları gönderiyor (sürümde) ve profilleri gösteriyor (sonraki sürüm); web profilleri. Kalanlar: vitrin, profil teması, avatar denetimi, launcher'ın kupa ekranında tarih ve nadirlik, Open Graph görselleri. |
| 2 Arkadaşlar, çevrimiçi durumu, akış, liderlik tabloları | **arkadaşlar ve çevrimiçi durumu yapıldı** (web; launcher sürümde; telefon sonraki sürüm). Kalanlar: QR kodları, akış, liderlik tabloları. |
| 3 Mesajlar ve anlık bildirim | **mesajlar metin için yapıldı** (web; launcher ve telefon sonraki sürüm). Kalanlar: görseller, tepkiler, yazıyor göstergesi, anlık bildirimler. |
| 4 Partiler ve ses | **yapıldı**: partiler, çağrılar, web'de, launcher'da ve telefonda (sonraki sürüm) eşten eşe ses, macOS'ta bas-konuş, relay desteği; ve oyun oturumlarıyla **arkadaşın oyununa katılma** (launcher, sonraki sürüm). Kalanlar: parti sohbeti, kulaklık olarak telefon, görüşme kalitesi raporları. |
| 5 Share play | planlandı, **yalnızca izleme**. |
| 6 Tema Hub'ı, indirmeler, uyumluluk | planlandı. |
| 7 Çevrimiçi oyun | **tasarım aşamasında**: AnyPS5-ARM'ın `online-play` branch'inde motor köprüsü; sunucudaki oyun oturumları yapıldı. |
| Kendi sunucunu kurmak | **yapıldı**: Docker Compose ve bir kurulum rehberi; launcher ve telefon başka bir sunucuya yönlendirilebilir (sonraki sürüm). |
| Windows ve Linux | [AnyPS5-Desktop](https://github.com/utkuhalis/AnyPS5-Desktop) herkese açık ve geliştiriliyor; AnyTogether kısmı planlandı. |

## Plan

İş başlamadan önce yapılan ilk plan (sıra hâlâ geçerli; 0-4 arası aşamaların çoğu bu tarihlerin çok
önünde yapıldı):

```mermaid
gantt
    dateFormat YYYY-MM-DD
    axisFormat %b
    section Temel
    0 Temeller           :p0, 2026-11-01, 3w
    section Ben
    1 Profil, kütüphane, kupalar :p1, after p0, 4w
    section Birlikte
    2 Arkadaşlar, çevrimiçi durumu, akış, liderlik tabloları :p2, after p1, 3w
    3 Mesajlar ve anlık bildirim     :p3, after p2, 3w
    4 Partiler ve ses     :p4, after p3, 4w
    5 Share play            :p5, after p4, 5w
    section Raf
    6 Tema Hub'ı, indirmeler, uyumluluk :p6, after p2, 3w
    section Çevrimiçi
    7 Çevrimiçi oyun      :p7, after p4, 6w
```

Tarihler; sunucu, macOS launcher ve telefon uygulaması üzerinde Claude ile çalışan tek bir
geliştirici için yol göstericidir; Windows/Linux launcher'ını AnyPS5-Desktop aynı API ve protokollere
göre kendisi bağlar. 6. aşama 3-5 ile paralel yürüyebilir.

## Aşama 0: Temeller (≈3 hafta)

**Çıkanlar**: depo, sunucu, tek dokunuşla giriş ve oturumu açık tüm launcher'lar.

- AnyTogether monorepo'su (apps/api, realtime, worker, web; packages/shared, db), CI, staging.
- Sunucumuzda: uygulamalar (web, api, realtime, worker), PostgreSQL ve Valkey,
  bellek sınırları, R2'ye yedekler, `anytogether.kodla.agency` üzerinde `/api` ve `/rt` yolları.
- Giriş: Apple, Google, Discord (OpenID Connect + PKCE), e-posta kodları, passkey'ler, telefona
  devretme, cihaz kodu yedeği; ilk giriş hesabı oluşturur; oturumlar; refresh rotasyonu.
- hello, heartbeat ve resume destekli realtime gateway (üzerinde henüz özellik yok).
- macOS launcher: `TogetherClient`, `TogetherAuth`, `TogetherSocket`, Ayarlar → AnyTogether →
  Apple / Google / Discord / telefon / e-posta ile devam et, üst çubukta oturum açık rozeti.
- OpenAPI belgesi ve gateway protokolü sürümlü olarak yayımlanır; böylece her launcher (ilk olarak
  AnyPS5-Desktop) bizim yardımımız olmadan bağlanabilir. Kodun kendisi de herkese açık.
- macOS launcher sürüm derlemeleri Developer ID ile imzalanır ve notarize edilir.
- Web sitesi: "Coming soon"un yerini alan açılış sayfası, tek dokunuşla giriş, `/link`, ayarlar,
  gizlilik sayfaları.

**Bitti sayılması için**
- [ ] Yeni bir kullanıcı launcher'da "Google ile devam et"e dokunur ve tek dokunuşta hesabı
      oluşturulmuş olarak giriş yapar (tarayıcıda Google'a zaten giriş yapmışken); web'de
      çıkış yapmak launcher'ın da oturumunu 5 s içinde kapatır.
- [x] Oturumu açık telefon, launcher'a tek dokunuşla giriş yaptırır.
- [ ] Yayımlanan OpenAPI belgesi doğrulanır ve çalışan API ile örtüşür (CI).
- [ ] Sunucuya ulaşamayan bir launcher, AnyTogether'dan önce nasıl davranıyorsa tam olarak öyle
      davranır (otomatik test).
- [ ] Yedekler staging'e geri yüklenir; geri yükleme testi yeşil.
- [x] Refresh token'ın yeniden kullanılması oturumu iptal eder (test).

## Aşama 1: Profil, oyun kütüphanesi, kupalar (≈4 hafta)

**Çıkanlar**: oyuncu kartın, oyunların ve kupaların çevrimiçi.

- Profiller, kullanıcı adları, avatarlar (R2 + worker ile yeniden boyutlandırma + çıplaklık
  denetimi), vitrin, gizlilik ayarları.
- Oyun kataloğu, oturumlar (launcher `SessionRecorder` + outbox), oynama süreli kütüphane.
- Kupa setleri ve kazanılan kupalar (launcher `TrophySync`), nadirlik işi, puanlar.
- Launcher: profil katmanı, kupa ekranında ve bildirim bandında tarih ve nadirlik, tüm
  bilgisayarlardan toplanan oynama süresi. Telefon: profil kartı. Web: `/u/<handle>`, Open Graph
  görselli oyun ve kupa sayfaları.

**Bitti sayılması için**
- [ ] Silksong'u 10 dakika oynayıp bir kupa kazanmak, ikisini de 30 s içinde web profilinde
      gösterir; çevrimdışıyken, launcher yeniden bağlandıktan sonra bir kez görünürler.
- [ ] Tek hesaptaki iki bilgisayar (bir Mac ve bir Windows PC) oynama süresini doğru toplar.
- [ ] Bir kupanın nadirliği, staging verisinde elle yapılan sayımla eşleşir.
- [x] Gizli kupalar, onları kazanmamış kullanıcılara gizli kalır (test).

## Aşama 2: Arkadaşlar, çevrimiçi durumu, aktivite akışı, liderlik tabloları (≈3 hafta)

- Arkadaşlık istekleri (kullanıcı adı, QR), engellemeler, oyunlarla birlikte çevrimiçi durumu,
  gruplamalı akış, beğeniler ve yorumlar, liderlik tabloları (oyun başına arkadaşlar ve genel).
- Launcher: Arkadaşlar paneli, çevrimiçi sayısı, akış paneli, oyun sayfasında "oynayan
  arkadaşlar". Telefon: Arkadaşlar ve Akış sekmeleri. Web: arkadaşlar, akış, liderlik tabloları.

**Bitti sayılması için**
- [ ] Bir oyunu başlatmak, bir arkadaşın launcher'ında 3 s içinde "X oynuyor" gösterir; oyunu
      kapatmak en geç 60 s içinde (süre dolumu), genellikle anında yansır.
- [x] "Hiç kimse" yapılan çevrimiçi durumu ve engellemeler çevrimiçi durumunu tamamen gizler (test).
- [ ] Bir saat içindeki beş kupa için akış tek bir gruplanmış öğe gösterir.

## Aşama 3: Mesajlar ve anlık bildirim (≈3 hafta)

- Birebir ve grup sohbetleri, ekler, okundu durumu, yazıyor göstergesi, şikâyetler.
- Telefon için anlık bildirim (APNs, FCM); launcher'da oyundan odağı çalmayan bildirim balonları.

**Bitti sayılması için**
- [ ] Web'den gönderilen bir mesaj launcher'a 1 s'nin altında, kilitli bir telefona da anlık
      bildirim olarak 5 s'nin altında ulaşır.
- [x] Gönderim ortasında ağı kesip yeniden göndermek hiçbir zaman mesajı çoğaltmaz (test).
- [ ] Okunmamış sayıları üç kapının hepsinde tutarlıdır.

## Aşama 4: Partiler ve ses (≈4 hafta)

- Sunucuda coturn (`anytogether-relay.kodla.agency`; 3478 ve 5349 portları ile relay (aktarma
  sunucusu) aralığı Utku'nun onayıyla açılır); gateway üzerinden görüşmeler ve sinyalleşme; her
  launcher'da (macOS'ta WebRTC framework'ü; Windows/Linux portunda kendi WebRTC kütüphanesi), telefonda
  (`flutter_webrtc`) ve web'de eşten eşe (P2P) ses; bas-konuş; kulaklık olarak telefon; parti
  sohbeti; oyun sürümü ve motor derlemesi kontrol edilerek oyun oturumlarıyla arkadaşın oyununa katılma.

**Bitti sayılması için**
- [ ] Beş kişi (Mac, Windows PC, Linux, iPhone, tarayıcı) 30 dakika boyunca kopmadan konuşur;
      Türkiye/Avrupa içinde ağızdan kulağa gecikme 200 ms'nin altındadır (ölçülmüş).
- [ ] Görüşmelerin çoğu doğrudan bağlanır; kalite raporları relay gereken
      oranı gösterir.
- [ ] Önde bir oyun açıkken ses devam eder; parti katmanı kimin konuştuğunu gösterir.
- [ ] UDP'yi engelleyen bir ağın arkasındaki kullanıcı TURN/TLS üzerinden katılır.
- [x] Bir arkadaş yayıncının oyununa yalnızca aynı oyun sürümü ve motor derlemesiyle katılır (test).

## Aşama 5: Share play (birlikte oynama, ≈5 hafta)

- **Yalnızca izleme**: izleyiciler görür ve duyar, kontrol hiçbir zaman onlara geçmez.
- Her launcher ev sahipliği yapar: macOS `RemotePlay`'in yakalaması ve düşük gecikmeli H.264 ile,
  Windows ve Linux kendi yakalama ve donanım kodlayıcılarıyla; her izleyiciye doğrudan, gerekirse
  relay üzerinden; izleyiciler telefonda, web'de, herhangi bir launcher'da; kalite kademeleri;
  gecikme rozeti.

**Bitti sayılması için**
- [ ] 500 km uzaktaki bir arkadaş 720p60'ı 120 ms'nin altında (medyan) ekrandan ekrana gecikmeyle
      izler; hem ev sahibi bir Mac iken hem de ev sahibi bir Windows PC iken.
- [ ] Bir izleyicinin gönderdiği hiçbir şey ev sahibinin oyununa ulaşmaz (test).
- [ ] Zayıf bir ağ, 500 ms'den uzun donmadan kaliteyi düşürür.

## Aşama 6: Tema Hub'ı, indirmeler, uyumluluk (≈3 hafta, 3-5 ile paralel)

- Studio'dan tema yükleme, moderasyon kuyruğu, beğeniler, sürümler; launcher'ın Temalar ekranı
  API'den okur (GitHub klasörü yedek olarak kalır); profil temaları.
- Yansılanmış sürümler ve sağlama toplamlarıyla İndirmeler sayfası; `GET /releases/latest`.
- Uyumluluk raporları (isteğe bağlı) ve oyun sayfalarında ve launcher'ın kütüphanesinde
  değerlendirmeler.
- Sonra aynı rafta: telefon kol düzenleri, oyun başına ön ayarlar, paylaşılan shader önbellekleri.

**Bitti sayılması için**
- [ ] Studio'da yapılan bir tema, onaylandıktan 1 dakika sonra başka bir kullanıcı tarafından
      kurulabilir.
- [ ] İndirmeler GitHub sürümleriyle bayt bayt eşleşir (CI'da sağlama toplamı testi).
- [ ] Uyumluluk raporlarını kapatınca hiçbir şey gönderilmez (test).

## Aşama 7: Çevrimiçi oyun (tasarım aşamasında)

Her oyuncu oyunu kendi bilgisayarında çalıştırır ve kopyalar, PlayStation Network üzerindeymiş gibi,
AnyTogether üzerinden birlikte oynar. Tasarım: AnyPS5-ARM'ın `online-play` branch'inde
[ONLINE_PLAY.md](https://github.com/utkuhalis/AnyPS5-ARM/blob/online-play/docs/dev/ONLINE_PLAY.md);
özeti [Anlık iletişim](06-anlik-ses-birlikte-oynama.md) 6.7'de.

- Motor: kimliği doğrulanmış loopback köprüsü, gözlem günlüğü, giriş durumu ve Plus kontrolleri, web
  API aktarımı, sanal adreslerde datagram trafiği (yapıldı, sahte bir launcher'a karşı test edildi);
  push olayları, oturum sinyalleşmesi, akışlar, katılma intent'leri (planlandı).
- Launcher: köprünün diğer ucu, oyun oturumlarına eşlenen `anyps5` API grubu, ilk eş bağlantısı (paket
  başına HMAC ile düz UDP), varsayılan olarak kapalı (branch'te yapıldı); relay ile WebRTC veri
  kanalları ya da QUIC (planlandı).
- AnyTogether: sürüm korumalı oyun oturumları (yapıldı); oyuncuların uç noktaları ve bir oturum
  anahtarı, oturum sinyalleşmesi (planlandı).

**Bitti sayılması için**
- [ ] Yalnızca platform servisleri üzerine kurulu bir oyunun iki kopyası önce tek bir Mac'te, sonra
      aynı ağdaki iki Mac'te, sonra relay üzerinden iki ayrı ağda birlikte oynar.
- [ ] Farklı bir oyun sürümü ya da motor derlemesi iki tarafta da nedeniyle reddedilir.
- [ ] Hiçbir şey Sony'ye gitmez ya da bir yayıncının sunucularının yerine geçmez (gözlem
      günlüklerinin incelenmesi).

## Sonrası

- Uçtan uca şifreli birebir mesajlar ve ses; telefon uygulamasının App Store / Play
  Store sürümleri; liderlik tablolarında turnuvalar ve meydan okumalar; arkadaşların
  arkadaşları için herkese açık share play'i izleme; topluluk araçları için açık bir API.
