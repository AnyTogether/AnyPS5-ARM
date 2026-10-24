# 1. Vizyon

## Tek cümlede

AnyTogether, AnyPS5 launcher'ını tek bir Mac'teki bir programdan oyuncuların buluştuğu bir yere
dönüştürür: profilin ve kupaların seninle gelir, arkadaşların ne oynadığını görür, oynarken
konuşursunuz ve bir arkadaşın nerede olursa olsun oyununu izleyebilir ya da kontrolü devralabilir.

## Neden şimdi

Launcher, bir çevrimiçi profilin ihtiyaç duyduğu şeylerin çoğunu zaten tutuyor; ama yalnızca tek
bir Mac'te:

| AnyPS5'te zaten var | Bugün nerede duruyor | AnyTogether ne ekliyor |
|---|---|---|
| Oyun başına oynama süresi ve son oynanma | `Preferences.lastPlayed`, launcher'daki oynama süresi | Tüm Mac'lerini kapsayan, arkadaşlarının görebildiği bir oyun kütüphanesi |
| Her oyundan okunan ve oynarken anında fark edilen kupalar | `Trophies.swift`, kupa bildirimi, telefondaki kupa kartı | Tarihli kupa geçmişi, tüm oyuncular arasında nadirlik, liderlik tabloları |
| Şu an oynanan oyun | Discord durumu (`DiscordPresence.swift`) | Discord'a gerek kalmadan, AnyPS5 içinde arkadaşlara çevrimiçi durumu |
| Tema Stüdyosu'nda yapılan temalar | GitHub deposundaki `hub/` klasörü, bir issue ile paylaşılıyor | Stüdyo'dan doğrudan yükleme, beğeniler, indirmeler, profilde görünen tema |
| Remote Play: oyunun görüntüsü ve sesi aynı ağdaki bir telefona | `RemotePlay.swift`, `StreamEncoder.swift`, telefondaki çözücüler | Aynı yayın internet üzerinden bir arkadaşa; arkadaş kontrolü devralabilir |
| Dört kola dönüşen en fazla dört telefon | `RemoteServer` köprüleri, `ANYPS5_REMOTE_PAD_2..4` | Her yerden bağlanan bir arkadaşın kolu 2. oyuncu olarak katılır |
| Klipler ve ekran görüntüleri | Galeri | Aktivite akışında öne çıkanlar (isteğe bağlı) |

## Kimin için

1. **AnyPS5 oyuncusu**: Mac'te oynar, telefon uygulamasını kol ya da ikinci ekran olarak kullanır.
   AnyTogether'ın büyük kısmı launcher'da ve telefon uygulamasında yaşanır; web sitesi üçüncü kapıdır.
2. **Arkadaşları**: belki hiç AnyPS5'leri yoktur. Bir arkadaş web'de bir profili açabilir, bir
   partinin sesli sohbetine tarayıcıdan ya da telefon uygulamasından katılabilir, bir Share play
   oturumunu izleyebilir.
3. **Topluluk**: tema yapanlar, hangi oyunların çalıştığını bildirenler, liderlik tablolarında
   yükselenler.

## Ne olduğu

