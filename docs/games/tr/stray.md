[← Tüm oyunlar](README.md) · [English](../stray.md) · **Türkçe**

# Stray

`PPSA02100` · Unreal Engine 4

**Durum:** 🟢 Oynanabilir, ilk bölüm sorunsuz · **FPS:** oyun içinde ~1-11, çoğunlukla 4-8 (M3 Pro, 1080p)

İlk bölüm baştan sona oynanıyor: sarmaşıklı borulardaki açılış, kedi ailesi, tırmanışlar ve kartonda uyuma. Görüntü doğru, eksik ya da bozuk grafik yok. Tek sorun FPS ve çok düşük. Sıradaki iş o.

![Sarmaşıklı borulardaki açılış](../img/stray-opening.jpg)
*Sarmaşıklı borulardaki açılış*

![Kedi ailesi](../img/stray-family.jpg)
*Kedi ailesi*

| | |
|---|---|
| ![Duvarın altındaki ışık](../img/stray-sunlight.jpg) | ![Kartonda uyuma](../img/stray-cardboard.jpg) |
| *Duvarın altındaki ışık* | *Kartonda uyuma* |

![Sarmaşıkların altında](../img/stray-vines.jpg)
*Sarmaşıkların altında*

15 Ekim 2026'da, üçüncü upstream merge'ünden sonraki main'den (`cc213ee99`), 1920x1080'de çekildi.

## Adım adım

| | Aşama | Ayrıntı |
|---|---|---|
| ✅ | **160 GiB buffer çökmesi** | Kayıt sayısını aşan indeksler tek bir sıfır vertex'e yönlendirildi (upstream'e PR #4292). |
| ✅ | **Kök neden: geç write-back** | GPU sonuçları belleğe geç yazılıp oyunun yeniden kullandığı belleği eziyordu. Anında yazma modunda menüler ve yazılar tam çizildi. |
| ✅ | **Yazma izleyicisi hatası** | Rezervasyonun üstüne map edilen bellek izlenmiyordu (upstream'de düzeltildi). |
| ✅ | **Başlangıç gerilemesi** | Düzeltildi: karesel bir shader geçişi ve thread oluşturulurken engellenen sinyal maskesi. |
| ✅ | **Shader aritmetiği** | Pixel ve compute shader'larda her f32 toplama ve çarpma MoltenVK altında artık optimize edilmeyen bir yardımcı çağrıya dönüşmüyor (en ağır shader: 17 → 5 ms). |
| ✅ | **Çıkış çözünürlüğü** | PS5 sürümü 3840x2160 çıkışı sabit kodluyor. `tools/package_macos_app.py`'nin uyguladığı [tools/macos/patches/PPSA02100.json](../../../tools/macos/patches/PPSA02100.json) ile (`--no-game-patches` atlıyor) uygulama açılırken 720p, 900p, 1080p (varsayılan), 1440p ya da 4K soruyor; `APS5_RESOLUTION=1280x720` önceden cevaplıyor. |
| ✅ | **PlayGo dosyası olmayan dump** | Dump'ta hiç `playgo-*` dosyası yok. Upstream artık böyle bir dump'ta 0 dışındaki her chunk'ı reddediyor, Stray de açılışta chunk 1'i soruyor; port bu dump'ı tam kurulu sayıyor. |
| ✅ | **İlk bölüm** | Doğru grafiklerle baştan sona oynanıyor. |
| 🔧 | **FPS** | 1080p'de oyun içinde ~1-11 FPS. Daha önceki 1080p ölçümlerinde sınır sürücü iş parçacığıydı (frame başına ~52 ms, GPU'da ~31 ms): GPU senkronları, write-back'ler ve kuyruk gönderimleri. |

✅ tamamlandı · 🔧 şu an · ⏭️ sırada

## Teknik bilgi

| | |
|---|---|
| Motor | `Unreal Engine 4` |
| Bölünen 256-bit yazma | `211.077` |
| Çıkış | `Yamayla 1920x1080, yamasız 3840x2160` |
| Şu an | `İlk bölüm oynanabilir, ~1-11 FPS` |

## Bağlantılar

- [Upstream PR #4292](https://github.com/boykopovar/AnyPS5/pull/4292)
