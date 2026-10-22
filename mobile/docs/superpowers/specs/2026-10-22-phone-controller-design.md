# Telefonla kol: AnyPS5 Remote — tasarım

Tarih: 2026-10-22. Durum: onay bekliyor.

## Amaç ve neden

Mac'te AnyPS5 launcher'ıyla açılan PS5 oyunlarını, telefonu DualSense gibi kullanarak oynamak. Elinde kol olmayan ya da klavyeyle oynamak istemeyen biri, cebindeki telefonla koltuktan oyunu seçer, açar, oynar ve değiştirir. Telefon hem launcher'ın uzaktan kumandası hem oyunun kolu olur.

Başarı: Mac'te launcher açık, telefonda uygulama açık. Kod girmeden ikisi birbirini bulur, iki tarafta da yeşil "bağlandı" işareti yanar. Telefondan oyun seçilir, oyun açılınca telefon o oyunun tuş düzenine geçer, basılan tuş gecikme hissettirmeden oyuna gider, oyun kolu titrettiğinde telefon titrer.

## Hedefler

1. **Kendiliğinden bağlanma** aynı Wi-Fi ağında. İlk sefer bir kez onay, sonrasında hiç soru yok.
2. **Launcher modu:** Mac'teki oyunlar telefonda ikonlarıyla listelenir. Birine dokununca Mac'te açılır; çalışan bir oyun varsa önce o kapatılıp sonra diğeri açılır. Yön tuşları, ✕ ve ○ ile launcher'ın kendi ekranında da gezilebilir.
3. **Oyun modu:** tam bir DualSense: iki çubuk, ✕ ○ □ △, L1 R1, analog L2 R2, L3 R3, yön tuşları, Options, Create, dokunmatik yüzey ve PS tuşu.
4. **Oyuna özel düzen:** oyun açılınca telefon o oyuna kaydedilmiş düzene geçer. Bir kilit simgesiyle düzenleme moduna girilir: tuşlar sürüklenir, boyutlanır, saydamlığı değişir, gizlenir. Kilitleyince oyun moduna dönülür.
5. **Tuş davranışları:** her tuş için normal, basılı kilitle (bir dokunuş basar, bir dokunuş bırakır) ve tekrar (turbo).
6. **Geri bildirim:**
   - Oyunun titreşimi (büyük ve küçük motor) telefonun titreşimine çevrilir.
   - Oyunun tetik efektleri (DualSense'in sertleşen tetikleri) L2 ve R2'ye basarken titreşim desenleriyle taklit edilir.
7. **Arka plan ışığı:** telefonun arka planı oyundan gelen renkle yumuşakça parlar. Oyun ışık çubuğu rengi veriyorsa o kullanılır, vermiyorsa oyundaki ekranın baskın rengi.
8. **PS tuşu:** oyunun ortasında launcher moduna döner. Oradan oyun kapatılabilir ya da başka oyuna geçilebilir. İki davranışı da var; telefon uygulamasının ayarlarından seçilir:
   - **Konsol gibi (varsayılan):** launcher Mac'te oyunun önüne gelir. Oyun arkada çalışmaya devam eder ama telefonun tuşlarını almaz. Telefonla launcher'da gezinilir. Tekrar PS'e basınca ya da aynı oyun seçilince oyun öne döner ve tuşları yine alır.
   - **Sadece telefonda:** oyun önde kalır, telefon kendi oyun listesine geçer, Mac ekranında hiçbir şey değişmez. Bu sırada da oyun telefonun tuşlarını almaz.
9. **iOS ve Android** tek kod tabanından.

## Hedef olmayanlar

- İnternet üzerinden, farklı ağlardan bağlanma. Sadece aynı yerel ağ.
- Oyunun görüntüsünü telefona aktarmak (Remote Play gibi). Telefon kol, ekran değil.
- Birden çok telefonla çok oyunculu oynama. Bu sürümde tek kol; tasarım ileride ikinci kola kapı kapatmasın.
- Telefon ekranında tuşların dışında oyun bilgisi göstermek (kullanıcı istemedi).
- Mac dışı (Windows, Linux) launcher'lar.

## Anti-hedefler (çalışsa bile başarısızlık sayılır)

- **Fark edilen gecikme.** Tuşa basma ile oyunda tepki arasında hissedilen bir gecikme varsa proje amacına ulaşmamıştır. Hedef: yerel Wi-Fi'da uçtan uca 20 ms'nin altında, kayıp paketlerle takılmadan.
- **Bağlanmak için uğraştırmak.** Her açılışta IP yazdırmak, kod sordurmak, menüye sokmak.
- **Oyunun odağını bozmak.** Telefon bağlandı diye Mac'te oyun penceresinin odağı, fare yakalaması ya da klavye girişi etkilenmemeli. Telefon ile gerçek kumanda ya da klavye aynı anda çalışabilmeli.
- **Ağdaki yabancının oyunu kontrol edebilmesi.** Onaylanmamış bir cihaz hiçbir şey yapamamalı.
- **Launcher'ın tasarımından kopuk, sıradan görünen bir uygulama.** Görünüş ve his launcher'la aynı aileden olmalı. Referanslar: emilkowal.ski, impeccable.style, tasteskill.dev.

## Kararlar

### Kullanıcının verdiği kararlar

- Platformlar: iOS ve Android. Kullanıcının telefonu Android.
- PS tuşunun iki davranışı da olacak (konsol gibi, sadece telefonda); hangisinin varsayılan olacağını kullanıcı bana bıraktı.
- **Test:** Android APK'yı ben üretirim, kullanıcı kurar ve dener. Mac'te launcher'ı ya da bir oyunu açmak her seferinde kullanıcıya sorulur. Bu yüzden her aşama, kullanıcının denemesinden önce benim çalıştırabileceğim denetimlerle doğrulanır: sahte bir telefon istemcisi, sahte bir oyun kanalı, görünmez önizlemeler ve motor testleri.
- Haberleşme Wi-Fi üzerinden.
- Kendiliğinden bağlanma, iki tarafta yeşil "bağlandı" göstergesi.
- Düzen kilit simgesiyle açılıp düzenlenir.
- Titreşim, basma sertliği (tetik efekti) ve basılı tutma gibi davranışlar.
- Launcher'ın da telefondan kullanılması, oyun değiştirmek için.
- Arka plan ışığı oyundan gelir.

### Benim kararlarım (kullanıcı itiraz etmedi; ayrıca işaretli)

- **Uygulama Flutter ile** yazılır, tek kod tabanından iOS ve Android çıkar. Bu makinede Flutter araçları kurulu.
- **Telefon sadece launcher'la konuşur.** Launcher, kol durumunu çalışan oyuna yerel bir kanaldan iletir ve oyunun titreşimini, tetik efektini, ışık rengini telefona geri taşır. Telefonun motorla doğrudan bağlantısı olmaz. Böylece oyun değişse de bağlantı kopmaz; keşif ve eşleştirme tek yerde kalır.
- **Keşif Bonjour (mDNS) ile.** Launcher kendini yerel ağda duyurur, telefon onu bulur. Bulamazsa (bazı ağlar mDNS'i engeller) telefonda Mac'in adresini elle girme yolu yedek olarak durur.
- **İlk eşleştirme:** yeni bir telefon ilk bağlandığında Mac'te launcher bir kez "Bu telefon bağlansın mı?" diye sorar ve telefonda görünen dört haneli kodu gösterir. Onaylanan telefon hatırlanır, sonrakiler otomatiktir.
- **Oyuna özel düzenler Mac'te, launcher'da saklanır** (oyunun diğer ayarlarının yanında). Telefon kaybolsa ya da değişse düzenler kalır, launcher'ın ayar dışa aktarmasına da girer.
- **Telefonun hareket sensörleri** (jiroskop ve ivmeölçer) DualSense'in hareket sensörü olarak isteğe bağlı açılabilir; varsayılan kapalı. Oyunlar DualSense'i eğmeyi istediğinde işe yarar.
- **Launcher modu oyun açıkken:** "konsol gibi" davranışta launcher kendini öne getirir. Telefonun yön tuşları launcher'ın kendi giriş yoluna, arka planda da çalışacak şekilde verilir (bugün launcher sadece öndeyken tuş dinliyor). Motor, telefon launcher modundayken telefon girişini oyuna iletmez.
- **Launcher modunda iki yol birlikte:** telefondaki oyun listesi (dokun ve aç) ile launcher ekranında yön tuşlarıyla gezinme. Telefon launcher'a bir kumanda gibi komut gönderir; launcher bunu zaten anladığı komutlara çevirir.
- **İlk sürüm Android'de denenir**, çünkü kullanıcının telefonu Android ve kurmak kolay. iOS aynı koddan derlenir; iPhone'a yüklemek Apple geliştirici hesabı gerektirir (ücretsiz hesapla 7 günlük yükleme).

## Parçalar

### 1. Telefon uygulaması (Flutter)

- **Bağlantı ekranı:**
  - ağdaki AnyPS5 launcher'larını listeler (genelde tek);
  - bağlanır, ilk seferde dört haneli kodu gösterir;
  - durumu gösterir: yeşil bağlandı, sarı bağlanıyor, kırmızı bağlantı yok.
  - Bağlantı koparsa kendiliğinden yeniden bağlanır.
- **Launcher modu:**
  - oyun listesi: ikon, ad, kurulu ya da kilitli, kupa sayısı;
  - dokununca Mac'te açılır;
  - yön tuşları, ✕, ○, Options ile launcher'da gezinme;
  - çalışan oyunu kapatma.
- **Oyun modu:**
  - yatay ekranda DualSense düzeni;
  - çok dokunuşlu: aynı anda çubuk, tuş ve tetik;
  - analog çubuklar ve analog tetikler;
  - dokunmatik yüzey alanı;
  - PS tuşu launcher moduna döner.
- **Düzen düzenleyici:**
  - kilit simgesiyle açılır;
  - her öğe taşınır, boyutlanır, saydamlaşır, gizlenir;
  - her tuşa davranış atanır: normal, basılı kilitle, tekrar;
  - "varsayılan düzene dön";
  - düzen launcher'a kaydedilir.
- **Geri bildirim:**
  - Titreşim genliği motor değerlerinden gelir (Android'de genlikli titreşim, iOS'ta Core Haptics).
  - Tetik efekti modu, L2 ve R2 basılıyken bir titreşim deseni seçer.
  - Ekran açık kalır.
- **Arka plan:** launcher'dan gelen renk, yumuşak geçişlerle parlayan bir arka plan.

### 2. Launcher (Mac, mevcut SwiftUI uygulaması)

- **Yayın ve dinleme:** Bonjour ile kendini duyurur; telefonla bir kontrol kanalı (bağlantı, eşleştirme, oyun listesi, komutlar, düzenler) ve hızlı bir giriş kanalı (kol durumu) açar.
- **Eşleştirme:** ilk bağlantıda onay sorusu ve kod. Onaylı cihazlar launcher tercihlerinde. Ayarlar'da cihazları görme ve silme.
- **Oyun listesi ve komutlar:** kütüphaneyi (ad, ikon, durum, kupalar) telefona verir. "Aç", "kapat", "launcher'da şu komut" isteklerini yerine getirir. Oyun açma ve kapatma mevcut Oyna ve kapatma yollarını kullanır.
- **Köprü:** çalışan oyuna yerel bir kanal açar (örneğin bir Unix soketi; yolu oyuna ortam değişkeniyle verilir). Telefondan gelen kol durumunu oyuna, oyundan gelen titreşimi, tetik efektini ve ışık rengini telefona taşır.
- **Düzen saklama:** oyun başına telefon düzeni, mevcut oyun ayarlarının yanında (paylaşılan ayar dosyasına da girer).
- **Durum göstergesi:** launcher'da telefonun bağlı olduğunu gösteren yeşil işaret.

### 3. Motor (AnyPS5 çekirdeği)

- **Uzaktan kol girişi:** launcher'ın verdiği kanaldan gelen kol durumu, gerçek kumandanın, klavyenin ve farenin yanına bir giriş kaynağı olarak eklenir. Birleştirme `libSceVideoOut/PadInput.cpp`'deki mevcut kaynaklarla aynı kurallarla yapılır. Kapsam: tuşlar, çubuklar, analog tetikler, dokunmatik yüzey ve istenirse hareket sensörleri.
- **Çıkış:** `scePadSetVibration`, `scePadSetTriggerEffect` ve `scePadSetLightBar` ile gelen değerler aynı kanaldan launcher'a geri gönderilir.
- **Ekran rengi:** oyun ışık çubuğu rengi vermiyorsa sunulan karenin küçültülmüş bir kopyasından baskın renk düşük sıklıkla (saniyede birkaç kez) çıkarılır ve aynı kanaldan gönderilir. Oyunun hızını etkilememeli.
- Motor kuralları geçerli: kodda yorum yok, uygulanamayan bir şey uydurma başarı döndürmez, oyuna özel istisna yok (AGENTS.md).

## Kısıtlar

- **Gecikme:** tuştan oyuna yerel ağda 20 ms'nin altı. Kol durumu sık gönderilir (en az 120 Hz, değişince hemen). Kayıp bir paket bir sonrakini beklemez; her paket tam durumu taşır.
  - *Benim kararım:* 20 ms, telefonun dokunuşu aldığı andan motorun yeni kol durumunu okuyabildiği ana kadar ölçülür. Ekranda görünen tepki ölçüye girmez, çünkü onu oyunun kare hızı belirler.
  - Paketler zaman damgası taşır ve launcher ölçtüğü gecikmeyi gösterir.
  - 1. aşama bu ölçümle biter. Hedefi tutmazsa arayüz işine geçilmeden önce bağlantı düzeltilir.
- **Odak:** telefon bağlantısı Mac'te hiçbir pencereyi öne getirmez, oyundan odak almaz. İlk eşleştirme sorusu da sadece launcher öndeyken ya da launcher'ın kendi bildirimiyle sorulur.
- **Pil ve ısı:** telefon uygulaması oyun modunda ekranı açık tutar ama gereksiz çizim yapmaz; arka plan ışığı hafif bir animasyondur.
- **Mac tarafı kuralları:** commit'ler Utku adına, Claude satırı yok. Oyun ikilileri yeniden imzalanmaz. Test için kullanıcının ekranında izinsiz pencere ya da oyun açılmaz. Launcher mevcut görsel dilini korur.
- **Titreşim gücü:** kullanıcının telefon modeli bilinmiyor. Bazı Android telefonlar titreşimin gücünü ayarlayamıyor. Uygulama bunu açılışta sorar. Güç ayarı yoksa motor gücü ve tetik desenleri açık/kapalı darbelere iner.
- **Dağıtım:** Android için APK. iOS için Apple geliştirici hesabı gerekir; bu, iOS'u test etmenin önünde bir engel olabilir.
- **Ağ izinleri:** iOS'ta yerel ağ izni ve Bonjour hizmet adı Info.plist'te bildirilmeli. Android'de çoklu yayın kilidi gerekebilir.

## Kurana bırakılanlar

- Kanalların protokolü: paket biçimi, kodlama, sürümleme. Kontrol için güvenilir bir kanal, giriş için hızlı ve kayba dayanıklı bir kanal olması yeterli.
- Telefon arayüzünün görsel ayrıntıları, launcher'ın tasarım diliyle uyumlu olmak şartıyla.
- Tetik efekti modlarının hangi titreşim desenine karşılık geleceği.
- Ekranın baskın renginin nasıl hesaplanacağı.
- Projelerin yeri: Flutter uygulaması büyük ihtimalle ayrı bir depo, launcher ve motor değişiklikleri AnyPS5-ARM'da.

## Aşamalar (öneri)

1. **Uçtan uca iskelet:**
   - Launcher keşif ve eşleştirme.
   - Telefonda sabit bir DualSense düzeni.
   - Motorda uzaktan kol girişi.
   - Hollow Knight: Silksong telefonla oynanır.
2. **Launcher modu:** oyun listesi, aç, kapat, değiştir, PS tuşu.
3. **Düzen düzenleyici** ve tuş davranışları.
4. **Geri bildirim:** titreşim, tetik efekti desenleri, arka plan ışığı.
5. **İsteğe bağlı:** hareket sensörleri. Ardından iOS'ta deneme.
