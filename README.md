# AnyPS5-ARM

**Run PS5 games natively on Apple silicon Macs.**

[Full guide in English and Turkish / Türkçe rehber](docs/user/GUIDE.md)

## The AnyPS5 app

**AnyPS5.app** is a launcher laid out like the PS5 home screen. Point it at the folder with your game dumps and it does the rest: it finds the games, unlocks (converts) them for the Mac, starts them, and keeps your controls, saves and trophies per game. No Terminal, build or Vulkan SDK needed.

![The AnyPS5 launcher in action](docs/videos/launcher-preview.webp)

<p align="center"><a href="https://github.com/AnyTogether/AnyPS5-ARM/raw/main/docs/videos/launcher.mp4"><b>▶ Full video with sound</b></a> (1:39, MP4)</p>

```sh
curl -fsSL https://github.com/AnyTogether/AnyPS5-ARM/releases/latest/download/install.sh | sh
```

One line installs it into Applications (and Rosetta 2 if it is missing). A download through `curl` carries no quarantine flag, so macOS opens the app without any "cannot be opened" warning. [⬇ Or download the zip](https://github.com/AnyTogether/AnyPS5-ARM/releases/latest/download/AnyPS5-macOS.zip) · [How to use it](docs/user/GUIDE.md#the-anyps5-app)

**On Windows or Linux?** Use [**AnyPS5 Desktop**](https://github.com/AnyTogether/AnyLauncher-Port/releases/latest): this launcher for those systems, with AnyTogether built in (early preview).

### First start

Three steps: the language (Türkçe or English), one of four animated themes (Cosmic, Aurora, Sunset, and Glass: a see-through window that shows your desktop and the windows behind it frosted, with Liquid Glass panels on macOS 26) and the games folder. The folder and its subfolders are scanned, and games you add later show up on their own.

<p align="center"><img src="docs/screenshots/launcher-themes.jpg" alt="Picking a theme on the first start" width="720"></p>

### Home screen

![Home screen with Hollow Knight: Silksong selected](docs/screenshots/launcher-home-trophies.jpg)

Every game sits in a row of tiles with its icon. The selected one grows, its artwork drifts behind the screen, and below it are the facts: status, size on disk, title ID and version. A tile with a lock still has to be unlocked. Under the title:

- **Play**, or **Unlock**, **Retry** and **Cancel** as the state calls for.
- **🏆 8/34**, the trophies earned, when the game has a trophy list.
- **⋯** for the game's settings.

### Unlocking

![A game being unlocked](docs/screenshots/launcher-unlocking.jpg)

**Unlock** turns a PS5 dump into a Mac app in seconds to a few minutes, with a progress bar like the console's:

1. **Unwrap:** `eboot.bin` and every module are opened, even when they are still SELF containers. A dump that is still encrypted is reported, not converted.
2. **Relink:** the relinker writes a Mach-O executable and macOS modules. Unity titles get their `Media/Modules` and `Media/Plugins` folders too.
3. **Copy:** the game files become **APFS clones** of the dump, so an unlocked game takes no extra space.
4. **Bundle:** the libraries, MoltenVK, the per-title patches and a launch script go into the app.

Several games can be queued. When the launcher's toolkit is newer than the one a game was unlocked with, its status reads **Update available**; **⋯ → Unlock Again** brings it up to date and keeps its saves and trophies.

### Starting a game

![The start screen while a game opens](docs/screenshots/launcher-starting.jpg)

**Play** shows a start screen with the game's icon and a timer until the game's first window appears. The first start of a title takes longest, because Rosetta translates it and its shaders compile; later starts use the caches. Esc stops the game before it shows. Once the window is up the launcher hands it the front, and it can hide itself while you play (Settings → Behaviour).

### When a game stops

When a game ends on an error, the launcher reads why from that start's log and from the crash report macOS leaves, and says it in plain words, on the home screen and in the log:

- a **missing module** (unlocking again may fix it);
- a **system function the engine does not support yet**, by name;
- the **GPU stopping** or **running out of memory**;
- any other **engine error**, with its message;
- a **crash**, such as `EXC_BAD_ACCESS (SIGSEGV)`.

**⋯ → Make a Report** (or the button in the log) saves a text file to attach on Discord or GitHub: the Mac model and chip, macOS, the launcher and toolkit versions, the game, its settings, the reason and the log of its last start.

### Game settings

<img src="docs/screenshots/launcher-game-settings.jpg" alt="Game settings" align="right" width="440">

Each game keeps its own settings, applied at every start:

- **Output resolution**, for titles with a resolution patch (such as Stray).
- **Window or full screen**, and the window size.
- **Vertical sync.**
- **Frame generation** (experimental): a frame made between each two of the game's, from the motion between them, so a 60 fps game shows 120 on a 120 Hz display. It needs vertical sync and turns itself off where it would cost the game frames (a 60 Hz display, or Low Power Mode, which holds the display at 60 Hz).
- **Controls** (below).
- **Trophies** (below).
- **Advanced** (below).
- **Performance overlay**, off or in any corner of the window: **Minimal**, one line in a small capsule (frames per second, generated frames, frame time, GPU and CPU use, memory), or **Detailed**, the panel with the frame-time graph.
- **Game language**: the launcher's, or any of the console's languages.
- **Screenshots:** the game's F12 shots and clips in a grid, and one at a time over the whole screen, a clip playing.
- **Back Up Saves** and **Restore Saves**: the game's saves and trophies as a zip in Documents → AnyPS5 → Backups; a restore backs up what the game had first.
- **Unlock Again**, **Show in Finder**, **Open Log**, **Make a Report**, **Clear Shader Cache** and **Remove Installation**.

<br clear="right">

### Controls

![Waiting for a key for Square](docs/screenshots/launcher-controls.jpg)

The keyboard and mouse layout of each game. Pick a pad button or stick direction and press the key you want; Esc cancels. A key you give to one button leaves the button that had it, and mouse buttons stay where they were. **Reset to Default Keys** brings back the layout below. A connected game controller keeps its own buttons.

| Pad | Keys |
|-----|------|
| Left stick | W A S D |
| ✕ / □ / ○ / △ | K (also Space, Return) / J (also left click) / L / I |
| L1 / R1 | Q / E |
| L2 / R2 | U (also mouse button 4) / O (also right click) |
| L3 / R3 | Shift / Ctrl |
| D-pad | Arrow keys (also the mouse wheel for up and down) |
| Right stick | T F G H |
| Options / touchpad | Esc / Backspace (left) and Tab (right) |
| Slow movement | none: give it a key to walk with the keyboard |

For Unreal Engine games, each button also shows what the game itself does with it (Jump, Sprint, Move forward), read from the game's own input settings in its `.pak`. Games whose pak is encrypted or that keep their controls only in Enhanced Input assets show nothing there.

The launcher writes the layout to `~/Library/Application Support/AnyPS5/Controls/<game>.ini` at each start and passes it to the game ([format](docs/user/INPUT_MAPPING.md)).

### Advanced settings

![The advanced settings of a game](docs/screenshots/launcher-advanced.jpg)

**⋯ → Advanced** holds the finer settings of each game, each with a line on what it does:

- **Controller sticks:** a deadzone for each stick, which stops a drifting stick.
- **Mouse as the camera** (middle mouse button or F7 captures the mouse and drives the right stick):
  - sensitivity;
  - vertical speed;
  - the response curve;
  - the minimum tilt, so slow movement is not lost in the game's own deadzone;
  - the maximum speed;
  - smoothing;
  - how soon the camera stops after the mouse does.
- **Keyboard:**
  - how far the sticks tilt while **Slow Movement** is held;
  - how long a key takes to tilt a stick fully;
  - how long a key takes to press L2 or R2 fully, for racing games.
- **Graphics:** the shader cache, on or off.
- **Sharing:** **Export Settings** saves the game's keys and every setting as one file, and **Import Settings** applies a file someone shared. Post a setup that works for a game, or take one from a friend.
- **Reset Advanced Settings** brings back the engine's defaults.

**Engine versions:** **Settings → Engine** lists the engine builds published with this project's releases. Download one (it is checked before use) and choose it for every game or for one game only; a game unlocked with another engine offers **Update and Play**. **Engine Folder** uses an engine you built yourself. A game's options show which engine unlocked it.

**Crash reports:** when a game stops on an error, **Export Report** saves the log, macOS's crash report and the game's settings in one file, and **Open Issue** opens a pre-filled GitHub issue (your name, email and sign-in tokens are removed first). **Detailed logging (trace)** in a game's settings records more for a hard bug.

### Trophies

![The trophy list of Hollow Knight: Silksong](docs/screenshots/launcher-trophies.jpg)

<sub>The progress in this screenshot is sample data.</sub>

When a game earns a trophy while you play, a card drops in at the top of the screen, over the game and in full screen too, with the trophy's icon, name and grade and a sound. It never takes the keyboard or the mouse from the game.

![A trophy card over the game](docs/screenshots/launcher-trophy-banner.jpg)

<sub>The card as the launcher draws it, over a Silksong screenshot.</sub>

Every trophy is kept and listed as on the console:

- The **percentage**, weighted by grade as on the PS5, and the count of **platinum, gold, silver and bronze** trophies earned.
- Every trophy with its **icon, name, description, grade** and the **day and time you earned it**. Trophies you have not earned yet are greyed out.
- **Hidden** trophies stay hidden until you earn them. **Show** (△, or a click on the row) reveals the focused one for this look at the list; **Settings → Behaviour → Always Show Hidden Trophies** reveals them all.
- Trophies that count something (*Acquire all Tools*, *Bind all Silk Skills*) show **how far you are**, such as 23/51.

The list, the texts and the icons come from the game's own trophy package (`sce_sys/trophy2`), in the game's language when it has one. The engine records each unlock in the installed game, and the list updates when the game closes. Unlocking a game again keeps them.

### Library and settings

| Game library | Settings |
|---|---|
| ![Game library](docs/screenshots/launcher-library.jpg) | ![Settings](docs/screenshots/launcher-settings.jpg) |

The **library** button shows every game as a grid. **Settings** hold:

- **Appearance:** the theme, the accent color, and the background (the theme animation, your own picture or a looping video). Also the selected game's artwork behind the home screen, animations and **Full Screen** (on at the first start, then as you left it; F11 or ⌃⌘F).
  - **Theme Studio:** make your own theme: the motion, its color, highlight and lightness, the accent, a picture or video behind it and menu music. Every change shows behind the panel at once. **Save as a file** makes one `.anyps5theme` to give to anyone; opening one in Finder installs it.
  - **Themes:** the built-in themes, yours, and the ones people share on the **AnyPS5 Hub** ([`hub/`](hub/README.md)), installed with one press. **Share on the Hub** saves your theme and opens the page to send it. The phone wears the launcher's theme too.
- **Library:** the games folder and scanning it again.
- **Language:** Türkçe or English.
- **Behaviour:** the profile name, the volume of the interface sounds and of the selected game's theme song (the PS5 plays it while a game is selected, for games whose dump has one), hiding the launcher while a game runs, always showing hidden trophies, Discord, update checks, and installing Rosetta if it is missing. Also:
  - **Clips:** the launcher keeps the last 30 seconds, 1, 3 or 5 minutes of the game playing, picture and sound, in memory only (the row shows how much); **Create** on a DualSense (Share on a DualShock 4 or an Xbox pad), **⌥F12** or Create on the phone saves them as an MP4 beside the screenshots. Create held takes a screenshot. macOS asks once for the screen recording permission.
  - **Pause Game When Opening the Menu:** PS over a game raises the quick menu (Resume, Game Settings, Close Game) and first presses Options on player 1 in the game, whether a controller, the keyboard or a phone is player 1; PS held asks **Close game?**, and held in the launcher it opens **Quit AnyPS5**.
- **Shortcuts:** Home, Quick Menu, Screenshot, Save Clip, Full Screen and the previous / next section on any key and any controller button or chord, pressed or held; clashes are refused and **Reset to Defaults** brings them back. With a pad a setting's ‹ › value changes only after ✕, and the hints show the pad's glyphs or the keys, whichever you used last.
  - **Save Sync:** each game's saves and trophies stay the same on your other Macs through iCloud Drive or any folder you choose (Dropbox, a shared or USB folder). Newer saves from another Mac come down before a game starts, and the Mac's go up when it ends; whatever is replaced is backed up first.
- **Fonts:** games that ask for the console's system fonts get them without any setup; some (Astro's Playroom) stop at start without them. The app carries the Noto substitutes for Latin, italics, typewriter, Thai and Arabic (5.5 MB, SIL Open Font License 1.1). Japanese, Chinese and Korean (Noto Sans CJK, 105 MB once) download from Noto's own release the first time a game needs them, checked against their SHA-256 before use: a game started in one of those languages waits for them on its start screen, and any other game that asks for them while it runs (the engine logs every font set it opens) gets them for its next start. The page shows which font games get for each script and where it comes from, and holds **Your Fonts Folder**: the console's own fonts, if you have them, which come before the launcher's.
- **Advanced:** where F12 screenshots go (`~/Pictures/AnyPS5` unless you pick another folder).
- **Links:** `anyps5://game/<title ID>` selects a game and `anyps5://play/<title ID>` starts it (Copy Link in a game's settings); a folder opened with AnyPS5 from Finder can become the games folder.
- **About:** the app and toolkit versions, **Check for Updates**, and **Update to …** when a newer AnyPS5 is out: the launcher downloads it, takes its place and opens again.

### Broadcasting

Like the console's **Broadcast**, the launcher streams the game playing live to **Twitch**, **YouTube** or any **RTMP / RTMPS** server (another service's ingest address, or your own nginx-rtmp or MediaMTX).

- **Set it up once** in **Settings → Broadcasting:** the service, the stream key (typed in a hidden field or pasted from the clipboard; **Get your key** opens the service's page for it), the quality (**720p60 · 3 Mbit/s**, **1080p30 · 4.5 Mbit/s** or **1080p60 · 6 Mbit/s**), the microphone for commentary with its own level, the **LIVE** badge and the link viewers watch on.
- **Go live** from the game's panel while it plays (PS, then **⋯** / △ on the running game), or **Go Live** on the phone's launcher screen. The panel then shows how long you have been on air, the bit rate going out, dropped frames, **Copy viewer link**, the microphone and **Stop broadcast**; the broadcast also ends with the game.
- The game's window and sound are captured as for clips (macOS asks once for the screen recording permission) and encoded on the Mac's media engine: H.264 High with a key frame every two seconds and no B-frames, AAC at 48 kHz stereo 160 kbit/s, as Twitch and YouTube ask. When the upload cannot keep up, frames are dropped instead of the stream falling behind, and a lost connection is made again by itself.
- The stream key is kept in `~/Library/Application Support/AnyPS5/Broadcast/keys.json`, readable by your user only, rather than the Keychain: the app is signed ad hoc, so the Keychain would ask for it again after every update. The launcher never shows the key in full. The LIVE badge is drawn over the game for you and is not part of the broadcast.

### Play from Steam

**Settings → Steam → Add to Steam** puts AnyPS5 in your Steam library as a non-Steam game, tagged **AnyPS5**, with artwork drawn in the Cosmic look: the portrait cover, the wide capsule, the hero banner, the logo and the icon. Start it from Steam or Big Picture like any other game; Steam Input and the overlay apply to it.

- **Add My Games Too** gives every unlocked game its own entry with its own art (from the dump's `pic0` and `icon0`), started with `--steam --play <title ID>`: the game opens at once, and the launcher quits when it ends so Steam sees it end (a crash keeps it open on the report). A launcher already open takes the request instead of a second one starting.
- The shortcuts go into `~/Library/Application Support/Steam/userdata/<account>/config/shortcuts.vdf` of the account signed in last (a choice when there are several), the pictures into `config/grid`, named after each shortcut's ID (the CRC-32 of the quoted program and the name with the top bit set, written into the shortcut so Steam uses it). **Open Full Screen from Steam** adds `--fullscreen`.
- Steam writes its own copy of the file when it quits, so the launcher writes only while Steam is closed: with Steam open it offers **Quit Steam and Add**. The file is read and written back to the byte with only AnyPS5's entries changed, after a copy to `shortcuts.vdf.anyps5-backup`; **Remove from Steam** takes out only AnyPS5's entries and their pictures. The Windows and Linux launcher ([AnyPS5-Desktop](https://github.com/AnyTogether/AnyLauncher-Port)) does the same, for the Steam Deck too.

### Controllers & troubleshooting

The launcher reads every controller macOS has a profile for (DualSense, DualShock 4, Xbox, Switch Pro and MFi pads, over USB or Bluetooth) and, with its own USB reader, the **DualShock 3**, which macOS does not support (plug it in with a cable and press PS; it cannot be paired over Bluetooth on a Mac). Pads can come and go at any time, several at once; the one used last is **Player 1** (the launcher's vibration, Player 1's light). In games the engine reads them through SDL.

- **Settings → Controllers** lists the pads with their family, USB or Bluetooth and battery (and charging), and offers **Test Buttons and Sticks** (a live drawing of the pad: every button, both sticks inside the dead zone's ring, the triggers; hold ○ / B or press Esc to leave), **Test Vibration**, **Light Bar** (the theme's accent or a colour, DualSense and DualShock 4), **Confirm Button** (○ confirms and ✕ goes back, as on Japanese consoles; the hints follow) and **Stick Dead Zone** (in the launcher, and in every game that sets no dead zone of its own). A controller nearly out of battery shows in the top bar.
- The **troubleshooter** under it says what it sees: no controller at all (a data cable, how to pair each family over Bluetooth), a HID game controller macOS lists without a layout, a low battery, Steam running (its controller support can turn the pad into a mouse), and that the DualShock 3 works over USB only.
- Every connect and disconnect is logged with the pad's family, connection and driver; the game's log gets the controllers at each start, and crash reports (**Export Report**, the issue form) carry them with the recent connects and disconnects. The Windows and Linux launcher ([AnyPS5-Desktop](https://github.com/AnyTogether/AnyLauncher-Port)) has the same screen, reading pads through SDL2 with a troubleshooter for Steam, DS4Windows, DualSenseX, HidHide and Linux permissions.

### Getting around

The launcher works like a console: the arrow keys, Return (✕) and Esc (○), `O` (△) for options, `Q` / `E` (L1 / R1) for the previous or next game, also inside a game's panels, or a game controller (D-pad, ✕, ○, △, L1, R1; its PS button brings the launcher in front of the game, and back). The mouse and trackpad work too: click a tile, double-click to play, scroll through the row.

### Your phone as a controller

**AnyPS5 Remote** ([`mobile/`](mobile/README.md), Android and iOS) turns a phone on the same Wi-Fi, or on a cable, into a DualSense. It finds the launcher by itself; the first time, the Mac asks once and both show the same code.

- **On a cable, no Wi-Fi needed:** plug an iPhone into the Mac and it connects through the cable by itself. An Android phone does the same with USB debugging on and [adb](https://developer.android.com/tools/releases/platform-tools) installed on the Mac.
- **Remote Play:** turn it on in the phone's About sheet and the game plays on the phone's screen behind the pad, picture and sound. It is off by default: the phone stays the controller alone. The Mac needs the screen recording permission for it.

- **Launcher on the phone:** the Mac's games with their icons over the selected one's background. Picking a game on the phone picks it on the Mac too; **Play**, **Back to Game** and **Close Game** work from the phone, and the arrows, ✕, ○ and ≡ move around the launcher's own screen.
- **The pad:** both sticks, ✕ ○ □ △, L1 R1, L2 R2, the D-pad, Options and the touchpad (slide to move the touch, tap to click), any of them at once, with the latency shown. It takes over as soon as a game starts.
- **Up to four players:** four phones, and the Mac's game controllers, are four DualSenses for games with local co-op. Each becomes the next player the first time a button is pressed on it in the game; the launcher shows every connected phone with its player number. A new phone can pair while others are connected.
- **What the Mac is doing:** while a game is unlocked, updated or started, the phone shows the step, a bar that fills and the time it has taken.
- **Trophies:** a trophy earned in the game drops in at the top of the phone too, and the phone buzzes.
- **PS** takes the phone back to the launcher and brings the launcher in front of the game on the Mac.
- **Create** (◉, left of the touchpad) saves the last seconds of the game as a clip, as on the DualSense.
- **Go Live / End Broadcast** beside **Back to Game** starts and stops the launcher's [broadcast](#broadcasting) of the game playing.
- **Rumble, trigger effects and light:** the game's vibration on the phone, a pulse on L2/R2 where the trigger would push back, and the pad glowing with the game's light bar colour.
- **Motion:** the phone's accelerometer and gyroscope are the DualSense's motion sensors, for games that tilt or aim with them.
- **Your own layout, per game:** the lock on the pad opens an editor to move, size, fade or hide any control, or make it a toggle or turbo button; the Mac keeps it with the game's settings.
- The phone uses the launcher's language (English by default, or Turkish).

#### No app: play from a browser

**Settings → Advanced → Phones → Show QR code**: any phone on the same Wi-Fi scans it with its camera and its browser becomes the pad, nothing to install. Both sticks (they come to the thumb), the D-pad, ✕ ○ □ △, L1 R1 L2 R2, Options, Create, PS and the touchpad, with the game's light bar beside the touchpad, the DualSense's player lights under it, and vibration where the browser has it (Android). A browser goes through the same pairing card, seats (players 2 to 4 after the first) and pad path as the phone app.

- The QR code's link works once and for two minutes; it turns into a cookie for that browser alone. The page is served on the Mac's local network address only, to the local network only, and refuses other sites and hosts; too many requests or wrong codes are slowed down.
- The server runs only while the QR code is shown and while browsers it let in are connected (two more minutes for a reload or a locked screen), or always with **Keep browser play on**. Turning **Play from a browser** off stops it.
- Plain HTTP on the local network: tilt (motion sensors), keeping the screen awake and vibration on iPhones need HTTPS or Safari support the page does not have. For those, use the app.
- The Windows and Linux launcher ([AnyPS5-Desktop](https://github.com/AnyTogether/AnyLauncher-Port)) serves the same page ([`tools/macos/launcher/BrowserPad/index.html`](tools/macos/launcher/BrowserPad/index.html)).

| The QR code on the Mac | The pad in a phone's browser |
|---|---|
| ![Play from a browser on the Mac](docs/screenshots/browser-play-qr.jpg) | ![The browser pad](docs/screenshots/browser-pad.jpg) |

| The launcher, with the phone in the corner | Silksong played on the phone |
|---|---|
| ![The launcher with the phone connected](docs/screenshots/phone-live-launcher.jpg) | ![Silksong played with the phone](docs/screenshots/phone-live-silksong.jpg) |

<p align="center"><a href="https://github.com/AnyTogether/AnyPS5-ARM/raw/main/docs/videos/phone-demo.mp4"><b>▶ Video: the launcher and Silksong driven from the phone</b></a> (1:22, the phone's own screen in the corner, in sync)</p>

| Launcher mode | The pad |
|---|---|
| ![The phone in launcher mode](docs/screenshots/phone-launcher.jpg) | ![The phone pad](docs/screenshots/phone-pad.jpg) |

[⬇ Download the Android app](https://github.com/AnyTogether/AnyPS5-ARM/releases/latest/download/AnyPS5-Remote.apk) (APK; on the phone, allow installing from your browser when asked).

**On an iPhone** (iOS 15 or newer), install [AnyPS5-Remote.ipa](https://github.com/AnyTogether/AnyPS5-ARM/releases/latest/download/AnyPS5-Remote.ipa) with [AltStore](https://altstore.io) (or SideStore, or [Sideloadly](https://sideloadly.io) from a computer): it signs the app with your own Apple ID as it installs it. With a free Apple ID the app has to be refreshed every 7 days, which AltStore does by itself.

Games unlocked before phone support need **Update and Play** once, so they carry the engine that reads the phone.

### AnyTogether

[AnyTogether](https://anytogether.kodla.agency) is the launcher's online home: friends, profiles, messages, parties and voice. It is optional; signed out, the launcher works exactly as before. The server is open source ([AnyTogether](https://github.com/AnyTogether/AnyTogether), MIT) and anyone can run their own.

- **Sign-in:** Settings → AnyTogether, with a code sent to your email, or with one tap on your phone if it is already signed in (and the other way round). No password, no sign-up form. On the website you can also add a passkey.
- **Friends:** add someone by their handle and see who is online and what they are playing.
- **Play time and trophies:** each session and trophy goes to your account, so friends see them on your profile and hear of a new trophy as you earn it.
- **Profiles**: yours and your friends': games, hours, trophies and points, and the latest trophies with how rare they are. Change your name, bio, country and handle, and who sees your games, trophies, friends and online status.
- **Messages**: chats with a friend and group chats, also on the phone and the website.
- **Parties and voice**: up to eight friends together, with voice that goes straight between you; push-to-talk on ⌥V works over a game, and a ring shows who is speaking. The leader invites, removes and hands the lead over.
- **Join a friend's game**: friends see the game you play as joinable and can start the same one, checked against your game's version first.
- **Another server**: Settings → AnyTogether → Server, for a self-hosted AnyTogether.
- **Discord status:** the game you play shows on Discord (Settings → Behaviour), with or without AnyTogether.
- **Share play:** while you play, start Share play from the Friends panel. Friends watch in their browser, on the phone or in their launcher, and you can let one play as player 2, 3 or 4: local co-op together from anywhere. Your controller stays player 1.
- **Activity, leaderboards and notifications:** what friends unlock and play with reactions, boards per game and overall, and a bell in the top bar.
- **Theme Hub:** Settings → Appearance → Themes lists the themes people share on AnyTogether; Share on the Hub uploads yours.
- **How did it run?** After a session, one tap sends a compatibility report for the [compatibility list](https://anytogether.kodla.agency/compatibility).

| A friend's profile | Friends |
|---|---|
| ![A friend's profile with games, trophies and activity](docs/screenshots/launcher-profile.jpg) | ![The friends panel](docs/screenshots/launcher-friends.jpg) |
| **Activity** | **Messages** |
| ![Friends' activity with reactions](docs/screenshots/launcher-activity.jpg) | ![A conversation with a friend](docs/screenshots/launcher-messages.jpg) |
| **Party with voice** | **Share play** |
| ![A party in voice, one friend speaking](docs/screenshots/launcher-party.jpg) | ![Sharing a game with two friends](docs/screenshots/launcher-shareplay.jpg) |
| **Leaderboard** | **Notifications** |
| ![A game's leaderboard](docs/screenshots/launcher-leaderboard.jpg) | ![The notifications list](docs/screenshots/launcher-notifications.jpg) |
| **Themes from the Hub** | |
| ![Themes people share on the Hub](docs/screenshots/launcher-hub.jpg) | |

<sub>The people, messages and numbers in these screenshots are made up.</sub>

## Games on a Mac

| Hollow Knight: Silksong | Plants vs. Zombies: Replanted | Dreaming Sarah | AnyPS5 Breakout |
|---|---|---|---|
| ![Silksong](docs/games/img/silksong-120-moss.jpg) | ![PvZ Replanted](docs/games/img/pvz-ingame.jpg) | ![Dreaming Sarah](docs/games/img/dreaming-sarah.jpg) | ![AnyPS5 Breakout](docs/games/img/breakout.jpg) |
| **120 fps, playable** | opening screens at 60 fps, work in progress | 60 fps, playable | 60 fps, test title |

**[Game status notebook →](docs/games/README.md)** ([Türkçe](docs/games/tr/README.md)) one page per game with screenshots, the steps behind it and technical details: DOOM (homebrew) plays too, Stray plays its first chapter, at a low frame rate (~12 FPS) for now, and Minecraft gets into a world.

<sub>MacBook Pro M3 Pro, macOS 26.6.2. Silksong is unlocked and started from AnyPS5.app; PvZ was converted by hand and has not been tried in it yet.</sub>

## Status

[![libraries](https://boykopovar.github.io/AnyPS5/badge-libraries.svg)](https://boykopovar.github.io/AnyPS5/progress.html) [![shaders](https://boykopovar.github.io/AnyPS5/badge-shaders.svg)](https://boykopovar.github.io/AnyPS5/progress.html)

[![progress map](https://boykopovar.github.io/AnyPS5/progress.svg)](https://boykopovar.github.io/AnyPS5/progress.html)

[Progress history](https://boykopovar.github.io/AnyPS5/history.html)

Unsupported or unexpected states strictly throw `std::runtime_error`. `what()` is printed to stderr and the process terminates.

The [shader recompiler](core/shader/recompiler/Recompiler.cpp) successfully produces SPIR-V (validated via [Spirv-Tools](3rdparty/SPIRV-Tools) when built with `ANYPS5_ENABLE_SPIRV_TOOLS`).

## Compatibility

[Tested games and their frame rates](docs/user/COMPATIBILITY.md)

Per-game status and test reports live in the [Game bring-up](https://github.com/boykopovar/AnyPS5/discussions/categories/game-bring-up) discussions, one thread per title.

## About

AnyPS5-ARM is the macOS port of [AnyPS5](https://github.com/boykopovar/AnyPS5). AnyPS5 is not an emulator: its relinker turns a PS5 executable into a native program, and its system libraries are reimplemented as ordinary shared libraries the program links against. On Apple silicon:

- **CPU:** the game's x86-64 code runs under **Rosetta 2**. A [native arm64 mode](https://github.com/AnyTogether/AnyPS5-ARM/blob/native-arm64/docs/dev/NATIVE_ARM64.md) without Rosetta is in development on the `native-arm64` branch.
- **Executable:** the relinker writes a **Mach-O** executable.
- **Graphics:** the PS5 graphics driver runs on **Vulkan through MoltenVK**, which runs on Metal.
- **Distribution:** the result is a normal **`.app`** you open from Finder.

[Building from source](docs/user/GUIDE.md#building-from-source) · [macOS port changes](docs/dev/MACOS_PORT.md) · [Input mapping](docs/user/INPUT_MAPPING.md) · [Technical debt](docs/dev/TechnicalDebt.md)

Built on [boykopovar/AnyPS5](https://github.com/boykopovar/AnyPS5) and the community macOS port [mugurc/AnyPS5 `macos-port`](https://github.com/mugurc/AnyPS5/tree/macos-port).

## Branches

Each branch is its own project, with its own README:

| Branch | What it holds |
|---|---|
| [`main`](https://github.com/AnyTogether/AnyPS5-ARM/tree/main) | The whole project: the engine, the launcher and the phone app. Releases are made from it. |
| [`launcher`](https://github.com/AnyTogether/AnyPS5-ARM/tree/launcher) | The launcher (AnyPS5.app) only. |
| [`mobile-controller`](https://github.com/AnyTogether/AnyPS5-ARM/tree/mobile-controller) | The phone app (AnyPS5 Remote) only. |
| [`rosetta`](https://github.com/AnyTogether/AnyPS5-ARM/tree/rosetta) | The engine only, the way it runs today: x86-64 code under Rosetta 2. |
| [`native-arm64`](https://github.com/AnyTogether/AnyPS5-ARM/tree/native-arm64) | The engine running games as native arm64 code, without Rosetta (experimental). |

## Credits

**The core**

- **[AnyPS5](https://github.com/boykopovar/AnyPS5) by boykopovar** is where the core comes from: the relinker that turns a PS5 executable into a native program and the reimplemented system libraries. AnyPS5-ARM is its port to Apple silicon Macs, and every engine feature here starts from that work.
- **[mugurc's community macOS port](https://github.com/mugurc/AnyPS5/tree/macos-port)** of AnyPS5 is the port AnyPS5-ARM builds on.
- **[MoltenVK](https://github.com/KhronosGroup/MoltenVK)** (Khronos, Apache-2.0) runs the PS5 graphics driver's Vulkan on Metal, and **[SDL](https://github.com/libsdl-org/SDL)** (zlib) reads the controllers in games and in AnyLauncher Port.

**Online play**

- **The online design comes from [AnyPlay](https://github.com/anyplaynet).** Our bridge between the engine and the launcher follows AnyPlay's bridge spec ([anyplaynet/network](https://github.com/anyplaynet/network/blob/main/spec/bridge-protocol.md), MIT/Apache-2.0): the frame header, the message numbering, the virtual LAN range and the A/B/C screening of games come from it. Stream P2P sockets over the bridge follow the approach of AnyPlay's engine bridge ([anyplaynet/AnyPS5](https://github.com/anyplaynet/AnyPS5), GPL-2.0).
- **Ideas AnyPlay shipped first** ([anyplaynet/launcher](https://github.com/anyplaynet/launcher), [anyplaynet/cloud](https://github.com/anyplaynet/cloud)): "Try anyway" on a Play Together version mismatch, retiring old launchers with "Update required", asking before leave party / remove friend and similar actions, the noise suppression switch, the public profile switch and the compatibility filters.
- **A phone browser as a controller via a QR code** comes from [LudusCtrl](https://github.com/parl0v/ludusctrl)'s browser client by Josip Parlov (@parl0v), shipped in AnyPlay.

Our code is written independently; where we followed someone's design or idea, it is named here.

## Disclaimer

This project is intended for interoperability, research, preservation and compatibility purposes. It does not include, distribute or require copyrighted software, firmware, cryptographic keys or proprietary libraries. Users are responsible for obtaining and using any binaries with this project in accordance with applicable laws and their license terms.

AnyPS5 is an independent project and is not affiliated with, authorized or endorsed by Sony Interactive Entertainment. "PlayStation" and "PS5" are trademarks of Sony Interactive Entertainment Inc.

## License

GNU General Public License version 2 only.
