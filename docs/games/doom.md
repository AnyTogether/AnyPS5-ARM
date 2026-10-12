[← Tüm oyunlar](README.md)

# DOOM (homebrew)

`PPSA99666` · lowbit/ps5-doom

**Durum:** 🟡 Üzerinde çalışılıyor · Oyun içi, E1M1 · **FPS:** 35 (oyunun hedefi)

Deneme kuralıyla oyun içinde, E1M1 oynanıyor. Kalıcı olması için libc sembollerini doğru yere bağlayan genel bir kural gerekiyor.

![E1M1: HUD, silah ve Doomguy'ın yüzü](img/doom-e1m1.jpg)
*E1M1: HUD, silah ve Doomguy'ın yüzü*

## Adım adım

| | Aşama | Ayrıntı |
|---|---|---|
| ✅ | **Dönüştürme ve paketleme** | Homebrew paket, SELF → ELF, kendi libc.prx'i ile. |
| ✅ | **Kök neden bulundu** | Paketteki libc.prx'te memset/snprintf gibi export'lar boş fonksiyon; gerçekleri sistemin libSceLibcInternal'ında. macOS kuralı (oyunun export'u kazanır) bu yüzden log ve mesajları boşaltıyordu. |
| ✅ | **Deneme kuralıyla oyun içi** | Host kütüphanesi kazandığında oyun WAD'ı buluyor, E1M1'e giriyor. |
| 🔧 | **Genel kural** | Stray'i bozmadan DOOM'u çalıştıran, sembol bazında karar veren bir relinker kuralı. |

✅ tamamlandı · 🔧 şu an · ⏭️ sırada

## Teknik bilgi

| | |
|---|---|
| Kaynak | `github.com/lowbit/ps5-doom v1.1.1` |
| Sunum | `CPU çizim + AGC compute kopya` |
| WAD | `doom1.wad (shareware)` |
| Durum | `Deneme relinker kuralıyla` |

## Bağlantılar

- [ps5-doom kaynak kodu](https://github.com/lowbit/ps5-doom)
