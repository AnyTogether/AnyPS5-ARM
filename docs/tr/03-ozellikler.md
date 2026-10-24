# 3. Özellikler

Her özellik için: kullanıcının launcher'da (L), telefon uygulamasında (P) ve web sitesinde (W)
ne gördüğü; nasıl çalıştığı; ve sistemin geri kalanından neye ihtiyaç duyduğu.

---

## 3.1 Profiller

**Kullanıcının gördüğü**

- Bir **oyuncu kartı**: avatar, görünen ad, @handle, biyografi (160 karakter), ülke bayrağı
  (isteğe bağlı), "üyelik tarihi" ve dört sayı: oynanan oyunlar, oynanan saatler, kupalar, platinler.
- Kart **sahibinin temasını giyer** (Tema Stüdyosu'ndan): kartın arkasında temanın renkleri,
  banner olarak temanın resmi ya da videosu, sayılarda temanın vurgu rengi.
- **Vitrin**: profilin en üstüne sabitlenen, seçilmiş en fazla altı oyun ya da kupa.
- L: üst çubuktaki profil adı avatara dönüşür; seçildiğinde kartını açar, düzenleme orada yapılır.
  P: Mac'in adının altında aynı kart. W: `anytogether.kodla.agency/u/<handle>`, bağlantı
  önizlemeli herkese açık bir sayfa (karttan render edilen Open Graph görseli).

**Nasıl çalışır**

- Hesap (oturum açma) ve profil (başkalarının gördüğü) ayrı tablolardır; bir profil, oturum
  açmaya dokunmadan yeniden adlandırılabilir.
- Kullanıcı adları (@handle): 3-20 karakter, `a-z 0-9 _ .`, büyük-küçük harf ayrımı gözetmeksizin
  benzersiz, 30 günde bir değiştirilebilir; eski kullanıcı adı 30 gün boyunca yeni adrese yönlendirir.
- Avatarlar: presigned URL ile doğrudan R2'ye yüklenir (5 MB'a kadar PNG/JPEG/WebP); worker
  64, 128 ve 512 px WebP sürümlerini üretir ve avatar başka birine gösterilmeden önce küçük bir
  sınıflandırıcıyla çıplaklık kontrolü yapar (sahibi onu hemen görür).
- Dört sayı her görüntülemede değil, kupalar ya da oturumlar değiştiğinde worker tarafından hesaplanır.
- Öğe başına görünürlük (bkz. 3.5): herkes, arkadaşlar, yalnızca ben.

---

## 3.2 Kupalar

**Kullanıcının gördüğü**

- Oyun başına: launcher'ın bugün gösterdiği kupa listesi; artı her birinin **ne zaman**
  kazanıldığı, **nadirlik** (bu oyuna sahip AnyTogether oyuncuları içinde ona sahip olanların
  oranı: "Ultra nadir %2.1") ve ilerlemesi olan kupalar için ilerleme.
- Profilde bir **kupa zaman çizelgesi**; öne çıkan **platin** kartları.
- Bir arkadaş nadir bir kupa kazandığında, bu akışta görünebilir (3.8).
- L: kupa ekranı tarihleri ve nadirliği kazanır; kupa bildirimi, kupa nadirse "Nadir" der.
  P: bugün ekrana düşen kupa kartı nadirliği de gösterir. W: "Kupalar" profil sekmesi.

**Nasıl çalışır**

- Launcher bir oyunun kupa setini (adlar, dereceler, gizli olanlar) dump'ın kupa dosyalarından
  zaten bilir ve oynarken kazanılan kupaları oyunun kayıt verisinden fark eder.
