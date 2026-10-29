# Translating the Mac launcher

The Mac launcher (AnyPS5.app) reads every text it shows from one file per language in this
folder: `en.json` is English, the source, and `tr.json` is Turkish. The guide for translating
every AnyPS5 app, this one included, is
[TRANSLATING.md in AnyLauncher-Port](https://github.com/AnyTogether/AnyLauncher-Port/blob/main/TRANSLATING.md).
A hosted Weblate project is coming, where several people can translate one language at once; the
files stay the same.

In short:

- Copy `en.json`, name the copy after the language's code (`de.json`, `pt-BR.json`,
  `zh-Hant.json`) and translate the text after each colon. `languageName` is the language's
  own name (`Deutsch`), as Settings lists it. The language games start in comes from the file's
  name, so nothing else goes in the file.
- Keep the keys, the placeholders (`%@`, `%d`, `%%`, `%1$@` to change their order, and this
  launcher's `%02d` and `%.1f`) and the JSON quotes and commas.
- A text you leave out shows in English.
- Try it: put the file in `~/Library/Application Support/AnyPS5/Languages` (create the folder
  if it is not there), open AnyPS5 again and choose the language in **Settings › Language**. A
  file there comes before the built-in one of the same code. A file from an older launcher, with
  an `"@meta"` part at the top, still works there; for the repository, use `languageName`.

## The same keys in every app

A key means the same text on the Mac, on Windows/Linux and on the phone, so a translation of one
file carries over to the others. Some texts say Mac where the other launcher says PC
(`stepRelink`, `themesOnMac`): translate each file's own English. Numbers follow macOS's
formatting for the language's code, so this launcher has no number texts.

## The check

`swift test --filter "LanguageCheckTests|LanguageFilesTests"` in `tools/macos/launcher` (the Mac
launcher's CI job runs all of `swift test`) checks the files here: one flat JSON object of texts
per file (no `"@meta"`), named by a language code, every key of `en.json` in `tr.json`, no key
English lacks, each text with English's placeholders, and every key the launcher's code uses in
`en.json`. Other languages may leave keys out; the check says how much of each is translated.
