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
| Windows ve Linux | birinci sınıf: sunucu ve sözleşmeleri her platform için aynı. Windows/Linux launcher'ı, AnyTogether'a kendisi bağlanan herkese açık bir proje olan [AnyPS5-Desktop](https://github.com/utkuhalis/AnyPS5-Desktop) |
| AnyTogether ve AnyPlay | AnyTogether bizim, bağımsız olarak geliştiriliyor. Çevrimiçi oyun kendi motor köprümüzü kullanır; AnyPlay'in herkese açık tasarımını okuduk, kod kopyalamadık |
| Medya sunucumuzdan mı geçecek? | hayır: ses, Share play (birlikte oynama) ve çevrimiçi oyun trafiği doğrudan oyuncular arasında gider; sunucumuz onları birbirine tanıştırır ve yalnızca doğrudan bağlantı imkânsız olduğunda relay (aktarma sunucusu) görevi görür |
| **Share play** | **yalnızca izleme**: arkadaşlar yayıncının oyununu görür ve duyar; kontrol asla onlara verilmez. Birlikte oynamak çevrimiçi oyunla ya da tek bilgisayarda telefonlarla olur |
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
| 6 | **Büyük odalar**: 8'den fazla konuşmacılı partiler ya da çok izleyicili share play için sonradan bir SFU (LiveKit) eklensin mi? | başta hayır | Aşama 5'ten sonra |
| 7 | Senin dışında **moderatörler** | sen, sonra güvenilir topluluk üyeleri | herkese açık kayıtlardan önce |
| 8 | **Hukuki metinler** (kullanım koşulları, gizlilik politikası, KVKK aydınlatma metni) | burada taslağı hazırlanır, sen gözden geçirirsin | herkese açık kayıtlardan önce |
| 9 | Bir gün **ücretli özellikler** olacak mı? | planlanan yok | sonra |
