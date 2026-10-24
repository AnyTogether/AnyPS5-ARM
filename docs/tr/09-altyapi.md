# 9. Altyapı

## 9.1 Nerede çalışacak

**Elimizdeki sunucuda**, diğerlerinin yanında bir Coolify projesi daha olarak:

| | Bugün (sunucu yönetimi oturumunun okuduğu haliyle, 2026-10-24) |
|---|---|
| Makine | Hetzner Cloud, Falkenstein (fsn1, eu-central), 16 vCPU AMD EPYC Genoa, 30 GiB RAM, 601 GB disk (281 GB boş) |
| İşletim sistemi | Ubuntu 22.04 LTS |
| Ağ | yalnızca genel IPv4 (142.132.181.43), ayda 20 TB dahil, ayda ~1 TB kullanılıyor |
| Çalışanlar | Docker, **Coolify v4**, reverse proxy olarak Traefik (80/443, HTTP/3), ~100 container, 30+ site; uygulama başına PostgreSQL ve Redis kaynakları |
| DNS | `kodla.agency` Cloudflare'de; `anytogether.kodla.agency` → bu sunucu, proxy'li; bugün "AnyTogether" Coolify projesindeki "yakında" nginx uygulaması sunuyor |
| Dağıtım | Coolify: deploy key ve webhook'lu GitHub deposu, push'ta Dockerfile'dan derleme |

**Sunucu paylaşımlı** ve 19 Ekim'de paralel Next.js derlemeleri yüzünden belleği tükendi. Bu
yüzden AnyTogether **küçük ve sınırlandırılmış** olarak planlanıyor:

| Container | Bellek sınırı | CPU sınırı | Notlar |
|---|---|---|---|
| web (Next.js, standalone çıktı) | 512 MB | 1 | her dağıtımda bir kez derlenir (Coolify aynı anda tek derleme yapar) |
| api | 384 MB | 1 | başlangıçta tek replika |
| realtime | 384 MB | 1 | on binlerce boşta bekleyen soket sığar |
| worker | 256 MB | 0.5 | |
| postgres (Coolify kaynağı, 17) | 1 GB | 2 | `shared_buffers=256MB`, `max_connections=50` |
| valkey (Coolify kaynağı) | 128 MB | 0.5 | `maxmemory 96mb`, `allkeys-lru`, kalıcılık yok |
| coturn | 256 MB | 1 | UDP için host ağı |
| **Toplam** | **≈ 3 GB** | | boş kapasitenin rahatça içinde |

Ses, Share play (birlikte oynama) ve kol verileri eşten eşe (P2P) gittiği için sunucu, relay
(aktarma sunucusu) gerektiren çiftler dışında hiçbir zaman medya taşımaz.

## 9.2 Coolify düzeni

**AnyTogether** projesi (zaten var), `production` ve `staging` ortamları:

| Coolify kaynağı | Kaynak | Alan adı / yol |
|---|---|---|
| `web` | `utkuhalis/AnyTogether` deposu, `apps/web/Dockerfile` | `anytogether.kodla.agency` (yol `/`) |
| `api` | aynı depo, `apps/api/Dockerfile` | `anytogether.kodla.agency/api` (Traefik `PathPrefix(/api)`) |
| `realtime` | aynı depo, `apps/realtime/Dockerfile` | `anytogether.kodla.agency/rt` (WebSocket) |
| `worker` | aynı depo, `apps/worker/Dockerfile` | yok |
| `postgres` | Coolify PostgreSQL 17 kaynağı | yalnızca iç ağ |
| `valkey` | Coolify Redis/Valkey kaynağı | yalnızca iç ağ |
| `coturn` | Docker Compose kaynağı, `network_mode: host` | `anytogether-relay.kodla.agency` (yalnızca DNS) |
| staging | `staging` dalından aynı uygulamalar | `anytogether-staging.kodla.agency` |

İlk sürüm hazır olduğunda "yakında" uygulamasının yerini `web` alır.

## 9.3 Cloudflare

