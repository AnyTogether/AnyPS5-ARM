# 9. Altyapı

## 9.1 Nerede çalışacak

**Kendi sunucumuzda**, orada zaten çalışan projelerin yanında bir proje daha olarak. Sunucunun
ayrıntıları (adresi, sağlayıcısı, boyutu, üstünde başka ne çalıştığı) bu herkese açık plana
bilerek **yazılmadı**; AnyTogether deposunun özel altyapı notlarında duruyor.

Bugün çalışanlar (2026-10-25): web, api, realtime, PostgreSQL ve Valkey. Worker, R2 ve staging
kopyası henüz yok; relay isteğe bağlı. Dosyalar (avatarlar, tema dosyaları ve görselleri) R2
kullanılana kadar PostgreSQL'de duruyor ve az sayıdaki arka plan işini API kendisi çalıştırıyor
(bkz. [Mimari](02-mimari.md)). Web Push dışarıdan bir servise ihtiyaç duymaz: API push'ları kendi
VAPID anahtarlarıyla imzalar.

Sunucu başka sitelerle paylaşıldığı için AnyTogether **küçük ve sınırlı** planlandı:

| Container | Bellek sınırı | CPU sınırı | Notlar |
|---|---|---|---|
| web (Next.js, standalone çıktı) | 512 MB | 1 | her dağıtımda bir kez derlenir; derlemeler sırayla yapılır |
| api | 384 MB | 1 | başlangıçta tek kopya |
| realtime | 384 MB | 1 | on binlerce boşta bekleyen soket sığar |
| worker | 256 MB | 0.5 | |
| postgres 17 | 1 GB | 2 | `shared_buffers=256MB`, `max_connections=50` |
| valkey | 128 MB | 0.5 | `maxmemory 96mb`, `allkeys-lru`, kalıcılık yok |
| coturn | 256 MB | 1 | UDP için host ağı |
| **Toplam** | **≈ 3 GB** | | |

Bir Next.js derlemesi çalışırken ayrıca 2-3 GB bellek kullanır; derlemeler sırayla yapıldığı için
bu tepe başka bir derlemeyle çakışmaz.

Ses, share play ve çevrimiçi oyun trafiği eşten eşe gittiği için sunucu, relay'e ihtiyaç duyan
çiftler dışında hiçbir zaman medya taşımaz.

## 9.2 Uygulamalar

| Uygulama | Kaynak | Yol |
|---|---|---|
| `web` | `utkuhalis/AnyTogether` deposu, `infra/Dockerfile.web` | `anytogether.kodla.agency/` |
| `api` | aynı depo, `infra/Dockerfile.node` (`APP=api`) | `anytogether.kodla.agency/api` |
| `realtime` | aynı depo, `infra/Dockerfile.node` (`APP=realtime`) | `anytogether.kodla.agency/rt` (WebSocket) |
| `worker` (planlandı) | aynı depo, `infra/Dockerfile.node` (`APP=worker`) | yok |
| `postgres`, `valkey` | yönetilen veritabanı kaynakları | yalnızca iç ağ |
| `coturn` | host ağıyla çalışan container | `anytogether-relay.kodla.agency` (yalnızca DNS) |
| staging (planlandı) | `staging` dalından aynı uygulamalar | `anytogether-staging.kodla.agency` |

Sunucunun reverse proxy'si yola göre yönlendirir; ilk sürüm hazır olduğunda "yakında" sayfasının
yerini `web` alır.

## 9.3 Cloudflare

