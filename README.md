# AnyTogether

**The online home of the AnyPS5 launchers** on macOS, Windows and Linux. Profiles, trophies,
friends, parties, voice chat, messages, share play, leaderboards, themes and downloads, at
[anytogether.kodla.agency](https://anytogether.kodla.agency). A kodla.agency project.

Players talk to each other directly (voice, share play and online game traffic go peer-to-peer,
encrypted); the server introduces them and keeps what must be kept. Signing in is one tap: an
email code, a passkey, the phone already signed in, or Apple, Google and Discord.

The code is public and MIT licensed:
[github.com/utkuhalis/AnyTogether](https://github.com/utkuhalis/AnyTogether), with a
[self-hosting guide](https://github.com/utkuhalis/AnyTogether/blob/main/docs/self-hosting.md) for
running your own. This branch holds the plan; each document says what is built (as of 2026-10-24)
and what is still planned, and [Roadmap](docs/en/10-roadmap.md) sums it up. Each document exists in
English and in Turkish.

**macOS, Windows ve Linux'taki AnyPS5 launcher'larının online evi.** Profiller, kupalar,
arkadaşlar, partiler, sesli sohbet, mesajlar, birlikte oynama, liderlik tabloları, temalar ve
indirmeler;
[anytogether.kodla.agency](https://anytogether.kodla.agency) adresinde. Bir kodla.agency projesi.

Oyuncular birbirleriyle doğrudan konuşur (ses, birlikte oynama ve çevrimiçi oyun trafiği şifreli
olarak oyuncudan oyuncuya gider); sunucu onları tanıştırır ve saklanması gerekeni saklar. Giriş tek
dokunuş: e-posta kodu, passkey, zaten giriş yapmış telefon ya da Apple, Google ve Discord.

Kod herkese açık ve MIT lisanslı:
[github.com/utkuhalis/AnyTogether](https://github.com/utkuhalis/AnyTogether); kendi sunucunu
kurmak için bir [kurulum rehberi](https://github.com/utkuhalis/AnyTogether/blob/main/docs/self-hosting.md)
de var. Bu branch planı tutar; her belge neyin yapıldığını (2026-10-24 itibarıyla) ve neyin hâlâ
planlandığını söyler, [Yol haritası](docs/tr/10-yol-haritasi.md) da özetini verir. Her belge
İngilizce ve Türkçe olarak duruyor.

| # | English | Türkçe | What it covers / Ne anlatıyor |
|---|---------|--------|-------------------------------|
| 1 | [Vision](docs/en/01-vision.md) | [Vizyon](docs/tr/01-vizyon.md) | What AnyTogether is, for whom, principles, what it is not |
| 2 | [Architecture](docs/en/02-architecture.md) | [Mimari](docs/tr/02-mimari.md) | The system, the services and the technologies, with the reasons for each choice |
| 3 | [Features](docs/en/03-features.md) | [Özellikler](docs/tr/03-ozellikler.md) | All twelve features: what the user sees, how each one works, what is built |
| 4 | [API](docs/en/04-api.md) | [API](docs/tr/04-api.md) | REST endpoints as built, the realtime gateway, one-tap sign-in and passkeys, calls, game sessions |
| 5 | [Data model](docs/en/05-data-model.md) | [Veri modeli](docs/tr/05-veri-modeli.md) | The database tables as built, the planned ones, how trophy rarity is counted |
| 6 | [Realtime, voice and share play](docs/en/06-realtime-voice-shareplay.md) | [Anlık iletişim, ses ve birlikte oynama](docs/tr/06-anlik-ses-birlikte-oynama.md) | Presence, messages, peer-to-peer voice, share play (watch only), the relay, online play |
| 7 | [Clients](docs/en/07-clients.md) | [İstemciler](docs/tr/07-istemciler.md) | The macOS launcher, AnyPS5-Desktop on Windows/Linux, the phone app and the website, with what each has |
| 8 | [Security, privacy and rules](docs/en/08-security-privacy.md) | [Güvenlik, gizlilik ve kurallar](docs/tr/08-guvenlik-gizlilik.md) | Accounts and tokens, KVKK/GDPR, moderation, what may never be shared |
| 9 | [Infrastructure](docs/en/09-infrastructure.md) | [Altyapı](docs/tr/09-altyapi.md) | Server layout, Cloudflare, deployment, backups, monitoring, costs, running your own |
| 10 | [Roadmap](docs/en/10-roadmap.md) | [Yol haritası](docs/tr/10-yol-haritasi.md) | Where it stands, then the phases, each with what ships and how we know it works |
| 11 | [Open questions](docs/en/11-open-questions.md) | [Açık sorular](docs/tr/11-acik-sorular.md) | The decisions made and the ones still to make |
| 12 | [Platforms](docs/en/12-platforms.md) | [Platformlar](docs/tr/12-platformlar.md) | macOS, Windows, Linux, phone, web: the shared contracts, what differs, the phone protocol |

AnyTogether: [github.com/utkuhalis/AnyTogether](https://github.com/utkuhalis/AnyTogether) (MIT) ·
AnyPS5 on macOS: [github.com/utkuhalis/AnyPS5-ARM](https://github.com/utkuhalis/AnyPS5-ARM) ·
AnyPS5 on Windows and Linux: [github.com/utkuhalis/AnyPS5-Desktop](https://github.com/utkuhalis/AnyPS5-Desktop)