- İlk oturum açışta launcher, sunucuda o set zaten yoksa **bildiği kupa setlerini** (title ID,
  kupa ID'leri, dereceler, kullanıcının dilinde adlar ve açıklamalar, küçük WebP olarak simgeler),
  ardından da **kazanılan kupaları** zamanlarıyla birlikte yükler.
- Kupa setleri ortaktır: bir oyunla oturum açan ilk oyuncu, sunucuya o oyunun setini öğretir;
  diğerleri yalnızca kazandıklarını gönderir. Setler kupa dosyasının bir hash'ini taşır; böylece
  bir setin farklı bir sürümü eskisinin üzerine değil, yanına kaydedilir.
- Gizli kupalar, onları kazanmamış kişilere gizli kalır (adı ve açıklaması).
- **Nadirlik** = kupayı kazanan oyuncular ÷ oyunu en az bir kez oynamış oyuncular; değişen oyunlar
  için worker tarafından, oyun başına en fazla 10 dakikada bir hesaplanır ve kupa satırında
  önbelleğe alınır. Etiketler: Yaygın > %50, Az yaygın %20-50, Nadir %5-20, Çok nadir %1-5,
  Ultra nadir < %1.
- Bütünlük: bir kupa, launcher'ın bildirdiği gibi kabul edilir. Açıkça imkânsız örüntüler (bir
  oyunun tüm kupalarının aynı saniyede kazanılması, oyun ilk kez oynanmadan önce kazanılması)
  işaretlenir ve bir moderatör bakana kadar liderlik tablolarının dışında tutulur. Bunlar
  AnyTogether kupalarıdır; asla PlayStation Network'e gitmezler.

---

## 3.3 Sesli sohbet

**Kullanıcının gördüğü**

- Bir partinin (3.4) içinde herkesin sesi; konuşanın avatarının çevresinde bir halka, herkes için
  ayrı ses düzeyi, sessize alma, kulaklığı kapatma, bas-konuş (Mac'te bir tuş, telefonda bir düğme).
- Önde bir oyun varken de ses devam eder: launcher arka planda kalır ve partiyi taşımayı
  sürdürür; küçük bir kaplama kartı kimin konuştuğunu gösterebilir (bugünkü kupa bildirimi gibi).
- **Kulaklık olarak telefon**: partinin sesi Mac yerine telefondan geçebilir (mikrofonu ve
  hoparlörü ya da kulaklığı), telefon aynı anda kol olarak da kullanılırken. Mac'in hoparlörleri
  oyunun sesini verdiğinde işe yarar.
- W: kurulum gerektirmeden, partinin sesli sohbetine tarayıcıdan katılma.

**Nasıl çalışır**

- Her parti bir LiveKit odasıdır. API her üyeye bir oda token'ı verir (LiveKit secret'ıyla
  imzalanmış, 6 saat geçerli, izinleri olan bir JWT: ses yayınlama, abone olma).
- Ses: Opus, 48 kHz, 24-48 kbit/s; platformların yankı engelleme, gürültü bastırma ve otomatik
  kazanç özellikleriyle (macOS/iOS'ta Apple'ın ses işleme altyapısı, Android'de ve web'de WebRTC'ninki).
- Mac'te: launcher içinde LiveKit Swift SDK'sı; oyunun kendi sesi gönderilmez (launcher yalnızca
  mikrofonu yakalar). Launcher'ın mikrofon izni istemesi gerekir.
- Hedef: aynı kıtada ağızdan kulağa gecikme 200 ms'nin altında (LiveKit, ağ yoluna genellikle
  20-50 ms ekler).

---

## 3.4 Partiler

**Kullanıcının gördüğü**

