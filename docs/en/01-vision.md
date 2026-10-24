# 1. Vision

## One sentence

AnyTogether turns the AnyPS5 launcher from a program on one computer into a place where players meet:
your profile and trophies follow you, your friends see what you play, you talk while you play,
a friend can watch your game wherever they are and play along on a second pad, and you can join
each other's games.

## Why now

The launcher already holds most of what an online profile needs, and it holds it on one computer
only. On macOS that is AnyPS5-ARM's launcher; on Windows and Linux,
[AnyPS5-Desktop](https://github.com/utkuhalis/AnyPS5-Desktop), its port, which keeps the same
things per game:

| Already in AnyPS5 | Where it lives today | What AnyTogether adds |
|---|---|---|
| Play time and last played per game | `Preferences.lastPlayed`, play time in the launcher | A game library across all your computers, visible to friends |
| Trophies, read from each game and noticed live while playing | `Trophies.swift`, the trophy banner, the phone's trophy card | Trophy history with dates, rarity across all players, leaderboards |
| The game playing right now | Discord presence (`DiscordPresence.swift`) | Presence for friends inside AnyPS5, without Discord |
| Themes made in the Theme Studio | `hub/` folder in the GitHub repository, shared through an issue | The Theme Hub on AnyTogether: upload from the launcher, likes, downloads (built); the theme on your profile (planned) |
| Remote Play: the game's picture and sound to a phone on the same network | `RemotePlay.swift`, `StreamEncoder.swift`, the phone's decoders | The game to a friend over the internet, to watch, and to play along as player 2, 3 or 4 when the host hands them a pad (share play) |
| Up to four phones as four pads, on one computer | `RemoteServer` bridges, `ANYPS5_REMOTE_PAD_2..4` | Online play: a friend runs the same game on their own computer and joins yours |
| Clips and screenshots | The gallery | Highlights in the activity feed (opt-in) |

## Who it is for

1. **The AnyPS5 player** on a Mac, a Windows PC or a Linux machine, with the phone app as controller or second screen. Most of
   AnyTogether happens inside the launcher and the phone app; the website is the third door.
2. **Their friends**, who may not have AnyPS5 at all. A friend can open a profile on the web,
   join a party's voice from the browser or the phone app, and watch a share play session in the
   browser, playing along with a controller or the keyboard when the host hands them a pad.
3. **The community**: theme makers, people who report which games run, people who climb the
   leaderboards, people looking for someone to play a game with.

## What it is

The twelve features announced on [anytogether.kodla.agency](https://anytogether.kodla.agency):

1. **Profiles**: a gamer card, avatar, bio and stats, in your own theme.
2. **Trophies**: every trophy earned, with rarity, date and progress.
3. **Voice chat**: party voice while you play, in any game.
4. **Parties**: start a party, invite friends, jump into the same game.
5. **Friends**: add friends, see who is online and what they are playing.
6. **Messages**: direct and group chats, in the launcher, on the phone and on the web.
7. **Game library**: what you played, for how long and when, synced.
8. **Activity feed**: trophies, sessions and highlights from friends.
9. **Themes**: your profile and launcher looking the way you want, shared with everyone.
10. **Downloads**: the official launcher, phone app, updates and tools.
11. **Share play**: stream your session; friends watch and talk, and the ones you hand a pad play
    as player 2, 3 or 4. Your own pad stays player 1.
12. **Leaderboards**: trophies and play time against friends and the world.

Beside them, built along the way: **notifications** (a bell, browser push, a mail digest),
**finding players** (a looking-for-group board, parties and share plays listed in public, game
hubs, people who play the same games) and the **compatibility list** (how far each game gets, per
platform, from players' reports).

[Features](03-features.md) describes each one in full.

## Principles

1. **The launcher never needs AnyTogether.** Everything works offline and signed out, as today.
   Signing in adds things; it never takes anything away or blocks playing. If the server is down,
   the launcher queues what it would have sent and plays on.
2. **One account, every door.** The launcher on macOS, Windows and Linux, the phone app and the
   website are the same account and the same data. A message read on the phone is read in the
   launcher too. No platform comes second: the Windows/Linux launcher gets every feature the macOS
   one gets (see [Platforms](12-platforms.md)).
3. **Directly between players.** Voice, share play and online game traffic go peer-to-peer,
   encrypted, from one player's machine to the other's. The server introduces players, keeps what must be
   kept and relays only when a direct path is impossible.
4. **One tap to sign in.** No sign-up form, no password: an email code, a passkey, the phone
   already signed in, or Apple, Google and Discord.
5. **Private by default, social by choice.** A new profile shows only your name and avatar to
   strangers. Play time, library, trophies and activity are visible to friends until you open
   them to everyone. Each item can be hidden.
6. **It looks like AnyPS5.** The same console-style interface, the same themes. A profile wears
   the theme its owner made in the Theme Studio.
7. **No game files, ever.** AnyTogether never stores, sends or links game dumps, keys, firmware or
   anything that would let someone play a game they do not own. Downloads are AnyPS5's own
   software and what the community makes (themes, layouts). See
   [Security, privacy and rules](08-security-privacy.md).
8. **Small, well-understood parts.** Proven open-source pieces (PostgreSQL, Valkey, WebRTC,
   coturn) rather than a stack of hosted services; everything runs on our own server behind
   Cloudflare, and could move to another. The code is public and MIT licensed, and anyone can run
   their own AnyTogether with one Docker Compose file (see [Infrastructure](09-infrastructure.md)).
9. **Measured latency.** Voice and share play are judged by numbers (mouth-to-ear delay,
   glass-to-glass delay, input round trip), the way Remote Play's latency is shown today.

## What it is not

- **Not a store and not a place for games.** No game downloads, no dumps, no "where to get"
  links, no trading of accounts or keys.
- **Not a replacement for PSN.** Trophies come from what AnyPS5 reads in the user's own games;
  they are AnyTogether trophies, not PlayStation ones, and are never sent to Sony.
- **Not required for co-op on one computer.** Local co-op with phones keeps working as it does.
- **Not a general social network.** No public posting outside games, no follower counts for
  their own sake.
- **Not a cloud gaming service.** Share play streams *your* computer's game to *your* friend,
  directly between you, and a friend's pad comes back the same way; the game runs only on your
  computer. The server only introduces you and relays when a direct path is impossible. It never
  runs games.

## How we will know it works

| Goal | Measure |
|---|---|
| Players sign in | Share of active launchers signed in, by version |
| Profiles feel alive | Players with at least one friend; profiles opened per week |
| Voice is good enough to keep using | Mouth-to-ear delay under 200 ms on the same continent; party length |
| Share play feels local | Glass-to-glass delay under 120 ms within ~1000 km |
| Nothing breaks offline | Zero launcher regressions with the server unreachable (a test, every release) |
| Rules hold | Reports handled within 48 h; zero game files ever stored |
