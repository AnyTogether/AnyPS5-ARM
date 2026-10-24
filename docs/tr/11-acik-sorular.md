# 11. Açık sorular

Bu plandaki teknolojiler ve varsayılanlar, işe başlanabilsin diye seçilmiş önerilerdir; her biri
değişebilir.

## Cevaplananlar

| Soru | Cevap |
|---|---|
| Sunucu | mevcut kendi sunucumuz (ayrıntılar bu herkese açık plana yazılmadı); bkz. [Altyapı](09-altyapi.md) |
| Teknoloji yığını | TypeScript uygun |
| Giriş | tek dokunuş: e-posta kodu, passkey, telefon, Apple, Google, Discord; kayıt formu yok, parola yok |
| Developer ID imzalama | evet: macOS launcher'ın sürüm derlemeleri imzalanır ve notarize edilir |
| Alan adları | yalnızca `kodla.agency`'nin bir seviye altı: her şey yola göre `anytogether.kodla.agency` üzerinde, artı `anytogether-cdn` ve `anytogether-relay` |
| **Depo** | **herkese açık, MIT lisanslı**: [github.com/utkuhalis/AnyTogether](https://github.com/utkuhalis/AnyTogether); herkes kendi sunucusunu kurabilsin diye bir kurulum rehberiyle; launcher ve telefon başka bir sunucuya yönlendirilebilir |
| Windows ve Linux | birinci sınıf: sunucu ve sözleşmeleri her platform için aynı. Windows/Linux launcher'ı, AnyTogether'a kendisi bağlanan herkese açık bir proje olan [AnyPS5 Desktop](https://github.com/utkuhalis/AnyPS5-Desktop) (0.1.1 yayımlandı; kurulum paketleri ve kendini indiren bir motorla) |
| Lisans | AnyTogether için **MIT** (launcher'lar motor gibi GPL-2.0 kalır) |
| Web'de anlık bildirim | sunucunun kendi VAPID anahtarlarıyla Web Push, dışarıdan servis yok; anahtarı olmayan bir sunucuda kapalı |
| Yabancıların birlikte oynaması | evet, isteğe bağlı: oyuncu arama panosu ile herkese açık partiler ve share play'ler (host listelemedikçe kapalı); yeni hesaplar için daha düşük sınırlar ve ilanlar hakkında şikâyet; mesajlar arkadaşlar arasında kalır |
| AnyTogether ve AnyPlay | AnyTogether bizim, bağımsız olarak geliştiriliyor. Çevrimiçi oyun kendi motor köprümüzü kullanır; AnyPlay'in herkese açık tasarımını okuduk, kod kopyalamadık |
| Medya sunucumuzdan mı geçecek? | hayır: ses, Share play (birlikte oynama) ve çevrimiçi oyun trafiği doğrudan oyuncular arasında gider; sunucumuz onları birbirine tanıştırır ve yalnızca doğrudan bağlantı imkânsız olduğunda relay (aktarma sunucusu) görevi görür |
| **Share play** | **izle ve oyuna katıl**: arkadaşlar yayıncının oyununu görür ve duyar; yayıncı izleyicileri kendi kumandalarıyla **2., 3. ya da 4. oyuncu** olarak oynamaya davet edebilir (ilk planda yalnızca izleme vardı; bu sonradan kararlaştırıldı). Yayıncı 1. oyuncuyu asla devretmez ve kumandaları yalnızca yayıncı verir. Her oyuncunun kendi kopyasını çalıştırması çevrimiçi oyundur |
| Oyunların kendi çevrimiçi oyunu | evet, bizim kendi aşamamız (7): motor, oyunun platform çağrılarını launcher'a devreder, launcher da bunları AnyTogether üzerinden taşır; AnyPS5-ARM'ın `online-play` branch'inde tasarlanıyor ([Anlık iletişim](06-anlik-ses-birlikte-oynama.md) 6.7) |
| Çevrimiçi oyunda **PlayStation Plus kontrolleri** | launcher AnyTogether'a giriş yapmış bir kullanıcı bildirdiği sürece **"izin verildi"** yanıtını alır (`sceNpCheckPlus` ve premium kontrolleri; `sceNpIsPlusMember` üye bildirir); çıkış yapılmışken eskisi gibi yanıt verir. Giriş yapmanın amacı çevrimiçi oyundur |

## Hâlâ açık

| # | Soru | Bu plandaki varsayılan | Ne zamana kadar |
|---|---|---|---|
| 1 | **Onaylanacak sunucu değişiklikleri**: relay portları, relay'in kendine ait bir adreste yalnızca DNS'li kaydı, web trafiğinin Cloudflare aralıklarıyla sınırlanması | [Altyapı](09-altyapi.md) belgesindeki gibi | relay devreye girmeden |
| 2 | **Profil varsayılanları**: ayrıntıları yalnızca arkadaşlara açık genel bir kart mı, yoksa tamamen özel mi? | genel kart; oyunlar, kupalar, arkadaş listesi ve çevrimiçi durumu arkadaşlara; aramada herkes bulabilir (böyle yapıldı) | herkese açık kayıtlardan önce |
| 3 | Genel sayfalarda **oyun ve kupa ikonları** | gösterilir, küçültülür, talep üzerine kaldırılır (henüz saklanmıyor) | oyun sayfaları |
| 4 | **Mesajlar**: sunucunun okuyabileceği şekilde mi (moderasyon mümkün), yoksa uçtan uca şifreli mi? | şimdilik sunucu okuyabilir (böyle yapıldı; şikâyet edilen mesajlar moderatörler için saklanır), E2EE sonra | sonra |
| 5 | **iOS'ta anlık bildirim**, telefon uygulamasının senin ekibinle derlenmesini gerektirir (APNs); TestFlight mı, sonra App Store mu? | senin ekibinle APNs; hazır olunca TestFlight | anlık bildirimler |
| 6 | **Büyük odalar**: 8'den fazla konuşmacılı partiler ya da 4'ten fazla izleyicili share play için sonradan bir SFU (LiveKit) eklensin mi? | başta hayır | share play'ler dolmaya başlayınca |
| 7 | Senin dışında **moderatörler** | sen, sonra güvenilir topluluk üyeleri | herkese açık kayıtlardan önce |
| 8 | **Hukuki metinler** (kullanım koşulları, gizlilik politikası, KVKK aydınlatma metni) | burada taslağı hazırlanır, sen gözden geçirirsin | herkese açık kayıtlardan önce |
| 9 | Bir gün **ücretli özellikler** olacak mı? | planlanan yok | sonra |
| 10 | **Yabancılar için relay**: arkadaş olmayan kişilerle bağlantılar (herkese açık share play'ler, oyuncu arama panosu) varsayılan olarak relay üzerinden mi gitsin, böylece iki taraf da birbirinin IP adresini görmesin? | doğrudan, **Her zaman relay kullan** ayarıyla (planlandı) | oyuncu bulma uygulamalara gelmeden |
| 11 | **Share play'in oyun sesi**: Remote Play'in PCM'i bir veri kanalında mı kalsın (kodlama gecikmesi yok, ~1.5 Mbit/s), yoksa bir Opus kanalına mı geçilsin (~128 kbit/s)? | PCM (böyle yapıldı) | yavaş yüklemeli host'lar şikâyet edince |
