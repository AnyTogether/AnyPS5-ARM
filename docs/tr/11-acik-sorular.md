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
| Windows ve Linux | birinci sınıf: Rust launcher, `anytogether` crate'i aracılığıyla her özelliğe sahip olur |
| Medya sunucumuzdan mı geçecek? | hayır: ses, Share play (birlikte oynama) ve kol verileri doğrudan oyuncular arasında gider; sunucumuz onları birbirine tanıştırır ve yalnızca doğrudan bağlantı imkânsız olduğunda relay (aktarma sunucusu) görevi görür |

## Hâlâ açık

| # | Soru | Bu plandaki varsayılan | Ne zamana kadar |
|---|---|---|---|
| 1 | **Onaylanacak sunucu değişiklikleri**: relay portları, relay'in kendine ait bir adreste yalnızca DNS'li kaydı, veritabanları, web trafiğinin Cloudflare aralıklarıyla sınırlanması | [Altyapı](09-altyapi.md) belgesindeki gibi | Aşama 0 (veritabanı), Aşama 4 (relay) |
| 2 | **AnyPlay**: Windows/Linux launcher'ın geliştiricileri kendi ağlarını tasarlıyor (Rust, hesaplar, arkadaşlar, oyuncular arasında şifreli QUIC tünelleri, kendi sunucusunda barındırılabilen bir bulut ve oyunların kendi çevrimiçi modları için bir motor köprüsü). AnyTogether'ı bağımsız geliştirip onlara `anytogether` crate'ini mi önermeli, yoksa birlikte mi çalışmalı (ortak protokol, oyunların çevrimiçi oyunu için onların köprüsü, bizim hesaplarımız/profillerimiz/kupalarımız)? | bağımsız; crate ve telefon protokolü açıkça önerilir | Aşama 0 bitmeden |
| 3 | **Depo**: yeni bir `utkuhalis/AnyTogether`, lansmana kadar özel mi? Rust crate'i baştan açık mı (Windows/Linux launcher kullanabilsin diye)? | özel depo, açık crate | Aşama 0 |
| 4 | **Profil varsayılanları**: ayrıntıları yalnızca arkadaşlara açık genel bir kart mı, yoksa tamamen özel mi? | genel kart, ayrıntılar yalnızca arkadaşlara | Aşama 1 |
| 5 | Genel sayfalarda **oyun ve kupa ikonları** | gösterilir, küçültülür, talep üzerine kaldırılır | Aşama 1 |
| 6 | **Mesajlar**: başta sunucunun okuyabileceği şekilde mi (moderasyon mümkün), yoksa ilk günden uçtan uca şifreli mi? | sunucu okuyabilir, E2EE sonra | Aşama 3 |
| 7 | **iOS'ta anlık bildirim**, telefon uygulamasının senin ekibinle derlenmesini gerektirir (APNs); TestFlight mı, sonra App Store mu? | senin ekibinle APNs; hazır olunca TestFlight | Aşama 3 |
| 8 | **Büyük odalar**: 8'den fazla konuşmacılı partiler ya da çok izleyicili share play için sonradan bir SFU (LiveKit) eklensin mi? | başta hayır | Aşama 5'ten sonra |
| 9 | **Oyunların kendi çevrimiçi oyunu** (her oyuncu oyunu kendisi çalıştırır, motorun ağ çağrıları aralarında taşınır): bizim sonraki bir aşamamız mı, yoksa AnyPlay'in köprüsü mü (2. soru)? | Aşama 6'dan sonra, 2. soruyla birlikte karar verilir | sonra |
| 10 | Senin dışında **moderatörler** | sen, sonra güvenilir topluluk üyeleri | Aşama 2 |
| 11 | **Hukuki metinler** (kullanım koşulları, gizlilik politikası, KVKK aydınlatma metni) | burada taslağı hazırlanır, sen gözden geçirirsin | herkese açık kayıtlardan önce |
| 12 | Bir gün **ücretli özellikler** olacak mı? | planlanan yok | sonra |
