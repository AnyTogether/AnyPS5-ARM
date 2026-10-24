# 12. Platformlar

AnyTogether **her AnyPS5 launcher'ı** içindir: macOS launcher (AnyPS5-ARM, Swift), Windows ve
Linux launcher (Rust portu), telefon uygulaması (iOS ve Android) ve web. Bu belge, her yerde aynı
olanları ve her platformun kendi yoluyla yaptıklarını listeler; ayrıca herhangi bir launcher'ın
telefon uygulamasıyla konuşabilmesi için telefon protokolünü yazıya döker.

## 12.1 Her yerde aynı olanlar (sözleşmeler)

| Sözleşme | Tanımlandığı yer | Kullananlar |
|---|---|---|
| REST API `/api/v1` | ortak Zod şemalarından üretilen OpenAPI 3.1 belgesi | üretilen tipler aracılığıyla tüm istemciler |
| Realtime gateway `/rt` | `packages/shared` olay ve sinyalleşme tipleri; [API](04-api.md) 4.7 | tüm istemciler |
| Giriş | PKCE'li OpenID Connect (RFC 7636), yerel uygulama yönlendirme kuralları (RFC 8252), e-posta kodları, telefona devretme, cihaz kodu (RFC 8628) | tüm istemciler |
| Görüşmeler | WebRTC: Opus ses, H.264 Share play (birlikte oynama) videosu (Constrained Baseline ya da Main, B-frame yok), `pad` data channel'ı (sırasız, `maxRetransmits: 0`) | her launcher, telefon, web |
| Kol paketi | aşağıdaki 80 baytlık girdi paketi (12.4) | telefon → launcher, share play izleyicisi → ev sahibi |
| Kupa ve oturum verisi | [Veri modeli](05-veri-modeli.md) | her launcher |
| Tema dosyası | `.anyps5theme` (zip: `theme.json` + isteğe bağlı resim/video ve müzik) | her launcher, Hub |

## 12.2 Her platformun kendi yoluyla yaptıkları

| İhtiyaç | macOS launcher | Windows launcher | Linux launcher | Telefon | Web |
|---|---|---|---|---|---|
| Dil | Swift | Rust | Rust | Dart (Flutter) | TypeScript |
| AnyTogether istemcisi | `AnyPS5Core/Together` | `anytogether` crate'i | `anytogether` crate'i | `mobile/lib/together` | `apps/web` |
| Giriş | yerel Apple, `ASWebAuthenticationSession` | varsayılan tarayıcı + loopback | varsayılan tarayıcı + loopback | yerel Apple/Google, Discord | yönlendirmeler |
| Güvenli token deposu | Keychain | Credential Manager | Secret Service (GNOME Keyring, KWallet) | Keychain / Keystore | HttpOnly çerez |
| WebRTC | Google WebRTC framework'ü | `webrtc-rs` ya da `libwebrtc` bağlamaları | aynısı | `flutter_webrtc` | tarayıcı |
| Oyun görüntüsü yakalama | ScreenCaptureKit | Windows.Graphics.Capture | xdg-desktop-portal üzerinden PipeWire | - (yalnızca izleyici) | - (yalnızca izleyici) |
| Oyun sesi yakalama | ScreenCaptureKit ses | WASAPI süreç loopback'i | oyunun PipeWire düğümü | - | - |
| Donanımsal H.264 | VideoToolbox | Media Foundation, NVENC, AMF, Quick Sync | VA-API, NVENC | çözücüler: VideoToolbox, MediaCodec | tarayıcı |
| Mikrofon işleme | Apple ses işleme | WebRTC APM | WebRTC APM | platform | tarayıcı |
| Genel bas-konuş | Carbon kısayol tuşu | `RegisterHotKey` | GlobalShortcuts portalı | düğme | odaktayken tuş |
| İstenecek izinler | Mikrofon, Ekran Kaydı | Mikrofon | Mikrofon; portalın ekran paylaşımı istemi | Mikrofon, bildirimler | Mikrofon |
| Anlık bildirimler | - (çalışırken soket) | - | - | APNs / FCM | Web Push (sonra) |
| İmzalama | Developer ID + notarization (güncellemelerde izinler korunur) | Authenticode (SmartScreen uyarılarını önler) | paketler (Flatpak, AppImage, dağıtım paketleri) | App Store / sideload, Play / APK | - |

