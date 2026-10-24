# 3. Özellikler

Her özellik için: kullanıcının launcher'da (L), telefon uygulamasında (P) ve web sitesinde (W) ne gördüğü;
nasıl çalıştığı; ve sistemin geri kalanından neye ihtiyaç duyduğu. Her biri 2026-10-25 itibarıyla
durumuyla başlar. "Sürümde", AnyPS5-ARM 0.2.15'te (macOS launcher'ı), telefon uygulaması 1.11.0'da
ya da AnyPS5 Desktop 0.1.1'de (Windows/Linux launcher'ı) yer alıyor demektir; web sitesi ve sunucu
yapıldıkça yayına girer.

| # | Özellik | Durum |
|---|---|---|
| 3.1 | Profiller | kısmen yapıldı: kullanıcı adı, ad, biyografi, ülke, avatar, gizlilik, son etkinlikler; tema ve vitrin planlandı |
| 3.2 | Kupalar | yapıldı: setler, kazanılan kupalar, nadirlik; launcher'ın kendi kupa ekranında tarih ve nadirlik planlandı |
| 3.3 | Sesli sohbet | yapıldı: web'de, macOS launcher'ında, telefonda ve AnyPS5 Desktop'ta partiler ve birebir çağrılar |
| 3.4 | Partiler | arkadaşın oyununa katılma ve herkese açık partilerle birlikte yapıldı; parti sohbeti planlandı |
| 3.5 | Arkadaşlar | arkadaşların dışında kişileri bulmayla birlikte yapıldı; QR kodları planlandı |
| 3.6 | Mesajlar | metin için, yazıyor göstergesi ve gruplarla yapıldı; görseller ve tepkiler planlandı |
| 3.7 | Oyun kütüphanesi | yapıldı: oturumlar, katalog, oynama süresi, web'de oyun sayfaları |
| 3.8 | Aktivite akışı | yapıldı: web'de, macOS launcher'ında ve telefonda öğeler ve tepkiler |
| 3.9 | Temalar | yapıldı: AnyTogether'daki Tema Hub; profil temaları planlandı |
| 3.10 | İndirmeler | yapıldı: web sitesinin indirme sayfası ve sürümler API'si |
| 3.11 | Share play | yapıldı: macOS launcher'ı yayınlar; web'deki, telefondaki ve macOS launcher'ındaki izleyiciler 2-4. kumandalarla birlikte oynar |
| 3.12 | Liderlik tabloları | yapıldı: genel kupa puanları; oyun başına puanlar, oynama süresi ve tamamlanma |
| 3.13 | Bildirimler | yapıldı: her yerde zil, tarayıcı bildirimleri, e-posta özeti; telefona anlık bildirim planlandı |
| 3.14 | Oyuncu bulma | web'de yapıldı: oyuncu arama panosu, herkese açık partiler ve share play'ler, keşif, oyun sayfaları |
| 3.15 | Uyumluluk listesi | yapıldı: macOS launcher'ından ve web'den raporlar, platform başına değerlendirmeler |

---

## 3.1 Profiller

**Durum:** kısmen yapıldı. Yapılanlar: kullanıcı adı, görünen ad, biyografi, ülke, avatar ve bölüm
başına gizlilik; web'de oyunlar, oynama süresi, kupalar ve son etkinliklerle herkese açık
`/u/<handle>` sayfası; macOS launcher'ında, telefonda (1.11.0'dan beri profilini ve resmini telefonda
düzenleyebilirsin) ve AnyPS5 Desktop'ta oyunlar, saatler, kupalar ve puanlarla ve son kupaların
nadirliğiyle kendi kartın ve arkadaşlarınınki. Planlananlar: kartın üzerindeki tema, vitrin, sunucuda
tutulan sayılar, Open Graph görselleri, avatar denetimi.

**Kullanıcının gördüğü**

- Bir **oyuncu kartı**: avatar, görünen ad, @kullanıcı adı, biyografi (160 karakter), ülke bayrağı (isteğe bağlı),
  "üyelik tarihi" ve dört sayı: oynanan oyun, oynanan saat, kupa, platin.
- Kart **sahibinin temasını giyer** (Tema Stüdyosu'ndan): kartın arkasında temanın renkleri, kapak olarak
  temanın görseli ya da videosu, sayılarda temanın vurgu rengi (planlandı).
- **Vitrin**: profilin en üstüne sabitlenmiş, seçilmiş en fazla altı oyun ya da kupa (planlandı).
- L: üst çubuktaki profil adı avatara dönüşür; onu seçince kartın açılır, düzenlemesi de orada yapılır.
  P: aynı kart, düzenlenebilir. W: `anytogether.kodla.agency/u/<handle>`, herkese açık bir sayfa.

**Nasıl çalışır**

- Hesap (giriş) ve profil (başkalarının gördüğü) ayrı tablolardır; bir profil, girişe dokunmadan
  yeniden adlandırılabilir.
- Kullanıcı adları: 3-20 karakter, `a-z 0-9 _ .`, büyük/küçük harf ayrımı gözetmeksizin benzersiz, 30 günde bir
  değiştirilebilir; eski kullanıcı adı 30 gün boyunca sahibine ayrılır ve profile götürmeye devam eder.
- Avatarlar: API'ye gönderilir (5 MB'a kadar PNG ya da JPEG), meta verisi olmadan 256 px JPEG olarak
  yeniden kodlanır ve baytlarının hash'iyle sunulur; şimdilik PostgreSQL'de, ileride R2'de tutulur.
  Bir moderatör, bir şikâyet üzerine avatarı ya da biyografiyi sıfırlayabilir.
