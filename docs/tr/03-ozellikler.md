# 3. Özellikler

Her özellik için: kullanıcının launcher'da (L), telefon uygulamasında (P) ve web sitesinde (W) ne gördüğü;
nasıl çalıştığı; ve sistemin geri kalanından neye ihtiyaç duyduğu.

---

## 3.1 Profiller

**Kullanıcının gördüğü**

- Bir **oyuncu kartı**: avatar, görünen ad, @kullanıcı adı, biyografi (160 karakter), ülke bayrağı (isteğe bağlı),
  "üyelik tarihi" ve dört sayı: oynanan oyun, oynanan saat, kupa, platin.
- Kart **sahibinin temasını giyer** (Tema Stüdyosu'ndan): kartın arkasında temanın renkleri, kapak olarak
  temanın görseli ya da videosu, sayılarda temanın vurgu rengi.
- **Vitrin**: profilin en üstüne sabitlenmiş, seçilmiş en fazla altı oyun ya da kupa.
- L: üst çubuktaki profil adı avatara dönüşür; ona tıklayınca kartın açılır, düzenlemesi de orada yapılır. P: bilgisayarın
  adının altında aynı kart. W: `anytogether.kodla.agency/u/<handle>`, bağlantı önizlemeli (karttan render edilen
  Open Graph görseli) herkese açık bir sayfa.

**Nasıl çalışır**

- Hesap (giriş) ve profil (başkalarının gördüğü) ayrı tablolardır; bir profil, girişe dokunmadan
  yeniden adlandırılabilir.
- Kullanıcı adları: 3-20 karakter, `a-z 0-9 _ .`, büyük/küçük harf ayrımı gözetmeksizin benzersiz, 30 günde bir
  değiştirilebilir; eski kullanıcı adı 30 gün boyunca yenisine yönlendirir.
- Avatarlar: imzalı bir URL ile doğrudan R2'ye yüklenir (5 MB'a kadar PNG/JPEG/WebP); worker
  64, 128 ve 512 px WebP sürümlerini üretir ve avatar başkalarına gösterilmeden önce küçük bir sınıflandırıcıyla
  çıplaklık denetimi yapar (sahibi onu hemen görür).
- Dört sayı her görüntülemede değil, kupalar ya da oturumlar değiştiğinde worker tarafından hesaplanır.
- Öğe başına görünürlük (bkz. 3.5): herkes, arkadaşlar, yalnızca ben.

---

## 3.2 Kupalar

**Kullanıcının gördüğü**

- Oyun başına: launcher'ın bugün gösterdiği kupa listesi, artı her birinin **ne zaman** kazanıldığı,
  **nadirlik** (bu oyuna sahip AnyTogether oyuncuları içinde o kupaya sahip olanların oranı: "Ultra nadir %2.1")
  ve ilerlemesi olan kupalar için ilerleme.
- Profilde bir **kupa zaman çizelgesi**; öne çıkan **platin** kartları.
- Bir arkadaş nadir bir kupa kazandığında bu, akışta görünebilir (3.8).
- L: kupa ekranına tarihler ve nadirlik eklenir; kupa bildirimi nadir olduğunda "Nadir" der.
  P: bugün ekrana düşen kupa kartı nadirliği de gösterir. W: profilde "Kupalar" sekmesi.

**Nasıl çalışır**

- Launcher bir oyunun kupa setini (adlar, dereceler, gizli olanlar) dump'taki kupa dosyalarından
  zaten bilir ve oynarken kazanılan kupaları oyunun kayıt verisinden fark eder.
- İlk girişte launcher, sunucuda o set zaten yoksa **bildiği kupa setlerini** (title ID, kupa ID'leri,
  dereceler, kullanıcının dilinde adlar ve açıklamalar, küçük WebP olarak ikonlar), ardından da zamanlarıyla
  birlikte **kazanılmış kupaları** yükler.
- Kupa setleri ortaktır: bir oyunla giriş yapan ilk oyuncu, o oyunun setini sunucuya öğretir;
  diğerleri yalnızca kazandıklarını gönderir. Setler kupa dosyasının bir hash'ini taşır; böylece bir setin farklı
  bir sürümü eskisinin üzerine değil, yanına kaydedilir.
