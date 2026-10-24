# 8. Güvenlik, gizlilik ve kurallar

## 8.1 Hesaplar

- Çalınacak ya da başka yerde tekrar kullanılacak **parola yok**: giriş Apple, Google ya da Discord
  (OpenID Connect; ID token'ları sağlayıcının anahtarlarıyla doğrulanır, her açık istemci için PKCE),
  bir e-posta kodu ya da kullanıcının kendi oturum açılmış telefonuyla yapılır.
- E-posta kodları: 6 haneli, 10 dakika geçerli; adres başına saatte en fazla 5 gönderim ve 15 dakikalık
  kilitlenmeden önce 10 hatalı deneme hakkı; sihirli bağlantı tek kullanımlıktır.
- Telefona devretme: onay ekranı bilgisayarın adını, platformunu ve yaklaşık konumunu (IP'den şehir)
  gösterir; böylece kullanıcının yapmadığı bir istek fark edilir.
- Cihaz kodları (yedek yol): birbirine benzeyen karakterler içermeyen 8 karakter, 10 dakika geçerli.
- Yeni hesaplar ilk 24 saat boyunca tanımadıkları kişilere mesaj gönderemez.
- Oturumlar ayarlarda cihazı ve son kullanım zamanıyla listelenir; herhangi birinden çıkış yapılabilir.
- Yenileme token'ları her kullanımda yenilenir; eski bir token'ın yeniden kullanılması oturumu iptal eder.
- İleride ek bir giriş yolu olarak passkey'ler (WebAuthn).

## 8.2 İletim ve depolama

- Her yerde TLS (tarayıcıya kadar Cloudflare, Cloudflare'den origin'imize origin sertifikasıyla;
  kimliği doğrulanmış origin çekmeleri sayesinde origin'e yalnızca Cloudflare ulaşabilir).
- Ses, share play (birlikte oynama) ve kumanda verileri oyuncular arasında **uçtan uca şifrelidir**
  (WebRTC'nin DTLS-SRTP'si); doğrudan akarlar, TURN relay'imiz (aktarma sunucusu) üzerinden geçmeleri gerektiğinde
  ise relay yalnızca okuyamadığı şifreli paketleri iletir. Sunucu bir görüşmeyi asla duymaz ya da görmez.
- Doğrudan bağlantı, her oyuncunun IP adresini karşı tarafa gösterir. Görüşmeler yalnızca arkadaşlar ya
  da parti üyeleri arasında yapılabilir; **Her zaman relay kullan** ayarı biraz gecikme pahasına IP
  adresini gizler.
- Veritabanı diski şifrelidir; yedekler R2'ye yüklenmeden önce şifrelenir (age ya da restic).
- Gizli bilgiler (veritabanı parolası, JWT imzalama anahtarı, TURN gizli anahtarı, OAuth istemci gizli
  anahtarları, APNs anahtarı) yalnızca servislerin okuyabildiği ortam dosyalarında tutulur, asla depoda
  değil; yılda bir ya da en ufak şüphede yenilenir.
- R2 bucket'ları `cdn` (avatarlar, önizlemeler, indirmeler) dışında özeldir; yüklemeler yalnızca boyut ve
  içerik türüyle sınırlı, 10 dakika geçerli, önceden imzalanmış URL'lerle yapılır.

## 8.3 Kötüye kullanım ve moderasyon

- **Şikâyet**: her kullanıcı, mesaj, aktivite, tema ve oyun adı şikâyet edilebilir; şikâyetler bir yönetim
  sayfasındaki (`/admin`, `moderator` ve `admin` rolleri) moderatör kuyruğuna düşer.
- **Engelleme**: engellenen kullanıcı senin çevrimiçi durumunu, profilini (adın dışında) ve aktiviteni
  göremez, sana istek ya da mesaj gönderemez; sen de onunkileri görmezsin.
- **Otomatik kontroller**: avatarlar ve tema görselleri başkaları görmeden önce bir çıplaklık
  sınıflandırıcısından geçer; mesajlardaki bağlantılar bir engelleme listesine (korsan siteler, bilinen
  zararlı yazılımlar) karşı denetlenir; art arda gönderilen aynı mesajlar yavaşlatılır.
- **Yaptırımlar**: uyarı, içeriği kaldırma, susturma (bir süre mesaj gönderememe), askıya alma, yasaklama;
  her biri moderatör ve gerekçesiyle birlikte `audit_log` tablosuna kaydedilir; kullanıcı bilgilendirilir
  ve e-postayla itiraz edebilir.
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
- Share play, host'un kendi oturumunu davet ettiği arkadaşlarına aktarır; herkese açık bir yayın değildir.
  Her ekran paylaşımında olduğu gibi, yayının sorumluluğu host'a aittir.
- Bir kaldırma talebi adresi (`abuse@kodla.agency` ya da benzeri) ve 48 saat içinde yanıt vermeyi sağlayan
  bir süreç.

## 8.5 Gizlilik (KVKK ve GDPR)

AnyTogether Türkiye'den işletilir ve AB'de de kullanıcıları olacaktır: hem KVKK (6698 sayılı Kanun) hem de
GDPR geçerlidir.

| Topladığımız veri | Neden | Hukuki dayanak |
|---|---|---|
| E-posta, parola hash'i, kullanıcı adı, görünen ad | hesap | sözleşme |
| Avatar, biyografi, ülke (isteğe bağlı) | profil | sözleşme / isteğe bağlı alanlar için açık rıza |
| Oynanan oyunlar, oturumlar, kupalar | kullanıcının giriş yapma nedeni olan özellikler | sözleşme |
| Çevrimiçi durumu (çevrimiçi, oyun) | arkadaşların çevrimiçi durumu | sözleşme, gizlenebilir |
| Mesajlar | iletilmeleri | sözleşme |
| Uyumluluk raporları (platform, makine, işletim sistemi, motor, FPS) | başkalarına yardımcı olmak | açık rıza (isteğe bağlı katılım) |
| IP adresleri, cihaz adları | güvenlik, kötüye kullanımın önlenmesi | meşru menfaat, loglarda 30 gün tutulur |
| Ses ve share play medyası | canlı olarak taşınır, sunucu tarafından **asla kaydedilmez** | sözleşme |

- **Reklam yok, veri satışı ya da paylaşımı yok**, web sitesinde üçüncü taraf izleyici yok (yalnızca
  gizlilik dostu analitik, örn. çerezsiz, kendi sunucumuzda çalışan Plausible).
- **Dışa aktarma**: ayarlar → "Verilerimi indir", 48 saat içinde bir zip (JSON ve kullanıcının dosyaları)
  hazırlar.
- **Silme**: ayarlar → "Hesabı sil"; fikrini değiştirmek için 14 gün, ardından her şey kaldırılır;
  gönderdiğin mesajlar silinir, yaptığın şikâyetler anonimleştirilir; yedekler 30 gün içinde süresi dolarak
  silinir.
- **Yaş**: 13 ve üzeri (rıza için yasanın gerektirdiği yerlerde 16); daha küçük kullanıcılar için hesap yok.
- Web sitesinde Türkçe ve İngilizce, açık bir gizlilik bildirimi ve KVKK aydınlatma metni; launcher'dan ve
  telefon uygulamasından bunlara bağlantı verilir.
- Veriler AB'de ya da Türkiye'deki sunucumuzda (sunucunun konumuyla birlikte karar verilecek) ve Cloudflare
  R2'de (AB yargı bölgesindeki bucket) saklanır.

## 8.6 Güvenlik çalışmaları

- Bağımlılıklar: Renovate ya da Dependabot; CI'da `npm audit`/`osv-scanner`.
- Kod: TypeScript kodu için CI'da CodeQL; Swift için launcher'ın mevcut inceleme alışkanlıkları.
- Kayıtları herkese açmadan önce sızma testi (kontrol listesi olarak OWASP ASVS seviye 2 ile, kendi
  imkânlarımızla).
- Bir `security.txt` ve bir sorumlu açıklama (responsible disclosure) sayfası.