- Bölüm başına görünürlük (bkz. 3.5): herkes, arkadaşlar, hiç kimse.

---

## 3.2 Kupalar

**Durum:** API'de, macOS launcher'ında ve AnyPS5 Desktop'ta (oynama süresi ve kupalar bir giden kutusu
üzerinden gönderilir) ve web profillerinde yapıldı. Nadirlik kupalar geldiğinde hesaplanır; arkadaşlar
bir kupayı kazanıldığı anda duyar (gizli bir kupayı adı olmadan) ve kupalar akış öğesine dönüşür (3.8).
Planlananlar: launcher'ın kendi kupa ekranında ve bildiriminde tarihler ve nadirlik, zaman çizelgesi,
imkânsız örüntülerin işaretlenmesi.

**Kullanıcının gördüğü**

- Oyun başına: launcher'ın bugün gösterdiği kupa listesi, artı her birinin **ne zaman** kazanıldığı,
  **nadirlik** (bu oyuna sahip AnyTogether oyuncuları içinde o kupaya sahip olanların oranı: "Ultra nadir %2.1")
  ve ilerlemesi olan kupalar için ilerleme.
- Profilde bir **kupa zaman çizelgesi**; öne çıkan **platin** kartları (planlandı).
- Bir arkadaş bir kupa kazandığında bu akışta görünür (3.8); nadir olanlar ve platinler işaretlenir.

**Nasıl çalışır**

- Launcher bir oyunun kupa setini (adlar, dereceler, gizli olanlar) dump'taki kupa dosyalarından
  zaten bilir ve oynarken kazanılan kupaları oyunun kayıt verisinden fark eder.
- İlk girişte launcher, sunucuda o set zaten yoksa **bildiği kupa setlerini** (title ID, kupa ID'leri,
  dereceler, kullanıcının dilinde adlar ve açıklamalar), ardından da zamanlarıyla birlikte
  **kazanılmış kupaları** yükler.
- Kupa setleri ortaktır: bir oyunla giriş yapan ilk oyuncu, o oyunun setini sunucuya öğretir;
  diğerleri yalnızca kazandıklarını gönderir. Setler bir hash taşır; böylece bir setin farklı
  bir sürümü eskisinin üzerine değil, yanına kaydedilir.
- Gizli kupalar, onları kazanmamış olanlara gizli kalır (adı ve açıklaması).
- **Nadirlik** = kupayı kazanan oyuncular ÷ oyunu en az bir kez oynamış oyuncular; bir oyun için kupa
  geldikçe yeniden hesaplanır ve kupa satırında önbelleğe alınır.
  Etiketler: Yaygın > %50, Az yaygın %20-50, Nadir %5-20, Çok nadir %1-5, Ultra nadir < %1.
- Bütünlük: bir kupa, launcher'ın bildirdiği gibi kabul edilir. Açıkça imkânsız örüntülerin (bir oyunun tüm
  kupalarının aynı saniyede kazanılması, oyun ilk kez oynanmadan önce kazanılması) işaretlenip bir
  moderatör bakana kadar liderlik tablolarının dışında tutulması planlandı. Bunlar AnyTogether kupalarıdır;
  asla PlayStation Network'e gitmez.

---

## 3.3 Sesli sohbet

**Durum:** partilerde ve iki arkadaş arasındaki çağrılarda; web'de, macOS launcher'ında, telefon
uygulamasında ve AnyPS5 Desktop'ta yapıldı (AnyPS5 Desktop'un sesi yapıldı ama henüz istemciler arası
teste dahil değil): eşten eşe bir ağ, herkesin gördüğü bir susturmayla mikrofonu açıp kapama, konuşanın
çevresinde bir halka, macOS launcher'ında ⌥V ile, AnyPS5 Desktop'ta seçtiğin bir tuşla (varsayılan V)
bas-konuş; ikisi de oyunun üstündeyken de okunur; süresi dolmadan yenilenen relay kimlik bilgileri;
soketi kopan bir cihaz çağrılarından çıkar. Bir arkadaşa çağrı web sitesinin her sayfasından
başlatılabilir. Planlananlar: kişi başına ses düzeyi, sağırlaştırma, kaplama kartı, bilgisayarın
kulaklığı olarak telefon.

**Kullanıcının gördüğü**

- Bir partide (3.4) herkesin sesi; avatarlarının çevresinde konuşma halkası, susturma ve bas-konuş
  (bilgisayarda bir tuş). Her birinin ayrı ses düzeyi ve sağırlaştırma planlandı.
- Bir arkadaşa **çağrı**: tüm cihazlarında çalar, biri yanıtlayınca diğerlerinde susar, kimse
  yanıtlamazsa cevapsız çağrı bildirimine dönüşür.
