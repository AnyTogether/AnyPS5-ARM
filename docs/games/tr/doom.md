[← Tüm oyunlar](README.md) · [English](../doom.md) · **Türkçe**

# DOOM (homebrew)

`PPSA99666` · lowbit/ps5-doom

**Durum:** 🟢 Oynanabilir · Oynanabilir, E1M1 ve sonrası · **FPS:** 35 (oyunun kendi hedefi)

Oyun içinde oynanıyor. Paketle gelen libc.prx'teki boş yer tutucu fonksiyonları artık relinker kendisi tanıyıp yerine sistemin gerçek uygulamalarını bağlıyor.

![E1M1: HUD, silah ve Doomguy'ın yüzü](../img/doom-e1m1.jpg)
*E1M1: HUD, silah ve Doomguy'ın yüzü*

## Adım adım

| | Aşama | Ayrıntı |
|---|---|---|
| ✅ | **Dönüştürme ve paketleme** | Homebrew paket, SELF → ELF, kendi libc.prx'i ile. |
| ✅ | **Kök neden bulundu** | Paketteki libc.prx'te memset/snprintf gibi export'lar yalnızca 0 döndüren yer tutucular; gerçekleri sistemin libSceLibcInternal'ında. macOS'ta guest export'u kazandığı için log ve mesajlar boş kalıyor, oyun WAD'ı bulamıyordu. |
| ✅ | **Genel relinker kuralı** | macOS'ta sadece 0 döndüren guest export'ları (xor eax,eax; ret ve pxor xmm0 biçimi) host kütüphanesine bırakılıyor; gerçek fonksiyonlarda guest kazanmaya devam ediyor. Windows yükleyicisinin ZeroReturnExports kuralının macOS karşılığı. |
| ✅ | **Oynanabilir** | WAD'ı buluyor, E1M1 ve sonrasına giriyor; Dreaming Sarah, PvZ ve Silksong ile birlikte kontrol edildi. |

✅ tamamlandı · 🔧 şu an · ⏭️ sırada

## Teknik bilgi

| | |
|---|---|
| Kaynak | `github.com/lowbit/ps5-doom v1.1.1` |
| Sunum | `CPU çizim + AGC compute kopya` |
| WAD | `doom1.wad (shareware)` |
| Relinker testi | `macos_placeholder_exports` |

## Bağlantılar

- [ps5-doom kaynak kodu](https://github.com/lowbit/ps5-doom)
