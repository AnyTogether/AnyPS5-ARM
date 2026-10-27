[← Tüm oyunlar](README.md) · [English](../katamari.md) · **Türkçe**

# Once Upon a KATAMARI

`PPSA21904` · Unity (IL2CPP)

**Durum:** 🟡 Üzerinde çalışılıyor · başlık ekranı ve eğitim sahnesi çiziliyor; siyah açılış ara sahnesini atlamak için Esc'yi basılı tutun · **FPS:** menü 30,45; eğitim 1,19 (anlık görüntü, ısınmış FPS değil)

7 çekirdekli GPU'lu bir Apple M1 Mac'te, macOS 27.0.1 ile, 1920×1080 Vulkan çizim boyutunda test edildi. Kullanıcı, açılışta ve yeni oyun başlatırken görünen siyah ekranın çizilmeyen bir ara sahne olduğunu bildiriyor; klavyede Esc'yi basılı tutunca atlanıp oyuna devam ediliyor.

Kullanıcı ayrıca oyunu yeniden açınca baştan başladığını bildiriyor. Uygulamanın `_sd` klasöründe kayıt dosyaları var, ama bu dosyaların varlığı ilerlemenin gerçekten kaydedildiğini ya da yüklendiğini göstermiyor. Oyun içi kaydetme ve devam etme henüz doğrulanmalı; bunu şimdilik kesinleşmiş bir kayıt verisi hatası saymayın.

Test, oyunun ve Unity modüllerinin şifresi çözülmüş dosyalarından yeni yapılmış bir macOS relink'i ile, `0deeb2a99` commit'indeki `main` build'i ve MoltenVK ile paketlenerek yapıldı. Upstream'in rect-list ayıklama düzeltmesi (`140bdd3d4`) test edilen çalıştırmadaki geçersiz rect-list hatalarını giderdi.

## Ekran görüntüleri

![Geleneksel Çince Once Upon a KATAMARI başlık ekranı](../img/katamari-title.jpg)
*Başlık ekranı: görüntü alındığında 30,45 FPS (19.433 sunulan kare).*

![İlk oynanış eğitim sahnesi](../img/katamari-ingame.jpg)
*İlk eğitim sahnesi: görüntü alındığında 1,19 FPS (164.403 sunulan kare).*

Bunlar anlık ölçümlerdir. Pencere başlığındaki parantezli sayı shader sayısı değil, toplam sunulan kare sayısıdır. Kullanıcı shader derlemesinin hâlâ sürdüğünü ve Mac pilde olduğu için oturumu bitirdiğini bildiriyor; ısınmış cache ile FPS ölçülmedi.

## Adım adım

| | Aşama | Ayrıntı |
|---|---|---|
| ✅ | **Açılış dosyası ve modüller** | Oyunun çalıştırılabilir dosyası, iki Unity modülü ve beş Unity eklentisi şifresi çözülmüş dosyalardan relink edildi. Paketlenen oyun açılıyor ve Unity içeriğini yüklüyor. |
| ✅ | **Dejenere rect-list çizimleri** | Upstream'in ayıklama düzeltmesinden sonra logda artık geçersiz dikdörtgen doğrulama hatası yok. |
| ✅ | **Açılış ara sahnesi ve ilk sahne** | Açılış ara sahnesi siyah; Esc basılı tutularak atlanıyor. Başlık ekranı ve ilk eğitim sahnesi çiziliyor. |
| 🔧 | **Shader ısınması ve performans** | Kullanıcı pilde olduğu için shader derlemesi sürerken oturumu bitirdi. Ekran görüntülerinde menüde 30,45, eğitim sahnesinde 1,19 FPS görülüyor; oturmuş performans için ısınma sonrası tekrar ölçüm gerekiyor. |
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
| Sonuç | `Siyah ara sahne atlandıktan sonra başlık ve eğitim sahnesi çiziliyor; ekran görüntülerinde 30,45 ve 1,19 FPS; kaydetme/devam ve ısınmış FPS doğrulanmadı` |

İlk rapor [PR #8](https://github.com/AnyTogether/AnyPS5-ARM/pull/8) ile Eyad Al-Daoud'dan geldi.