- Gizli kupalar, onları kazanmamış olanlara gizli kalır (adı ve açıklaması).
- **Nadirlik** = kupayı kazanan oyuncular ÷ oyunu en az bir kez oynamış oyuncular; değişen oyunlar için
  worker tarafından, oyun başına en fazla 10 dakikada bir hesaplanır ve kupa satırında önbelleğe alınır.
  Etiketler: Yaygın > %50, Az yaygın %20-50, Nadir %5-20, Çok nadir %1-5, Ultra nadir < %1.
- Bütünlük: bir kupa, launcher'ın bildirdiği gibi kabul edilir. Açıkça imkânsız örüntüler (bir oyunun tüm
  kupalarının aynı saniyede kazanılması, oyun ilk kez oynanmadan önce kazanılması) işaretlenir ve
  bir moderatör bakana kadar liderlik tablolarının dışında tutulur. Bunlar AnyTogether kupalarıdır;
  asla PlayStation Network'e gitmez.

---

## 3.3 Sesli sohbet

**Kullanıcının gördüğü**

- Bir partide (3.4) herkesin sesi; avatarlarının çevresinde konuşma halkası, her birinin ayrı ses
  düzeyi, susturma, sağırlaştırma, bas-konuş (bilgisayarda bir tuş, telefonda bir düğme).
- Oyun öndeyken de ses devam eder: launcher arka planda kalır ve partiyi taşımayı sürdürür;
  küçük bir kaplama kartı kimin konuştuğunu gösterebilir (bugünkü kupa bildirimi gibi).
- **Kulaklık olarak telefon**: partinin sesi bilgisayar yerine telefondan (mikrofonu ve hoparlörü ya da
  kulaklığı üzerinden) geçebilir; telefon bu sırada kontrolcü olmayı da sürdürür. Bilgisayarın hoparlörleri
  oyunun sesini verirken işe yarar.
- W: partinin sesli sohbetine kurulum gerektirmeden tarayıcıdan katılma.

**Nasıl çalışır**

- Ses **doğrudan üyeler arasında** akar (WebRTC; her üye diğer her üyeye bağlı;
  en fazla 8 konuşan üye). Sunucu yalnızca onları tanıştırır (gateway üzerinden sinyalleşme) ve ağları
  doğrudan bağlanamayan çiftlere relay (aktarma sunucusu) kimlik bilgilerini dağıtır.
