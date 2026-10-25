# AnyPS5 Hub

What the launcher's **Themes** screen offers. `themes.json` lists every shared theme, and each
one's file is in `themes/`.

## Sharing a theme

1. Make it in the launcher: **Settings → Theme Studio** (colors, motion, a picture or video, menu
   music).
2. Choose **Share on the Hub**. The launcher saves the `.anyps5theme` file and opens a new issue
   here; attach the file to it.
3. Once it is added to `themes.json` and `themes/`, every launcher sees it.

A theme file is a zip of `theme.json` and the files it names:

```json
{
  "id": "neon-nights",
  "name": "Neon Nights",
  "author": "AnyPS5",
  "version": 1,
  "style": 0,
  "deep": "#0A0014",
  "middle": "#4A0E6B",
  "bright": "#FF5EDB",
  "accent": "#FF4FD8",
  "background": "background.jpg",
  "music": "music.m4a"
}
```

`style` is the animated background (0 Cosmic, 1 Aurora, 2 Sunset, 3 Glass); `background` and `music` are
optional. Raise `version` when a theme changes, so launchers that have it offer the new one.