- Oyun öndeyken de ses devam eder: launcher arka planda kalır ve partiyi taşımayı sürdürür.
- **Kulaklık olarak telefon** (planlandı): telefon kumanda olmayı sürdürürken partinin sesi
  telefondan geçer.
- W: partinin sesli sohbetine kurulum gerektirmeden tarayıcıdan katılma.

**Nasıl çalışır**

- Ses **doğrudan üyeler arasında** akar (WebRTC; her üye diğer her üyeye bağlı;
  en fazla 8 konuşan üye). Sunucu yalnızca onları tanıştırır (gateway üzerinden sinyalleşme) ve ağları
  doğrudan bağlanamayan çiftlere relay (aktarma sunucusu) kimlik bilgilerini dağıtır.
- Ses: Opus, 48 kHz, konuşmaya göre ayarlı; platformların yankı giderme, gürültü bastırma ve otomatik
  kazanç özellikleriyle (macOS/iOS'ta Apple'ın ses işleme altyapısı; Windows'ta, Linux'ta, Android'de
  ve web'de WebRTC'ninki).
- Oyunun kendi sesi gönderilmez (launcher yalnızca mikrofonu yakalar). Launcher mikrofon iznini ilk
  seferde ister.
- Hedef: aynı kıtada ağızdan kulağa gecikme 200 ms'nin altında.

---

## 3.4 Partiler

**Durum:** yapıldı: davet eden, çıkaran ve liderliği devreden bir liderle en fazla 8 kişilik partiler;
web'de, macOS launcher'ında, telefon uygulamasında ve AnyPS5 Desktop'ta; iki launcher'da da
**arkadaşın oyununa katılma**; web'de, başkalarının katılmak istediği ya da doğrudan girdiği
**herkese açık partiler** (3.14). Planlananlar: partinin yazılı sohbeti, telefonda davetler için anlık
bildirim.

**Kullanıcının gördüğü**

- Launcher'dan, telefondan ya da web'den **parti kur**; arkadaşlarını davet et (bir kart ve bir
  bildirim alırlar); en fazla 8 üye.
- Parti **her üyenin ne oynadığını** gösterir; arkadaşlar da çevrimiçi durumunda partide olduğunu görür.
- **Herkese açık listele** (lider açmadıkça kapalı): bir oyun ve bir dille; ya "katılmak iste"
  (insanları lider içeri alır) ya da "açık" (herkes girebilir). Parti bundan sonra Oyuncu bul altında
  ve oyunun sayfasında görünür.
- **Arkadaşın oyununa katıl**: bir oyun çalışırken launcher, "Arkadaşlarım oyunuma katılabilsin"
  kapalı değilse, onun için bir oyun oturumu açar. Arkadaşlar oyunu katılınabilir olarak görür ve
  Arkadaşlar panelinde **… ile oyna** seçeneğini alır; yayıncı onları davet de edebilir. Katılmak,
  yayıncının oyun sürümü ve motor derlemesi kontrol edildikten sonra aynı oyunu başlatır; farklıysa
  bunu açıkça söyler. Çevrimiçi oyunla ([6.7](06-anlik-ses-birlikte-oynama.md)) iki kopya sonra birlikte oynar.
