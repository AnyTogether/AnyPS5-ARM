# Translating the Mac launcher

The Mac launcher (AnyPS5.app) reads every text it shows from one file per language in this
folder: `en.json` is English, `tr.json` is Turkish. They are the same kind of file as the
Windows/Linux launcher's, in
[AnyPS5-Desktop's `assets/l10n`](https://github.com/AnyTogether/AnyLauncher-Port/tree/main/assets/l10n),
and follow the same rules: its
[TRANSLATING.md](https://github.com/AnyTogether/AnyLauncher-Port/blob/main/TRANSLATING.md) is the
guide. In short:

- Copy `en.json`, name the copy after the language's code (`de.json`, `pt-BR.json`) and fill in
  `"@meta"`: the language's own `name` and the `consoleLanguage` number from the guide's table.
- Translate the text after each colon; keep the keys, the placeholders (`%@`, `%d`, `%%`, and
  `%1$@` to change their order) and the JSON quotes and commas.
- A text you leave out shows in English.

## The same keys on both launchers

A key means the same text on the Mac and on Windows/Linux, so a translation of one file carries
over to the other. Some texts say Mac where the other launcher says PC (`stepRelink`,
`themesOnMac`): translate each file's own English. Texts only the Mac launcher shows have keys of
their own here, and the other launcher's file has keys this one does not use. To start from the
other launcher's translation, copy its texts for the keys this `en.json` has, then fill in the
rest.

The Mac launcher also uses a few placeholders the other one does not, such as `%02d` (a number
with two digits) and `%.1f` (a number with one decimal): keep them as they are.

## Try it

Put your file in `~/Library/Application Support/AnyPS5/Languages` (create the folder if it is not
there) and open AnyPS5 again; then choose your language in **Settings › Language**. A file there
comes before the built-in one of the same code, so a changed `tr.json` can be tried the same way.
A text whose placeholders are not English's is shown in English instead, and a file that is not
valid JSON is left out.

## The check

`swift test` in `tools/macos/launcher` (the Mac launcher's CI job runs it) checks the files here:
every key of `en.json` is in `tr.json`, no file has a key English lacks, each text has English's
placeholders, and every key the launcher's code uses is in `en.json`. Other languages may leave
keys out; the check says how much of each is translated.
