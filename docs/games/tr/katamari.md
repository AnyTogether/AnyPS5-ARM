[← Tüm oyunlar](README.md) · [English](../katamari.md) · **Türkçe**

# Once Upon a KATAMARI

`PPSA21904` · Unity (IL2CPP)

**Durum:** 🟡 Üzerinde çalışılıyor · oynanışa geliyor; shader ısınması sürüyor · **FPS:** kullanıcı raporuna göre ısınma sırasında oyun içinde ~3; oturmuş FPS ölçülmedi

7 çekirdekli GPU'lu bir Apple M1 Mac'te, macOS 27.0.1 ile, 1920×1080 Vulkan çizim boyutunda test edildi. Kullanıcı ikinci denemede oynanışa ~3 FPS ile ulaştığını, oyunun ekranda gösterdiği shader sayacının da 30.000'i geçip artmaya devam ettiğini bildiriyor. Bu soğuk cache ile yapılmış bir gözlem: shader/pipeline ısınması tamamlanmadı, ısınmış bir tekrar denemedeki performans da ölçülmedi. 3 FPS'i oturmuş oyun performansı değil, geçici bir rakam olarak okuyun.

Kullanıcı ayrıca oyunu yeniden açınca baştan başladığını bildiriyor. Uygulamanın `_sd` klasöründe kayıt dosyaları var, ama bu dosyaların varlığı ilerlemenin gerçekten kaydedildiğini ya da yüklendiğini göstermiyor. Oyun içi kaydetme ve devam etme henüz doğrulanmalı; bunu şimdilik kesinleşmiş bir kayıt verisi hatası saymayın.

Test, oyunun ve Unity modüllerinin şifresi çözülmüş dosyalarından yeni yapılmış bir macOS relink'i ile, güncel `main` build'i (`0deeb2a99`) ve MoltenVK ile paketlenerek yapıldı. Upstream'in rect-list ayıklama düzeltmesi (`140bdd3d4`) test edilen çalıştırmadaki geçersiz rect-list hatalarını giderdi. Daha önceki bir deneme açılış logosundan sonra siyah ekranda kalmıştı; ikinci denemedeki oynanış raporu o sonucun yerini alıyor.

## Adım adım

| | Aşama | Ayrıntı |
|---|---|---|
| ✅ | **Açılış dosyası ve modüller** | Oyunun çalıştırılabilir dosyası, iki Unity modülü ve beş Unity eklentisi şifresi çözülmüş dosyalardan relink edildi. Paketlenen oyun açılıyor ve Unity içeriğini yüklüyor. |
| ✅ | **Dejenere rect-list çizimleri** | Upstream'in ayıklama düzeltmesinden sonra logda artık geçersiz dikdörtgen doğrulama hatası yok. |
| ✅ | **İlk çizilen sahne** | Kullanıcının ikinci denemesinde oynanışa ulaşılıyor. |
| 🔧 | **Shader ısınması ve performans** | Shader sayacı 30.000'i geçip artıyor; kullanıcı bu soğuk cache denemesinde ~3 FPS bildiriyor. Sayaç durduktan sonra aynı sahnede tekrar ölçüp karşılaştırmak gerekiyor. |
| 🔧 | **Kaydetme ve devam etme** | Kullanıcı, kayıt dosyaları olduğu hâlde bir sonraki açılışın baştan başladığını bildiriyor. Oyun içi kaydetme adımı ve kayıtlı bir oyunun devam edip etmediği doğrulanmalı. |

✅ tamamlandı · 🔧 şu an · ⏭️ sırada

## Teknik bilgi

| | |
|---|---|
| Oyun kimliği | `PPSA21904` |
| Motor | `Unity (IL2CPP)` |
| Grafik yolu | `libSceAgc → Vulkan → MoltenVK → Metal` |
| CPU yolu | `x86-64 → Rosetta 2` |
| Test donanımı | `Apple M1, 7 çekirdekli GPU; macOS 27.0.1` |
| Test edilen kaynak | `main, 0deeb2a99` |
| Sonuç | `Oynanışa ulaşıldı; kullanıcı ısınma sırasında ~3 FPS ve baştan başlama bildiriyor; kaydetme/devam ve ısınmış FPS doğrulanmadı` |

İlk rapor [PR #8](https://github.com/utkuhalis/AnyPS5-ARM/pull/8) ile Eyad Al-Daoud'dan geldi.
