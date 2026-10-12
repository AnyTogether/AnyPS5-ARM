[← Tüm oyunlar](README.md) · [English](../dreaming-sarah.md) · **Türkçe**

# Dreaming Sarah

`PPSA02929` · Construct 2

**Durum:** 🟢 Oynanabilir · Oynanabilir · **FPS:** 60

Baştan sona çalışıyor. 2D, hafif GPU yükü.

![Başlık ekranı, 60 FPS](../img/dreaming-sarah.jpg)
*Başlık ekranı, 60 FPS*

## Adım adım

| | Aşama | Ayrıntı |
|---|---|---|
| ✅ | **Dönüştürme** | sce_module içindeki .esbak yedek dosyaları çalışma kopyasından çıkarılıyor (relinker onları ikinci bir libc sanıyordu). |
| ✅ | **Çizim** | Barycentric interpolasyon MoltenVK'da host tarafında hesaplanıyor. |
| ✅ | **Oynanabilir** | Görüntü, ses ve kol çalışıyor. |

✅ tamamlandı · 🔧 şu an · ⏭️ sırada

## Teknik bilgi

| | |
|---|---|
| Motor | `Construct 2 (JavaScript çalıştırıcısı)` |
| Oyun verisi | `data.js + images/ + media/` |
| FPS | `60` |