**Motor**: her launcher oyunları aynı motorla başlatır; bu yüzden motorda yaşayan özellikler,
launcher aynı ayarları geçirdiği anda her yerde çalışır. Telefon ve share play kolları, motorun
**uzak kol köprülerini** kullanır (`ANYPS5_REMOTE_PAD`, `ANYPS5_REMOTE_PAD_2` … `_4`: kol başına
bir loopback UDP adresi). Bunlar bugün AnyPS5-ARM'ın motorunda var; motoru başka bir fork'tan
derleyen bir launcher, telefon kolunu ve share play'in "birlikte oyna" özelliğini sunabilmek için
bu değişikliği kendi fork'una almalıdır (değişiklik motorun kol kütüphanesinin içinde, kendi
başına bir bütündür).

## 12.3 Özellik eşitliği

| Özellik | macOS | Windows | Linux | Telefon | Web |
|---|---|---|---|---|---|
| Profiller, kupalar, kütüphane, arkadaşlar, akış, liderlik tabloları | ✓ | ✓ | ✓ | ✓ | ✓ |
| Mesajlar | ✓ | ✓ | ✓ | ✓ + anlık bildirim | ✓ |
| Partiler ve ses | ✓ | ✓ | ✓ | ✓ (bilgisayarın kulaklığı olarak da) | ✓ |
| Ev sahibi olarak share play | ✓ | ✓ | ✓ | - | - |
| İzleyici / 2. oyuncu olarak share play | ✓ | ✓ | ✓ | ✓ | ✓ |
| Temalar ve Hub | ✓ | ✓ (launcher `.anyps5theme` okuduğunda) | ✓ | launcher'ın temasını giyer | ✓ (profiller) |
| Uyumluluk raporları | ✓ | ✓ | ✓ | - | - |

Bir AnyTogether sürümü ancak mevcut launcher'lar onu kullanabildiğinde "bitmiş" sayılır; Rust
crate'i sunucuyla aynı CI'da derlenir ve test edilir.

## 12.4 Telefon protokolü

Bir launcher ile AnyPS5 Remote telefon uygulamasının aynı ağda ya da kabloyla nasıl konuştuğu. Bunu
uygulayan bir launcher, telefon uygulamasıyla macOS launcher'ın çalıştığı gibi çalışır.

### Bulma ve eşleştirme

- Launcher, adıyla birlikte `_anyps5-remote._tcp` Bonjour/mDNS servisini duyurur ve **TCP
  47700**'de WebSocket'leri dinler (meşgulse başka bir port; telefonun elle adres alanı 47700'ü
  varsayar).
- Mesajlar JSON metin çerçeveleridir, `{"type": "...", ...}`.

