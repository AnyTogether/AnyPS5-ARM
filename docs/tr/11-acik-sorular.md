# 11. Açık sorular

Bu plandaki teknolojiler ve varsayılanlar, işe başlanabilsin diye seçilmiş önerilerdir; her biri
değişebilir.

## Cevaplananlar (2026-10-24)

| Soru | Cevap |
|---|---|
| Sunucu | mevcut kendi sunucumuz (ayrıntılar bu herkese açık plana yazılmadı); bkz. [Altyapı](09-altyapi.md) |
| Teknoloji yığını | TypeScript uygun |
| Giriş | tek dokunuş: Apple, Google, Discord, e-posta kodu; kayıt formu yok, parola yok |
| Developer ID imzalama | evet: macOS launcher'ın sürüm derlemeleri imzalanır ve notarize edilir |
| Alan adları | yalnızca `kodla.agency`'nin bir seviye altı: her şey yola göre `anytogether.kodla.agency` üzerinde, artı `anytogether-cdn` ve `anytogether-relay` |
| Windows ve Linux | birinci sınıf: sunucu ve sözleşmeleri her platform için aynı; Windows/Linux launcher'ının geliştiricisi onu portlama sırasında belgelenmiş API ve protokollere göre bağlar |
| AnyTogether ve AnyPlay | AnyTogether bizim; bağımsız olarak geliştirilir; Windows/Linux launcher'ı portlama sırasında ona bağlanır |
| Medya sunucumuzdan mı geçecek? | hayır: ses, Share play (birlikte oynama) ve kol verileri doğrudan oyuncular arasında gider; sunucumuz onları birbirine tanıştırır ve yalnızca doğrudan bağlantı imkânsız olduğunda relay (aktarma sunucusu) görevi görür |

## Hâlâ açık

| # | Soru | Bu plandaki varsayılan | Ne zamana kadar |
|---|---|---|---|
| 1 | **Onaylanacak sunucu değişiklikleri**: relay portları, relay'in kendine ait bir adreste yalnızca DNS'li kaydı, veritabanları, web trafiğinin Cloudflare aralıklarıyla sınırlanması | [Altyapı](09-altyapi.md) belgesindeki gibi | Aşama 0 (veritabanı), Aşama 4 (relay) |
| 2 | **Depo**: `utkuhalis/AnyTogether`, lansmana kadar özel; diğer launcher'lar bağlanabilsin diye OpenAPI belgesi ve protokol belgeleri herkese açık | özel depo, açık sözleşmeler | Aşama 0 |
| 3 | **Profil varsayılanları**: ayrıntıları yalnızca arkadaşlara açık genel bir kart mı, yoksa tamamen özel mi? | genel kart, ayrıntılar yalnızca arkadaşlara | Aşama 1 |
| 4 | Genel sayfalarda **oyun ve kupa ikonları** | gösterilir, küçültülür, talep üzerine kaldırılır | Aşama 1 |
| 5 | **Mesajlar**: başta sunucunun okuyabileceği şekilde mi (moderasyon mümkün), yoksa ilk günden uçtan uca şifreli mi? | sunucu okuyabilir, E2EE sonra | Aşama 3 |
| 6 | **iOS'ta anlık bildirim**, telefon uygulamasının senin ekibinle derlenmesini gerektirir (APNs); TestFlight mı, sonra App Store mu? | senin ekibinle APNs; hazır olunca TestFlight | Aşama 3 |
| 7 | **Büyük odalar**: 8'den fazla konuşmacılı partiler ya da çok izleyicili share play için sonradan bir SFU (LiveKit) eklensin mi? | başta hayır | Aşama 5'ten sonra |
| 8 | **Oyunların kendi çevrimiçi oyunu** (her oyuncu oyunu kendisi çalıştırır, motorun ağ çağrıları aralarında taşınır): bizim sonraki bir aşamamız mı? | Aşama 6'dan sonra | sonra |
| 9 | Senin dışında **moderatörler** | sen, sonra güvenilir topluluk üyeleri | Aşama 2 |
| 10 | **Hukuki metinler** (kullanım koşulları, gizlilik politikası, KVKK aydınlatma metni) | burada taslağı hazırlanır, sen gözden geçirirsin | herkese açık kayıtlardan önce |
| 11 | Bir gün **ücretli özellikler** olacak mı? | planlanan yok | sonra |