[anytogether.kodla.agency](https://anytogether.kodla.agency) adresinde duyurulan on iki özellik:

1. **Profiller**: kendi temanla bir oyuncu kartı, avatar, biyografi ve istatistikler.
2. **Kupalar**: kazanılan her kupa; nadirliği, tarihi ve ilerlemesiyle.
3. **Sesli sohbet**: oynarken, hangi oyun olursa olsun parti içi sesli sohbet.
4. **Partiler**: parti kur, arkadaşlarını davet et, aynı oyuna birlikte gir.
5. **Arkadaşlar**: arkadaş ekle, kimin çevrimiçi olduğunu ve ne oynadığını gör.
6. **Mesajlar**: launcher'da, telefonda ve web'de birebir ve grup sohbetleri.
7. **Oyun kütüphanesi**: ne oynadığın, ne kadar ve ne zaman; senkronize.
8. **Aktivite akışı**: arkadaşlarından kupalar, oturumlar ve öne çıkanlar.
9. **Temalar**: profilin ve launcher'ın istediğin gibi görünsün, herkesle paylaş.
10. **İndirmeler**: resmi launcher, telefon uygulaması, güncellemeler ve araçlar.
11. **Share play (birlikte oynama)**: oturumunu yayınla; bir arkadaşın izlesin ya da kontrolü devralsın.
12. **Liderlik tabloları**: arkadaşlarına ve tüm dünyaya karşı kupalar ve oynama süresi.

[Özellikler](03-ozellikler.md) her birini ayrıntısıyla anlatıyor.

## İlkeler

1. **Launcher'ın AnyTogether'a hiçbir zaman ihtiyacı yok.** Bugün olduğu gibi her şey çevrimdışı
   ve oturum açmadan çalışır. Oturum açmak bir şeyler ekler; hiçbir şeyi elinden almaz, oynamayı
   asla engellemez. Sunucu çökerse launcher göndereceklerini kuyruğa alır ve oynamaya devam eder.
2. **Tek hesap, üç kapı.** Launcher, telefon uygulaması ve web sitesi aynı hesap ve aynı veridir.
   Telefonda okunan bir mesaj launcher'da da okunmuş görünür.
3. **Varsayılan olarak gizli, tercihe göre sosyal.** Yeni bir profil, yabancılara yalnızca adını ve
   avatarını gösterir. Oynama süresi, kütüphane, kupalar ve aktivite, sen herkese açana kadar
   yalnızca arkadaşlara görünür. Her öğe ayrı ayrı gizlenebilir.
4. **AnyPS5 gibi görünür.** Aynı konsol tarzı arayüz, aynı temalar. Bir profil, sahibinin Tema
   Stüdyosu'nda yaptığı temayı giyer.
5. **Asla oyun dosyası yok.** AnyTogether oyun dump'larını, anahtarları, firmware'i ya da birinin
   sahip olmadığı bir oyunu oynamasını sağlayacak hiçbir şeyi saklamaz, göndermez, bağlantısını
   vermez. İndirmeler, AnyPS5'in kendi yazılımı ve topluluğun ürettikleridir (temalar, yerleşimler).
   Bkz. [Güvenlik, gizlilik ve kurallar](08-guvenlik-gizlilik.md).
6. **Küçük, iyi anlaşılmış parçalar.** Bir yığın barındırılan hizmet yerine kendini kanıtlamış
   açık kaynak parçalar (PostgreSQL, Valkey, LiveKit, coturn); her şey Cloudflare arkasında kendi
   sunucumuzda çalışır ve başka bir sunucuya taşınabilir.
7. **Ölçülen gecikme.** Sesli sohbet ve Share play, bugün Remote Play'in gecikmesinin gösterildiği
   gibi rakamlarla değerlendirilir (ağızdan kulağa gecikme, ekrandan ekrana gecikme, giriş gidiş-dönüş süresi).

## Ne olmadığı

- **Bir mağaza ya da oyun bulunacak bir yer değil.** Oyun indirme yok, dump yok, "nereden bulunur"
  bağlantısı yok, hesap ya da anahtar alışverişi yok.
- **PSN'in yerine geçmiyor.** Kupalar, AnyPS5'in kullanıcının kendi oyunlarından okuduklarından
  gelir; bunlar PlayStation kupaları değil AnyTogether kupalarıdır ve asla Sony'ye gönderilmez.
- **Tek Mac'te co-op için gerekli değil.** Telefonlarla yerel co-op bugünkü gibi çalışmaya devam eder.
- **Genel bir sosyal ağ değil.** Oyunlar dışında herkese açık paylaşım yok, salt kendisi için
  takipçi sayısı yok.
- **Bir bulut oyun hizmeti değil.** Share play, *senin* Mac'indeki oyunu *senin* arkadaşına
  yayınlar; sunucu gerektiğinde aktarır, asla oyun çalıştırmaz.

## İşe yaradığını nasıl anlayacağız

| Hedef | Ölçüt |
|---|---|
| Oyuncular oturum açıyor | Oturum açılmış aktif launcher'ların oranı, sürüme göre |
| Profiller canlı hissettiriyor | En az bir arkadaşı olan oyuncular; haftalık açılan profil sayısı |
| Sesli sohbet kullanmaya devam edecek kadar iyi | Aynı kıtada ağızdan kulağa gecikme 200 ms'nin altında; parti süresi |
| Share play yerel gibi hissettiriyor | ~1000 km içinde ekrandan ekrana gecikme 120 ms'nin altında; giriş gidiş-dönüş süresi 80 ms'nin altında |
| Çevrimdışıyken hiçbir şey bozulmuyor | Sunucuya ulaşılamazken sıfır launcher gerilemesi (her sürümde bir test) |
| Kurallar işliyor | Şikâyetler 48 saat içinde ele alınıyor; hiçbir zaman tek bir oyun dosyası saklanmamış |