- Partinin sesli sohbetin yanında bir yazılı sohbeti vardır (3.6'daki partiye bağlı grup sohbeti; planlandı).

**Nasıl çalışır**

- Parti, üyeleri (biri aynı anda tek bir partide olabilir), davetleri ve katılma istekleriyle bir
  veritabanı satırıdır (lider, gizlilik ve varsa herkese açık listelemesi); buna ilk üye sesi açtığında
  ihtiyaç anında kurulan bir çağrı eşlik eder.
- Üyelik değişiklikleri API üzerinden geçer ve gateway tarafından iletilir (`party.member_joined`,
  `party.member_left`, `party.updated`, `party.request`).
- Parti son üyesi ayrılınca sona erer; lider ayrılınca sıradaki üye lider olur.
- Oyun oturumu da bir satırdır: yayıncı, title ID, oyun sürümü, motor derlemesi, kapasite (2-16),
  katılınabilir olup olmadığı ve launcher'ların belirlediği en fazla 4 KB özellik, artı her oyuncunun
  kendi özellikleri; oyuncuları listelenir ve başka bir oyun sürümü ya da motor derlemesiyle katılma
  reddedilir (`version_mismatch`). Oyuncular çevrimiçi oyun için gateway üzerinden birbirlerine sinyal
  gönderebilir ve oturum için relay kimlik bilgileri alabilir. Yayıncının çevrimiçi durumu oyunu ve
  yer olup olmadığını gösterir.

---

## 3.5 Arkadaşlar

**Durum:** yapıldı: kullanıcı adıyla ya da aramadan istek, kabul, ret, silme, engelleme; oynanan oyunla
ve parti, oyun oturumu ya da share play ile çevrimiçi durumu; gizlilik ayarları; arkadaşlarının dışında
kişileri bulma (3.14). Web'de, macOS launcher'ında, telefon uygulamasında ve AnyPS5 Desktop'ta.
Planlananlar: QR kodları, ana ekranda arkadaşlar satırı, kimlerin istek gönderebileceği ayarı.

**Kullanıcının gördüğü**

- @kullanıcı adıyla, aramadan, tanıyor olabileceğin kişilerden (3.14) ya da karşı tarafın telefonunda
  gösterilen bir QR koduyla (planlandı) ekleme; istekler kabul ya da reddedilebilir; arkadaşlar
  silinebilir, kullanıcılar engellenebilir.
- Çevrimiçi durumuyla bir **arkadaş listesi**: çevrimiçi, uzakta, çevrimdışı ve **ne oynadıkları** (oyunun
  adı ve ikonu, ne zamandır oynadıkları), partide olup olmadıkları, oyunlarını paylaşıp paylaşmadıkları.
- L: bir Arkadaşlar paneli (üst çubukta, kaç kişinin çevrimiçi olduğunu gösteren bir sayıyla).
  P: bir Arkadaşlar ekranı. W: arkadaşlar sayfası.

**Nasıl çalışır**

- Bir arkadaşlık, her çift için bir satırdır; bir durumu (bekliyor, kabul edildi) ve isteği kimin gönderdiği bilgisi vardır.
- **Çevrimiçi durumu**: her istemci gateway üzerinden 25 sn'de bir, durumunu içeren bir heartbeat gönderir
  (`online`; 10 dk boşta kalınca `away`; title ID ve başlama zamanıyla `in_game`). Gateway bunu
  60 sn ömürle Valkey'e yazar; değiştiğinde kullanıcının arkadaşlarına yayınlar.
  Birden fazla cihaz birleştirilir: oyunda, çevrimiçiye; çevrimiçi de uzaktaya üstün gelir.
- Engellediğin ya da çevrimiçi durumunu "hiç kimse" yapmış birinin çevrimiçi durumu asla gönderilmez.
- Discord durumu yan yana çalışmaya devam eder; AnyTogether'a bağlı değildir.

**Görünürlük ayarları** (kullanıcı başına, her biri herkes / arkadaşlar / hiç kimse seçenekli), yapıldığı
haliyle: oyun kütüphanesi ve oynama süresi, kupalar, arkadaş listesi, çevrimiçi durumu ve aramada seni
kimlerin bulabileceği (tam kullanıcı adına istek her zaman gönderilebilir). Varsayılanlar arkadaşlar,
arama için herkes. Aktivite, neyle ilgiliyse onun ayarına uyar (bir kupa öğesi kupaların ayarına).
**Keşif** ("Oyuncuları" listelerinde, önerilerde ve oyun sayfalarında görünmek), ayrıca seçilmedikçe
kütüphane ayarına uyar. Planlananlar: kimlerin arkadaşlık isteği gönderebileceği, kimlerin mesaj
atabileceği (bugün: yalnızca arkadaşlar).

---

## 3.6 Mesajlar

**Durum:** metin için yapıldı: birebir ve grup konuşmaları (en fazla 32 kişi, arkadaşlar arasında;
grup web sitesinden kurulabilir), 4000 karaktere kadar mesajlar, yanıtlar, 15 dakika içinde düzenleme,
silme, okunma durumu ve okunmamış sayıları, yazıyor göstergesi, bir mesajı şikâyet etme ve bağlantı
alan adları için bir engel listesi (varsayılan olarak IP loglayıcılar). Web'de, macOS launcher'ında,
telefon uygulamasında ve AnyPS5 Desktop'ta. Hiçbir cihazı bağlı olmayan birine giden mesajlar bildirime
dönüşür (3.13). Planlananlar: tepkiler, bağlantı önizlemeleri, görseller ve klipler, ayar olarak okundu
bilgisi.

**Kullanıcının gördüğü**

- Bir arkadaşla **birebir** sohbetler ve **grup** sohbetleri (en fazla 32 kişi); metin, yanıtlar,
  yazıyor göstergesi ve okunmamış sayılarıyla. Emoji tepkileri, önizlemeli bağlantılar, görseller
  (10 MB'a kadar) ve paylaşılan klipler planlandı.
- Mesajlar seni takip eder: launcher (bir Mesajlar paneli), telefon uygulaması, web; sen yokken de
  zil, bir tarayıcı bildirimi ve istersen bir e-posta özeti.

**Nasıl çalışır**

- Mesajlar PostgreSQL'de, üyeleri olan konuşmalar içinde saklanır (uçtan uca şifreli değil; bkz. açık
  sorular). Her mesajın, konuşma başına sunucunun atadığı artan bir numarası vardır; istemciler sahip
  oldukları son numarayı tutar ve yeniden bağlandıklarında daha yenilerini ister
  (`GET /api/v1/conversations/{id}/messages?after=...`); böylece hiçbir şey kaybolmaz ya da tekrarlanmaz.
- Gönderme: tekrar denemenin iki kez göndermemesi için istemcinin ürettiği bir ID ile
  `POST /api/v1/conversations/{id}/messages`; gateway `message.created` olayını üyelerin soketlerine
  iletir. "Yazıyor" bilgisi yalnızca gateway üzerinden, en fazla iki saniyede bir gider ve asla saklanmaz.
- Moderasyon: mesajı şikâyet etme; engellenen kullanıcılar sana mesaj atamaz; engel listesindeki alan
  adlarına giden bağlantılar reddedilir (sunucuyu işleten listeyi değiştirebilir).

---

## 3.7 Oyun kütüphanesi

**Durum:** yapıldı: oturumlar, launcher'ların öğrettiği katalog, launcher'ın kaydettiği bilgisayarlar,
oynama süresi ve kupa ilerlemesiyle kütüphane, web profillerinde gösteriliyor; web'de
`/games/<title id>` adresinde **oyun sayfaları**. Planlananlar: sıralama, launcher'ın kendi
kütüphanesinde tüm bilgisayarlarındaki oynama süresi.

**Kullanıcının gördüğü**

- Oynadığın her oyun: ad, ikon, **toplam oynama süresi**, **son oynama**, ilk oynama, kupa
  ilerlemesi (çubuk ve yüzde), hangi bilgisayarlarda oynandığı.
- Web'de bir **oyun sayfası** (`/games/<title id>`): şu anda kimin oynadığı (çevrimiçi durumu herkese
  açık olanlar), açık oyuncu arama ilanları, herkese açık partiler ve share play'ler, en iyi oyuncular,
  nasıl çalıştığı (3.15), oyunu kütüphanesinde gösteren oyuncular ve adını bu oyundan alan temalar.

