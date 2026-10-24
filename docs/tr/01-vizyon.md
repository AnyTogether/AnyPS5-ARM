# 1. Vizyon

## Tek cümlede

AnyTogether, AnyPS5 launcher'ını tek bir bilgisayardaki programdan oyuncuların buluştuğu bir yere dönüştürür:
profilin ve kupaların seninle gelir, arkadaşların ne oynadığını görür, oynarken konuşursunuz,
bir arkadaşın nerede olursa olsun oyununu izleyebilir ve ikinci bir kumandayla sana eşlik edebilir;
birbirinizin oyununa da katılabilirsiniz.

## Neden şimdi

Launcher, bir çevrimiçi profilin ihtiyaç duyduğu şeylerin çoğunu zaten tutuyor, ama yalnızca tek bir
bilgisayarda. macOS'ta bu AnyPS5-ARM'ın launcher'ı; Windows ve Linux'ta ise aynı bilgileri oyun bazında
tutan portu, [AnyPS5-Desktop](https://github.com/utkuhalis/AnyPS5-Desktop):

| AnyPS5'te zaten var | Bugün nerede duruyor | AnyTogether ne ekliyor |
|---|---|---|
| Oyun başına oynama süresi ve son oynama tarihi | `Preferences.lastPlayed`, launcher'daki oynama süresi | Tüm bilgisayarlarını kapsayan, arkadaşlarının görebildiği bir oyun kütüphanesi |
| Her oyundan okunan ve oynarken anında fark edilen kupalar | `Trophies.swift`, kupa bildirimi, telefondaki kupa kartı | Tarihleriyle kupa geçmişi, tüm oyuncular genelinde nadirlik, liderlik tabloları |
| O anda oynanan oyun | Discord durumu (`DiscordPresence.swift`) | Discord'a gerek kalmadan, AnyPS5 içinde arkadaşlara çevrimiçi durumu |
| Tema Stüdyosu'nda yapılan temalar | GitHub deposundaki `hub/` klasörü, bir issue üzerinden paylaşılıyor | AnyTogether'daki Tema Hub: launcher'dan yükleme, beğeniler, indirmeler (yapıldı); profilindeki tema (planlandı) |
| Remote Play: oyunun görüntüsü ve sesi aynı ağdaki bir telefona | `RemotePlay.swift`, `StreamEncoder.swift`, telefondaki decoder'lar | Oyun internet üzerinden bir arkadaşa: izlemesi için, yayıncı ona bir kumanda verdiğinde de 2., 3. ya da 4. oyuncu olarak birlikte oynaması için (share play) |
| Tek bilgisayarda, dört kumanda olarak en fazla dört telefon | `RemoteServer` köprüleri, `ANYPS5_REMOTE_PAD_2..4` | Çevrimiçi oyun: arkadaşın aynı oyunu kendi bilgisayarında çalıştırır ve seninkine katılır |
| Klipler ve ekran görüntüleri | Galeri | Aktivite akışında öne çıkan anlar (isteğe bağlı) |

## Kimin için

1. Mac, Windows PC ya da Linux makinesinde oynayan, telefon uygulamasını kumanda veya ikinci ekran olarak kullanan **AnyPS5 oyuncusu**. AnyTogether'ın
   büyük kısmı launcher'da ve telefon uygulamasında yaşanır; web sitesi üçüncü kapıdır.
2. Belki hiç AnyPS5'i olmayan **arkadaşları**. Bir arkadaş web'de bir profili açabilir,
   bir partinin sesli sohbetine tarayıcıdan ya da telefon uygulamasından katılabilir ve bir share play (birlikte oynama)
   oturumunu tarayıcıda izleyebilir; yayıncı ona bir kumanda verdiğinde bir kumandayla ya da klavyeyle birlikte oynar.
3. **Topluluk**: tema yapanlar, hangi oyunların çalıştığını bildirenler, liderlik tablolarında
   yükselenler, bir oyunu birlikte oynayacak birini arayanlar.

## Ne olduğu

[anytogether.kodla.agency](https://anytogether.kodla.agency) üzerinde duyurulan on iki özellik:

1. **Profiller**: kendi temanla bir oyuncu kartı, avatar, biyografi ve istatistikler.
2. **Kupalar**: kazanılan her kupa; nadirliği, tarihi ve ilerlemesiyle.
3. **Sesli sohbet**: hangi oyun olursa olsun, oynarken parti içi sesli sohbet.
4. **Partiler**: parti kur, arkadaşlarını davet et, aynı oyuna birlikte gir.
5. **Arkadaşlar**: arkadaş ekle, kimin çevrimiçi olduğunu ve ne oynadığını gör.
6. **Mesajlar**: launcher'da, telefonda ve web'de birebir ve grup sohbetleri.
7. **Oyun kütüphanesi**: neyi, ne kadar süre ve ne zaman oynadığın, senkronize.
8. **Aktivite akışı**: arkadaşlarından kupalar, oturumlar ve öne çıkan anlar.
9. **Temalar**: profilin ve launcher'ın istediğin gibi görünür, herkesle paylaşılır.
10. **İndirmeler**: resmi launcher, telefon uygulaması, güncellemeler ve araçlar.
11. **Share play**: oturumunu yayınla; arkadaşların izlesin ve konuşun, kumanda verdiklerin de
    2., 3. ya da 4. oyuncu olarak oynasın. Senin kumandan 1. oyuncu olarak kalır.
12. **Liderlik tabloları**: arkadaşlarına ve tüm dünyaya karşı kupalar ve oynama süresi.

Bunların yanında, yol boyunca yapılanlar: **bildirimler** (bir zil, tarayıcı bildirimleri, bir
e-posta özeti), **oyuncu bulma** (oyuncu arama panosu, herkese açık listelenen
partiler ve share play'ler, oyun sayfaları, aynı oyunları oynayan kişiler) ve **uyumluluk listesi**
(oyuncuların raporlarından, her oyunun platform başına ne kadar ilerlediği).

[Özellikler](03-ozellikler.md) her birini ayrıntısıyla anlatır.

## İlkeler

1. **Launcher'ın AnyTogether'a hiçbir zaman ihtiyacı yoktur.** Bugün olduğu gibi her şey çevrimdışı ve oturum açmadan çalışır.
   Giriş yapmak bir şeyler ekler; hiçbir şeyi elinden almaz, oynamayı engellemez. Sunucu çökerse
   launcher göndereceklerini sıraya koyar ve oynamaya devam eder.
2. **Tek hesap, her kapı.** macOS, Windows ve Linux'taki launcher, telefon uygulaması ve
   web sitesi aynı hesap ve aynı veridir. Telefonda okunan bir mesaj launcher'da da okunmuş
   olur. Hiçbir platform ikinci sırada değildir: Windows/Linux launcher'ı macOS'takinin aldığı her
   özelliği alır (bkz. [Platformlar](12-platformlar.md)).
3. **Doğrudan oyuncular arasında.** Ses, share play ve çevrimiçi oyun trafiği eşten eşe (P2P), şifreli olarak
   bir oyuncunun makinesinden diğerininkine gider. Sunucu oyuncuları birbirine tanıştırır, saklanması gerekeni
   saklar ve yalnızca doğrudan bir yol mümkün olmadığında relay (aktarma sunucusu) görevi görür.
4. **Tek dokunuşla giriş.** Kayıt formu yok, şifre yok: e-postayla gelen bir kod, bir passkey, zaten giriş
   yapmış olan telefon ya da Apple, Google ve Discord.
5. **Varsayılan olarak gizli, tercihe göre sosyal.** Yeni bir profil yabancılara yalnızca adını ve avatarını
   gösterir. Oynama süresi, kütüphane, kupalar ve aktivite, sen herkese açana kadar yalnızca arkadaşlara
   görünür. Her öğe ayrı ayrı gizlenebilir.
6. **AnyPS5 gibi görünür.** Aynı konsol tarzı arayüz, aynı temalar. Bir profil, sahibinin Tema Stüdyosu'nda
   yaptığı temayı giyer.
7. **Asla oyun dosyası yok.** AnyTogether oyun dump'larını, anahtarları, firmware'i ya da birinin sahip olmadığı
   bir oyunu oynamasını sağlayacak hiçbir şeyi saklamaz, göndermez, bağlantısını vermez. İndirmeler AnyPS5'in kendi
   yazılımı ve topluluğun ürettikleridir (temalar, düzenler). Bkz.
   [Güvenlik, gizlilik ve kurallar](08-guvenlik-gizlilik.md).
8. **Küçük, iyi anlaşılmış parçalar.** Bir yığın barındırılan servis yerine kendini kanıtlamış açık kaynak parçalar
   (PostgreSQL, Valkey, WebRTC, coturn); her şey Cloudflare arkasında kendi sunucumuzda çalışır ve başka
   bir sunucuya taşınabilir. Kod herkese açık ve MIT lisanslı; herkes tek bir Docker Compose dosyasıyla kendi
   AnyTogether'ını kurabilir (bkz. [Altyapı](09-altyapi.md)).
9. **Ölçülen gecikme.** Ses ve share play, bugün Remote Play'in gecikmesinin gösterildiği gibi, sayılarla
   değerlendirilir (ağızdan kulağa gecikme, ekrandan ekrana gecikme, girdi gidiş-dönüş süresi).

## Ne olmadığı

- **Bir mağaza ya da oyun yeri değil.** Oyun indirmesi yok, dump yok, "nereden bulunur"
  bağlantıları yok, hesap ya da anahtar ticareti yok.
- **PSN'in yerine geçmez.** Kupalar, AnyPS5'in kullanıcının kendi oyunlarında okuduklarından gelir;
  bunlar PlayStation kupaları değil AnyTogether kupalarıdır ve asla Sony'ye gönderilmez.
- **Tek bilgisayarda co-op için gerekli değil.** Telefonlarla yerel co-op bugünkü gibi çalışmaya devam eder.
- **Genel bir sosyal ağ değil.** Oyunlar dışında herkese açık paylaşım yok, sırf sayı olsun diye takipçi
  sayıları yok.
- **Bir bulut oyun servisi değil.** Share play *senin* bilgisayarındaki oyunu *senin* arkadaşına,
  doğrudan aranızda yayınlar, arkadaşının kumandası de aynı yoldan geri gelir; oyun yalnızca senin
  bilgisayarında çalışır. Sunucu yalnızca sizi tanıştırır ve doğrudan bir yol mümkün olmadığında
  relay görevi görür. Asla oyun çalıştırmaz.

## İşe yaradığını nasıl anlayacağız

| Hedef | Ölçüt |
|---|---|
| Oyuncular giriş yapıyor | Aktif launcher'lar içinde giriş yapmış olanların oranı, sürüme göre |
| Profiller canlı hissettiriyor | En az bir arkadaşı olan oyuncular; haftada açılan profil sayısı |
| Ses, kullanmaya devam edilecek kadar iyi | Aynı kıtada ağızdan kulağa gecikme 200 ms'nin altında; parti süresi |
| Share play yerel gibi hissettiriyor | ~1000 km içinde ekrandan ekrana gecikme 120 ms'nin altında |
| Çevrimdışıyken hiçbir şey bozulmuyor | Sunucuya ulaşılamazken sıfır launcher gerilemesi (her sürümde çalışan bir test) |
| Kurallar işliyor | Şikâyetler 48 saat içinde ele alınıyor; hiçbir zaman tek bir oyun dosyası saklanmamış |