- DNS (hepsi `kodla.agency`'nin bir seviye altında, böylece mevcut sertifikalar hepsini kapsar):
  - `anytogether` → sunucu, **proxy'li** (zaten öyle).
  - `anytogether-cdn` → R2 genel bucket'ının özel alan adı, proxy'li.
  - `anytogether-relay` → **yalnızca DNS** (gri): UDP üzerinden STUN/TURN proxy'lenemez, bu
    yüzden bu ad işaret ettiği adresi gösterir. Kendine ait bir adrese (ayrı bir IP ya da küçük
    ayrı bir makine) işaret etmeli; Cloudflare arkasında gizli kalan web sunucusunun adresine
    asla.
  - `anytogether-staging` → sunucu, proxy'li.
- SSL Full (strict); sunucu Let's Encrypt sertifikalarını Cloudflare üzerinden DNS-01 ile alır.
- Sunucu web trafiğini **yalnızca Cloudflare'in adres aralıklarından** kabul eder; böylece adresi
  bilinse bile Cloudflare atlanarak ulaşılamaz.
  coturn'ün TLS portu (5349), `anytogether-relay` için kendi Let's Encrypt sertifikasını kullanır
  (DNS-01, küçük bir certbot container'ı yeniler, yenilemede coturn yeniden yüklenir).
- WAF yönetilen kuralları; `/api/v1/auth/*` üzerinde uçta hız sınırları; bot fight mode web sitesi
  yollarında açık, `/api`'de kapalı (launcher'lar tarayıcı değildir).
- Önbellek: genel profil sayfaları 60 s, stale-while-revalidate ile; R2 dosyaları uzun süre.
- R2 bucket'ları: `anytogether-files` (özel), `anytogether-cdn` (genel), `anytogether-backups`
  (özel, 30 günlük yaşam döngüsü). Sunucunun Cloudflare API token'ının R2 yetkisi olmayabilir; bucket'ları açmak ve
  `anytogether-cdn`'i genel bucket'ın özel alan adı olarak bağlamak gerekirse Utku tarafından
  Cloudflare panelinden yapılır.

## 9.4 Güvenlik duvarı

Yalnızca relay'in kendi portlarına ihtiyacı var; Utku'nun onayıyla açılır:

| Port | Protokol | Ne için |
|---|---|---|
| 3478 | UDP ve TCP | STUN ve TURN |
| 5349 | TCP | TLS üzerinden TURN (UDP'yi engelleyen ağlar için) |
| 49160-49360 | UDP | TURN relay portları (200 port ≈ aynı anda 100 relay'li görüşme; gerekirse genişletilir) |

Geri kalan her şey 443'te reverse proxy'nin arkasında kalır.

## 9.5 coturn

```
listening-port=3478
tls-listening-port=5349
min-port=49160
max-port=49360
external-ip=<relay'in genel adresi>
realm=anytogether.kodla.agency
use-auth-secret
static-auth-secret=<ortam değişkeninden>   # API bundan süreli kimlik bilgileri üretir
cert=/certs/anytogether-relay/fullchain.pem
pkey=/certs/anytogether-relay/privkey.pem
no-cli
no-multicast-peers
denied-peer-ip=10.0.0.0-10.255.255.255
denied-peer-ip=172.16.0.0-172.31.255.255
denied-peer-ip=192.168.0.0-192.168.255.255
total-quota=200
user-quota=4
max-bps=2000000                         # tahsis başına 2 MB/s (~16 Mbit/s), 720p60 için yeterli
```

Yasaklanan özel aralıklar, relay'in sunucunun iç ağlarına erişmek için kullanılmasını
engeller. Kimlik bilgileri standart TURN REST şemasıdır (kullanıcı adı = bitiş zamanı:kullanıcı
id'si, parola = bunun HMAC'i), 12 saat geçerlidir.

## 9.6 Dağıtım

- `utkuhalis/AnyTogether` deposunun `main` dalına push → sunucu değişen her uygulamayı derler ve
  dağıtır (webhook, aynı anda tek derleme).
- GitHub Actions yalnızca denetim yapar: lint, typecheck, PostgreSQL ve Valkey servis
  container'larına karşı testler (yapıldı); migration kontrolü ve `main` üzerinde dal koruması
  planlandı.
- Migration'lar API başlarken çalışır ve her zaman hâlâ çalışan sürümle geriye dönük uyumludur
  (genişlet, dağıt, daralt): yalnızca tablo, sütun ve indeks eklerler.
- Her Dockerfile'da sağlık kontrolleri var; böylece proxy yalnızca hazır bir container'a
  yönlendirir.

## 9.7 Yedekler ve kurtarma

- Zamanlanmış PostgreSQL yedekleri, günlük, R2 yedek bucket'ına (S3 uyumlu), şifreli; 30 gün
  saklanır.
- Her ay staging veritabanına bir geri yükleme testi.
- Dosya bucket'ında R2 sürümlemesi.
- Hedefler: lansmanda RPO 24 saat (günlük dökümler), WAL arşivleme (R2'ye wal-g) eklendiğinde
  5 dk; RTO 1 saat.

## 9.8 İzleme

- Sunucu platformunun container sağlık kontrolleri ve bildirimleri.
- Erişilebilirlik kontrolleri (bu tür sunucularda zaten yaygın olan Uptime Kuma ya da Cloudflare
  sağlık kontrolleri): web sitesi, `/api/v1/health`, gateway (WebSocket el sıkışması), relay
  üzerinde STUN.
- Metrikler: API ve gateway Prometheus metrikleri sunar; coturn'ün Prometheus exporter'ı
  (tahsisler, relay edilen bayt).
- Hatalar: Sentry (API, web, telefon uygulaması), planlandı. Oyun çökmeleri kendiliğinden hiçbir
  yere gönderilmez: macOS launcher'ının çökme paneli bir rapor dışa aktarır ve yalnızca oyuncu
  isterse, kişisel ayrıntılar ve AnyTogether token'ları çıkarılmış, önceden doldurulmuş bir GitHub
  issue'su açar.
- İstemciler görüşme kalitesini raporlar (doğrudan mı relay'li mi, gidiş-dönüş süresi, kayıp,
  ekrandan ekrana gecikme örnekleri); toplu halde, içerik olmadan. Relay'li görüşmelerin oranı
  bize ne kadar TURN bant genişliği bekleyeceğimizi söyler.

## 9.9 Maliyetler

| Kalem | Aylık |
|---|---|
| Sunucu | €0 ek (mevcut sunucumuz) |
| Trafik | sunucunun dahil trafiği içinde; yalnızca relay'li görüşmeler |
| Cloudflare (ücretsiz plan), R2 (birkaç GB, çıkış ücreti yok) | ~€0-1 |
| Giriş kodları için e-posta (Resend ücretsiz katmanı ya da kodla.agency SMTP) | €0 |
| Apple Developer (zaten ödeniyor: APNs, Developer ID imzalama) | €0 ek |
| **Toplam** | **≈ €0-1** |

Relay'li share play bir gün çok büyürse coturn kendine ait küçük bir makineye taşınır.

## 9.10 Kendi sunucunu kurmak

AnyTogether MIT lisanslı ve herkes çalıştırabilir. Deponun `deploy/` klasörü her şeyi Docker Compose
ile tek bir makineye kurar;
[docs/self-hosting.md](https://github.com/utkuhalis/AnyTogether/blob/main/docs/self-hosting.md)
adım adım anlatır:

| Servis | Nedir |
|---|---|
| `caddy` | reverse proxy: kendini yenileyen Let's Encrypt sertifikalarıyla hostname'in için HTTPS, `/api` API'ye, `/rt` gateway'e, gerisi web sitesine |
| `web`, `api`, `realtime` | depodan derlenen üç uygulama; API açılırken migration'ları uygular |
| `postgres` | PostgreSQL 17, verinin tutulduğu tek yer (avatarlar dahil) |
| `valkey` | hız sınırları, giriş challenge'ları, çevrimiçi durumu, olay yolu; diske hiçbir şey yazılmaz |
| `coturn` | isteğe bağlı (`--profile turn`): sesin katı ağların arkasında da bağlanması için bir STUN/TURN relay |

- **Gerekenler**: genel adresi olan bir Linux makinesi, 2 GB bellek (çoğu web sitesini derlemek için),
  Compose'lu Docker, ona işaret eden bir hostname, 80 ve 443 portları (relay ile birlikte 3478 ve küçük
  bir UDP aralığı).
- **Ayarlar** tek bir `.env` dosyasında: hostname, Let's Encrypt iletişim adresi, veritabanı parolası,
  erişim token'larını imzalayan Ed25519 anahtarı, e-posta (SMTP, Resend ya da denemek için API'nin
  logu), Apple, Google ve Discord istemci ID'leri (boşken her biri kapalı), TURN sırrı ve URL'leri,
  tarayıcı push'u için VAPID anahtar çifti (boşken kapalı), ziyaretçinin adresini hangi header'ın
  taşıdığı ve oyun simgelerinin gelebileceği host'lar.
- **Yedekler**: her şey PostgreSQL'de olduğu için tek bir `pg_dump` tam bir yedektir.
- **Moderasyon**: bir hesap, API'nin container'ı içinde çalışan komut satırı aracıyla
  (`admin grant @handle`) admin yapıldıktan sonra `/admin` adresindeki yönetim sayfası.
- **İstemciler**: macOS launcher'ı, AnyPS5 Desktop ve telefon uygulaması başka bir sunucuya
  yönlendirilebilir (Ayarlar → AnyTogether → Sunucu); bir passkey, yapıldığı hostname'e aittir.
- **Lisans**: MIT; istediğin gibi kullan, değiştir ve çalıştır.
