# 8. Güvenlik, gizlilik ve kurallar

## 8.1 Hesaplar

Planlandı denmedikçe yapıldı.

- Çalınacak ya da başka yerde tekrar kullanılacak **parola yok**: giriş bir e-posta kodu, bir passkey,
  kullanıcının kendi oturum açılmış telefonu ya da Apple, Google veya Discord (OpenID Connect; ID
  token'ları sağlayıcının anahtarlarıyla doğrulanır, her açık istemci için PKCE) ile yapılır.
- E-posta kodları: 6 haneli, 10 dakika geçerli, adres başına saatte en fazla 5; 10 hatalı deneme kodu
  bitirir; postadaki bağlantı tek kullanımlıktır. Kodlar ve bağlantılar yalnızca hash olarak tutulur.
- **Passkey'ler** (WebAuthn): web sitesinde Ayarlar'dan eklenir, hesap başına en fazla 10; biriyle giriş
  yapmak e-posta gerektirmez. Passkey hesabın ID'sini taşır, asla bir e-posta ya da kullanıcı adı değil;
  challenge'ı bir kez kullanılır ve 5 dakika geçerlidir; geriye giden bir imza sayacı (kopyalanmış bir
  anahtar) reddedilir. Passkey'ler sitenin hostname'ine aittir; bir siteyi başka bir ada taşımak onları
  işe yaramaz hale getirir.
- Telefondan devir: onay ekranı bilgisayarın adını gösterir; platformunu ve yaklaşık konumunu (IP'den
  şehir) eklemek planlandı.
- Cihaz kodları (yedek yol): birbirine benzeyen karakterler içermeyen 8 karakter, 10 dakika geçerli;
  4 saniyeden sık yoklayana yavaşlaması söylenir.
- Mesajlar yalnızca arkadaşlar arasında; çağrılar yalnızca arkadaşlara ve parti üyelerine.
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
  da parti üyeleri arasında yapılabilir; **Her zaman relay kullan** ayarı (planlandı) biraz gecikme
  pahasına IP adresini gizler.
- Veritabanı diski şifrelidir; yedekler R2'ye yüklenmeden önce şifrelenir (age ya da restic).
- Gizli bilgiler (veritabanı parolası, JWT imzalama anahtarı, TURN gizli anahtarı, OAuth istemci gizli
  anahtarları, APNs anahtarı) yalnızca servislerin okuyabildiği ortam dosyalarında tutulur, asla depoda
  değil; yılda bir ya da en ufak şüphede yenilenir.
- Avatarlar sunucuda 256 px JPEG olarak yeniden kodlanır; bu, yüklemenin taşıdığı meta verileri (konum
  gibi) atar; yalnızca 5 MB ve 25 megapiksele kadar PNG ve JPEG kabul edilir.
- R2 (planlandı) bucket'ları `cdn` (avatarlar, önizlemeler, indirmeler) dışında özeldir; yüklemeler yalnızca
  boyut ve içerik türüyle sınırlı, 10 dakika geçerli, önceden imzalanmış URL'lerle yapılır.
- Web sitesinin tarayıcısı hiç token tutmaz: token'lar HttpOnly çerezlerde kalır, gateway soketi 30
  saniye geçerli tek kullanımlık bir biletle açılır.
- Her yolda adres ve hesap başına hız sınırları ([API](04-api.md) 4.9).

## 8.3 Kötüye kullanım ve moderasyon

- **Şikâyet** (kullanıcılar ve mesajlar için yapıldı; aktiviteler, temalar ve oyun adları planlandı): kişi
  ve hedef başına tek açık şikâyet; şikâyet edilen mesajın metni, yazarı silse bile şikâyetle birlikte
  saklanır. Moderatörler şikâyetleri API'nin yanında çalışan bir komut satırı aracıyla ele alır
  (`admin reports`, `report <id> dismiss|action`, `ban`, `unban`, `user`); bir yönetim sayfası (`/admin`)
  planlandı.
- **Engelleme**: engellenen kullanıcı senin çevrimiçi durumunu, profilini (adın dışında) ve aktiviteni
  göremez, sana istek ya da mesaj gönderemez; sen de onunkileri görmezsin.
- **Otomatik kontroller**: adlar ve biyografiler bağlantı içeremez (yapıldı). Planlananlar: avatarlar ve
  tema görselleri başkaları görmeden önce bir çıplaklık sınıflandırıcısından geçer; mesajlardaki
  bağlantılar bir engelleme listesine (korsan siteler, bilinen zararlı yazılımlar) karşı denetlenir; art
  arda gönderilen aynı mesajlar yavaşlatılır.
- **Yaptırımlar**: bir hesaba, bir e-postaya ya da ikisine, belli bir süre ya da kaldırılana kadar
  yasaklama (yapıldı); uyarı, içeriği kaldırma, susturma (planlandı). Her biri moderatör ve gerekçesiyle
  birlikte `audit_log` tablosuna kaydedilir; kullanıcı bilgilendirilir ve e-postayla itiraz edebilir.
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
- Share play, host'un kendi oturumunu davet ettiği arkadaşlarına izlemeleri için aktarır; kontrol asla
  onlara geçmez ve herkese açık bir yayın değildir. Her ekran paylaşımında olduğu gibi, yayının
  sorumluluğu host'a aittir.
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
| Uyumluluk raporları (platform, makine, işletim sistemi, motor, FPS) | başkalarına yardımcı olmak | açık rıza (isteğe bağlı katılım) |
| IP adresleri, cihaz adları | güvenlik, kötüye kullanımın önlenmesi | meşru menfaat, loglarda 30 gün tutulur |
| Ses ve share play medyası | canlı olarak taşınır, sunucu tarafından **asla kaydedilmez** | sözleşme |

- **Reklam yok, veri satışı ya da paylaşımı yok**, web sitesinde üçüncü taraf izleyici yok (yalnızca
  gizlilik dostu analitik, örn. çerezsiz, kendi sunucumuzda çalışan Plausible).
- **Dışa aktarma**: ayarlar → "Verilerimi indir" anında tek bir JSON dosyası verir (yapıldı).
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
