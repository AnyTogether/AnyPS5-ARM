[← Tüm oyunlar](README.md) · [English](../stray.md) · **Türkçe**

# Stray

`PPSA02100` · Unreal Engine 4

**Durum:** 🟡 Ana menü · Oyuna giriş henüz doğrulanmadı · **FPS:** ana menüde ~18-20 (M3 Pro, 1080p yaması)

Oyun yeniden açılıyor ve ana menüye geliyor. macOS paketi 1080p çıkış yamasını uyguluyor (aşağıda); yama olmadan PS5 sürümü 3840x2160 çiziyor ve menü ~11 FPS'te kalıyor.

![Önceki deneme: GPU sonuçları anında yazılınca save ekranı tam çiziliyordu](../img/stray-saveselect.jpg)
*Önceki deneme: GPU sonuçları anında yazılınca save ekranı tam çiziliyordu*

## Adım adım

| | Aşama | Ayrıntı |
|---|---|---|
| ✅ | **160 GiB buffer çökmesi** | Kayıt sayısını aşan indeksler tek bir sıfır vertex'e yönlendirildi (upstream'e PR #4292). |
| ✅ | **Kök neden: geç write-back** | GPU sonuçları belleğe geç yazılıp oyunun yeniden kullandığı belleği eziyordu. Anında yazma modunda menüler ve yazılar tam çizildi (yukarıdaki görüntü). |
| ✅ | **Yazma izleyicisi hatası** | Rezervasyonun üstüne map edilen bellek izlenmiyordu (upstream'de düzeltildi). |
| ✅ | **Başlangıç gerilemesi** | Düzeltildi: karesel bir shader geçişi ve thread oluşturulurken engellenen sinyal maskesi. |
| ✅ | **Shader aritmetiği** | Pixel ve compute shader'larda her f32 toplama ve çarpma MoltenVK altında artık optimize edilmeyen bir yardımcı çağrıya dönüşmüyor (en ağır shader: 17 → 5 ms). |
| ✅ | **Çıkış çözünürlüğü** | PS5 sürümü 3840x2160 çıkışı sabit kodluyor. `tools/package_macos_app.py`'nin uyguladığı [tools/macos/patches/PPSA02100.json](../../../tools/macos/patches/PPSA02100.json) ile (`--no-game-patches` atlıyor) uygulama açılırken 720p, 900p, 1080p (varsayılan), 1440p ya da 4K soruyor; `APS5_RESOLUTION=1280x720` önceden cevaplıyor. 720p'de menü ~19-24 FPS. |
| 🔧 | **Menü FPS'i** | 1080p'de sınır sürücü iş parçacığı (frame başına ~52 ms, GPU ~31 ms): GPU senkronları, write-back'ler ve kuyruk gönderimleri. |
| ⏭️ | **Oyuna giriş** | Oyun içindeki write-back'ler henüz doğrulanmadı. |

✅ tamamlandı · 🔧 şu an · ⏭️ sırada

## Teknik bilgi

| | |
|---|---|
| Motor | `Unreal Engine 4` |
| Bölünen 256-bit yazma | `211.077` |
| Çıkış | `Yamayla 1920x1080, yamasız 3840x2160` |
| Şu an | `Ana menü, ~18-20 FPS` |

## Bağlantılar

- [Upstream PR #4292](https://github.com/boykopovar/AnyPS5/pull/4292)