- Launcher'dan, telefondan ya da web'den **parti kur**; arkadaşlarını davet et (anlık bildirim ve
  launcher'da bir kart alırlar); en fazla 8 üye.
- Parti, **her üyenin ne oynadığını** gösterir ve **"Aynı oyunu oyna"** seçeneğini sunar: bir
  üyenin launcher'ında, o oyun varsa onu seçer, yoksa olmadığını söyler.
- Partide sesin yanında bir yazılı sohbet de vardır (partiye bağlı 3.6 grup sohbeti).
- Partiden, yayıncı diğerleri için **Share play** (3.11) başlatabilir.
- Parti gizliliği: yalnızca davetle (varsayılan), arkadaşlar katılabilir ya da bağlantıya sahip herkes.

**Nasıl çalışır**

- Bir parti, bir veritabanı satırı (sahip, gizlilik, oluşturulma) artı ilk üye sesi açtığında
  talep üzerine oluşturulan bir LiveKit odasıdır.
- Üyelik değişiklikleri API üzerinden geçer ve gateway tarafından itilir (`party.member_joined`,
  `party.member_left`, `party.updated`).
- 10 dakika boyunca hiçbir üyesi bağlı olmayan bir parti kendiliğinden sona erer.
- "Aynı oyunu oyna", `party.play_request {title_id}` gönderir; her launcher title ID'yi kendi
  kütüphanesinde arar. Oyunların kendileri bu işe hiç karışmaz.

---

## 3.5 Arkadaşlar

**Kullanıcının gördüğü**

- @handle ile, karşı tarafın telefonunda gösterilen bir QR kodla ya da bir partiden ekleme;
  istekler kabul edilebilir ya da reddedilebilir; arkadaşlar çıkarılabilir, kullanıcılar engellenebilir.
- Çevrimiçi durumuyla bir **arkadaş listesi**: çevrimiçi, uzakta, çevrimdışı ve **ne oynadıkları**
  (oyunun adı ve simgesi, ne kadar süredir oynandığı), partide olup olmadıkları.
- L: bir Arkadaşlar paneli (üst çubukta, kaç kişinin çevrimiçi olduğunu gösteren yeni bir öğe);
  ana ekran çevrimiçi arkadaşları gösteren küçük bir satır gösterebilir. P: bir Arkadaşlar sekmesi.
  W: arkadaşlar sayfası.

**Nasıl çalışır**

- Bir arkadaşlık, her çift için tek satırdır; bir durum (beklemede, kabul edildi) ve isteği kimin
  gönderdiği bilgisiyle.
- **Çevrimiçi durumu**: her istemci gateway üzerinden her 25 s'de bir durumunu içeren bir
  heartbeat gönderir (`online`; 10 dk boşta kaldıktan sonra `away`; title ID ve başlama zamanıyla
  `in_game`). Gateway bunu 60 s'lik sona erme süresiyle Valkey'e yazar; değiştiğinde kullanıcının
  arkadaşlarına yayınlar. Birden çok cihaz birleştirilir: oyunda, çevrimiçine; çevrimiçi de uzakta'ya üstün gelir.
- Engellediğin ya da "çevrimdışı görün"ü seçmiş birinin çevrimiçi durumu asla gönderilmez.
- Discord durumu yan yana çalışmaya devam eder; AnyTogether'a bağlı değildir.

**Görünürlük ayarları** (kullanıcı başına, her biri herkes / arkadaşlar / yalnızca ben):
profil ayrıntıları, oyun kütüphanesi, oynama süresi, kupalar, aktivite, çevrimiçi durumu, kimlerin
arkadaşlık isteği gönderebileceği (herkes / arkadaşların arkadaşları / hiç kimse), kimlerin mesaj
gönderebileceği (arkadaşlar / herkes).

---

## 3.6 Mesajlar

**Kullanıcının gördüğü**

- Bir arkadaşla **birebir** sohbetler ve **grup** sohbetleri (en fazla 32 kişi); metin, emoji
  tepkileri, yanıtlar, bağlantılar (önizlemeli), görseller (10 MB'a kadar) ve galeriden
  paylaşılan klipler ya da ekran görüntüleriyle.
- Okundu bilgisi (kapatılabilir), yazıyor göstergesi, okunmamış sayıları.
- Mesajlar seni takip eder: launcher (bir Mesajlar paneli ve oynarken odağı oyundan çalmayan bir
  bildirim balonu), telefon uygulaması (bir Mesajlar sekmesi, uygulama kapalıyken anlık
  bildirimler), web.

**Nasıl çalışır**

- Mesajlar PostgreSQL'de, üyeleri olan sohbetler içinde saklanır (başlangıçta uçtan uca şifreli
  değil; bkz. açık sorular). Her mesajın, sohbet başına sunucunun atadığı artan bir ID'si vardır;
  istemciler ellerindeki son ID'yi tutar ve yeniden bağlandıklarında daha yenilerini ister
  (`GET /v1/conversations/{id}/messages?after=...`); böylece hiçbir şey kaybolmaz ya da yinelenmez.
- Gönderme: yeniden denemenin iki kez göndermemesi için istemcinin ürettiği bir ID (UUIDv7) ile
  `POST /v1/conversations/{id}/messages`; gateway, üyelerin soketlerine `message.created` iter;
  bağlı olmayan üyeler worker aracılığıyla anlık bildirim (APNs/FCM) alır, sohbet başına dakikada
  en fazla bir tane.
- Görseller presigned URL ile R2'ye gider; mesaj dosyanın anahtarını, boyutunu ve ölçülerini tutar.
- Moderasyon: mesaj şikâyet edilebilir; engellenen kullanıcılar sana mesaj atamaz; bilinen korsan
  sitelerine giden bağlantılar reddedilir (bkz. kurallar).

---

## 3.7 Oyun kütüphanesi

**Kullanıcının gördüğü**

- Oynadığın her oyun: ad, simge, **toplam oynama süresi**, **son oynanma**, ilk oynanma, kupa
  ilerlemesi (çubuk ve yüzde), hangi Mac'lerde oynandığı. Son oynanana, süreye, ada, tamamlanma
  oranına göre sıralama.
- Web'de oyun başına sayfa (`/g/<title id>`): arkadaşlarından kimlerin oynadığı, ilerlemeleri,
  topluluğun uyumluluk kararı (aşağıya bakın), küresel kupa nadirliği.
- L: mevcut kütüphane ve ana ekran, "Oynayan arkadaşlar" bilgisini ve tüm Mac'lerinden gelen
  oynama süresini kazanır.

**Nasıl çalışır**

- Launcher **oturumları** kaydeder: title ID, başlangıç, bitiş, Mac (her Mac için sabit, rastgele
  bir ID; adını kullanıcı verir). Oturumlar da kupalar gibi giden kutusundan geçer. Oynama süresi
  = oturumların toplamı.
- **Oyun kataloğu**: title ID başına bir satır; her dildeki adı ve simgesiyle. Bunu, oyuna sahip
  ilk launcher öğretir (ad `param.json`'dan, simge 256 px'e ölçeklenmiş `icon0.png`'den).
  Moderatörler adları düzeltebilir. Yalnızca title ID, ad ve simge: asla başka oyun dosyaları değil.
- **Uyumluluk** (eski 6. fikir, artık burada): bir oturumdan sonra launcher dört yanıtla "Nasıl
  çalıştı?" diye sorabilir (açılmadı, yalnızca menüler, sorunlarla oynanabilir, iyi oynanıyor);
  buna zaten bildiği otomatik bilgiler eklenir: motor sürümü, Mac modeli, macOS sürümü, ortalama
  FPS (kaplamanın sayaçlarından) ve oyunun nasıl bittiği (normal çıkış ya da launcher'ın çökme
  teşhisi). Kullanıcı "Başkalarına yardım et: oyunların nasıl çalıştığını bildir" seçeneğini
  açmadıkça kapalıdır. Oyun sayfası, motor sürümü başına en son kararı gösterir.

---

## 3.8 Aktivite akışı

**Kullanıcının gördüğü**

- Arkadaşların yaptıklarından oluşan bir akış: kupa kazandı (nadir olanlar ve platinler öne
  çıkar), yeni bir oyun oynamaya başladı, uzun bir oturum oynadı, %100'e ulaştı, bir klip ya da
  ekran görüntüsü paylaştı, bir tema yaptı, AnyTogether'a katıldı.
- Beğenme (tek bir tepki) ve yorum yapma (küçük bir sohbet dizisi açar).
- L: bir Akış paneli; P: bir Akış sekmesi; W: oturum açıkken ana sayfa.

**Nasıl çalışır**

- Olaylar, nedenleri gerçekleştiğinde satır olarak yazılır (`activity` tablosu: aktör, tür, yük,
  görünürlük); yazma anında aktörün görünürlük ayarlarına uyulur.
- Akış, arkadaşların aktiviteleri üzerinde en yeniden eskiye, keyset sayfalamayla
  (`before=<id>`) bir sorguyla okunur; `(actor_id, id desc)` üzerindeki bir indeksle, bizim
  ölçeğimizde materyalize bir "okumada fan-out" yeterince hızlıdır. Büyürse, çok arkadaşı olan
  kullanıcılar için yazmada fan-out'a geçilir.
- Gürültü kontrolü: tek bir oyunda bir saat içinde art arda kazanılan kupalar tek bir öğede
  toplanır ("Silksong'da 5 kupa kazandı"); 10 dakikadan kısa oturumlar gösterilmez.
- Klipler ve ekran görüntüleri yalnızca kullanıcı onları açıkça paylaştığında görünür (galeriden:
  "AnyTogether'da paylaş"); asla otomatik olarak değil.

---

## 3.9 Temalar

**Kullanıcının gördüğü**

- **Tema Hub'ı**, GitHub klasöründen AnyTogether'a taşınır: canlı önizlemelerle temalara göz at;
  yeniye, popülere, beğenilene göre sırala; tek tuşla kur ve uygula (bugün launcher'ın Temalar
  ekranında olduğu gibi); bir temayı beğen; yapanın profilini gör.
- Doğrudan Tema Stüdyosu'ndan **yayınla** ("Hub'da paylaş" bir GitHub issue'su açmak yerine
  dosyayı yükler). Kendi temanda yaptığın güncellemeler sürümünü yükseltir; onu kurmuş olanlara
  güncelleme önerilir.
- **Profil teması**: profilin seçtiğin bir temayı giyer (kendi temanı ya da kurduğun birini).
- Daha sonra aynı rafta: telefon için oyun başına **kol yerleşimleri**, **oyun başına ayar ön
  ayarları** (çözünürlük, kare üretimi, giriş ince ayarı), paylaşılan **shader önbellekleri**
  (eski 7. fikir).

**Nasıl çalışır**

- Bir tema, launcher'ın zaten ürettiği aynı `.anyps5theme` dosyasıdır (theme.json artı isteğe
  bağlı bir resim/video ve müzik). Yükleme: launcher `POST /v1/themes`'ten bir presigned R2 URL'si
  ister, dosyayı yükler, ardından onaylar; worker dosyayı bir sandbox içinde açar, launcher'ın
  yükleyicisinin denetlediği kuralların aynısını denetler (sade dosya adları, boyut sınırları,
  yalnızca adı geçen dosyalar), bir önizleme görseli (1280x720 WebP) ve varsa kısa bir önizleme
  videosu üretir ve yayınlar.