**Nasıl çalışır**

- Launcher **oturumları** kaydeder: title ID, başlangıç, bitiş, bilgisayar (bilgisayar başına sabit, rastgele bir ID;
  adı kullanıcı tarafından verilir). Oturumlar da kupalar gibi giden kutusu üzerinden gider. Oynama süresi = oturumların toplamı.
- **Oyun kataloğu**: title ID başına bir satır; her dildeki adı ve ikonuyla; bunları oyuna sahip
  ilk launcher öğretir. Moderatörler bir adı kilitleyebilir. Yalnızca title ID, ad ve ikon: başka
  hiçbir oyun dosyası asla. İkon URL'leri yalnızca sunucuyu işletenin listelediği adreslerden kabul edilir.
- Bir oyunu şu anda kimin oynadığı gateway'den gelir: "oyunda" diyen bir heartbeat, oyuncuyu o oyunun
  kümesinde iki heartbeat'ten biraz daha uzun bir süre tutar.

---

## 3.8 Aktivite akışı

**Durum:** yapıldı: tepkilerle birlikte web sitesinin ana sayfasında, macOS launcher'ında (bir
Etkinlikler paneli ve profillerde son etkinlikler) ve telefonda akış. Planlananlar: yorumlar, galeriden
paylaşılan klipler ve ekran görüntüleri, yapılan temalar.

**Kullanıcının gördüğü**

- Arkadaşların yaptıklarından oluşan bir akış: bir kupa kazandı (bir oyunda bir saat içinde kazanılan
  birkaç kupa tek bir öğede toplanır; nadir olanlar ve platinler öne çıkar), platin kazandı, bir oyunu
  ilk kez oynadı, iki saat ya da daha uzun oynadı, biriyle arkadaş oldu, yuvarlak bir sayıya ulaştı
  (kupa, platin, oyun, saat).
- Öğe başına kişi başı tek tepki, dört tanesinden biri: 🔥 👏 😮 ❤️.
- L: bir Etkinlikler paneli ve profillerde "Son etkinlikler"; P: bir akış ekranı; W: giriş yapılmışken
  ana sayfa ve profil.

**Nasıl çalışır**

- Öğeler, nedenleri gerçekleştiği anda yazılan satırlardır (`activities`: aktör, tür, oyun, içerik) ve
  yalnızca son 24 saatte olanlar için yazılır; böylece bir launcher'ın yılların kupalarını içeren ilk
  yüklemesi arkadaşların akışına düşmez.
- Bir öğeyi kimin görebileceği akış okunurken, aktörün öğenin ilgili olduğu şeye dair gizlilik ayarından
  (kütüphane ya da kupalar; bir arkadaşlık için iki kişinin de arkadaş listesi ayarı) hesaplanır; böylece
  bir ayarı değiştirmek eski öğeleri hemen gizler ya da gösterir.
- Akış, arkadaşların öğeleri üzerinde en yeniden eskiye, son ID'ye göre sayfa başına 30 öğe getiren bir
  sorgudur. Yeni bir öğe ya da daha fazla kupa toplayan bir öğe arkadaşların soketlerine `feed.item`
  olarak ulaşır.
- Kilometre taşları: kupalar 10, 50, 100, 250 … 5000; platinler 5, 10, 25, 50, 100; oyunlar 5 … 100;
  saatler 10 … 2500. Aynı anda geçilenlerden yalnızca en yükseği yazılır.

---

## 3.9 Temalar

**Durum:** yapıldı: AnyTogether'daki **Tema Hub**. macOS launcher'ı ondan listeler ve kurar, giriş
yapılmışken ona paylaşır ve `anyps5://theme/<id>` bağlantılarını açar; web sitesinde Hub, bir temanın
sayfası, paylaşma ve kendi temaların var; eski launcher'lar aynı temaları eski index üzerinden okur.
Bir sunucuda hiç tema yokken GitHub klasörü yedek olarak kalır. Planlananlar: profil temaları,
aynı rafta kumanda düzenleri ve oyun başına ön ayarlar.

