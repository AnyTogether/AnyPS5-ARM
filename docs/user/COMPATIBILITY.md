# Tested compatibility

[English](#macos-apple-silicon) · [Türkçe](#türkçe)

## macOS (Apple silicon)

Measured on a MacBook Pro M3 Pro, macOS 26.6.2, Vulkan SDK 1.4.363.0. The game's code runs under Rosetta 2.

| Game | ID | Engine | Status | FPS |
|---|---|---|---|---|
| Dreaming Sarah | PPSA02929 | | In game, playable | 60 |
| AnyPS5 Breakout (test title) | APS5TEST1 | | Playable: video, pad and audio | 60 |
| Stray | PPSA02100 | Unreal Engine 4 | **Work in progress:** boots through the studio logo to the brightness setup screen and past it into loading, where it still stops. Some font glyphs are missing. | about 10 |
| Grand Theft Auto III – The Definitive Edition | PPSA03527 | Unreal Engine 4 | Does not boot: some of its shaders compile to very large SPIR-V that MoltenVK takes too long to translate, and it uses 64-bit image atomics, which MoltenVK lacks | – |

## Windows and Linux

From [upstream AnyPS5](https://github.com/boykopovar/AnyPS5/blob/main/docs/user/COMPATIBILITY.md):

| Game | ID | Windows | Linux | GTX 1050 Ti / i5-7500 3.4GHz | Intel(R) HD Graphic 620 / i5-7200 2.5GHz |
|---|---|---|---|---|---|
| Dreaming Sarah | PPSA02929 | In game, playable | ? | 60 FPS | 36 FPS |

## Türkçe

### macOS (Apple silicon)

Ölçümler macOS 26.6.2 çalışan bir MacBook Pro M3 Pro'da, Vulkan SDK 1.4.363.0 ile yapıldı. Oyun kodu Rosetta 2 altında çalışıyor.

| Oyun | Kimlik | Motor | Durum | FPS |
|---|---|---|---|---|
| Dreaming Sarah | PPSA02929 | | Oyun içi, oynanabilir | 60 |
| AnyPS5 Breakout (test oyunu) | APS5TEST1 | | Oynanabilir: görüntü, kol ve ses | 60 |
| Stray | PPSA02100 | Unreal Engine 4 | **Üzerinde çalışılıyor:** stüdyo logosundan parlaklık ayar ekranına geliyor ve onu geçip yüklemeye giriyor, orada hâlâ duruyor. Yazı tipinin bazı harfleri eksik. | yaklaşık 10 |
| Grand Theft Auto III – The Definitive Edition | PPSA03527 | Unreal Engine 4 | Açılmıyor: bazı shader'ları MoltenVK'nın çevirmesi çok uzun süren dev SPIR-V'ler üretiyor; ayrıca MoltenVK'de olmayan 64-bit image atomic'leri kullanıyor | – |

### Windows ve Linux

[Upstream AnyPS5](https://github.com/boykopovar/AnyPS5/blob/main/docs/user/COMPATIBILITY.md) listesinden: Dreaming Sarah (PPSA02929) Windows'ta oyun içi oynanabilir; GTX 1050 Ti / i5-7500'de 60 FPS, Intel HD Graphics 620 / i5-7200'de 36 FPS.