- Yeni yapımcıların ilk teması için moderasyon kuyruğu (resimler her şey olabilir); güvenilir
  yapımcılar anında yayınlar.
- Launcher'ın mevcut `ThemeHub` istemcisi, GitHub raw URL'si yerine yeni dizin uç noktasını
  (`GET /v1/themes?sort=popular`) gösterir; GitHub klasörü eski launcher'lar için yedek olarak kalır.

---

## 3.10 İndirmeler

**Kullanıcının gördüğü**

- Tek bir sayfada Mac için **resmi** AnyPS5 launcher'ı, telefon uygulaması (APK; sideload
  rehberiyle IPA; ileride mağazalar), sürüm notları ve projenin yaptığı araçlar.
- Sürüm kontrolleri: launcher'ın "Güncellemeleri Denetle" özelliği GitHub'ın yanı sıra
  AnyTogether'a da sorabilir.

**Nasıl çalışır**

- Dosyalar her sürümde bir GitHub Action tarafından GitHub sürümlerinden R2'ye aynalanır (asıl
  kaynak sürüm olarak kalır); her dosyanın yanında ve API'de SHA-256 sağlama toplamları gösterilir.
- `GET /v1/releases/latest?product=launcher` sürümü, notları, URL'yi ve sağlama toplamını döndürür.
- **Katı kural:** yalnızca AnyPS5'in kendi yazılımı ve topluluk yapımı içerik (temalar,
  yerleşimler). Asla oyun dosyaları, dump'lar, firmware, anahtarlar ya da bunlara bağlantılar
  değil. Bunların dışında herhangi bir şeyin yüklenmesi reddedilir ve bildirilir.

