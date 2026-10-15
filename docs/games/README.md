**English** · [Türkçe](tr/README.md)

# Game status notebook

What we have run of PS5 games on Apple silicon Macs, through Rosetta 2 and MoltenVK. Each game's page has screenshots, the steps that got it this far, and the technical details.

Test hardware: MacBook Pro M3 Pro, macOS 26.6.2, Vulkan SDK 1.4.363.0. Last updated: 15 October 2026.

🟢 Playable · 🟡 Work in progress · 🔴 Does not start · ⚪ Out of scope

| | Game | ID | Engine | Status | FPS |
|---|---|---|---|---|---|
| <img src="img/silksong-enemy.jpg" width="180"> | [**Hollow Knight: Silksong**](silksong.md) | `PPSA12544` | Unity (IL2CPP) | 🟢 Playable, new game through Moss Grotto | Menus 100–120 · in game ~25–50 |
| <img src="img/pvz-ingame.jpg" width="180"> | [**Plants vs. Zombies: Replanted**](pvz.md) | `PPSA29802` | Unity (IL2CPP) | 🟢 Playable, levels 1-1 to 1-3 | Menu ~120 · in game 60–120 |
| <img src="img/doom-e1m1.jpg" width="180"> | [**DOOM (homebrew)**](doom.md) | `PPSA99666` | lowbit/ps5-doom | 🟢 Playable, E1M1 onwards | 35 (the game's own target) |
| <img src="img/dreaming-sarah.jpg" width="180"> | [**Dreaming Sarah**](dreaming-sarah.md) | `PPSA02929` | Construct 2 | 🟢 Playable | 60 |
| <img src="img/breakout.jpg" width="180"> | [**AnyPS5 Breakout**](breakout.md) | `APS5TEST1` | The project's test game | 🟢 Playable | 60 |
| <img src="img/stray-family.jpg" width="180"> | [**Stray**](stray.md) | `PPSA02100` | Unreal Engine 4 | 🟢 Playable, first chapter (FPS very low) | In game ~1-11 (1080p) |
| <img src="img/minecraft-ingame.jpg" width="180"> | [**Minecraft**](minecraft.md) | `PPSA17221` | Bedrock Edition | 🟡 Reaches a world, crashes ~20 s in | Menus 60 · in game ~7-8 |
| <img src="img/quake2-base1.jpg" width="180"> | [**Quake II and Quake III**](quake.md) | `PPSA99007 · PPSA99303` | PS5_Mesa (OpenGL / RADV) | 🟡 Quake II in game · Quake III needs data files | Menu ~48 · in game ~40 |
|  | [**Once Upon a KATAMARI**](katamari.md) | `PPSA21904` | Unity (IL2CPP) | 🟡 Startup logos render; later screen stays black | Startup ~54–60 · game not reached |
|  | **GTA III – Definitive Edition** | `PPSA03527` | Unreal Engine 4 | 🔴 Not retried yet | — |
