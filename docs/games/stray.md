[← Tüm oyunlar](README.md)

# Stray

`PPSA02100` · Unreal Engine 4

**Durum:** 🔴 Açılmıyor · Başlangıçta kapanıyor (gerileme) · **FPS:** —

Kök neden çözüldü ama son upstream birleştirmelerinden sonra oyun daha açılışta kapanıyor. Bu gerileme araştırılıyor.

![Önceki deneme: GPU sonuçları anında yazılınca save ekranı tam çiziliyordu](img/stray-saveselect.jpg)
*Önceki deneme: GPU sonuçları anında yazılınca save ekranı tam çiziliyordu*

## Adım adım

| | Aşama | Ayrıntı |
|---|---|---|
| ✅ | **160 GiB buffer çökmesi** | Kayıt sayısını aşan indeksler tek bir sıfır vertex'e yönlendirildi (upstream'e PR #4292). |
| ✅ | **Kök neden: geç write-back** | GPU sonuçları belleğe geç yazılıp oyunun yeniden kullandığı belleği eziyordu. Anında yazma modunda menüler ve yazılar tam çizildi (yukarıdaki görüntü). |
| ✅ | **Yazma izleyicisi hatası** | Rezervasyonun üstüne map edilen bellek izlenmiyordu (upstream'de düzeltildi). |
| 🔧 | **Başlangıç gerilemesi** | Unreal'ın bellek ayırıcısı kurulurken atexit → oyunun libc'si → malloc → henüz hazır olmayan ayırıcı. Son birleştirmelerle geldi; hangi değişiklik olduğu bulunacak. |
| ⏭️ | **Hızlı write-back düzeltmesi** | Anında yazmayı yalnızca izlenemeyen bellekle sınırlayan sürüm hazır, test edilecek. |

✅ tamamlandı · 🔧 şu an · ⏭️ sırada

## Teknik bilgi

| | |
|---|---|
| Motor | `Unreal Engine 4` |
| Bölünen 256-bit yazma | `211.077` |
| Son çalışan durum | `Menü/save ekranı (anında write-back ile, ~0.4 FPS)` |
| Şu an | `Açılışta segfault` |

## Bağlantılar

- [Upstream PR #4292](https://github.com/boykopovar/AnyPS5/pull/4292)
