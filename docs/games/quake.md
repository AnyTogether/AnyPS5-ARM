[← Tüm oyunlar](README.md)

# Quake II ve Quake III

`PPSA99007 · PPSA99303` · Kendi GPU sürücüsü (Mesa/RADV)

**Durum:** ⚪ Kapsam dışı · Bu yaklaşımın dışında · **FPS:** —

İki homebrew port, Sony'nin grafik kütüphanelerini kullanmıyor; Mesa/RADV sürücüsüyle GPU'ya PS5 çekirdeği üzerinden doğrudan erişiyor.

## Adım adım

| | Aşama | Ayrıntı |
|---|---|---|
| ✅ | **İnceleme** | Quake III Vulkan (RADV), Quake II OpenGL 3.3 (Mesa) kullanıyor; ikisi de libSceAgc'yi atlıyor. |
| ⏭️ | **Gerekirse** | PS5 çekirdeğinin GPU arayüzünü (ioctl'ler, komut kuyrukları) emüle eden ayrı bir alt seviye katman. Ticari oyunlar bunu kullanmadığı için düşük öncelik. |

✅ tamamlandı · 🔧 şu an · ⏭️ sırada

## Teknik bilgi

| | |
|---|---|
| Quake III | `Quake3e + PS5_Mesa RADV` |
| Quake II | `Yamagi Quake II + Mesa OpenGL` |
| Ticari oyunlarda | `Görülmez; Sony buna izin vermiyor` |

## Bağlantılar

- [PS5_Quake3e](https://github.com/griches/PS5_Quake3e)