- Ses: Opus, 48 kHz, 24-48 kbit/s; platformların yankı giderme, gürültü bastırma ve otomatik kazanç
  özellikleriyle (macOS/iOS'ta Apple'ın ses işleme altyapısı, Android'de ve web'de WebRTC'ninki).
- Her launcher'da (macOS, Windows, Linux): launcher'ın WebRTC'si kullanılır; oyunun kendi sesi gönderilmez
  (launcher yalnızca mikrofonu yakalar). Launcher'ın mikrofon izni istemesi gerekir.
- Hedef: aynı kıtada ağızdan kulağa gecikme 200 ms'nin altında; doğrudan bir yol, ağın kendisinin üzerine
  hiçbir şey eklemez.

---

## 3.4 Partiler

**Kullanıcının gördüğü**

- Launcher'dan, telefondan ya da web'den **parti kur**; arkadaşlarını davet et (anlık bildirim ve
  launcher'da bir kart alırlar); en fazla 8 üye.
- Parti **her üyenin ne oynadığını** gösterir ve **"Aynı oyunu oyna"** seçeneği sunar: bir üyenin
  launcher'ında, o oyun varsa onu seçer, yoksa olmadığını söyler.
- Partinin sesli sohbetin yanında bir yazılı sohbeti vardır (3.6'daki partiye bağlı grup sohbeti).
- Parti içinden yayıncı, diğerleri için **share play (birlikte oynama)** başlatabilir (3.11).
- Parti gizliliği: yalnızca davetle (varsayılan), arkadaşlar katılabilir ya da bağlantıya sahip herkes.

**Nasıl çalışır**

- Parti bir veritabanı satırıdır (sahip, gizlilik, oluşturulma zamanı); buna ilk üye sesi açtığında
  ihtiyaç anında kurulan bir çağrı eşlik eder.
- Üyelik değişiklikleri API üzerinden geçer ve gateway tarafından iletilir (`party.member_joined`,
  `party.member_left`, `party.updated`).
- 10 dakika boyunca hiçbir üyesi bağlı olmayan parti kendiliğinden sona erer.
- "Aynı oyunu oyna" `party.play_request {title_id}` gönderir; her launcher title ID'yi kendi
  kütüphanesinde arar. Oyunların kendisi hiçbir şekilde işin içine girmez.

---

## 3.5 Arkadaşlar

**Kullanıcının gördüğü**

- @kullanıcı adıyla, karşı tarafın telefonunda gösterilen bir QR koduyla ya da bir partiden ekleme; istekler
  kabul ya da reddedilebilir; arkadaşlar silinebilir, kullanıcılar engellenebilir.
- Çevrimiçi durumuyla bir **arkadaş listesi**: çevrimiçi, uzakta, çevrimdışı ve **ne oynadıkları** (oyunun
  adı ve ikonu, ne zamandır oynadıkları), partide olup olmadıkları.
- L: bir Arkadaşlar paneli (üst çubukta, kaç kişinin çevrimiçi olduğunu gösteren yeni bir öğe); ana ekran
  çevrimiçi arkadaşlardan oluşan küçük bir satır gösterebilir. P: bir Arkadaşlar sekmesi. W: arkadaşlar sayfası.

**Nasıl çalışır**

- Bir arkadaşlık, her çift için bir satırdır; bir durumu (bekliyor, kabul edildi) ve isteği kimin gönderdiği bilgisi vardır.
- **Çevrimiçi durumu**: her istemci gateway üzerinden 25 sn'de bir, durumunu içeren bir heartbeat gönderir
  (`online`; 10 dk boşta kalınca `away`; title ID ve başlama zamanıyla `in_game`). Gateway bunu
  60 sn ömürle Valkey'e yazar; değiştiğinde kullanıcının arkadaşlarına yayınlar.
  Birden fazla cihaz birleştirilir: oyunda, çevrimiçiye; çevrimiçi de uzaktaya üstün gelir.
- Engellediğin ya da "çevrimdışı görün" ayarını seçmiş birinin çevrimiçi durumu asla gönderilmez.
- Discord durumu yan yana çalışmaya devam eder; AnyTogether'a bağlı değildir.

**Görünürlük ayarları** (kullanıcı başına, her biri herkes / arkadaşlar / yalnızca ben seçenekli):
profil ayrıntıları, oyun kütüphanesi, oynama süresi, kupalar, aktivite, çevrimiçi durumu, kimlerin arkadaşlık
isteği gönderebileceği (herkes / arkadaşların arkadaşları / hiç kimse), kimlerin mesaj atabileceği (arkadaşlar / herkes).

---

## 3.6 Mesajlar

**Kullanıcının gördüğü**

- Bir arkadaşla **birebir** sohbetler ve **grup** sohbetleri (en fazla 32 kişi); metin, emoji
  tepkileri, yanıtlar, bağlantılar (önizlemeli), görseller (10 MB'a kadar) ve galeriden paylaşılan klipler ya da
  ekran görüntüleriyle.
- Okundu bilgisi (kapatılabilir), yazıyor göstergesi, okunmamış sayıları.
- Mesajlar seni takip eder: launcher (bir Mesajlar paneli ve oynarken odağı oyundan almayan bir
  bildirim balonu), telefon uygulaması (bir Mesajlar sekmesi, uygulama kapalıyken anlık bildirimler),
  web.

**Nasıl çalışır**

- Mesajlar PostgreSQL'de, üyeleri olan konuşmalar içinde saklanır (başlangıçta uçtan uca şifreli değil; bkz. açık
  sorular). Her mesajın, konuşma başına sunucunun atadığı artan bir ID'si vardır; istemciler sahip oldukları
  son ID'yi tutar ve yeniden bağlandıklarında daha yenilerini ister
  (`GET /v1/conversations/{id}/messages?after=...`); böylece hiçbir şey kaybolmaz ya da tekrarlanmaz.
- Gönderme: tekrar denemenin iki kez göndermemesi için istemcinin ürettiği bir ID (UUIDv7) ile
  `POST /v1/conversations/{id}/messages`; gateway `message.created` olayını üyelerin soketlerine iletir; bağlı
  olmayan üyeler worker üzerinden anlık bildirim (APNs/FCM) alır; konuşma başına dakikada en fazla bir tane.
- Görseller imzalı URL ile R2'ye gider; mesaj dosyanın anahtarını, boyutunu ve ölçülerini tutar.
- Moderasyon: mesajı şikâyet etme; engellenen kullanıcılar sana mesaj atamaz; bilinen korsan sitelerine giden
  bağlantılar reddedilir (bkz. kurallar).

---

## 3.7 Oyun kütüphanesi

**Kullanıcının gördüğü**

- Oynadığın her oyun: ad, ikon, **toplam oynama süresi**, **son oynama**, ilk oynama, kupa
  ilerlemesi (çubuk ve yüzde), hangi bilgisayarlarda oynandığı. Son oynanana, süreye, ada, tamamlanma oranına göre sıralama.
- Web'de oyun başına sayfa (`/g/<title id>`): arkadaşlarından kimlerin oynadığı, ilerlemeleri,
  topluluğun uyumluluk değerlendirmesi (aşağıya bkz.), genel kupa nadirliği.
- L: mevcut kütüphane ve ana ekran "Oynayan arkadaşlar" bilgisini ve tüm bilgisayarlarındaki oynama süresini kazanır.

**Nasıl çalışır**

- Launcher **oturumları** kaydeder: title ID, başlangıç, bitiş, bilgisayar (bilgisayar başına sabit, rastgele bir ID;
  adı kullanıcı tarafından verilir). Oturumlar da kupalar gibi giden kutusu üzerinden gider. Oynama süresi = oturumların toplamı.
- **Oyun kataloğu**: title ID başına bir satır; her dildeki adı ve ikonuyla; bunları oyuna sahip
  ilk launcher öğretir (ad `param.json`'dan, ikon `icon0.png`'den 256 px'e ölçeklenerek).
  Moderatörler adları düzeltebilir. Yalnızca title ID, ad ve ikon: başka hiçbir oyun dosyası asla.
- **Uyumluluk** (eski 6 numaralı fikir, artık burada): bir oturumdan sonra launcher "Nasıl çalıştı?" diye
  sorabilir; dört yanıt vardır (açılmadı, yalnızca menüler, sorunlarla oynanabilir, iyi oynanıyor); buna launcher'ın
  zaten bildiği otomatik bilgiler eklenir: motor sürümü, platform, makine (Mac modeli ya da CPU/GPU), işletim sistemi sürümü,
  ortalama FPS (kaplamanın sayaçlarından) ve oyunun nasıl sona erdiği (normal çıkış ya da launcher'ın çökme
  teşhisi). Kullanıcı "Başkalarına yardım et: oyunların nasıl çalıştığını bildir" seçeneğini açmadıkça kapalıdır. Oyun sayfası
  motor sürümü başına en son değerlendirmeyi gösterir.

---

## 3.8 Aktivite akışı

**Kullanıcının gördüğü**

- Arkadaşların yaptıklarından oluşan bir akış: bir kupa kazandı (nadir olanlar ve platinler öne çıkar), yeni bir
  oyun oynamaya başladı, uzun bir oturum oynadı, %100'e ulaştı, bir klip ya da ekran görüntüsü paylaştı,
  bir tema yaptı, AnyTogether'a katıldı.
- Beğeni (tek bir tepki) ve yorum (küçük bir sohbet dizisi açar).
- L: bir Akış paneli; P: bir Akış sekmesi; W: giriş yapılmışken ana sayfa.

**Nasıl çalışır**

- Olaylar, nedenleri gerçekleştiği anda satır olarak yazılır (`activity` tablosu: aktör, tür, içerik,
  görünürlük); yazma anında aktörün görünürlük ayarlarına uyulur.
- Akış, arkadaşların aktiviteleri üzerinde en yeniden eskiye, keyset sayfalamayla (`before=<id>`) çalışan bir
  sorguyla okunur; `(actor_id, id desc)` üzerinde bir index ile, materyalize edilmiş bir "fan-out on read"
  bizim ölçeğimizde yeterince hızlıdır. Büyürse, çok arkadaşı olan kullanıcılar için fan-out on write'a geçilir.
- Gürültü kontrolü: bir oyunda bir saat içinde art arda kazanılan kupalar tek bir öğede toplanır ("Silksong'da 5
  kupa kazandı"); 10 dakikadan kısa oturumlar gösterilmez.
- Klipler ve ekran görüntüleri yalnızca kullanıcı onları açıkça paylaştığında görünür (galeriden:
  "AnyTogether'da paylaş"); asla otomatik olarak değil.

---

## 3.9 Temalar

**Kullanıcının gördüğü**

- **Tema Hub'ı** GitHub klasöründen AnyTogether'a taşınır: temalara canlı önizlemelerle göz at,
  yeni, popüler, beğenilen olarak sırala; tek basışla kurulur ve uygulanır (bugün launcher'ın Temalar
  ekranında olduğu gibi); bir temayı beğen; yapanın profilini gör.
- Doğrudan Tema Stüdyosu'ndan **yayınla** ("Hub'da paylaş", bir GitHub issue'su açmak yerine yükleme yapar).
  Kendi temanda yaptığın güncellemeler sürümünü yükseltir; onu kurmuş olanlara güncelleme
  önerilir.
- **Profil teması**: profilin seçtiğin bir temayı giyer (kendininkini ya da kurduğun birini).
- İleride aynı rafta: oyun başına telefon için **kontrolcü düzenleri**, **oyun başına ayar ön ayarları**
  (çözünürlük, kare üretimi, girdi ayarı), paylaşılan **shader önbellekleri** (eski 7 numaralı fikir).

**Nasıl çalışır**

- Tema, launcher'ın zaten ürettiği aynı `.anyps5theme` dosyasıdır (theme.json artı isteğe bağlı bir
  görsel/video ve müzik). Yükleme: launcher `POST /v1/themes` ile imzalı bir R2 URL'si ister,
  dosyayı yükler, sonra onaylar; worker dosyayı bir sandbox içinde açar, launcher'ın yükleyicisinin denetlediği
  kuralların aynısını denetler (düz dosya adları, boyut sınırları, yalnızca adı geçen dosyalar), bir
  önizleme görseli (1280x720 WebP) ve varsa kısa bir önizleme videosu üretir ve yayınlar.
- Yeni yapımcıların ilk teması için moderasyon kuyruğu (görseller her şey olabilir); güvenilir yapımcılar
  anında yayınlar.
- Launcher'ın mevcut `ThemeHub` istemcisi GitHub raw URL'si yerine yeni index endpoint'ine
  (`GET /v1/themes?sort=popular`) yönelir; GitHub klasörü eski launcher'lar için yedek olarak
  kalır.

---

## 3.10 İndirmeler

**Kullanıcının gördüğü**

- macOS, Windows ve Linux için **resmi** AnyPS5 launcher'ları (her biri kendi projesinin sürümlerinden), telefon uygulaması (APK; sideload
  rehberiyle IPA; ileride mağazalar), sürüm notları ve projenin yaptığı araçlarla tek bir sayfa.
- Sürüm kontrolleri: launcher'ın "Güncellemeleri Denetle" özelliği GitHub'ın yanında AnyTogether'a da sorabilir.

**Nasıl çalışır**

- Dosyalar her sürümde bir GitHub Action ile GitHub sürümlerinden R2'ye aynalanır (kaynak yine
  GitHub sürümü olarak kalır); her dosyanın yanında ve API'de SHA-256 sağlama toplamları gösterilir.
- `GET /v1/releases/latest?product=launcher` sürümü, notları, URL'yi ve sağlama toplamını döndürür.
- **Katı kural:** yalnızca AnyPS5'in kendi yazılımı ve topluluğun ürettiği içerik (temalar, düzenler).
  Asla oyun dosyaları, dump'lar, firmware, anahtarlar ya da bunlara giden bağlantılar değil. Başka herhangi bir şeyin
  yüklenmesi reddedilir ve bildirilir.

---

## 3.11 Share play

**Kullanıcının gördüğü**

- Bir partide ya da birebir sohbette yayıncı **Share play**'e basar: arkadaşlar yayıncının oyununu canlı olarak
  (görüntü ve ses) telefon uygulamasında, web'de ya da kendi launcher'larında görür.
- **İzleme** modu (varsayılan): arkadaşlar izler ve konuşur.
- **Kontrolü devral** / **Birlikte oyna**: yayıncı kontrolcüyü bir arkadaşına devreder (arkadaşın
  kontrolcüsü 1. oyuncuyu yönetir) ya da onu 2. oyuncu olarak ekler (arkadaşın kontrolcüsü, tıpkı bugün aynı Wi-Fi'daki ikinci bir
  telefon gibi, yayıncının oyununda ikinci bir DualSense olur). Yayıncı kendi kontrolcüsünün PS düğmesiyle
  kontrolü istediği an geri alabilir.
- Gecikme, bugün Remote Play'in gösterdiği gibi her iki tarafa da gösterilir.

**Nasıl çalışır** (ayrıntılar [Anlık iletişim, ses ve birlikte oynama](06-anlik-ses-birlikte-oynama.md) belgesinde)

- macOS launcher'ı oyunu zaten yakalar (ScreenCaptureKit) ve düşük gecikmeyle kodlar
  (`StreamEncoder`: H.264, yeniden sıralama yok); Windows/Linux launcher'ı da aynısını kendi platformunun
  yakalama altyapısı ve donanım kodlayıcısıyla yapar. Share play için bu görüntüyü ve oyunun sesini,
  yerel ağdaki bir telefona göndermek yerine (ya da buna ek olarak) her izleyiciye doğrudan bir WebRTC
  bağlantısı üzerinden yayınlar.
- Arkadaşın istemcisi bu track'lere abone olur. Oynamasına izin verilen bir arkadaş, kontrolcü durumunu bir
  WebRTC veri kanalı üzerinden gönderir (güvenilmez, sırasız, saniyede 120 paket; telefonun bugün gönderdiği
  80 baytlık paketin aynısı); yayıncının launcher'ı bunu boştaki bir uzak kontrolcü köprüsüne (`ANYPS5_REMOTE_PAD_2`
  vb.) verir; böylece oyun bir DualSense daha görür.
- Aynı ağdaki arkadaşlar yerel yolu kullanmaya devam eder. İnternet üzerinden bağlantı yayıncı ile
  izleyici arasında doğrudandır; relay'imiz yalnızca ağlar birbirine ulaşamadığında devreye girer.
  Her launcher yayıncı olabilir: macOS ScreenCaptureKit ile, Windows Windows.Graphics.Capture ile,
  Linux PipeWire ile (bkz. [Platformlar](12-platformlar.md)).
- Hedefler: ~1000 km içinde ekrandan ekrana gecikme 120 ms'nin altında; 6-10 Mbit/s'te 720p60, ağ
  gerektirdiğinde 540p'ye ya da 30 fps'ye düşer.

---

## 3.12 Liderlik tabloları

**Kullanıcının gördüğü**

- **Arkadaşlar** ve **genel** tablolar: kupa puanları (PlayStation'ın saydığı gibi bronz 15, gümüş 30, altın 90,
  platin 300), platinler, oynanan saat, tamamlanma yüzdesi; tüm zamanlar, bu ay,
  bu hafta.
- **Oyun başına** tablolar: tamamlanma ve %100'e ulaşma süresi; arkadaşlar arasında ve genel.
- Senin sıran ve hemen üstündeki ve altındaki kişiler.

**Nasıl çalışır**

- Worker tabloları her 10 dakikada bir kupalardan ve oturumlardan Valkey sorted set'lerine
  (`lb:global:points:all`, `lb:game:<title>:completion`, ...) yeniden oluşturur ve geçmiş için PostgreSQL'de her gece
  bir anlık görüntü saklar.
- Arkadaş tabloları istek anında arkadaşların satırlarından hesaplanır (en fazla birkaç yüz).
- İşaretlenmiş kupalar (bkz. 3.2) ve gizli profiller genel tabloların dışında kalır; gizli oyuncular
  yalnızca kendi sıralarını görür.
