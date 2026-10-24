# 11. Açık sorular

Bu plandaki teknolojiler ve varsayılanlar, işe başlanabilsin diye seçilmiş önerilerdir; hepsi
değişebilir. Aşağıdakiler, belirtilen aşamadan önce ya da o aşama sırasında yanıtlanması gereken
kararlar; ortadaki sütun, o zamana kadar planın varsaydığı şey.

| # | Soru | Bu plandaki varsayılan | Ne zamana kadar |
|---|---|---|---|
| 1 | **Sunucu**: hangi makine, nerede (şehir), ne kadar CPU/RAM/bant genişliği, üzerinde halihazırda neler çalışıyor? | İstanbul ya da Frankfurt'ta tek bir 4 vCPU / 16 GB makine, Docker Compose | Aşama 0 |
| 2 | **Teknoloji yığını**: TypeScript (Hono, Next.js) uygun mu, yoksa kodla.agency'nin halihazırda kullandığı ve korumak istediği başka bir şey var mı? | TypeScript | Aşama 0 |
| 3 | Lansmanda **giriş yöntemleri**: e-posta + Apple + Discord mu? Google da olsun mu? | e-posta, Apple, Discord | Aşama 0 |
| 4 | **Depo**: yeni bir `utkuhalis/AnyTogether` (özel mi, herkese açık mı)? | yeni depo, lansmana kadar özel | Aşama 0 |
| 5 | Mikrofon ve ekran kaydı izinlerinin güncellemelerden sonra korunması için **launcher'ın Developer ID ile imzalanması** (bugün ad-hoc imzalı her güncellemede bu izinler kayboluyor) | sesten önce gerekli | Aşama 4 (daha iyisi: Aşama 0) |
| 6 | **Profil varsayılanları**: ayrıntıları yalnızca arkadaşlara açık, herkese açık bir profil mi (bu plan), yoksa varsayılan olarak tamamen gizli mi? | herkese açık kart, yalnızca arkadaşlara açık ayrıntılar | Aşama 1 |
| 7 | Herkese açık sayfalarda **oyun ve kupa simgeleri**: gösterilsin mi (launcher'ların okuduğu haliyle) yoksa yalnızca oturum açılmış sayfalarda mı? | gösterilir, küçültülmüş, talep üzerine kaldırılır | Aşama 1 |
| 8 | **Mesaj şifrelemesi**: başlangıçta sunucunun okuyabildiği biçimde mi (moderasyon mümkün) yoksa ilk günden uçtan uca mı? | sunucu okuyabilir, E2EE sonra | Aşama 3 |
| 9 | **iOS'ta anlık bildirim** için APNs, telefon uygulamasının senin ekibinle imzalanmasını gerektiriyor; bugün dağıtım AltStore üzerinden: ileride TestFlight mı, App Store mu? | senin ekibinle APNs; hazır olunca TestFlight | Aşama 3 |
| 10 | **Ses kaydı**: asla (bu plan). Kayıt için herhangi bir gerekçe olabilir mi (şikâyetler)? | asla | Aşama 4 |
| 11 | **Parti dışındaki kişilere share play** (herkese açık yayınlar)? | hayır, yalnızca parti üyeleri | Aşama 5 |
| 12 | **Marka**: AnyPS5 içinde iki halkalı logosuyla "AnyTogether" olarak AnyTogether; launcher'ın üst çubuğu için ayrıca bir logo da olsun mu? | iki halkalı logo | Aşama 0 |
| 13 | **Moderatörler**: senin dışında kimler? | sen, ardından güvenilir topluluk üyeleri | Aşama 2 |
| 14 | **Hukuki metinler**: kullanım koşulları, gizlilik politikası, KVKK aydınlatma metni: kodla.agency'nin her zamanki hukuk danışmanı mı yazacak, yoksa önce burada taslağı mı hazırlanacak? | burada taslak hazırlanır, gözden geçirilir | kayıtlar herkese açılmadan önce |
| 15 | Hiç **ücretli özellik** olacak mı (kozmetik temalar, daha yüksek share play kalitesi)? | planlanan yok | daha sonra |
