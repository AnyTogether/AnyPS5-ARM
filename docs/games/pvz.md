[← Tüm oyunlar](README.md)

# Plants vs. Zombies: Replanted

`PPSA29802` · Unity (IL2CPP)

**Durum:** 🟡 Üzerinde çalışılıyor · Kullanıcı sözleşmesi ekranı · **FPS:** 60

Açılış akışı 60 FPS'te ve kusursuz çiziliyor; 5 dakikalık testte hiç kapanmadı. Sırada sözleşmeyi geçip ana menüye ve oyuna girmek var.

![EA kullanıcı sözleşmesi ekranı, 60 FPS](img/pvz-agreement.jpg)
*EA kullanıcı sözleşmesi ekranı, 60 FPS*

## Adım adım

| | Aşama | Ayrıntı |
|---|---|---|
| ✅ | **Silksong ile aynı Unity hazırlığı** | SELF → ELF, modüller exe ile, eklentiler ayrı. |
| ✅ | **C# exception'ları yakalanıyor** | Tarih/saat hesabındaki bir ArgumentOutOfRangeException oyunun kendi kodunda yakalanamıyordu. macOS'ta unwind tablolarını raporlayan düzeltme (PR #4, kabonKoda) ile çözüldü. |
| ✅ | **MSAA sample locations** | Oyun 4x MSAA'da standart dışı örnek noktaları kullanıyor; VK_EXT_sample_locations ile uygulandı. |
| ✅ | **MSAA bellek boyutu** | 4x MSAA hedefinin boyutu 2 MB fazla hesaplanıyordu ve küçük bir görüntüyle çakışıyordu; AddrLib'in GFX10 kuralıyla düzeltildi. |
| ✅ | **Rosetta + AVX çökmesi** | Upstream #4194 ile çözüldü; exe'de 53.718 yazma bölündü. |
| 🔧 | **Sözleşme ekranı** | Cross ile ilerleme komutu sözleşmeyi geçmiyor; menü gezintisi için girdi senaryosu ayarlanacak. |
| ⏭️ | **Ana menü ve oyun** | Oyun içi çizim ve performans. |

✅ tamamlandı · 🔧 şu an · ⏭️ sırada

## Teknik bilgi

| | |
|---|---|
| Kimlik | `PPSA29802 · içerik 01.001.001` |
| Motor | `Unity, IL2CPP` |
| MSAA | `4x, özel örnek noktaları` |
| Bölünen 256-bit yazma | `53.718 (exe)` |
| 5 dk test | `17.933 kare, kapanma yok` |

## Bugün nasıl dönüştürülür (Unity, elle)

AnyPS5.app bu adımları henüz yapmıyor; şimdilik elle:

1. `eboot.bin`, `sce_module/*.prx`, `Media/Modules/*.prx` ve `Media/Plugins/*.prx` dosyalarını SELF'ten ELF'e çevir.
2. `Media/Modules` içindekileri (`Il2cppUserAssemblies.prx`, `PS5Util.prx`) `sce_module` ile birlikte koyup exe'yi `relinker --macos --to-rosetta` ile relink et.
3. `Media/Plugins` eklentilerini exe'ye bağlamadan ayrı bir relink ile `.guest.prx` olarak üret ve orijinallerinin yanına koy; Unity onları çalışma anında başlangıç argümanlarıyla yükler.
4. Paketledikten sonra `Media/Modules/*.guest.prx` dosyalarını `sce_module` kopyalarına symlink yap (oyun aynı modülü `Il2CppUserAssemblies` adıyla da açar), eklentilerin `libc`/`libSceNpCppWebApi` bağımlılıkları için `Media/Plugins` altına symlink ekle, `app0/libs` → `../../../MacOS/libs` bağla.


## Bağlantılar

- [PR #4: macOS unwind tabloları](https://github.com/utkuhalis/AnyPS5-ARM/pull/4)
- [Upstream #4194](https://github.com/boykopovar/AnyPS5/pull/4194)
