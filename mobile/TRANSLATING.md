# Translating the phone app

AnyPS5 Remote reads every text it shows from one file per language in
[`assets/l10n`](assets/l10n): `en.json` is English, the source, and `tr.json` is Turkish. They
are the same kind of file as the launchers', with the same keys wherever the text is the same.
The guide for translating every AnyPS5 app, this one included, is
[TRANSLATING.md in AnyLauncher-Port](https://github.com/AnyTogether/AnyLauncher-Port/blob/main/TRANSLATING.md);
a hosted Weblate project is coming.

In short: copy `en.json` to your language's code (`de.json`, `pt-BR.json`), translate the text
after each colon (`languageName` is the language's own name), keep the keys and the
placeholders (`%@`, `%d`, `%%`, `%1$@`). A text you leave out shows in English. The phone uses
the language the launcher it is connected to uses, when there is a file for it here.

The phone has no Languages folder to try a file in: build the app with the file in
`assets/l10n` (`flutter run`). `dart run tool/check_translations.dart` here checks the files the
way CI does and shows how much of each language is translated.
