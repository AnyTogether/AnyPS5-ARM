# 9. Altyapı

## 9.1 Nerede çalışacak

**Tek bir sunucuyla** başlıyoruz (uygunsa elimizdeki sunucu, değilse bir VPS):

| Kaynak | Başlangıç | Neden |
|---|---|---|
| CPU | 4 vCPU | API, gateway, worker, web, PostgreSQL, LiveKit bir arada |
| RAM | 8 GB (16 GB rahat) | PostgreSQL tamponları, Next.js, LiveKit |
| Disk | 160 GB NVMe | veritabanı ve loglar; dosyalar R2'de durur |
| Ağ | 1 Gbit/s, cömert trafik kotası | share play bant genişliği demek: 1 Gbit/s ≈ 720p60'ta 100 izleyici |
| İşletim sistemi | Ubuntu 24.04 LTS ya da Debian 12 | |
| Konum | oyuncuların çoğuna yakın (İstanbul ya da Frankfurt) | ses ve share play gecikmesi |

Share play büyüdüğünde ilk olarak LiveKit, daha fazla bant genişliğine sahip kendi makinesine
taşınır; geri kalan her şey yerinde kalır.

## 9.2 Docker Compose

```yaml
services:
  caddy:      # origin'de TLS (Cloudflare origin sertifikası), web/api/rt'ye reverse proxy
  web:        # Next.js, port 3000
  api:        # Hono, port 8080, 2 replika
  realtime:   # gateway, port 8081
  worker:     # pg-boss işleri
  postgres:   # 17, volume NVMe üzerinde, shared_buffers=2GB olarak ayarlı
  valkey:     # 8, kalıcılık gerekmez (appendonly no)
  livekit:    # UDP 50000-60000, 7880 (Caddy arkasında WSS), 7881 TCP için host ağı
  coturn:     # LiveKit'in TURN'ü kullanılırsa isteğe bağlı; 3478 UDP/TCP, 5349 TLS
  backup:     # her gece pg_dump | age | R2'ye yükleme
  uptime:     # Uptime Kuma, tüm servisleri denetler
```

Güvenlik duvarı (ufw/nftables): 443 yalnızca Cloudflare'in IP aralıklarından (web, api, rt,
cdn); LiveKit/TURN için 7880 WSS ve UDP 50000-60000, TCP 7881, 3478, 5349 herkese açık; SSH
yalnızca anahtarla ve bilinen adreslerden.

## 9.3 Cloudflare

- DNS: `anytogether`, `api.anytogether`, `rt.anytogether`, `cdn.anytogether` proxy'li (turuncu);
  `live.anytogether`, `turn.anytogether` yalnızca DNS (gri).
- Origin sertifikasıyla SSL modu Full (strict); Authenticated Origin Pulls açık.
- WAF yönetilen kuralları; `/v1/auth/*` için edge'de rate limiting; bot fight mode web'de açık,
  API'de kapalı (launcher bir tarayıcı değil).
- Önbellek: herkese açık profil sayfaları stale-while-revalidate ile 60 s önbelleğe alınır;
  `cdn` uzun süre önbellekte tutulur.
- R2 bucket'ları: `anytogether-files` (özel), `anytogether-cdn` (`cdn.` üzerinden herkese açık),
  `anytogether-backups` (özel, 30 günlük yaşam döngüsü).
- `rt.` üzerinde WebSocket (proxy'li hostname'lerde destekleniyor).

## 9.4 Dağıtım

- **CI (GitHub Actions)** her push'ta: tip denetimi, lint, birim testleri, servis olarak çalışan
  gerçek PostgreSQL ve Valkey'e karşı API testleri, migration kontrolü (önceki şemanın bir
  kopyasına uygulanır), Docker imajlarının derlenmesi ve GitHub Container Registry'ye gönderilmesi.
- **CD**: `vX.Y.Z` etiketi atıldığında bir action SSH ile bağlanıp
  `docker compose pull && docker compose up -d` çalıştırır; api/web için kesintisiz geçiş
  sağlanır (iki replika, Caddy sağlık kontrolleri); migration'lar önce tek seferlik bir iş olarak
  çalışır ve çalışan kodla geriye dönük uyumlu olmak zorundadır (genişlet, dağıt, daralt).
- **Staging**: aynı compose dosyası daha küçük bir makinede ya da aynı makinede ikinci bir proje
  olarak, `staging.anytogether.kodla.agency` adresinde çalışır; launcher'ın ve telefon
  uygulamasının test sürümleri bunu kullanır.

## 9.5 Yedekleme ve kurtarma

- PostgreSQL: her gece `pg_dump -Fc`, `age` ile şifrelenip R2'ye yüklenir (30 gün saklanır);
  gerçek kullanıcılar gelmeye başladığında zamanda belirli bir noktaya (dakikasına kadar) kurtarma
  için `wal-g` ile R2'ye WAL arşivleme.
- Geri yükleme her ay staging'de test edilir (son dump'ı geri yükleyip API testlerini ona karşı
  çalıştıran bir script).
- R2'de dosya bucket'ı için nesne sürümlemesi açık.
- Kurtarma hedefleri: RPO 5 dakika (WAL ile), RTO 1 saat.

## 9.6 İzleme

- **Uptime Kuma**: web, api, rt (WebSocket), LiveKit ve TURN için dakikada bir HTTP kontrolü;
  uyarılar e-posta ve Telegram/Discord üzerinden.
- **Prometheus + Grafana**: istek oranları ve gecikmeleri (API), soketler (gateway), iş kuyruğu
  derinliği (worker), PostgreSQL (postgres_exporter), LiveKit (kendi `/metrics` uç noktası:
  odalar, katılımcılar, paket kaybı, bant genişliği), sunucu metrikleri (node_exporter).
- **Loglar**: her servisten Loki'ye JSON loglar (ya da başlangıçta rotasyonlu basit
  `docker logs`); loglarda mesaj metni ve token bulunmaz.
- **Hatalar**: API, web, launcher (isteğe bağlı çökme raporları) ve telefon uygulamasında Sentry
  SDK'ları.
- **İstemciler** ses ve share play kalitesini (gidiş-dönüş süresi, kayıp, ekrandan ekrana gecikme
  örnekleri) bir metrik uç noktasına raporlar; veriler toplulaştırılır, içerik gönderilmez.

## 9.7 Maliyetler (kabaca, aylık)

| Kalem | Başlangıç |
|---|---|
| Sunucu (4 vCPU, 16 GB, 1 Gbit/s, Frankfurt/İstanbul) | €20-60 (ya da mevcut sunucumuzda €0) |
| Cloudflare (ücretsiz plan; WAF kuralları gerekirse Pro €20) | €0-20 |
| R2 (10 GB depolama, çıkış trafiği ücretsiz) | < €1 |
| E-posta (Resend ücretsiz katmanı ya da kendi SMTP'miz) | €0 |
| Apple Developer (APNs, imzalama, belki App Store) | ~€8 (€99/yıl) |
| Alan adı | kodla.agency zaten var |
| **Toplam** | **€0-90** |

Share play ile birlikte büyüyen maliyet bant genişliği; LiveKit'i bant genişliği açısından
cömert bir sağlayıcıda (Hetzner 20 TB dahil ediyor) çalıştırmak bu maliyeti sabit tutar.
