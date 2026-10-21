# AnyPS5-ARM guide

[English](#english) · [Türkçe](#türkçe)

---

## English

### Games that run

| Dreaming Sarah | AnyPS5 Breakout | Stray (WIP) |
|---|---|---|
| ![Dreaming Sarah](../screenshots/dreaming-sarah-gameplay.jpg) | ![AnyPS5 Breakout](../screenshots/breakout.jpg) | ![Stray](../screenshots/stray-brightness.jpg) |
| PPSA02929 · 60 fps, playable | Test title · 60 fps, video, pad and audio | PPSA02100 · Unreal Engine 4 · about 1 fps, **work in progress** |

All three run on a MacBook Pro M3 Pro with macOS 26.6.2.

#### Dreaming Sarah

The menu and gameplay run at 60 fps (about 18 fps before the macOS write watch).

| Main menu | Opening scene |
|---|---|
| ![Main menu at 59.95 fps](../screenshots/dreaming-sarah-menu.jpg) | ![Opening scene at 60 fps](../screenshots/dreaming-sarah-intro.jpg) |

#### Stray: work in progress

Stray is the first Unreal Engine 4 title to render on macOS here. It boots through the studio logo to the brightness setup screen at about 10 fps, and past it into loading. Getting there took these fixes:

- larger shader image and sampler heaps
- a SPIR-V loop shape that MoltenVK's shader translator turned into an infinite loop and a GPU hang
- depth and stencil surfaces read as storage images
- draws the Metal backend cannot run (geometry shaders, the depth bounds test) skipped instead of stopping the game
- the guest's own `libc.prx` bound before the host libraries, write-watch fixes, a smaller SPIR-V output that the Metal compiler can build, and relaxed float semantics on MoltenVK

It runs with the default settings now. A few letters of its font are missing (glyphs the GPU adds to the font atlas later), and it still stops on the loading after the brightness screen.

| Studio logo | Brightness setup |
|---|---|
| ![Stray: the BlueTwelve logo](../screenshots/stray-boot-logo.jpg) | ![Stray: the brightness setup screen](../screenshots/stray-brightness.jpg) |

### Compatibility

The [compatibility list](COMPATIBILITY.md) has every game tested on macOS, its status and its frame rate.

### Status

[![libraries](../progress/badge-libraries.svg)](../progress/badge-libraries.svg) [![shaders](../progress/badge-shaders.svg)](../progress/badge-shaders.svg)

[![progress map](../progress/progress.svg)](../progress/progress.svg)

<sub>* System libraries: the share of the functions the project knows so far (declared in [core/libs/prx](../../core/libs/prx)) that are implemented, not of every PS5 system function. GPU shader instructions: the share of the RDNA instructions the shader recompiler translates. Regenerate them with `python3 tools/progress.py <directory>` and copy the three SVG files to `docs/progress/`.</sub>

| Check | Result |
|---|---|
| Guest fixtures (TLS, exceptions, threads, modules) | 10 of 10 pass |
| Test suite on MoltenVK | 477 of 484 pass |

Measured with Vulkan SDK 1.4.363.0. The 7 failing tests hit Apple GPU or Metal limits, such as 64-bit buffer atomics and 32 KiB threadgroup memory. [MACOS_PORT.md](../dev/MACOS_PORT.md) lists them, along with every change this fork makes.

### The AnyPS5 app

**AnyPS5.app** is a launcher laid out like the PS5 home screen. It finds the game dumps in a folder, unlocks (converts) them for the Mac and starts them: no Terminal, no build, no Vulkan SDK.

<p><a href="https://github.com/utkuhalis/AnyPS5-ARM/releases/latest/download/AnyPS5-macOS.zip"><b>⬇ Download AnyPS5 for macOS</b></a> · Apple silicon · macOS 14+</p>

**Install.** The quickest way is one line in Terminal; a download through `curl` is not quarantined, so macOS opens the app without any "cannot be opened" warning:

```sh
curl -fsSL https://github.com/utkuhalis/AnyPS5-ARM/releases/latest/download/install.sh | sh
```

With the zip from the [latest release](https://github.com/utkuhalis/AnyPS5-ARM/releases/latest) instead, the app is not notarized, so macOS blocks it the first time: open **System Settings → Privacy & Security** and click **Open Anyway**. If it then runs from the read-only copy macOS makes of downloaded apps, the launcher offers to move itself to Applications and reopen from there.

**First start.** Pick the language, one of three animated themes (Cosmic, Aurora, Sunset) and the folder that holds your PS5 dumps. Subfolders are scanned, and games added later show up on their own.

**Unlocking.** A game that has not been converted yet shows a lock. **Unlock** opens its `eboot.bin` and modules even when they are still SELF containers, relinks them for macOS and makes the game app, with a PS5-style progress bar. The game files are APFS clones of the dump, so an unlocked game takes no extra space. A dump that is still encrypted is reported instead of converted.

**Playing.** **Play** starts the game. **⋯** (or `O` / △) opens its settings: output resolution (for titles with a resolution patch, such as Stray), window or full screen, window size, vertical sync, the performance overlay, the game's language, **Controls**, and Show in Finder, the log, clearing the shader cache, unlocking again or removing the installation.

**Controls.** The keyboard and mouse layout for each game. Pick a pad button or stick direction, then press the key you want for it; Esc cancels. A key you give to one button leaves the button that had it, and mouse buttons stay where they were. The default layout:

| Pad | Keys |
|-----|------|
| Left stick | W A S D |
| ✕ / □ / ○ / △ | K (also Space, Return) / J (also left click) / L / I |
| L1 / R1 | Q / E |
| L2 / R2 | U (also mouse button 4) / O (also right click) |
| L3 / R3 | Shift / Ctrl |
| D-pad | Arrow keys |
| Right stick | T F G H |
| Options / touchpad | Esc / Backspace and Tab |

The launcher writes the layout to `~/Library/Application Support/AnyPS5/Controls/<game>.ini` at each start and passes it to the game as `ANYPS5_INPUT_CONFIG` ([format](INPUT_MAPPING.md)). A connected game controller keeps its own buttons.

**Trophies.** A game with a trophy list shows a 🏆 button beside **Play** with how many you have earned. It opens the list as the console shows it: the percentage, the count per grade (platinum, gold, silver, bronze), and every trophy with its icon, description and the day you earned it; hidden ones stay hidden until then, and trophies that count something (such as *Acquire all Tools*) show how far you are. The list and texts come from the game's own `sce_sys/trophy2` package, in the game's language when it has it; the engine records each unlock in the installed game's `_trophy` folder. Unlocking a game again keeps its saves and trophies. When a game earns a trophy while you play, a card drops in at the top of the screen, over the game (full screen too), without taking the keyboard or the mouse from it.

**Advanced.** **⋯ → Advanced** holds each game's finer settings: a deadzone for each controller stick; the mouse as the camera (sensitivity, vertical speed, response curve, minimum tilt, maximum speed, smoothing, how soon the camera stops); the keyboard (the tilt while **Slow Movement** is held, how long a key takes to tilt a stick or press a trigger fully); the shader cache; and **Export Settings** / **Import Settings**, which save the game's keys and settings as one file to share. Settings → Advanced picks where F12 screenshots go (`~/Pictures/AnyPS5` by default) and a folder of console system fonts.

**When a game stops.** A game that ends on an error gets the reason in plain words on the home screen and in the log: a missing module, an unsupported system function, the GPU stopping or running out of memory, an engine error or a crash. **⋯ → Make a Report** saves a text file with the Mac, the versions, the game's settings, the reason and the log of its last start, to attach on Discord or GitHub.

**Personalizing.** Settings change the theme, the accent color, the background (the theme animation, your own picture or a looping video), the selected game's artwork behind the home screen, animations, interface sounds and the profile name.

The launcher is driven with the arrow keys, Return and Esc, a game controller (D-pad, ✕, ○, △) or the mouse and trackpad.

| Home | Game settings | Unlocking | Game library |
|---|---|---|---|
| ![Home screen](../screenshots/launcher-home.jpg) | ![Game settings](../screenshots/launcher-game-settings.jpg) | ![Unlocking](../screenshots/launcher-unlocking.jpg) | ![Game library](../screenshots/launcher-library.jpg) |

[▶ Watch the launcher in action](../videos/launcher.mp4) (1:39)

### About the project

AnyPS5-ARM is the macOS port of [AnyPS5](https://github.com/boykopovar/AnyPS5). AnyPS5 is not an emulator. Its relinker turns a PS5 executable into a native program, and its system libraries are reimplemented as ordinary shared libraries the program links against. This fork makes that work on Apple silicon:

- **CPU:** the game's x86-64 code runs under **Rosetta 2**. A [native arm64 mode](https://github.com/utkuhalis/AnyPS5-ARM/blob/native-arm64/docs/dev/NATIVE_ARM64.md) that translates the code ahead of time, with no Rosetta, is in development on the `native-arm64` branch.
- **Executable:** the relinker writes a **Mach-O** executable.
- **Graphics:** the PS5 graphics driver runs on **Vulkan through MoltenVK**, which runs on Metal.
- **Distribution:** the result is packaged as a normal **`.app`** you open from Finder.

### Building from source

#### Requirements

- A Mac with Apple silicon (M1 or newer)
- Rosetta 2: `softwareupdate --install-rosetta --agree-to-license`
- Xcode command-line tools: `xcode-select --install`
- CMake and Ninja: `brew install cmake ninja`
- The [Vulkan SDK for macOS](https://vulkan.lunarg.com/sdk/home#mac), which provides the Vulkan loader and MoltenVK
- A **decrypted dump of a game you own**. It needs a plain ELF executable; a signed SELF does not work.

#### 1. Build

```sh
git clone --recursive https://github.com/utkuhalis/AnyPS5-ARM.git
cd AnyPS5-ARM
cmake -S . -B build-mac -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=x86_64
ninja -C build-mac all libs
```

`CMAKE_OSX_ARCHITECTURES=x86_64` is required, because the system libraries have to match the game's x86-64 code. The build produces:

- the relinker at `build-mac/core/relinker/relinker`
- the system libraries in `build-mac/core/libs/libs/`

#### 2. Convert a game

The dump folder holds the executable, its bundled modules and the game's data:

```text
MyGame/
    eboot.bin        decrypted ELF executable
    sce_module/      the game's bundled modules (libc.prx, ...)
    sce_sys/         param.json, icon0.png, ...
    ...              the game's data files
```

Relink the executable for macOS:

```sh
build-mac/core/relinker/relinker --macos --to-rosetta MyGame/eboot.bin out/eboot
```

- `--macos` writes a Mach-O executable.
- `--to-rosetta` rewrites the AMD-only instructions and the ones Rosetta lacks (RDSEED, RDPID, CLWB).
- The converted modules are written to `out/app0/sce_module/`.

#### 3. Package it as an app

```sh
python3 tools/package_macos_app.py \
    --relinked out \
    --game MyGame \
    --libs build-mac/core/libs/libs \
    --vulkan ~/VulkanSDK/<version>/macOS \
    "My Game.app"
```

The bundle contains everything it needs: the game, the system libraries, the Vulkan loader and MoltenVK. Its name and icon come from `sce_sys/param.json` and `icon0.png`. You can move it to `/Applications` and start it from Finder or Launchpad. The app is not signed: if macOS refuses to open it, right-click it and choose **Open** once.

To build AnyPS5.app itself from this build, run `tools/macos/build_launcher_app.sh build-mac ~/VulkanSDK/<version>/macOS dist`. `AnyPS5.app/Contents/MacOS/AnyPS5 --render-preview <folder> <games folder>` draws its screens into PNG files without opening a window.

#### 4. Play

| Keyboard / mouse | PS5 button |
|---|---|
| Arrow keys | D-pad |
| W A S D | Left stick |
| T F G H | Right stick |
| Return or Space | Cross |
| C | Circle |
| I | Triangle |
| Left click | Square |
| Q / E (or Alt) | L1 / R1 |
| Right click | R2 |
| Left Shift / Left Ctrl | L3 / R3 |
| Escape | Options |
| Backspace / Tab | Touchpad left / right |
| F11 | Toggle fullscreen |

Controllers that SDL recognizes, such as DualSense, DualShock and Xbox pads, work automatically. To change the keyboard and mouse bindings, see [INPUT_MAPPING.md](INPUT_MAPPING.md).

#### Troubleshooting

- **Log:** `~/Library/Logs/AnyPS5/<TITLE ID>.log`. When a game stops, the reason is at the end of this file. Unsupported states always end the program with an error message rather than continuing silently.
- **Shader cache:** `~/Library/Caches/org.anyps5.<title id>/shader_cache`. The first run compiles shaders, so it can stutter; later runs load them from the cache.
- **Performance profile:** start the executable from a terminal with `APS5_PROFILE_DRAW=1`. Every 10 seconds the log gets a `[present]` line with the number of frames drawn and the GPU time per frame.

#### Limitations

- The game's code runs under Rosetta 2. Apple has announced that macOS 27 is the last release with full Rosetta support.
- Games may stop at a function or GPU feature that is not implemented yet. See the [compatibility list](COMPATIBILITY.md).
- MoltenVK has no geometry shaders, mesh shaders, 64-bit atomics or 64-bit floats. Mesh-shader draws run as a compute shader followed by a pass-through vertex shader (`APS5_NO_MESH_EMULATION=1` skips them instead); indirect ones and draws that need geometry shaders are skipped, and shaders that need the others do not run.
- Known costs of the macOS port are listed in [TechnicalDebt.md](../dev/TechnicalDebt.md).

### Documentation

- [macOS port: status and changes](../dev/MACOS_PORT.md)
- [Native arm64 mode: design and plan](https://github.com/utkuhalis/AnyPS5-ARM/blob/native-arm64/docs/dev/NATIVE_ARM64.md)
- [Relinker usage](USAGE.md)
- [Input mapping](INPUT_MAPPING.md)
- [Architecture](../dev/ARCHITECTURE.md)
- [Technical debt](../dev/TechnicalDebt.md)
- [Code conventions](../dev/CONVENTIONS.md)

### Credits

- [boykopovar/AnyPS5](https://github.com/boykopovar/AnyPS5): the relinker, the system libraries and the shader recompiler this fork is built on.
- [mugurc/AnyPS5 `macos-port`](https://github.com/mugurc/AnyPS5/tree/macos-port): the community macOS port that added Mach-O output, merged here.

---

## Türkçe

### Çalışan oyunlar

| Dreaming Sarah | AnyPS5 Breakout | Stray (geliştiriliyor) |
|---|---|---|
| ![Dreaming Sarah](../screenshots/dreaming-sarah-gameplay.jpg) | ![AnyPS5 Breakout](../screenshots/breakout.jpg) | ![Stray](../screenshots/stray-brightness.jpg) |
| PPSA02929 · 60 FPS, oynanabilir | Test oyunu · 60 FPS, görüntü, kol ve ses | PPSA02100 · Unreal Engine 4 · yaklaşık 1 FPS, **üzerinde çalışılıyor** |

Üçü de macOS 26.6.2 çalışan bir MacBook Pro M3 Pro'da çalışıyor.

#### Dreaming Sarah

Menü ve oynanış 60 FPS'te çalışıyor (macOS yazma izleme eklenmeden önce yaklaşık 18 FPS).

| Ana menü | Açılış sahnesi |
|---|---|
| ![Ana menü, 59.95 FPS](../screenshots/dreaming-sarah-menu.jpg) | ![Açılış sahnesi, 60 FPS](../screenshots/dreaming-sarah-intro.jpg) |

#### Stray: üzerinde çalışılıyor

Stray, burada macOS'ta görüntü veren ilk Unreal Engine 4 oyunu. Stüdyo logosundan parlaklık ayar ekranına yaklaşık 10 FPS ile geliyor ve onu geçip yüklemeye giriyor. Bunun için şu düzeltmeler yapıldı:

- daha büyük shader image ve sampler heap'leri
- MoltenVK'nın shader çeviricisinin sonsuz döngüye ve GPU kilitlenmesine çevirdiği bir SPIR-V döngü biçimi
- storage image olarak okunan depth ve stencil yüzeyleri
- Metal'in çalıştıramadığı çizimlerin (geometry shader'lar, depth bounds testi) oyunu durdurmak yerine atlanması
- oyunun kendi `libc.prx`'inin host kütüphanelerinden önce bağlanması, write watch düzeltmeleri, Metal derleyicisinin derleyebildiği daha küçük SPIR-V çıktısı ve MoltenVK'da gevşek float kuralları

Artık varsayılan ayarlarla çalışıyor. Yazı tipinin bazı harfleri eksik (GPU'nun font atlasına sonradan eklediği harfler) ve parlaklık ekranından sonraki yüklemede hâlâ duruyor.

| Stüdyo logosu | Parlaklık ayarı |
|---|---|
| ![Stray: BlueTwelve logosu](../screenshots/stray-boot-logo.jpg) | ![Stray: parlaklık ayar ekranı](../screenshots/stray-brightness.jpg) |

### Uyumluluk

[Uyumluluk listesi](COMPATIBILITY.md#türkçe), macOS'ta test edilen her oyunu, durumunu ve FPS'ini gösterir.

### Durum

[![libraries](../progress/badge-libraries.svg)](../progress/badge-libraries.svg) [![shaders](../progress/badge-shaders.svg)](../progress/badge-shaders.svg)

[![ilerleme haritası](../progress/progress.svg)](../progress/progress.svg)

<sub>* Sistem kütüphaneleri: projenin şimdiye kadar bildiği fonksiyonların ([core/libs/prx](../../core/libs/prx) içinde tanımlananlar) ne kadarının yazıldığı; PS5'in bütün sistem fonksiyonlarının değil. GPU shader komutları: shader derleyicisinin çevirebildiği RDNA komutlarının oranı. Yeniden üretmek için `python3 tools/progress.py <klasör>` çalıştırıp üç SVG dosyasını `docs/progress/` klasörüne kopyala.</sub>

| Kontrol | Sonuç |
|---|---|
| Misafir testleri (TLS, istisnalar, thread'ler, modüller) | 10/10 geçiyor |
| MoltenVK üzerinde test paketi | 484 testin 477'si geçiyor |

Ölçümler Vulkan SDK 1.4.363.0 ile yapıldı. Geçmeyen 7 test, Apple GPU'sunun veya Metal'in sınırlarına takılıyor; örneğin 64-bit buffer atomikleri ve 32 KiB threadgroup belleği. [MACOS_PORT.md](../dev/MACOS_PORT.md) bu testleri ve bu fork'un yaptığı tüm değişiklikleri listeler.

### AnyPS5 uygulaması

**AnyPS5.app**, PS5 ana ekranı gibi tasarlanmış bir launcher. Bir klasördeki oyun dump'larını bulur, Mac için kilidini açar (dönüştürür) ve başlatır: Terminal, derleme ya da Vulkan SDK gerekmez.

<p><a href="https://github.com/utkuhalis/AnyPS5-ARM/releases/latest/download/AnyPS5-macOS.zip"><b>⬇ AnyPS5'i indir</b></a> · Apple silicon · macOS 14+</p>

**Kurulum.** En kolayı Terminal'de tek satır. `curl` ile inen dosya karantinaya alınmadığı için macOS uygulamayı "açılamıyor" uyarısı vermeden açar:

```sh
curl -fsSL https://github.com/utkuhalis/AnyPS5-ARM/releases/latest/download/install.sh | sh
```

[Son sürümdeki](https://github.com/utkuhalis/AnyPS5-ARM/releases/latest) zip'i kullanırsan uygulama notarize edilmediği için macOS ilk seferde engeller: **Sistem Ayarları → Gizlilik ve Güvenlik**'te **Yine de Aç**'a tıkla. macOS indirilen uygulamayı salt okunur bir kopyadan açarsa launcher kendini Uygulamalar'a taşıyıp oradan yeniden açmayı önerir.

**İlk açılış.** Dili, üç hareketli temadan birini (Kozmik, Aurora, Gün Batımı) ve PS5 dump'larının olduğu klasörü seç. Alt klasörler de taranır, sonradan eklenen oyunlar kendiliğinden görünür.

**Kilidi açmak.** Henüz dönüştürülmemiş oyunlarda kilit işareti olur. **Kilidi Aç**, `eboot.bin` ve modüller hâlâ SELF kabı olsa bile açar, macOS için relink eder ve oyun uygulamasını hazırlar; ilerleme PS5'teki gibi bir çubukla görünür. Oyun dosyaları dump'ın APFS klonlarıdır, kilidi açılan oyun ek yer kaplamaz. Hâlâ şifreli bir dump dönüştürülmez, bildirilir.

**Oynamak.** **Oyna** oyunu başlatır. **⋯** (ya da `O` / △) oyunun ayarlarını açar: çıkış çözünürlüğü (Stray gibi çözünürlük yaması olan oyunlarda), pencere ya da tam ekran, pencere boyutu, dikey senkronizasyon, performans göstergesi, oyun dili, **Tuş Atamaları**, **Kupalar**; ayrıca Finder'da göster, günlük, shader önbelleğini temizleme, kilidi yeniden açma ya da kurulumu kaldırma.

**Kupalar.** Kupa listesi olan oyunlarda **Oyna**'nın yanında kaç kupa kazandığını gösteren bir 🏆 düğmesi çıkar. Liste konsoldaki gibi açılır: yüzde, derece başına sayı (platin, altın, gümüş, bronz) ve her kupanın ikonu, açıklaması, kazandığın gün. Gizli kupalar kazanılana kadar gizli kalır, bir şey sayan kupalar (*Tüm aletleri edin* gibi) ne kadar kaldığını gösterir. Liste ve metinler oyunun kendi `sce_sys/trophy2` paketinden, varsa oyunun dilinde gelir; motor her kazanılan kupayı kurulu oyunun `_trophy` klasörüne kaydeder. Kilidi yeniden açmak kayıtları ve kupaları korur. Oynarken bir kupa kazanınca ekranın en üstünde, oyunun üstünde (tam ekranda da) bir kart belirir; oyunun klavyesini ya da faresini almaz.

**Gelişmiş.** **⋯ → Gelişmiş** her oyunun ince ayarlarını tutar: iki kumanda çubuğu için ölü bölge; fareyle kamera (hassasiyet, dikey hız, tepki eğrisi, en küçük eğim, en yüksek hız, yumuşatma, kameranın durma süresi); klavye (**Yavaş Hareket** basılıyken eğim, bir tuşun çubuğu ya da tetiği sonuna kadar götürme süresi); shader önbelleği; ve oyunun tuşlarını ve ayarlarını paylaşmak için tek bir dosyaya kaydeden **Ayarları Dışa Aktar** / **Ayarları İçe Aktar**. Ayarlar → Gelişmiş, F12 ekran görüntülerinin nereye kaydedileceğini (varsayılan `~/Pictures/AnyPS5`) ve konsolun sistem fontlarının klasörünü seçer.

**Oyun kapanınca.** Hatayla kapanan bir oyunun nedeni ana ekranda ve günlükte düz bir dille yazılır: eksik modül, desteklenmeyen sistem fonksiyonu, GPU'nun durması ya da belleğin yetmemesi, motor hatası ya da çökme. **⋯ → Tanı Raporu Oluştur**, Discord'a ya da GitHub'a eklemek için Mac'i, sürümleri, oyunun ayarlarını, nedeni ve son açılışın günlüğünü içeren bir metin dosyası kaydeder.

**Kişiselleştirme.** Ayarlar'dan tema, vurgu rengi, arka plan (tema animasyonu, kendi resmin ya da döngüdeki bir video), seçili oyunun ana ekrandaki görseli, animasyonlar, arayüz sesleri ve profil adı değiştirilir.

Launcher ok tuşları, Return ve Esc ile, oyun kumandasıyla (yön tuşları, ✕, ○, △) ya da fare ve trackpad ile kullanılır.

| Ana ekran | Oyun ayarları | Kilit açılıyor | Oyun kütüphanesi |
|---|---|---|---|
| ![Ana ekran](../screenshots/launcher-home.jpg) | ![Oyun ayarları](../screenshots/launcher-game-settings.jpg) | ![Kilit açılıyor](../screenshots/launcher-unlocking.jpg) | ![Oyun kütüphanesi](../screenshots/launcher-library.jpg) |

[▶ Launcher'ın videosunu izle](../videos/launcher.mp4) (1:39)

### Proje hakkında

AnyPS5-ARM, [AnyPS5](https://github.com/boykopovar/AnyPS5)'in macOS sürümüdür. AnyPS5 bir emülatör değildir. Relinker'ı PS5 oyun dosyasını yerel bir programa dönüştürür. Sistem kütüphaneleri de yeniden yazılmıştır ve program bunlara normal paylaşımlı kütüphaneler gibi bağlanır. Bu fork, bunu Apple silicon'da çalışır hale getirir:

- **İşlemci:** Oyunun x86-64 kodu **Rosetta 2** altında çalışır. Kodu önceden arm64'e çeviren ve Rosetta gerektirmeyen bir [native arm64 modu](https://github.com/utkuhalis/AnyPS5-ARM/blob/native-arm64/docs/dev/NATIVE_ARM64.md), `native-arm64` dalında geliştiriliyor.
- **Çalıştırılabilir dosya:** Relinker, oyunu bir **Mach-O** dosyası olarak yazar.
- **Grafik:** PS5 grafik sürücüsü, **MoltenVK üzerinden Vulkan** ile çalışır. MoltenVK da Metal'i kullanır.
- **Dağıtım:** Sonuç, Finder'dan açılan normal bir **`.app`** olarak paketlenir.

### Kaynak koddan derleme

#### Gereksinimler

- Apple silicon işlemcili bir Mac (M1 veya daha yenisi)
- Rosetta 2: `softwareupdate --install-rosetta --agree-to-license`
- Xcode komut satırı araçları: `xcode-select --install`
- CMake ve Ninja: `brew install cmake ninja`
- [macOS için Vulkan SDK](https://vulkan.lunarg.com/sdk/home#mac); Vulkan yükleyicisini ve MoltenVK'yi sağlar
- **Sahip olduğun bir oyunun şifresi çözülmüş dump'ı.** Çalıştırılabilir dosya düz bir ELF olmalı; imzalı SELF çalışmaz.

#### 1. Derleme

```sh
git clone --recursive https://github.com/utkuhalis/AnyPS5-ARM.git
cd AnyPS5-ARM
cmake -S . -B build-mac -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=x86_64
ninja -C build-mac all libs
```

`CMAKE_OSX_ARCHITECTURES=x86_64` zorunlu, çünkü sistem kütüphanelerinin oyunun x86-64 koduyla aynı mimaride olması gerekiyor. Derleme şunları üretir:

- relinker: `build-mac/core/relinker/relinker`
- sistem kütüphaneleri: `build-mac/core/libs/libs/`

#### 2. Oyunu dönüştürme

Dump klasöründe çalıştırılabilir dosya, oyunla gelen modüller ve oyunun verileri bulunur:

```text
MyGame/
    eboot.bin        şifresi çözülmüş ELF
    sce_module/      oyunla gelen modüller (libc.prx, ...)
    sce_sys/         param.json, icon0.png, ...
    ...              oyunun veri dosyaları
```

Çalıştırılabilir dosyayı macOS için dönüştür:

```sh
build-mac/core/relinker/relinker --macos --to-rosetta MyGame/eboot.bin out/eboot
```

- `--macos`, Mach-O dosyası üretir.
- `--to-rosetta`, AMD'ye özel komutları ve Rosetta'nın çalıştıramadığı komutları (RDSEED, RDPID, CLWB) dönüştürür.
- Dönüştürülen modüller `out/app0/sce_module/` klasörüne yazılır.

#### 3. Uygulama olarak paketleme

```sh
python3 tools/package_macos_app.py \
    --relinked out \
    --game MyGame \
    --libs build-mac/core/libs/libs \
    --vulkan ~/VulkanSDK/<sürüm>/macOS \
    "My Game.app"
```

Paket, çalışmak için gereken her şeyi içerir: oyun, sistem kütüphaneleri, Vulkan yükleyicisi ve MoltenVK. Adı ve simgesi `sce_sys/param.json` ile `icon0.png`'den alınır. Uygulamayı `/Applications` klasörüne taşıyıp Finder'dan ya da Launchpad'den açabilirsin. Uygulama imzasız: macOS açmayı reddederse, uygulamaya sağ tıklayıp bir kere **Aç**'ı seç.

AnyPS5.app'in kendisini bu derlemeden üretmek için `tools/macos/build_launcher_app.sh build-mac ~/VulkanSDK/<sürüm>/macOS dist` çalıştır. `AnyPS5.app/Contents/MacOS/AnyPS5 --render-preview <klasör> <oyun klasörü>` ekranlarını pencere açmadan PNG dosyalarına çizer.

#### 4. Oynama

| Klavye / fare | PS5 tuşu |
|---|---|
| Yön tuşları | D-pad |
| W A S D | Sol analog |
| T F G H | Sağ analog |
| Return veya Space | Çarpı (Cross) |
| C | Daire (Circle) |
| I | Üçgen (Triangle) |
| Sol tık | Kare (Square) |
| Q / E (veya Alt) | L1 / R1 |
| Sağ tık | R2 |
| Sol Shift / Sol Ctrl | L3 / R3 |
| Escape | Options |
| Backspace / Tab | Touchpad sol / sağ |
| F11 | Tam ekran aç/kapat |

SDL'in tanıdığı kollar (DualSense, DualShock, Xbox kolları gibi) kendiliğinden çalışır. Klavye ve fare tuşlarını değiştirmek için [INPUT_MAPPING.md](INPUT_MAPPING.md) dosyasına bak.

#### Sorun giderme

- **Log:** `~/Library/Logs/AnyPS5/<TITLE ID>.log`. Oyun kapanırsa sebebi bu dosyanın sonunda yazar. Desteklenmeyen bir durumda program sessizce devam etmez, her zaman bir hata mesajıyla kapanır.
- **Shader önbelleği:** `~/Library/Caches/org.anyps5.<title id>/shader_cache`. İlk açılışta shader'lar derlendiği için takılmalar olabilir; sonraki açılışlarda önbellekten yüklenir.
- **Performans ölçümü:** Çalıştırılabilir dosyayı terminalden `APS5_PROFILE_DRAW=1` ile başlat. Log dosyasına her 10 saniyede bir `[present]` satırı düşer; bu satırda çizilen kare sayısı ve kare başına GPU süresi yazar.

#### Sınırlamalar

- Oyun kodu Rosetta 2 altında çalışıyor. Apple, macOS 27'nin tam Rosetta desteği olan son sürüm olacağını duyurdu.
- Oyunlar henüz yazılmamış bir fonksiyona ya da GPU özelliğine takılıp durabilir. [Uyumluluk listesine](COMPATIBILITY.md#türkçe) bak.
- MoltenVK'de geometry shader, mesh shader, 64-bit atomic ve 64-bit float yok. Mesh shader çizimleri bir compute shader ve ardından bir geçiş vertex shader'ı olarak çalışır (`APS5_NO_MESH_EMULATION=1` bunları atlar); indirect olanlar ve geometry shader gerektiren çizimler atlanır, diğerlerini gerektiren shader'lar çalışmaz.
- macOS sürümünün bilinen maliyetleri [TechnicalDebt.md](../dev/TechnicalDebt.md) dosyasında listelenir.

### Belgeler

- [macOS sürümü: durum ve değişiklikler](../dev/MACOS_PORT.md)
- [Native arm64 modu: tasarım ve plan](https://github.com/utkuhalis/AnyPS5-ARM/blob/native-arm64/docs/dev/NATIVE_ARM64.md)
- [Relinker kullanımı](USAGE.md)
- [Tuş atamaları](INPUT_MAPPING.md)
- [Mimari](../dev/ARCHITECTURE.md)
- [Teknik borç](../dev/TechnicalDebt.md)
- [Kod kuralları](../dev/CONVENTIONS.md)

### Teşekkürler

- [boykopovar/AnyPS5](https://github.com/boykopovar/AnyPS5): Bu fork'un temeli olan relinker, sistem kütüphaneleri ve shader derleyicisi.
- [mugurc/AnyPS5 `macos-port`](https://github.com/mugurc/AnyPS5/tree/macos-port): Mach-O çıktısını ekleyen topluluk macOS sürümü; buraya birleştirildi.