| Yön | type | Alanlar |
|---|---|---|
| telefon → launcher | `hello` | `protocol` (1), `deviceID`, `deviceName`, `key` (ilk seferde null) |
| launcher → telefon | `pairing` | `code`: 4 hane, ikisinde de gösterilir; kullanıcı bilgisayarda izin verir |
| launcher → telefon | `welcome` | `session` (64 bit, ondalık dize olarak), `udpPort`, `macName` (bilgisayarın adı), `key` (bir sonraki sefer gönderilecek) |
| launcher → telefon | `rejected` | `reason`: `denied`, `busy`, `protocol` |
| telefon → launcher | `latency` | `milliseconds` |
| launcher → telefon | `library` | `games` [`id`, `name`, `state`, `trophies`, `art`, `layout`], `selected`, `running`, `language` |
| telefon → launcher | `wantArt` | `id` → launcher `art` ile cevap verir {`id`, `icon`, `background`: base64 JPEG} |
| telefon → launcher | `select`, `launch`, `close`, `home`, `command` {`name`: left, right, up, down, select, back, options, l1, r1, capture} | launcher modu |
| telefon → launcher | `saveLayout` | `id`, `layout` (telefonun kendi JSON'u, oyun başına saklanır) |
| launcher → telefon | `trophy` | `name`, `detail`, `grade`, `icon` |
| launcher → telefon | `activity` | launcher'ın bir oyunla ne yaptığı ya da null |
| launcher → telefon | `look` | `deep`, `middle`, `accent` (#RRGGBB): launcher'ın teması |
| telefon → launcher | `stream` | `on`, `width`, `height`: Remote Play istenip istenmediği |
| telefon → launcher | `keyFrame` | telefon görüntünün bir kısmını kaybetti |
| launcher → telefon | `streaming` | `state`: on, off, noPermission, noGame |

Aynı anda en fazla dört telefon, oyuncu başına bir tane; her seferinde yalnızca bir yeni telefon
için onay istenir.

### Kol (UDP)

Telefon kolunu launcher'daki `udpPort`'a gönderir; launcher bunu o telefonun yuvasına ait oyun
köprüsüne aktarır ve oyunun cevaplarını geri aktarır. Hepsi little-endian.

**Girdi, 80 bayt** (telefon → launcher → oyun; ayrıca share play izleyicisi → ev sahibi):

| Offset | Boyut | Alan |
|---|---|---|
| 0 | 4 | magic `0x49525041` ("APRI") |
| 4 | 2 | sürüm 1 |
| 6 | 2 | boyut 80 |
| 8 | 4 | sıra numarası |
| 12 | 4 | bayraklar: 1 = hareket verisi var |
| 16 | 8 | gönderim zamanı, gönderenin saatine göre mikrosaniye |
| 24 | 8 | oturum (`welcome`'dan) |
| 32 | 4 | düğmeler (libScePad bitleri: L3 0x2, R3 0x4, Options 0x8, Up 0x10, Right 0x20, Down 0x40, Left 0x80, L2 0x100, R2 0x200, L1 0x400, R1 0x800, Triangle 0x1000, Circle 0x2000, Cross 0x4000, Square 0x8000, Touchpad 0x100000) |
| 36 | 4 | analog çubuklar: sol x, sol y, sağ x, sağ y (0-255, merkez 128, yukarı 0) |
| 40 | 1 | L2 (0-255) |
| 41 | 1 | R2 (0-255) |
| 44 | 6 × 2 | iki dokunuş: active, id, x (0-1919, u16), y (0-1079, u16) |
| 56 | 6 × 4 | hareket: ivmeölçer x y z (m/s², float), jiroskop x y z (rad/s, float); hareket verisi yoksa accel y = 9.80665 |

**Çıktı, 32 bayt** (oyun → launcher → telefon):

| Offset | Boyut | Alan |
|---|---|---|
| 0 | 4 | magic `0x4F525041` ("APRO") |
| 4 | 2 | sürüm 1 |
| 6 | 2 | boyut 32 |
| 8 | 4 | cevap verdiği girdinin sıra numarası |
| 12 | 4 | girdinin motorda ne kadar beklediği, mikrosaniye |
| 16 | 8 | girdinin gönderim zamanı, geri yansıtılır (telefon gecikmeyi buradan ölçer) |
| 24 | 1 | büyük motor |
| 25 | 1 | küçük motor |
| 26 | 1 | ışık çubuğu geçerli |
| 27 | 3 | ışık çubuğu R, G, B |
| 30 | 1 | L2 tetik efekti yedek gücü |
| 31 | 1 | R2 tetik efekti yedek gücü |

**Oyun selamı, 16 bayt** (oyun → launcher köprüsü): magic `0x48525041` ("APRH"), sürüm 1, boyut
16, bayt 8 = oyunun bu kola verdiği oyuncu numarası (0 = henüz yok).

Kabloyla bağlı bir telefonun UDP yolu yoktur: aynı girdi paketlerini kontrol bağlantısı üzerinden
**ikili WebSocket çerçeveleri** olarak gönderir ve çıktıları da aynı şekilde geri alır.

### Remote Play (yerel ağ)

Launcher → telefon, UDP ile kolun geldiği adrese (ya da kabloda ikili çerçevelerle):

- **Video parçası**, başlık 24 bayt: magic `0x56525041` ("APRV"), sürüm 1, başlık boyutu 24, kare
  numarası (u32), parça indeksi (u16), parça sayısı (u16), bayraklar (u16, 1 = anahtar kare),
  ayrılmış (u16), yayın başladığından beri geçen milisaniye (u32); ardından karenin en fazla 1176
  baytı. Bir kare, start-code (Annex B) biçiminde H.264'tür; anahtar karede önce SPS ve PPS gelir.
- **Ses**, başlık 16 bayt: magic `0x41525041` ("APRA"), sürüm 1, başlık boyutu 16, numara (u32),
  milisaniye (u32); ardından 48 kHz'de 16 bit stereo PCM (paket başına 5 ms).

### Kablo

- **iPhone**: telefon uygulaması telefonda TCP **47702**'yi dinler. Launcher buna Apple'ın USB
  çoklayıcısı üzerinden bağlanır (macOS'ta usbmuxd; Windows'ta Apple'ın mobil cihaz servisinin
  çalıştırdığı çoklayıcı; Linux'ta `usbmuxd`) ve bu bağlantıyı kendi WebSocket portuna bağlar;
  telefon da bunun üzerinden yukarıdaki protokolü konuşur, kol verisi ikili çerçeveler olarak.
- **Android**: adb ve USB hata ayıklama açıkken launcher `adb forward tcp:0 tcp:47702` çalıştırır
  ve aynısını yapar.
