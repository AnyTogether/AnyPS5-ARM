# 8. Güvenlik, gizlilik ve kurallar

## 8.1 Hesaplar

- Parolalar: Argon2id (64 MB, 3 geçiş); en az 10 karakter; kayıt ve parola değişikliğinde
  sızdırıldığı bilinen parolalarla karşılaştırılır (k-anonimlik aralık sorgusu, Have I Been Pwned).
- Bir hesabın aranıp bulunabilmesi ya da ona mesaj gönderilebilmesi için önce e-posta doğrulaması
  gerekir; yeni hesaplar ilk 24 saat boyunca tanımadıkları kişilere mesaj gönderemez.
- Web ve telefon için baştan itibaren isteğe bağlı iki adımlı giriş (TOTP); passkey (WebAuthn)
  desteği sonraki bir adım.
- Oturumlar ayarlarda cihaz ve son kullanım bilgisiyle listelenir; herhangi birinden çıkış
  yapılabilir; parola değiştirildiğinde diğer tüm oturumlar kapatılır.
- Yenileme token'ları her kullanımda döndürülür; eski bir token'ın yeniden kullanılması oturumu
  iptal eder (hırsızlık işareti).
- Cihaz kodları: birbirine benzeyen karakterlerin çıkarıldığı bir alfabeden 8 karakter, 10 dakika
  geçerli, hesap başına saatte en fazla 5 hatalı giriş; onay ekranında cihazın adı ve konumu
  (IP'den şehir) gösterilir, böylece oltalamayla ele geçirilmiş bir kod fark edilir.

## 8.2 İletim ve depolama

- Her yerde TLS (tarayıcıya kadar Cloudflare, Cloudflare'den bizim origin sunucumuza origin
  sertifikasıyla; yalnızca Cloudflare'in origin'e ulaşabilmesi için authenticated origin pulls).
- WebRTC medyası şifrelidir (DTLS-SRTP); LiveKit medyayı SFU içinde görür (SFU'larda standart
  durum budur). Ses için uçtan uca şifreleme (LiveKit, insertable streams ile E2EE destekliyor)
  ileride değerlendirilecek bir seçenek.
- Veritabanı diski şifreli; yedekler R2'ye yüklenmeden önce şifrelenir (age veya restic).
- Gizli bilgiler (veritabanı parolası, JWT imzalama anahtarı, LiveKit anahtarı, APNs anahtarı)
  yalnızca servislerin okuyabildiği ortam dosyalarında tutulur, asla depoda yer almaz; yılda bir
  ya da en ufak şüphede yenilenir.
- `cdn` (avatarlar, önizlemeler, indirmeler) dışındaki R2 bucket'ları özeldir; yüklemeler
  yalnızca boyut ve içerik türü sınırlı, 10 dakika geçerli presigned URL'lerle yapılır.

## 8.3 Kötüye kullanım ve moderasyon

- **Şikâyet**: her kullanıcı, mesaj, aktivite, tema ve oyun adı şikâyet edilebilir; şikâyetler
  bir yönetim sayfasındaki moderatör kuyruğuna düşer (`/admin`, roller `moderator`, `admin`).
- **Engelleme**: engellenen kullanıcı senin çevrimiçi durumunu, profilini (ad dışında) ve
  aktiviteni göremez, sana istek ya da mesaj gönderemez; sen de onunkileri görmezsin.
- **Otomatik kontroller**: avatarlar ve tema görselleri başkaları görmeden önce bir çıplaklık
  sınıflandırıcısından geçer; mesajlardaki bağlantılar bir engel listesiyle (korsan siteler,
  bilinen kötü amaçlı yazılımlar) karşılaştırılır; tekrarlanan aynı mesajlar yavaşlatılır.
- **Yaptırımlar**: uyarı, içeriği kaldırma, susturma (bir süre mesaj gönderememe), askıya alma,
  yasaklama; her biri moderatör ve gerekçeyle birlikte `audit_log`'a kaydedilir; kullanıcı
  bilgilendirilir ve e-postayla itiraz edebilir.
- **Liderlik tablosu bütünlüğü**: imkânsız kupa örüntüleri otomatik olarak işaretlenir ve bir
  moderatör tarafından incelenir.

## 8.4 AnyTogether'da asla bulunamayacaklar

Bu kural kullanım koşullarında yer alır, moderasyonla uygulanır ve ürünün kendisine işlenmiştir:

- **Hiçbir türde oyun dosyası yok**: dump'lar, PKG'ler, oyun verileri, güncelleme ya da DLC
  dosyaları, başkalarının kayıt dosyaları, firmware, anahtarlar, şifre çözme araçları ya da
  bunları edinmeye yönelik bağlantı veya talimatlar.
- **Hesap ya da anahtar ticareti yok.**
- AnyTogether oyunlarla ilgili yalnızca şunları saklar: launcher'ın kullanıcının kendi oyunundan
  okuduğu haliyle title ID, ad, simge (küçültülmüş) ve kupa metinleri ile simgeleri. Bunlar oyunu
  profillerde ve kütüphanelerde göstermek için kullanılır.
- Share play, ev sahibinin kendi oturumunu yalnızca davet ettiği arkadaşlarına yayınlar; herkese
  açık bir yayın değildir. Her ekran paylaşımında olduğu gibi, yayının sorumluluğu ev sahibine
  aittir.
- Bir kaldırma talebi adresi (`abuse@kodla.agency` ya da benzeri) ve talepleri 48 saat içinde
  yanıtlayan bir süreç.

## 8.5 Gizlilik (KVKK ve GDPR)

AnyTogether Türkiye'den işletilecek ve AB'de de kullanıcıları olacak: hem KVKK (6698 sayılı
Kanun) hem de GDPR geçerli.

| Ne topluyoruz | Neden | Hukuki dayanak |
|---|---|---|
| E-posta, parola hash'i, kullanıcı adı, görünen ad | hesap | sözleşme |
| Avatar, biyografi, ülke (isteğe bağlı) | profil | sözleşme / isteğe bağlı alanlar için açık rıza |
| Oynanan oyunlar, oturumlar, kupalar | kullanıcının kaydolma sebebi olan özellikler | sözleşme |
| Çevrimiçi durumu (çevrimiçi, oyun) | arkadaşların çevrimiçi durumu | sözleşme, gizlenebilir |
| Mesajlar | mesajların iletilmesi | sözleşme |
| Uyumluluk raporları (Mac modeli, macOS, motor, FPS) | başkalarına yardımcı olmak | açık rıza (isteğe bağlı katılım) |
| IP adresleri, cihaz adları | güvenlik, kötüye kullanım | meşru menfaat, loglarda 30 gün tutulur |
| Ses ve share play medyası | canlı iletilir, sunucu tarafından **asla kaydedilmez** | sözleşme |

- **Reklam yok, veri satışı ya da paylaşımı yok**, web sitesinde üçüncü taraf izleyici yok
  (yalnızca gizlilik dostu analitik, örneğin çerez kullanmayan, kendi sunucumuzda çalışan
  Plausible).
- **Dışa aktarma**: ayarlar → "Verilerimi indir", 48 saat içinde bir zip (JSON ve kullanıcının
  dosyaları) hazırlar.
- **Silme**: ayarlar → "Hesabı sil"; fikrini değiştirmek için 14 gün süre tanınır, ardından her
  şey kaldırılır; gönderdiğin mesajlar silinir, yaptığın şikâyetler anonimleştirilir; yedeklerdeki
  kopyalar 30 gün içinde sona erer.
- **Yaş**: 13 yaş ve üzeri (rıza için yasanın gerektirdiği yerlerde 16); daha küçük kullanıcılara
  hesap açılmaz.
- Web sitesinde Türkçe ve İngilizce, açık ve anlaşılır bir gizlilik bildirimi ile KVKK aydınlatma
  metni; launcher'dan ve telefon uygulamasından bunlara bağlantı verilir.
- Veriler AB'deki ya da Türkiye'deki sunucumuzda (sunucunun konumuyla birlikte karar verilecek)
  ve Cloudflare R2'de (AB yargı bölgesindeki bucket) saklanır.

## 8.6 Güvenlik çalışmaları

- Bağımlılıklar: Renovate ya da Dependabot; CI'da `npm audit`/`osv-scanner`.
- Kod: TypeScript kodu için CI'da CodeQL; Swift tarafında launcher'ın mevcut inceleme
  alışkanlıkları.
- Kayıtlar herkese açılmadan önce sızma testi (kontrol listesi olarak OWASP ASVS seviye 2 ile,
  kendi yürüttüğümüz).
- Bir `security.txt` ve sorumlu açıklama (responsible disclosure) sayfası.
