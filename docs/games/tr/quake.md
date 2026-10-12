[← Tüm oyunlar](README.md) · [English](../quake.md) · **Türkçe**

# Quake II ve Quake III

`PPSA99007 · PPSA99303` · PS5_Mesa (OpenGL / RADV) · `sceAgcDriverSubmitDcb`

**Durum:** 🟡 Quake II oyun içi · Quake III veri dosyası bekliyor · **FPS:** Quake II menü ~48, oyun içi ~13

| Menü | Oyun içi (base1) |
|---|---|
| <img src="../img/quake2-menu.jpg" width="420"> | <img src="../img/quake2-base1.jpg" width="420"> |

İki homebrew port GPU'ya Mesa üzerinden erişiyor, ama komutlarını Sony'nin `sceAgcDriverSubmitDcb` çağrısıyla gönderiyor. Yani AnyPS5'in kapsamında; upstream de bu portlar için PR'lar alıyor. (Bu sayfanın eski sürümü "kapsam dışı" diyordu, o yanlıştı.)

## Adım adım

| | Aşama | Ayrıntı |
|---|---|---|
| ✅ | **Açılış** | Upstream #3840 (`fcntl`/`ioctl`) ve #3886 (120 Hz çıkış) ile oyun ilk kareye kadar geliyor. |
| ✅ | **Son köşe (provoking vertex)** | MoltenVK'da `provokingVertexLast` yok. Düz (flat) girdi okuyan çizimler, her üçgen son köşesiyle başlayacak şekilde ayrı bir index kopyasıyla çiziliyor; sarım yönü korunuyor. |
| ✅ | **GL derinlik aralığı** | Mesa'nın blitter'ı `[-1, 1]` derinlik aralığı kullanıyor; MoltenVK `depth_range_unrestricted` desteklemiyor. Bu aralık eşdeğer sıfır-bir kırpmaya çevriliyor. |
| ✅ | **Menü ve oyun içi** | Menü ~48 FPS, base1 açılıyor. |
| 🔧 | **Oyun içi hız** | ~13 FPS. Mesa her karede aynı akış belleğini yeniden yazıyor ve her yazma Rosetta altında ~20 µs'lik bir sayfa hatası. Bu hataları kaldıran deneme ~40 FPS veriyor ama bir testi bozduğu için henüz ana dalda değil. |
| ⏭️ | **Quake III** | Çalışıyor ama pencere açmıyor: `baseq3/` içinde yalnızca `zz-ps5-ui.pk3` var. Kendi kopyandan `pak0.pk3` ve 1.32 yamasındaki `pak1–8.pk3` gerekiyor. |

✅ tamamlandı · 🔧 şu an · ⏭️ sırada

## Teknik bilgi

| | |
|---|---|
| Quake II | `Yamagi Quake II v8.70 + PS5_Mesa OpenGL 3.3` |
| Quake III | `Quake3e + PS5_Mesa RADV (Vulkan)` |
| Çerçeve tamponu | `3840x2160, oyunun kendi seçimi` |
| İlgili commit | `8ebc654e6 fix(agc): draw Yamagi Quake II's GL pipeline on MoltenVK` |

## Bağlantılar

- [PS5_Quake3e](https://github.com/griches/PS5_Quake3e)
- [Yamagi Quake II](https://github.com/yquake2/yquake2)