**Kullanıcının gördüğü**

- Temalara önizlemelerle göz at; yeni, popüler (indirmeler) ya da beğenilen olarak sırala; ada ya da
  yapana göre ara; tek basışla kurulur ve uygulanır (launcher'ın Temalar ekranında olduğu gibi); bir
  temayı beğen; yapanını gör.
- Launcher'dan (giriş yapılmışken) **Hub'da paylaş** kullanılan temayı yükler; aynı temayı yeniden
  paylaşmak onu bir sonraki sürümü olarak gönderir. Web'de bir tema dosyası bir görselle paylaşılabilir.
- **Profil teması** (planlandı): profilin seçtiğin bir temayı giyer.

**Nasıl çalışır**

- Tema, launcher'ın zaten ürettiği aynı `.anyps5theme` dosyasıdır (`theme.json` artı isteğe bağlı bir
  görsel ya da video ve müzik). Tek bir istekle yüklenir (en fazla 50 MB, en fazla 8 MB'lık bir durağan
  görselle); API onu launcher'ın yükleyicisinin denetlediği kuralların aynısıyla açar (düz dosya adları,
  boyut sınırları, yalnızca adı geçen dosyalar, açılmış haliyle 80 MB), yeniden paketler, WebP olarak bir
  önizleme ve bir küçük resim üretir ve hemen yayınlar.
- Dosyalar blob deposunda durur (bugün PostgreSQL); indirmeler sürümü ve SHA-256'yı taşır ve her kişi
  (ya da adres) bir tema için günde bir kez sayılır.
- Moderasyon: giriş yapmış herkes bir temayı şikâyet edebilir; üç kişinin açık şikâyeti temayı yeniden
  incelemeye alır (yapanı dışında herkesten gizlenir); bir moderatör onu yeniden gösterene ya da
  gizleyene kadar öyle kalır.

---

## 3.10 İndirmeler

**Durum:** yapıldı: web sitesinin `/download` sayfası ve her projenin en son GitHub sürümünden okunan
sürümler API'si.

**Kullanıcının gördüğü**

- **Resmi** AnyPS5 launcher'larıyla tek bir sayfa: macOS (zip ve tek satırlık kurulum), telefon
  uygulaması (APK; sideload rehberiyle IPA), Windows ve Linux (AnyPS5 Desktop: yükleyici, AppImage,
  .deb); her biri sürümü, boyutu, sürüm notları ve sağlama toplamıyla.

**Nasıl çalışır**

- API her projenin en son sürümünü GitHub'a sorar (Mac ve telefon için AnyPS5-ARM, Windows ve Linux
  için AnyPS5-Desktop), yanıtı on dakika, son geçerli yanıtı da bir hafta tutar. Kaynak GitHub olarak
  kalır; GitHub'ın her dosya için yayınladığı SHA-256 dosyanın yanında gösterilir.
- `GET /api/v1/releases/latest?product=launcher|phone|phone-ios|desktop` sürümü, notları, URL'yi,
  boyutu ve sağlama toplamını döndürür.
- **Katı kural:** yalnızca AnyPS5'in kendi yazılımı ve topluluğun ürettiği içerik (temalar). Asla oyun
  dosyaları, dump'lar, firmware, anahtarlar ya da bunlara giden bağlantılar değil.

---

## 3.11 Share play

**Durum:** yapıldı: macOS launcher'ı yayınlar (0.2.15); arkadaşlar tarayıcıda, telefonda (1.11.0) ya da
kendi macOS launcher'larında izler ve yayıncı en fazla üçünün, her biri kendi kumandasıyla,
**2., 3. ya da 4. oyuncu** olarak oynamasına izin verebilir. Yayıncının kendi kumandası her zaman
**1. oyuncu** olarak kalır: yayıncı onu asla devretmez, bir izleyicinin kumandası de onu asla alamaz.
Planlananlar: Windows ve Linux'ta AnyPS5 Desktop'tan yayınlama.

**Kullanıcının gördüğü**

- Bir oyun çalışırken yayıncı **Arkadaşlar** panelini açar ve **Birlikte oyna**'yı başlatır: arkadaşlar
  doğrudan girebilir (ya da yalnızca davet edilenler), en fazla 4 izleyici (varsayılan 2). Arkadaşlar
  çevrimiçi durumunda yayıncının paylaştığını **İzle** ile birlikte görür; davetler onlara bir kart ve
  bir bildirim olarak ulaşır.
- İzleyiciler yayıncının oyununu canlı olarak görür ve duyar: launcher'da ve telefonda tam ekran, ya da
  web sitesinin izleme sayfasında tam ekran, ses düzeyi ve bir kalite satırıyla.
- Yayıncı her izleyici için **…, N. oyuncu olsun**'u seçer, kumandayı geri alır (önce tüm tuşlar
  bırakılır) ya da izleyiciyi çıkarır. Kumandası olan bir izleyici kendi kumandasıyla (launcher, web
  sitesi), klavyeyle (web sitesi) ya da telefonun ekrandaki kumandasıyla oynar; oyunun titreşimi ve
  ışık çubuğu ona geri gelir.