---

## 3.11 Share play

**Kullanıcının gördüğü**

- Bir partide ya da birebir sohbette yayıncı **Share play**'e basar: arkadaşlar yayıncının
  oyununu canlı olarak (görüntü ve ses) telefon uygulamasında, web'de ya da kendi launcher'larında görür.
- **İzleme** modu (varsayılan): arkadaşlar izler ve konuşur.
- **Kontrolü devral** / **Birlikte oyna**: yayıncı kolu bir arkadaşa verir (arkadaşın kolu 1.
  oyuncuyu yönetir) ya da onu 2. oyuncu olarak ekler (arkadaşın kolu, tıpkı bugün aynı Wi-Fi'daki
  ikinci bir telefon gibi, yayıncının oyununda ikinci bir DualSense olur). Yayıncı, kendi kolunun
  PS düğmesiyle kontrolü istediği an geri alabilir.
- Gecikme, bugün Remote Play'de olduğu gibi iki tarafa da gösterilir.

**Nasıl çalışır** (ayrıntılar [Gerçek zamanlı iletişim, sesli sohbet ve Share play](06-anlik-ses-birlikte-oynama.md) belgesinde)

- Launcher oyunu zaten yakalıyor (ScreenCaptureKit) ve düşük gecikmeyle kodluyor (`StreamEncoder`:
  H.264, yeniden sıralama yok). Share play için bu görüntüyü ve oyunun sesini, yerel ağdaki bir
  telefona göndermek yerine (ya da buna ek olarak) partinin LiveKit odasına track olarak yayınlar.
