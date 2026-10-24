# 8. Güvenlik, gizlilik ve kurallar

## 8.1 Hesaplar

Planlandı denmedikçe yapıldı.

- Çalınacak ya da başka yerde tekrar kullanılacak **parola yok**: giriş bir e-posta kodu, bir passkey,
  kullanıcının kendi oturum açılmış telefonu ya da Apple, Google veya Discord (OpenID Connect; ID
  token'ları sağlayıcının anahtarlarıyla doğrulanır, her açık istemci için PKCE) ile yapılır.
- E-posta kodları: 6 haneli, 10 dakika geçerli, adres başına saatte en fazla 5; 10 deneme kodu bitirir
  (her deneme, onu kontrol eden aynı veritabanı güncellemesinde sayılır, bu yüzden paralel gönderilen
  denemeler de sayılır) ve günde 30 hatalı kod, hangi kod için olursa olsun bir adresi kilitler;
  postadaki bağlantı tek kullanımlıktır. Kodlar ve bağlantılar yalnızca hash olarak tutulur.
- **Passkey'ler** (WebAuthn): web sitesinde Ayarlar'dan eklenir, hesap başına en fazla 10; biriyle giriş
  yapmak e-posta gerektirmez. Passkey hesabın ID'sini taşır, asla bir e-posta ya da kullanıcı adı değil;
  challenge'ı bir kez kullanılır ve 5 dakika geçerlidir; geriye giden bir imza sayacı (kopyalanmış bir
  anahtar) reddedilir. Passkey'ler sitenin hostname'ine aittir; bir siteyi başka bir ada taşımak onları
  işe yaramaz hale getirir.
- Telefondan devir: onay ekranı bilgisayarın adını gösterir; platformunu ve yaklaşık konumunu (IP'den
  şehir) eklemek planlandı.
- Cihaz kodları (yedek yol): birbirine benzeyen karakterler içermeyen 8 karakter, 10 dakika geçerli;
  4 saniyeden sık yoklayana yavaşlaması söylenir.
- Mesajlar yalnızca arkadaşlar arasında; çağrılar yalnızca arkadaşlara ve parti üyelerine. Bir share
  play'i host'un arkadaşları (onlara açıkken), davet edilenler ve başkaları yalnızca host onu herkese
  açık listelediği sürece görür; kumandayı yalnızca host verir, 1. oyuncuyu ise asla.
- Oturumlar ayarlarda cihazı ve son kullanım zamanıyla listelenir; herhangi birinden ya da hepsinden
  birden çıkış yapılabilir.
