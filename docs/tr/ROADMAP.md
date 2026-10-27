[English](../ROADMAP.md) · **Türkçe**

# Yol haritası

AnyPS5-ARM'ın Apple Silicon Mac'lerde nereye gittiği, sırasıyla. Bugün oyunlar Rosetta 2 altında çalışıyor (oyun ve sistem kodu x86-64), PS5 grafik sürücüsü de MoltenVK üzerinden Metal'de. Oyun oyun durum [oyun durum defterinde](../games/tr/README.md), Rosetta port'unun kendisi [MACOS_PORT.md](../dev/MACOS_PORT.md)'de.

Son güncelleme: 15 Ekim 2026.

✅ tamamlandı · 🔧 şu an · ⏭️ sırada · 💤 sonra

## 1. FPS 🔧

Ağır 3D oyunlarda sınır GPU değil CPU. Stray 1080p'de bir kareyi ~100–150 ms'de çiziyor; bunun sadece ~41–45 ms'inde GPU çalışıyor. GPU'yu kare başına yalnızca ~3 ms bekliyor ve cihazı hiç boşaltmıyor. Zaman sürücü thread'inde gidiyor: her PS5 draw paketini tek tek Vulkan'a çeviriyor, 10 saniyede ~24.000 draw, her biri ~270–415 µs.

| | Adım | Ayrıntı |
|---|---|---|
| ⏭️ | **Kilit beklemeleri** | Draw başına en büyük maliyet (137–247 µs), diğer sürücü thread'leriyle paylaşılan GPU mutex'ini beklemek. Kilidi daha kısa tutmak ya da bölmek draw başına süreyi yarıya indirebilir. |
| ⏭️ | **Her draw'da tekrarlanan iş** | Shader belleği yakalama (~40 µs), PM4 decode (~35 µs) ve recompile aramaları (~40–60 µs) her draw'da yeniden yapılıyor. Draw'lar arasında değişmeyeni önbelleğe almak. |
| ⏭️ | **Karşılaştırmalı ölçüm** | Her adım Stray'de, 1080p'de, ısınmış shader cache ile, bir önceki build'e karşı ölçülüyor. |

Hedef: 1080p'de Stray oyun içi ~5'ten 20+ FPS'e. Bu iş native arm64 build'e de aynen taşınıyor.

## 2. Rosetta'nın maliyeti 🔧

Sürücü kodu da oyun gibi Rosetta ile çevrilerek çalışıyor. Kütüphaneler native arm64 için de derleniyor (`native-arm64` branch'i), yani aynı sürücü testleri iki şekilde de koşabiliyor.

| | Adım | Ayrıntı |
|---|---|---|
| ⏭️ | **Aynı testler, iki mimari** | Sürücü ve shader recompiler testlerini `build-arm64` (native) ve `build-mac` (Rosetta) ile süre ölçerek koşmak. |
| ⏭️ | **Karar** | Aradaki fark, Rosetta'sız bir build'in ne kadar değdiğini ve 5. adıma ne zaman ciddi başlanacağını söylüyor. |

## 3. Oyun uyumluluğu 🔧

| | Oyun | Sırada |
|---|---|---|
| 🟢 | **Stray** (`PPSA02100`) | İlk bölüm doğru grafiklerle oynanıyor. Sırada: sonraki bölümler ve FPS (1. adım). |
| 🟢 | **Hollow Knight: Silksong**, **Plants vs. Zombies: Replanted** | Oynanabilir; Unity modül adımları hâlâ elle (4. adım). |
| 🟡 | **Quake II / Quake III** | Quake II oyun içinde; Quake III veri dosyalarını istiyor. |
| 🟡 | **Minecraft** (`PPSA17221`) | Menüler 60 FPS, dünyaya giriyor. Sırada: ~20 sn sonra çökerten açık dosya sınırı, sonra dünyadaki FPS (~7-8). |
| 🔴 | **GTA III – Definitive Edition** (`PPSA03527`) | Güncel main ile yeniden denemek. |
| ⏭️ | **Yeni oyunlar** | Her yeni oyun [defterde](../games/tr/README.md) kendi sayfasını alıyor. |

## 4. AnyPS5 uygulaması ve sürümler ⏭️

Son sürüm [v0.1.0-arm](https://github.com/AnyTogether/AnyPS5-ARM/releases/tag/v0.1.0-arm), yukarıdaki işlerin çoğundan önce çıktı.

| | Adım | Ayrıntı |
|---|---|---|
| ⏭️ | **Yeni sürüm** | Güncel main: üçüncü upstream merge'ü ve Stray düzeltmeleri. |
| ⏭️ | **Oyun yamaları uygulamada** | `tools/package_macos_app.py` oyuna özel yamaları (Stray'in çıkış çözünürlüğü) uyguluyor; AnyPS5.app henüz uygulamıyor. |
| ⏭️ | **Unity modül adımları uygulamada** | Silksong ve PvZ Replanted hâlâ kendi sayfalarında anlatılan elle yapılan modül adımlarını istiyor. |

## 5. Rosetta'sız native arm64 💤

Plan ve tasarım: `native-arm64` branch'indeki [NATIVE_ARM64.md](https://github.com/AnyTogether/AnyPS5-ARM/blob/native-arm64/docs/dev/NATIVE_ARM64.md). Oyunun x86-64 kodu önceden arm64'e çevriliyor (Capstone, LLVM), sistem kütüphaneleri native derleniyor.

| | Kilometre taşı | Ayrıntı |
|---|---|---|
| ✅ | **Kütüphaneler arm64 için derleniyor** | Sadece x86'ya özel kısımlar port edilene kadar hata veriyor. |
| ✅ | **En küçük fixture native çalışıyor** | `import_fixture` (GOT üzerinden `puts` ve `exit`) arm64 process olarak çalışıyor. |
| ⏭️ | **C ve C++ fixture'ları** | Thread'ler, TLS, exception'lar, modüller. |
| 💤 | **Breakout, sonra Dreaming Sarah** | Rosetta'sız ilk gerçek oyunlar. |
| 💤 | **Zor kısımlar** | Yerel olmayan akış (setjmp/longjmp, exception landing pad'leri, fiber'lar), x86 bellek sıralamasının arm64'te korunması, variadic ve `long double` köprüleri. |

## 6. Metal backend'i 💤

Vulkan ve MoltenVK'yı doğrudan Metal ile değiştirmek bütün grafik backend'ini yeniden yazmak demek. GPU her karenin çoğunda boşta beklerken en az kazancı bu getirir, o yüzden en sonda.

## Upstream

Fork, oyun testlerinden önce [boykopovar/AnyPS5](https://github.com/boykopovar/AnyPS5) ile aynı seviyede tutuluyor. Mac'e özel olmayan düzeltmeler upstream'e pull request olarak gidiyor.