- Arkadaşın istemcisi bu track'lere abone olur. Oynamasına izin verilen bir arkadaş, kol durumunu
  bir LiveKit veri kanalı üzerinden gönderir (güvenilmez, sırasız, 120 paket/s, telefonun bugün
  gönderdiği aynı 80 baytlık paket); yayıncının launcher'ı bunu boştaki bir uzak kol köprüsüne
  (`ANYPS5_REMOTE_PAD_2` vb.) besler ve oyun bir DualSense daha görür.
- Aynı ağdaki arkadaşlar yerel yolu kullanmaya devam eder; LiveKit internet içindir. İki kişi için
  önce doğrudan eşler arası bağlantı denenir (daha düşük gecikme), SFU yedek olarak kalır.
- Hedefler: ~1000 km içinde ekrandan ekrana gecikme 120 ms'nin altında; 6-10 Mbit/s'de 720p60,
  ağ gerektirdiğinde 540p'ye ya da 30 fps'ye düşer.

---

## 3.12 Liderlik tabloları

**Kullanıcının gördüğü**

- **Arkadaş** ve **küresel** tablolar: kupa puanları (PlayStation'ın saydığı gibi bronz 15, gümüş
  30, altın 90, platin 300), platinler, oynanan saatler, tamamlanma yüzdesi; tüm zamanlar, bu ay,
  bu hafta.
- **Oyun başına** tablolar: arkadaşlar arasında ve küresel olarak tamamlanma ve %100'e ulaşma süresi.
- Senin sıralaman ve hemen üstündeki ve altındaki kişiler.

**Nasıl çalışır**

- Worker, tabloları her 10 dakikada bir kupalardan ve oturumlardan Valkey sorted set'lerine
  (`lb:global:points:all`, `lb:game:<title>:completion`, ...) yeniden oluşturur ve geçmiş için
  her gece PostgreSQL'e bir anlık görüntü kaydeder.
- Arkadaş tabloları, istek üzerine arkadaşların satırlarından (en fazla birkaç yüz) hesaplanır.
- İşaretlenmiş kupalar (bkz. 3.2) ve gizli profiller küresel tabloların dışında kalır; gizli
  oyuncular yalnızca kendi sıralamalarını görür.