- DNS (hepsi `kodla.agency`'nin bir seviye altında, böylece mevcut sertifikalar hepsini kapsar):
  - `anytogether` → 142.132.181.43, **proxy'li** (zaten öyle).
  - `anytogether-cdn` → R2 genel bucket'ının özel alan adı, proxy'li.
  - `anytogether-relay` → 142.132.181.43, **yalnızca DNS** (gri): UDP üzerinden STUN/TURN proxy'lenemez.
  - `anytogether-staging` → 142.132.181.43, proxy'li.
- SSL Full (strict); Traefik, Let's Encrypt sertifikalarını zaten Cloudflare üzerinden DNS-01 ile alıyor.
  coturn'ün TLS portu (5349), `anytogether-relay` için kendi Let's Encrypt sertifikasını kullanır
  (DNS-01, küçük bir certbot container'ı yeniler, yenilemede coturn yeniden yüklenir).
- WAF yönetilen kuralları; `/api/v1/auth/*` üzerinde uçta hız sınırları; bot fight mode web sitesi
  yollarında açık, `/api`'de kapalı (launcher'lar tarayıcı değildir).
- Önbellek: genel profil sayfaları 60 s, stale-while-revalidate ile; R2 dosyaları uzun süre.
- R2 bucket'ları: `anytogether-files` (özel), `anytogether-cdn` (genel), `anytogether-backups`
  (özel, 30 günlük yaşam döngüsü).

## 9.4 Güvenlik duvarı (Utku'nun onayıyla açılacak)

Bugün ufw izin verilmeyen her şeyi düşürüyor ve hiçbir relay portu açık değil. Yalnızca relay
için gerekenler:

| Port | Protokol | Amaç |
|---|---|---|
| 3478 | UDP ve TCP | STUN ve TURN |
| 5349 | TCP | TLS üzerinden TURN (UDP'yi engelleyen ağlar için) |
| 49160-49360 | UDP | TURN relay portları (200 port ≈ aynı anda 100 relay'li görüşme; gerekirse genişletilir) |

Docker'ın yayımladığı portlar ufw'yi atlar; bu yüzden coturn host ağıyla çalışır ve bu kurallar
ufw'de açıkça tanımlanır (sunucuya bağlı bir Hetzner Cloud Firewall varsa orada da: Utku Hetzner
konsolundan kontrol eder). Geri kalan her şey 443'te Traefik'in arkasında kalır.

## 9.5 coturn

```
listening-port=3478
tls-listening-port=5349
min-port=49160
max-port=49360
external-ip=142.132.181.43
realm=anytogether.kodla.agency
use-auth-secret
static-auth-secret=<from Coolify env>   # API bundan süreli kimlik bilgileri üretir
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

Yasaklanan özel aralıklar, relay'in sunucunun iç Docker ağlarına erişmek için kullanılmasını
engeller. Kimlik bilgileri standart TURN REST şemasıdır (kullanıcı adı = bitiş zamanı:kullanıcı
id'si, parola = bunun HMAC'i), 12 saat geçerlidir.

## 9.6 Dağıtım

- `utkuhalis/AnyTogether` deposunun `main` dalına push → Coolify değişen her uygulamayı derler ve
  dağıtır (webhook, bu sunucuda aynı anda tek derleme).
- GitHub Actions yalnızca denetim yapar: typecheck, lint, PostgreSQL ve Valkey servis
  container'larına karşı testler, migration kontrolü. Coolify yalnızca geçeni dağıtır (`main`
  üzerinde dal koruması).
- Migration'lar API container'ı başlarken çalışır (sunucudan önce `drizzle-kit migrate`) ve her
  zaman hâlâ çalışan sürümle geriye dönük uyumludur (genişlet, dağıt, daralt).
- Her Dockerfile'da sağlık kontrolleri var; böylece Traefik yalnızca hazır bir container'a
  yönlendirir.

## 9.7 Yedekler ve kurtarma

- Coolify'ın zamanlanmış PostgreSQL yedekleri, günlük, R2 yedek bucket'ına (Coolify'da S3 uyumlu
  hedef), şifreli; 30 gün saklanır.
- Her ay staging veritabanına bir geri yükleme testi.
- Dosya bucket'ında R2 sürümlemesi.
- Hedefler: lansmanda RPO 24 saat (günlük dökümler), WAL arşivleme (R2'ye wal-g) eklendiğinde
  5 dk; RTO 1 saat.

## 9.8 İzleme

- Coolify'ın kendi container sağlığı ve bildirimleri.
- Erişilebilirlik kontrolleri (bu tür sunucularda zaten yaygın olan Uptime Kuma ya da Cloudflare
  sağlık kontrolleri): web sitesi, `/api/v1/health`, gateway (WebSocket el sıkışması), relay
  üzerinde STUN.
- Metrikler: API ve gateway Prometheus metrikleri sunar; coturn'ün Prometheus exporter'ı
  (tahsisler, relay edilen bayt).
- Hatalar: Sentry (API, web, isteğe bağlı çökme raporlarıyla launcher'lar, telefon uygulaması).
- İstemciler görüşme kalitesini raporlar (doğrudan mı relay'li mi, gidiş-dönüş süresi, kayıp,
  ekrandan ekrana gecikme örnekleri); toplu halde, içerik olmadan. Relay'li görüşmelerin oranı
  bize ne kadar TURN bant genişliği bekleyeceğimizi söyler.

## 9.9 Maliyetler

| Kalem | Aylık |
|---|---|
| Sunucu | €0 ek (mevcut Hetzner makinesi) |
| Trafik | dahil olan 20 TB'ın içinde; yalnızca relay'li görüşmeler |
| Cloudflare (ücretsiz plan), R2 (birkaç GB, çıkış ücreti yok) | ~€0-1 |
| Giriş kodları için e-posta (Resend ücretsiz katmanı ya da kodla.agency SMTP) | €0 |
| Apple Developer (zaten ödeniyor: APNs, Developer ID imzalama) | €0 ek |
| **Toplam** | **≈ €0-1** |

Relay'li share play bir gün çok büyürse coturn kendine ait ucuz bir Hetzner makinesine taşınır
(orada da 20 TB dahil).
