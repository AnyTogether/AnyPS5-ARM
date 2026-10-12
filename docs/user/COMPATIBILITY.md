# Tested compatibility

[English](#macos-apple-silicon) · [Türkçe](#türkçe)

## macOS (Apple silicon)

Measured on a MacBook Pro M3 Pro, macOS 26.6.2, Vulkan SDK 1.4.363.0. The game's code runs under Rosetta 2.

| Game | ID | Engine | Status | FPS |
|---|---|---|---|---|
| Hollow Knight: Silksong | PPSA12544 | Unity (IL2CPP) | **Work in progress:** in game in the first area; an occasional crash in long sessions. Needs the manual Unity module steps ([page](../games/silksong.md)) | menus 60, in game about 28–48 |
| Plants vs. Zombies: Replanted | PPSA29802 | Unity (IL2CPP) | **Playable:** main menu and levels 1-1 to 1-3 played through, six minutes without a crash. One of two launches ended at startup on a masked-store Rosetta abort. Manual Unity module steps ([page](../games/pvz.md)) | menu ~120, in game 60–120 (120 Hz display) |
| DOOM Shareware (homebrew) | PPSA99666 | lowbit/ps5-doom | In game (E1M1 and later maps) ([page](../games/doom.md)) | 35 (the game's own cap) |
| Dreaming Sarah | PPSA02929 | Construct 2 | In game, playable | 60 |
| AnyPS5 Breakout (test title) | APS5TEST1 | | Playable: video, pad and audio | 60 |
| Stray | PPSA02100 | Unreal Engine 4 | **Regression:** crashes at start-up on current `main` while its memory allocator is set up; earlier builds reached the menus ([page](../games/stray.md)) | – |
| Grand Theft Auto III – The Definitive Edition | PPSA03527 | Unreal Engine 4 | Not retried since the last report: some shaders compile to very large SPIR-V and it uses 64-bit image atomics, which MoltenVK lacks | – |
| Quake II, Quake III Arena (homebrew) | PPSA99007, PPSA99303 | PS5_Mesa (OpenGL / RADV) through `sceAgcDriverSubmitDcb` | **Work in progress:** Quake II reaches the menu and base1; Quake III runs but needs the user's `pak0.pk3` and the 1.32 `pak1-8.pk3` ([page](../games/quake.md)) | Quake II: menu ~48, in game ~13 |

## Windows and Linux

From [upstream AnyPS5](https://github.com/boykopovar/AnyPS5/blob/main/docs/user/COMPATIBILITY.md):

| Game | ID | Windows | Linux | GTX 1050 Ti / i5-7500 3.4GHz | Intel(R) HD Graphic 620 / i5-7200 2.5GHz |
|---|---|---|---|---|---|
| Dreaming Sarah | PPSA02929 | In game, playable | ? | 60 FPS | 36 FPS |
| DOOM Shareware (homebrew) | PPSA99666 | In game (E1M1 and later maps) | In game (E1M1) | ? | ? |

DOOM Shareware is a public homebrew, [lowbit/ps5-doom](https://github.com/lowbit/ps5-doom), release v1.1.1 (content version 01.001.001).

- Windows 11, RTX 4070 (version 01.001.000, an integration build before [#553](https://github.com/boykopovar/AnyPS5/pull/553), [#683](https://github.com/boykopovar/AnyPS5/pull/683), [#684](https://github.com/boykopovar/AnyPS5/pull/684) and [#685](https://github.com/boykopovar/AnyPS5/pull/685) were merged): movement and shooting in E1M1. [In-game screenshots](https://github.com/boykopovar/AnyPS5/pull/685#issuecomment-5997547697).
- Windows 11, RTX 4070 SUPER (v1.1.1, `main` `2edaf7f4` plus open PRs, reported in [#690](https://github.com/boykopovar/AnyPS5/pull/690)): further maps, weapon switching, new games, level select, save/load round trip and audible audio.
- Linux, Ubuntu 24.04 container, Mesa llvmpipe, no hardware GPU (v1.1.1, `main` `0e173a46` plus [#1278](https://github.com/boykopovar/AnyPS5/pull/1278), [#1279](https://github.com/boykopovar/AnyPS5/pull/1279) and [#1307](https://github.com/boykopovar/AnyPS5/pull/1307), relinked with `--exclude-sce-module libc.prx`, see [#1497](https://github.com/boykopovar/AnyPS5/issues/1497)): E1M1, 35 FPS in game; audio and extended gameplay not tested. The `/download0` directory must exist beside the executable.
- Linux, CachyOS, NVIDIA RTX 3080 Ti, driver 610.57.04, KDE Plasma Wayland (v1.1.1, `main` `a11c8f7f7` without extra PRs; `eboot.bin` and `sce_module/libc.prx` unwrapped from fSELF before relinking, see [#2599](https://github.com/boykopovar/AnyPS5/issues/2599); the title's `libc.prx` converted as a guest module, no `--exclude-sce-module`): launcher at 60 FPS, E1M1 at 35 FPS in game; new game from the menu, movement, turning, firing, an item pickup and the automap checked with controller input from `APS5_PAD_INPUT_FILE`. Audio output opened at 48000 Hz but was not listened to; later maps and save/load not tested. The `/download0` directory did not need to exist before the first run.
- Linux, CachyOS, AMD Ryzen 5 PRO 5650U integrated graphics (RADV RENOIR), Mesa 26.2.4, kernel 7.2.9, KDE Plasma 6.7.5 Wayland (v1.1.1, `main` `a11c8f7f7` without extra PRs; `eboot.bin` and `sce_module/libc.prx` unwrapped from fSELF before relinking, see [#2599](https://github.com/boykopovar/AnyPS5/issues/2599); the title's `libc.prx` converted as a guest module, no `--exclude-sce-module`): launcher at 60 FPS, E1M1 and E1M2 completed at 35 FPS in game with a DualShock 4 through SDL (both sticks, D-pad, touchpad, options menu), audio heard, save/load round trip in `/download0`. The first run without a shader cache stayed on AGC compute presentation. `/dev/udmabuf` was accessible to the user, so shared direct memory was imported as dma-buf.
- Windows 11 Pro 10.0.26300, AMD Radeon RX 9060 XT (RDNA 4, driver 32.0.31041.1004) and the Ryzen 9 7950X integrated graphics (RDNA 2, driver 32.0.21045.5002), selected with `ANYPS5_GPU` (v1.1.1, `main` `b42ef24e0` without extra PRs; `eboot.bin` and `sce_module/libc.prx` unwrapped from their SELF and fSELF containers before relinking, see [#2599](https://github.com/boykopovar/AnyPS5/issues/2599); the title's `libc.prx` converted as a guest module, no `--exclude-sce-module`): on both devices, menus, a new game, movement, item pickups and firing in E1M1 with an Xbox One controller through SDL, audio heard. The first run without a shader cache was choppy and later runs were smooth; the frame rate was not measured. Later maps and save/load not tested. The `/download0` directory was created before the first run.
- On the first run without a shader cache, the presentation kernel is compiled at its first dispatch, frame 1 does not complete in time and the title switches to the CPU scaler. Later runs with the cached kernel stay on AGC compute presentation (measured on Windows 11, RTX 3080, `main` `d70b8998`).

Not verified: Linux with Intel GPUs.

## Türkçe

### macOS (Apple silicon)

Ölçümler macOS 26.6.2 çalışan bir MacBook Pro M3 Pro'da, Vulkan SDK 1.4.363.0 ile yapıldı. Oyun kodu Rosetta 2 altında çalışıyor.

| Oyun | Kimlik | Motor | Durum | FPS |
|---|---|---|---|---|
| Hollow Knight: Silksong | PPSA12544 | Unity (IL2CPP) | **Üzerinde çalışılıyor:** ilk bölgede oyun içi; uzun oturumlarda ara sıra kapanıyor. Elle Unity modül adımları gerekiyor ([sayfa](../games/tr/silksong.md)) | menü 60, oyun içi ~28–48 |
| Plants vs. Zombies: Replanted | PPSA29802 | Unity (IL2CPP) | **Oynanabilir:** ana menü ve 1-1–1-3 bölümleri oynandı, altı dakika boyunca çökme yok. İki açılıştan biri açılışta maskeli yazma kaynaklı bir Rosetta hatasıyla kapandı. Elle Unity modül adımları gerekiyor ([sayfa](../games/tr/pvz.md)) | menü ~120, oyun içi 60–120 (120 Hz ekran) |
| DOOM Shareware (homebrew) | PPSA99666 | lowbit/ps5-doom | Oyun içi (E1M1 ve sonrası) ([sayfa](../games/tr/doom.md)) | 35 (oyunun kendi sınırı) |
| Dreaming Sarah | PPSA02929 | Construct 2 | Oyun içi, oynanabilir | 60 |
| AnyPS5 Breakout (test oyunu) | APS5TEST1 | | Oynanabilir: görüntü, kol ve ses | 60 |
| Stray | PPSA02100 | Unreal Engine 4 | **Gerileme:** güncel `main`'de bellek ayırıcısı kurulurken açılışta kapanıyor; önceki derlemeler menülere geliyordu ([sayfa](../games/tr/stray.md)) | – |
| Grand Theft Auto III – The Definitive Edition | PPSA03527 | Unreal Engine 4 | Son rapordan beri yeniden denenmedi: bazı shader'lar çok büyük SPIR-V'lere dönüşüyor ve MoltenVK'de olmayan 64-bit image atomic kullanıyor | – |
| Quake II, Quake III Arena (homebrew) | PPSA99007, PPSA99303 | PS5_Mesa (OpenGL / RADV), `sceAgcDriverSubmitDcb` üzerinden | **Üzerinde çalışılıyor:** Quake II menüye ve base1'e geliyor; Quake III çalışıyor ama kullanıcının `pak0.pk3` ve 1.32 `pak1-8.pk3` dosyalarına ihtiyaç var ([sayfa](../games/tr/quake.md)) | Quake II: menü ~48, oyun içi ~13 |

### Windows ve Linux

[Upstream AnyPS5](https://github.com/boykopovar/AnyPS5/blob/main/docs/user/COMPATIBILITY.md) listesinden: Dreaming Sarah (PPSA02929) Windows'ta oyun içi oynanabilir; GTX 1050 Ti / i5-7500'de 60 FPS, Intel HD Graphics 620 / i5-7200'de 36 FPS.

DOOM Shareware (PPSA99666, homebrew [lowbit/ps5-doom](https://github.com/lowbit/ps5-doom) v1.1.1) Windows'ta oyun içi (E1M1 ve sonraki haritalar), Linux'ta E1M1'de oyun içi (Mesa llvmpipe yazılım Vulkan'ı ve NVIDIA RTX 3080 Ti ile denendi); ayrıntılar yukarıdaki İngilizce bölümde.