- İki taraf da bağlantının doğrudan mı yoksa relay üzerinden mi olduğunu, gidiş-dönüş süresini ve
  görüntünün boyutunu ve kare hızını görür.
- Bir share play **herkese açık listelenebilir** (yayıncı açmadıkça kapalı): "katılmak iste" ya da
  "açık"; açık olan, herkesin izleyebilmesi için **Şu an canlı** altında da görünebilir (3.14).
  Kumandayı her zaman yalnızca yayıncı verir.

**Nasıl çalışır** (ayrıntılar [Anlık iletişim, ses ve birlikte oynama](06-anlik-ses-birlikte-oynama.md) belgesinde)

- macOS launcher'ı oyun penceresini başlık çubuğu olmadan yakalar (ScreenCaptureKit) ve izleyici başına
  bir eş bağlantısı (peer connection) üzerinde tek bir H.264 görüntü track'i olarak gönderir (WebRTC'nin
  VideoToolbox kodlayıcısı, 720p60, WebRTC'nin bant genişliği tahminine göre; üçüncü izleyiciden itibaren
  her izleyiciye 540p30). Oyunun sesi, kayıplı bir veri kanalında Remote Play'in PCM paketleri olarak gider.
- Bir izleyicinin kumandası başka bir veri kanalında, telefonun gönderdiği aynı 80 baytlık paketler
  olarak geri gelir. Yayıncının launcher'ı bir izleyicinin paketlerini, yalnızca o izleyici bir kumanda
  tuttuğu sürece, kendine ait bir kumanda köprüsü üzerinden oyuna ulaştırır ve verilen oyuncu numarasını
  her pakete yazar; böylece motor onu o oyuncu olarak oturtur, asla 1. oyuncu olarak değil.
- Kimin hangi cihazda izlediğini ve kimin hangi kumandayı tuttuğunu API tutar; share play'ler yalnızca
  Valkey'de yaşar ve oyun sürdüğü kadar sürer. Sinyaller yalnızca yayıncı ile bir izleyici arasında gider,
  asla izleyiciden izleyiciye değil.
- Hedefler: ~1000 km içinde ekrandan ekrana gecikme 120 ms'nin altında; ağ gerektirdiğinde görüntü
  kalitesi düşer.

---

## 3.12 Liderlik tabloları

**Durum:** yapıldı: genel **kupa puanları**, oyun başına da **puanlar**, **oynama süresi** ve
**tamamlanma**; **arkadaşlar** arasında ya da **herkes** içinde; web sitesinde, macOS launcher'ında
ve telefonda. Planlananlar: bu ay ve bu hafta, platin sayıları, %100'e ulaşma süresi.

**Kullanıcının gördüğü**

- Arkadaşlar arasında ya da herkes içinde kupa puanları (PlayStation'ın saydığı gibi bronz 15, gümüş 30,
  altın 90, platin 300); oyun başına: puanlar, oynanan saat ya da tamamlanma yüzdesi.
- En fazla 100 kayıt, eşitler aynı sırayı paylaşır; senin sıran, daha aşağıdaysan hemen üstündeki ve
  altındaki kişiler ve tabloda kaç kişi olduğu.
- Genel bir tabloda değil misin (kupaların ya da kütüphanen herkese açık değil)? Bunu ve nerede
  olacağını söyler.

**Nasıl çalışır**

- Tablolar istek anında kütüphane satırlarından hesaplanır: genel tablolar bir dakika, bir okuyucunun
  arkadaş tablosu yarım dakika Valkey'de tutulur.
- Genel tablolar yalnızca kupaları (oyun başına tablolarda kütüphanesi de) herkese açık olan kişileri
  listeler; arkadaş tabloları yalnızca bunları arkadaşlarından gizlemeyenleri. İşaretlenmiş kupalar
  (3.2, planlandı) genel tabloların dışında kalacak.

---

## 3.13 Bildirimler

**Durum:** yapıldı: okunmamış sayısıyla saklanan bir liste; web sitesinde, macOS launcher'ında (yenileri
için kısa bir uyarıyla) ve telefonda zil; kişinin hiçbir cihazı bağlı değilken tarayıcılara Web Push;
bir e-posta özeti. Planlananlar: telefona anlık bildirim (APNs, FCM).

**Kullanıcının gördüğü**

- Şunlar için bildirimler: bir arkadaşlık isteği ya da kabulü, mesajlar (sen yokken), bir parti ya da
  oyun daveti, cevapsız çağrı, birinin oyuncu arama ilanına katılmak istemesi ya da birinin seni ilanına
  kabul etmesi ve bir moderatör uyarısı.
- Moderatör uyarısı dışında her tür ayarlardan kapatılabilir; e-posta özeti açılmadıkça kapalıdır.
- W: zil ve `/notifications`; tarayıcı bildirimleri cihaz başına açılır.

**Nasıl çalışır**

- Bildirim bir satırdır: tür, kimin yaptığı, neyle ilgili olduğu. Mesajlar, konuşmalarının tek okunmamış
  bildiriminde toplanır ve kaç tane geldiği sayılır. Bir cihazda okumak onu diğerlerinde de okunmuş yapar;
  bir şey artık geçerli değilse (geri çekilen bir istek, sona eren bir parti) okunmamış bildirim geri alınır.