- Yenileme token'ları her kullanımda yenilenir; eski bir token'ın yeniden kullanılması oturumu iptal eder.
- Yasaklanan bir hesabın her yerdeki oturumu anında kapatılır ve her giriş yolunda (e-posta kodu,
  sağlayıcılar, passkey'ler, devirler) reddedilir; bir e-postaya konan yasak o e-postayla yeni hesap
  açılmasını da engeller.

## 8.2 İletim ve depolama

- Her yerde TLS (tarayıcıya kadar Cloudflare, Cloudflare'den origin'imize origin sertifikasıyla;
  kimliği doğrulanmış origin çekmeleri sayesinde origin'e yalnızca Cloudflare ulaşabilir). Kendi
  kurulan bir AnyTogether sertifikalarını Caddy aracılığıyla Let's Encrypt'ten alır.
- Ses ve share play (birlikte oynama) oyuncular arasında **uçtan uca şifrelidir**
  (WebRTC'nin DTLS-SRTP'si); doğrudan akarlar, TURN relay'imiz (aktarma sunucusu) üzerinden geçmeleri gerektiğinde
  ise relay yalnızca okuyamadığı şifreli paketleri iletir. Sunucu bir görüşmeyi asla duymaz ya da görmez.
- Doğrudan bağlantı, her oyuncunun IP adresini karşı tarafa gösterir. Görüşmeler yalnızca arkadaşlar ya
  da parti üyeleri arasında yapılabilir; herkese açık listelenen bir share play ya da oyuncu arama
  panosundan katılınan bir parti veya share play, birbirini tanımayan insanları bağlayabilir. **Her
  zaman relay kullan** ayarı (planlandı) biraz gecikme pahasına IP adresini gizler.
- Veritabanı diski şifrelidir; yedekler R2'ye yüklenmeden önce şifrelenir (age ya da restic).
- Gizli bilgiler (veritabanı parolası, JWT imzalama anahtarı, TURN gizli anahtarı, OAuth istemci gizli
  anahtarları, APNs anahtarı) yalnızca servislerin okuyabildiği ortam dosyalarında tutulur, asla depoda
  değil; yılda bir ya da en ufak şüphede yenilenir.
- Avatarlar sunucuda 256 px JPEG olarak yeniden kodlanır; bu, yüklemenin taşıdığı meta verileri (konum
  gibi) atar; yalnızca 5 MB ve 25 megapiksele kadar PNG ve JPEG kabul edilir. Tema dosyaları sunucuda
  launcher'ın kendi kurallarıyla (sade adlar, yalnızca `theme.json`'un adını verdiği dosyalar, boyut ve
  görsel sınırları) açılır ve yeniden paketlenir; görselleri WebP olarak yeniden üretilir. Oyun
  simgeleri yalnızca operatörün listelediği host'lardan alınır, çünkü launcher'lar onları oyunu gören
  herkes için yükler.
- R2 (planlandı) bucket'ları `cdn` (avatarlar, önizlemeler, indirmeler) dışında özeldir; yüklemeler yalnızca
  boyut ve içerik türüyle sınırlı, 10 dakika geçerli, önceden imzalanmış URL'lerle yapılır.
- Web sitesinin tarayıcısı hiç token tutmaz: token'lar HttpOnly çerezlerde kalır, gateway soketi 30
  saniye geçerli tek kullanımlık bir biletle açılır.
- Her yolda adres ve hesap başına hız sınırları ([API](04-api.md) 4.10); ziyaretçinin adresini hangi
  header'ın taşıdığını operatör söyler (`CLIENT_IP_HEADER`), böylece ziyaretçi kendi adresini
  seçemez. API gövdeleri en fazla 8 MB (tema yüklemesi 50 MB).
- Web sitesi her sayfayla güvenlik header'ları gönderir (`X-Frame-Options: DENY`,
  `frame-ancestors 'none'` içeren bir CSP, sıkı bir referrer politikası, site için yalnızca mikrofona
  izin veren bir izin politikası, HSTS), başka sitelerin sayfalarından gönderilen değişiklikleri
  reddeder (Origin'i Host ile karşılaştırır) ve giriş sayfası sonrasında yalnızca sitedeki bir yola
  geri gönderir.
- Gateway kullanıcı başına en fazla 20 soket tutar ve share play sinyallerini yalnızca host'a ve
  host'tan iletir. Pakete dahil TURN relay'i bir sır olmadan başlamayı reddeder.
- Bir hesabı silmek, giriş isteklerini ve olay akışını da anında siler.

## 8.3 Kötüye kullanım ve moderasyon

- **Şikâyet** (kullanıcılar, mesajlar, temalar ve oyuncu arama ilanları için yapıldı; aktiviteler ve oyun
  adları planlandı): kişi ve hedef başına tek açık şikâyet; şikâyet edilen şey (bir mesajın metni, bir
  ilanın notu, bir temanın adı ve sürümü), yazarı silse bile şikâyetle birlikte saklanır.
- **Yönetim sayfası** (`/admin`, yapıldı): şikâyet edilen şeyle ve kaç kez şikâyet edildiğiyle birlikte
  şikâyet kuyruğu ve her biri için bir karar: reddet, uyar (kişiye bildirim gider), birkaç günlüğüne ya
  da kaldırılana kadar yasakla, mesajı kaldır, ilanı panodan indir, avatarı ya da biyografiyi sıfırla;
  bir işlem aynı şey hakkındaki tüm açık şikâyetleri kapatır. Ayrıca: bir hesabı bulma (kullanıcı adı,
  e-posta ya da ID ile: oturumları, yasakları ve şikâyetleri), yasaklar ve kaldırılmaları, denetim
  kaydı. Sayfa kendi başına hiçbir yetki vermez: API her çağrıda admin rolünü denetler. API'nin
  yanındaki komut satırı aracı aynısını ve fazlasını yapar (`admin reports`, `report`, `ban`, `unban`,
  `user`, admin rolü için `grant` ve `revoke`, `theme <id> show|hide|review`, `purge`).
- **Temalar**: üç kişiden gelen açık şikâyetler yayımlanmış bir temayı, bir moderatör onu gösterene ya
  da gizleyene kadar, yapanı dışında herkesten gizlenmiş olarak yeniden incelemeye alır.
- **Yabancılar**: oyuncu arama panosu ile herkese açık share play'ler ve partiler, arkadaş olmayan
  insanları bir araya getirir; bu yüzden yeni hesaplar (bir günden genç ya da az kupalı) günde 2 ilan
  verebilir ve saatte 10 kez katılmak isteyebilir; bir ilanın notu bağlantı engelleme listesine uyar;
  bir moderatör bir ilanı şikâyetle ya da şikâyetsiz kaldırabilir. Mesajlar arkadaşlar arasında kalır.
- **Engelleme**: engellenen kullanıcı senin çevrimiçi durumunu, profilini (adın dışında) ve aktiviteni
  göremez, sana istek ya da mesaj gönderemez; sen de onunkileri görmezsin.
- **Otomatik kontroller**: adlar, biyografiler ve uyumluluk notları bağlantı içeremez; mesajlar ve
  oyuncu arama ilanları bir engelleme listesindeki alan adlarına bağlantı veremez (varsayılan olarak IP
  logger'lar; operatör listeyi değiştirebilir) (yapıldı). Planlananlar: avatarlar ve tema görselleri
  başkaları görmeden önce bir çıplaklık sınıflandırıcısından geçer; art arda gönderilen aynı mesajlar
  yavaşlatılır.
- **Yaptırımlar**: bir hesaba, bir e-postaya ya da ikisine, belli bir süre ya da kaldırılana kadar
  yasaklama; uyarı; bir mesajı ya da ilanı kaldırma; bir avatarı ya da biyografiyi sıfırlama (yapıldı);
  susturma (planlandı). Her biri moderatör ve gerekçesiyle birlikte `audit_log` tablosuna kaydedilir;
  kullanıcı bilgilendirilir ve e-postayla itiraz edebilir.
- **Liderlik tablosu bütünlüğü**: imkânsız kupa örüntüleri otomatik olarak işaretlenir ve bir moderatör
  tarafından incelenir.

## 8.4 AnyTogether'da asla bulunamayacaklar

Bu kural kullanım koşullarında yer alır, moderasyonla uygulanır ve ürünün yapısına işlenmiştir:

- **Hiçbir türde oyun dosyası yok**: dump'lar, PKG'ler, oyun verileri, güncelleme ya da DLC dosyaları,
  başkalarının kayıt dosyaları, firmware, anahtarlar, şifre çözme araçları ya da bunları edinmek için
  bağlantılar veya talimatlar.
- **Hesap ya da anahtar ticareti yok.**
- AnyTogether oyunlar hakkında yalnızca şunları saklar: title ID, ad, simge (küçültülmüş) ve kupa metinleri
  ile simgeleri; launcher bunları kullanıcının kendi oyunundan okuduğu haliyle gönderir. Bunlar oyunu
  profillerde ve kütüphanelerde göstermek için kullanılır.
- Share play, host'un kendi oturumunu en fazla dört izleyiciye aktarır: arkadaşlara, davet edilenlere ya
  da yalnızca host onu herkese açık listelediğinde başkalarına. Host izleyicilerin 2., 3. ya da 4. oyuncu
  olarak oyuna katılmasına izin verebilir; oyun yalnızca host'un bilgisayarında çalışır ve hiçbir şey
  kaydedilmez. Her ekran paylaşımında olduğu gibi, yayının sorumluluğu host'a aittir.
- Bir kaldırma talebi adresi (`abuse@kodla.agency` ya da benzeri) ve 48 saat içinde yanıt vermeyi sağlayan
  bir süreç.

## 8.5 Gizlilik (KVKK ve GDPR)

AnyTogether Türkiye'den işletilir ve AB'de de kullanıcıları olacaktır: hem KVKK (6698 sayılı Kanun) hem de
GDPR geçerlidir.

| Topladığımız veri | Neden | Hukuki dayanak |
|---|---|---|
| E-posta (onunla giriş yapıldıysa), kullanıcı adı, görünen ad; passkey'ler (yalnızca genel anahtarlar) | hesap | sözleşme |
| Avatar, biyografi, ülke (isteğe bağlı) | profil | sözleşme / isteğe bağlı alanlar için açık rıza |
| Oynanan oyunlar, oturumlar, kupalar | kullanıcının giriş yapma nedeni olan özellikler | sözleşme |
| Çevrimiçi durumu (çevrimiçi, oyun) | arkadaşların çevrimiçi durumu | sözleşme, gizlenebilir |
| Mesajlar | iletilmeleri | sözleşme |
| Bildirimler, tarayıcı push abonelikleri (endpoint ve anahtarlar), özet e-posta ayarı | sen yokken ne olduğunu sana söylemek | sözleşme; her tür kapatılabilir |
| Aktivite öğeleri ve tepkiler | akış | sözleşme; gizlilik ayarlarına uyar |
| Oyuncu arama ilanları, keşif ayarı ve diller | oyuncu bulmak | sözleşme; keşif kapatılabilir |
| Paylaştığın temalar | Tema Hub'ı | sözleşme |
| Uyumluluk raporları (platform, makine, işletim sistemi, motor, FPS) | başkalarına yardımcı olmak | açık rıza (isteğe bağlı katılım) |
| IP adresleri, cihaz adları | güvenlik, kötüye kullanımın önlenmesi | meşru menfaat, loglarda 30 gün tutulur |
| Ses, share play görüntüsü, sesi ve kumandaları | oyuncular arasında canlı olarak taşınır, sunucu tarafından **asla kaydedilmez** ya da görülmez | sözleşme |

- **Reklam yok, veri satışı ya da paylaşımı yok**, web sitesinde üçüncü taraf izleyici yok (yalnızca
  gizlilik dostu analitik, örn. çerezsiz, kendi sunucumuzda çalışan Plausible).
- **Dışa aktarma**: ayarlar → "Verilerimi indir" anında tek bir JSON dosyası verir; konuşmalar ve
  gönderdiğin şikâyetler de içindedir (yapıldı).
- **Silme**: ayarlar → "Hesabı sil", postayla gelen bir kodla (e-postası olmayan bir hesap için kullanıcı
  adıyla) onaylanır; her cihazdaki oturum kapanır ve arkadaşlar hesabı anında görmez olur; fikrini
  değiştirmek için 14 gün (giriş yapmak hesabı korur), ardından her şey kaldırılır; gönderdiğin mesajlar
  silinir, yaptığın şikâyetler anonimleştirilir; yedekler 30 gün içinde süresi dolarak silinir (yapıldı).
- **Yaş**: 13 ve üzeri (rıza için yasanın gerektirdiği yerlerde 16); daha küçük kullanıcılar için hesap yok.
- Web sitesinde Türkçe ve İngilizce, açık bir gizlilik bildirimi ve KVKK aydınlatma metni; launcher'dan ve
  telefon uygulamasından bunlara bağlantı verilir.
- Veriler AB'de ya da Türkiye'deki sunucumuzda (sunucunun konumuyla birlikte karar verilecek) ve Cloudflare
  R2'de (AB yargı bölgesindeki bucket) saklanır.

## 8.6 Güvenlik çalışmaları

- Kod herkese açık ve MIT lisanslı; herkes sunucunun verileriyle ne yaptığını okuyabilir.
- Her push'ta CI: lint, tip denetimi ve PostgreSQL ile Valkey'e karşı testler (yapıldı).
- Bağımlılıklar: Renovate ya da Dependabot; CI'da `npm audit`/`osv-scanner`.
- Kod: TypeScript kodu için CI'da CodeQL; Swift için launcher'ın mevcut inceleme alışkanlıkları.
- Kayıtları herkese açmadan önce sızma testi (kontrol listesi olarak OWASP ASVS seviye 2 ile, kendi
  imkânlarımızla).
- Bir `security.txt` ve bir sorumlu açıklama (responsible disclosure) sayfası.
