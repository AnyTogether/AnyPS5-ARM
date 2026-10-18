[English](../README.md) · **Türkçe**

# Native mod: PS5 oyunları Apple silicon'da Rosetta olmadan

Dal: [`native-arm64`](https://github.com/utkuhalis/AnyPS5-ARM/tree/native-arm64). `main` Rosetta modunu sürdürüyor.

![DOOM E1M1, arm64 süreci olarak](../../games/img/doom-native-e1m1.jpg)
*DOOM (homebrew) E1M1'de, 35 FPS, arm64 süreci olarak: içinde hiçbir yerde Rosetta yok.*

## "Native" burada ne demek

PS5 oyunları x86-64 kodu; Apple silicon arm64 çalıştırıyor. Arada birinin çevirmesi gerekiyor.

| | Rosetta modu (`main`) | Native mod (`native-arm64`) |
|---|---|---|
| Oyun kodu | x86-64 kalıyor; macOS her açılışta Rosetta ile çeviriyor | uygulama hazırlanırken AnyPS5'in kendi çeviricisiyle **bir kere** arm64'e çevriliyor |
| Sistem kütüphaneleri (grafik, ses, kol...) | x86-64, onlar da Rosetta altında | arm64 olarak derleniyor |
| Uygulamanın ikilisi | `Mach-O 64-bit executable x86_64` | `Mach-O 64-bit executable arm64` |
| Etkinlik Monitörü, "Tür" sütunu | Intel | Apple |
| Rosetta kurulu olmalı mı | evet | hayır |

Grafik iki modda da MoltenVK üzerinden Metal'e gidiyor. Rosetta native modda yalnızca test setinde, çeviricinin sonuçlarını karşılaştırmak için referans olarak geçiyor; oyun oynarken hiç kullanılmıyor.

Amaç Rosetta'nın maliyetinden ve kısıtlarından kurtulmak. DOOM gibi hafif bir oyunda ölçülecek bir fark yok (iki modda da 35 FPS hedefinde); kazancın Stray gibi ağır oyunlarda görünmesi bekleniyor.

## Durum

| Oyun | Native durumu |
|---|---|
| **DOOM (homebrew)** `PPSA99666` | 🟢 Launcher (60 FPS), tanıtım demosu ve E1M1 35 FPS |
| Diğerleri | 🔴 Henüz denenmedi. Ticari oyunlar için önce aşağıdaki açık maddeler gerekiyor. |

Rosetta modunda oyun oyun durum [oyun defterinde](../../games/tr/README.md).

## Gereksinimler

- Apple silicon Mac (M1 veya sonrası), macOS 13 veya üstü
- Xcode komut satırı araçları, CMake, Ninja
- Homebrew `llvm` ve `capstone` (çevirici bunlara bağlanıyor): `brew install llvm capstone cmake ninja`
- macOS için [Vulkan SDK](https://vulkan.lunarg.com/sdk/home#mac) (pakete `libvulkan` ve MoltenVK buradan giriyor)
- Oyun: şifresi çözülmüş bir dump (fake-signed SELF'ler olur)

## Derleme

Depo kökünden, `native-arm64` dalında ve submodule'ler çekilmiş halde:

```sh
# 1. Sistem kütüphaneleri, arm64 için
cmake -S . -B build-arm64 -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64
ninja -C build-arm64 all libs

# 2. Çevirici (Homebrew LLVM ve Capstone gerekir)
cmake -S tools/translator -B build-translator -G Ninja -DCMAKE_BUILD_TYPE=Release -DLLVM_DIR=$(brew --prefix llvm)/lib/cmake/llvm
ninja -C build-translator
```

## Bir oyun için uygulama hazırlama

```sh
python3 tools/translator/package_native_app.py \
    --eboot <oyun>/eboot.bin --game <oyun> \
    --libs build-arm64/core/libs/libs \
    --vulkan ~/VulkanSDK/<sürüm>/macOS \
    --translator build-translator \
    "DOOM (native).app"
```

`--game` oyun klasörü (`sce_sys` olan), `--eboot` onun çalıştırılabilir dosyası. Şifresi çözülmüş SELF yolda açılıyor; düz ELF de olur. Araç eboot'u çeviriyor, arm64 kütüphanelerle bağlıyor ve normal bir `.app` yazıyor.

Hiçbir arm64 kütüphanenin sağlamadığı import'lar sonda listeleniyor; her biri kendi adını yazan ve çağrılırsa oyunu durduran bir stub'a bağlanıyor.

## Çalıştırma

Uygulamaya çift tıkla ya da terminalden başlat:

```sh
open "DOOM (native).app"
```

Çıktı `~/Library/Logs/AnyPS5/<oyun id>.log` dosyasına, shader önbelleği `~/Library/Caches/org.anyps5.<oyun id>` altına gidiyor.

Rosetta olmadığını görmek için: `file "DOOM (native).app/Contents/MacOS/eboot"` `arm64` yazar, Etkinlik Monitörü süreci Apple olarak gösterir.

### İşe yarayan ayarlar

| Değişken | Etkisi |
|---|---|
| `APS5_NATIVE_TRACE=1` | host'tan oyun koduna her çağrıyı (thread girişleri, callback'ler) loglar |
| `APS5_PAD_SCRIPT=6:cross,9:cross,...` | verilen saniyelerde kol tuşlarına basar, otomatik denemeler için |
| `APS5_PRESENT_OCCLUDED=1` | pencere kapalıyken de çizmeye devam eder |

Rosetta modunun değişkenlerinin çoğu burada da geçerli ([ENVIRONMENT.md](../../dev/ENVIRONMENT.md)).

## Testler

```sh
python3 tools/translator/tests/run_native_fixtures.py build-translator build-arm64/core/libs/libs
```

- `import`: GOT üzerinden `puts` ve `exit` çağıran elle hazırlanmış bir PS5 ELF'i.
- `lifter-smoke`: tamsayı aritmetiği, bayraklar, kaydırmalar, bölme, özyineleme, dolaylı çağrılar.
- `vector-smoke`: rastgele girdiler, NaN'ler ve sınır dışı değerlerle SSE/AVX2, FMA ve BMI; aynı C dosyasının Rosetta altında x86-64 olarak çalışmasıyla karşılaştırılıyor. Referans optimizasyonsuz derleniyor, çünkü Rosetta'nın kendisi bazı optimize AVX dizilerini yanlış hesaplıyor.

## Kısaca nasıl çalışıyor

1. **Çeviri:** `aps5-translator` eboot'un x86-64 kodunu Capstone ile çözüyor, her fonksiyonu x86 register durumu üzerinde LLVM IR'a çeviriyor; LLVM bunu optimize edip arm64 kodu üretiyor. Fonksiyonlar giriş noktasından, sembollerden, relocation'lardan, çağrı hedeflerinden, `lea` ile alınan kod adreslerinden ve switch atlama tablolarından bulunuyor.
2. **Bellek:** oyunun belleği host'un belleği, yani okuma ve yazmalar aynı adreslerde düz okuma/yazma olarak kalıyor.
3. **Kütüphanelere çağrılar:** oyunun sistem fonksiyonu çağrısı doğrudan arm64 kütüphaneye gidiyor; argümanlar x86 register'larından arm64 register'larına taşınıyor. Değişken argümanlı fonksiyonlar (`printf`, `sscanf`...) oyunun argümanlarını x86 usulü okuyor.
4. **Oyuna geri çağrılar:** thread girişleri ve callback'ler host'un doğrudan çağırdığı oyun adresleri. Oyunun imajı çalıştırılabilir olmadığından çağrı hata veriyor; runtime bu hatayı yakalayıp çevrilmiş fonksiyonu çalıştırıyor.
5. **Thread başına:** her thread'in kendi x86 register durumu, yığını ve PS5'in beklediği düzende TLS bloğu var.

Tasarım ayrıntıları, zor kısımlar ve plan: [NATIVE_ARM64.md](../../dev/NATIVE_ARM64.md).

## Bilinen sınırlar

- Oyunun kendi getirdiği prx modülleri (`sce_module`) henüz çevrilmiyor. DOOM'un `libc.prx`'i sadece stub olduğu için orada fark etmiyor; çoğu ticari oyunun buna ihtiyacı var.
- Henüz taşınmadı: `setjmp`/`longjmp`, fiber'lar, çevrilmiş kod içinden geçen C++ exception'ları, `getcontext`/`setcontext`, 80-bit `long double`. Bunlara gelindiğinde oyun açık bir mesajla duruyor.
- x86'nın bellek sıralaması arm64'ünkünden güçlü. Çevirici henüz bariyer eklemiyor, bu yüzden x86 sıralamasına güvenen çok thread'li kod sorun çıkarabilir.
- Yeni üretilen NaN'ler arm64'te pozitif, x86'da negatif; NaN'in işaretine bakan kod farklı davranabilir.
- Ses henüz kontrol edilmedi.