- Mesajlar yalnızca kişinin hiçbir cihazında açık bir gateway soketi yokken bildirime dönüşür; bağlı bir
  istemci onları kendisi gösterir.
- Sunucunun kendi VAPID anahtarlarıyla **Web Push** (bir anlık bildirim servisi hesabı gerekmez); bir
  abonelik girişine bağlıdır, bu yüzden çıkış yapmak onu sona erdirir. Metinler cihazın dilindedir.
- **Özet**: 6 saatte en fazla bir e-posta; bir süre okunmadan bekleyen mesajlar ve arkadaşlık
  isteklerinden oluşur; her bildirim bir kez e-postayla gönderilir.
- Okunan bildirimler 90 gün sonra, hepsi 180 gün sonra silinir.

---

## 3.14 Oyuncu bulma

**Durum:** web sitesinde yapıldı: oyuncu arama panosu (`/find`), herkese açık partiler ve share
play'lerle Şu an canlı (`/find/live`), kişiler (`/find/people`) ve oyun sayfaları (`/games/<title id>`).
Launcher'larda ve telefonda: planlandı.

**Kullanıcının gördüğü**

- **Grup arayanlar**: bir oyun için verilen ilan ne için olduğunu (share play üzerinden co-op, çevrimiçi
  bir oyun, konuşmak için bir parti, kupa yardımı), ne zaman olduğunu (şimdi ya da bugün daha sonra),
  dilleri, kabaca bir bölgeyi, kaç oyuncu arandığını ve kısa bir notu söyler. Diğerleri **Ben varım**'a
  basar; ilanı veren kabul eder ya da reddeder. Kabul edilirse oyuncu, ilanı verenin share play'ine
  (co-op) ya da partisine davet edilir. Bir ilan dolunca, ilanı veren kapatınca ya da bir gün içinde
  kendiliğinden kapanır.
- **Şu an canlı**: herkesin izleyebileceği açık share play'ler ve yayıncılarının herkese açık listelediği
  partiler ve share play'ler; oyuna ve dile göre.
- **Kişiler**: kullanıcı adına ya da ada göre; tanıyor olabileceğin kişiler (ortak arkadaşlar, ikinizin
  de oynadığı oyunlar, ortak bir dil) ve oyunlarından birini oynayanlar.
- **Oyun sayfaları**: bkz. 3.7.

**Nasıl çalışır**

- Kimin kimi gördüğü her zaman engellemelere (iki yönde de) ve her kişinin gizlilik ayarlarına uyar;
  keşif yalnızca bunu seçmiş ya da kütüphanesi herkese açık olan kişileri gösterir.
- Pano ve herkese açık listeler canlı güncellenir: bir soket, yalnızca "değişti" diyen, asla kimin ilan
  verdiğini söylemeyen konuları (`lfg`, `lfg:<title>`, `discover`, `discover:<title>`) izler; istemci de
  listeyi yeniden okur ve engellemeler sunucuda uygulanır.
- Kişi başına en fazla 3 açık ilan; yeni hesaplar (bir günden yeni ya da az kupalı) daha seyrek ilan
  verebilir ve katılmak isteyebilir. İlanlar şikâyet edilebilir ve bir moderatör bir ilanı panodan
  kaldırabilir.

---

## 3.15 Uyumluluk listesi

**Durum:** yapıldı: macOS launcher'ından (bir oturumdan sonra "nasıl çalıştı?" sorusu ve bir oyunun
seçeneklerinden) ve web sitesinden raporlar; `/compatibility` adresinde, her oyun için bir sayfası olan
liste; launcher'ın oyun bilgisinde topluluğun değerlendirmesi.

**Kullanıcının gördüğü**

- Bir oturumdan sonra launcher **_oyun_ nasıl çalıştı?** diye sorabilir; beş yanıt vardır: Hiç,
  Açılıyor, Menüler, Oyun içi, Oynanabilir. "Oyunlardan sonra sorma" soruyu kapatır; rapor yine de
  oyunun seçeneklerinden gönderilebilir.
- Liste: her oyun, platform başına (macOS, Windows, Linux) değerlendirmesi, test edilen sürüm ve kaç rapor
  olduğuyla; bir oyunun sayfası raporları makine, işletim sistemi, motor ve FPS ile listeler.

**Nasıl çalışır**

- Bir rapor title ID'yi, platformu, durumu, launcher'ın ve motorun sürümlerini ve launcher'ın bildiklerini
  (makine, işletim sistemi, ortalama FPS, oyunun sürümü) taşır; buna bağlantı içermeyen isteğe bağlı bir
  not eklenebilir. Launcher raporla birlikte ne gönderdiğini gösterir.
- Oyun ve platform başına değerlendirme: herhangi birinin test ettiği en yeni launcher sürümündeki
  raporlardan (her kişinin yalnızca en sonuncusu), çoğunun verdiği durum; eşitlikte iyi olan kazanır. Her
  rapor geldiğinde yeniden hesaplanır.
- Kendi raporlarını silebilirsin; bir hesap silindiğinde raporları kimin gönderdiği bilgisi olmadan kalır.
