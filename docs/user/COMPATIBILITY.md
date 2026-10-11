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
| DOOM Shareware (homebrew) | PPSA99666 | In game (E1M1 and later maps) | In game (E1M1), software Vulkan only | ? | ? |

DOOM Shareware is a public homebrew, [lowbit/ps5-doom](https://github.com/lowbit/ps5-doom), release v1.1.1 (content version 01.001.001).

- Windows 11, RTX 4070 (version 01.001.000, an integration build before [#553](https://github.com/boykopovar/AnyPS5/pull/553), [#683](https://github.com/boykopovar/AnyPS5/pull/683), [#684](https://github.com/boykopovar/AnyPS5/pull/684) and [#685](https://github.com/boykopovar/AnyPS5/pull/685) were merged): movement and shooting in E1M1. [In-game screenshots](https://github.com/boykopovar/AnyPS5/pull/685#issuecomment-5997547697).
- Windows 11, RTX 4070 SUPER (v1.1.1, `main` `2edaf7f4` plus open PRs, reported in [#690](https://github.com/boykopovar/AnyPS5/pull/690)): further maps, weapon switching, new games, level select, save/load round trip and audible audio.
- Linux, Ubuntu 24.04 container, Mesa llvmpipe, no hardware GPU (v1.1.1, `main` `0e173a46` plus [#1278](https://github.com/boykopovar/AnyPS5/pull/1278), [#1279](https://github.com/boykopovar/AnyPS5/pull/1279) and [#1307](https://github.com/boykopovar/AnyPS5/pull/1307), relinked with `--exclude-sce-module libc.prx`, see [#1497](https://github.com/boykopovar/AnyPS5/issues/1497)): E1M1, 35 FPS in game; audio and extended gameplay not tested. The `/download0` directory must exist beside the executable.
- On the first run without a shader cache, the presentation kernel is compiled at its first dispatch, frame 1 does not complete in time and the title switches to the CPU scaler. Later runs with the cached kernel stay on AGC compute presentation (measured on Windows 11, RTX 3080, `main` `d70b8998`).

Not verified: Linux with a hardware GPU, current `main` without extra PRs.

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

DOOM Shareware (PPSA99666, homebrew [lowbit/ps5-doom](https://github.com/lowbit/ps5-doom) v1.1.1) Windows'ta oyun içi (E1M1 ve sonraki haritalar), Linux'ta yalnızca yazılım Vulkan ile E1M1'de oyun içi; ayrıntılar yukarıdaki İngilizce bölümde.
