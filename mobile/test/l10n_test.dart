import 'dart:convert';
import 'dart:io';

import 'package:anyps5_remote/l10n.dart';
import 'package:anyps5_remote/media_strings.dart';
import 'package:anyps5_remote/social_strings.dart';
import 'package:anyps5_remote/strings.dart';
import 'package:anyps5_remote/together/storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/check_translations.dart';

/// An asset bundle of the given files and the manifest Flutter writes for them.
class _Bundle extends CachingAssetBundle {
  _Bundle(this.files);

  final Map<String, String> files;

  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.bin') {
      return const StandardMessageCodec().encodeMessage({
        for (final path in files.keys)
          path: [
            {'asset': path},
          ],
      })!;
    }
    final text = files[key];
    if (text == null) throw FlutterError('No asset $key');
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(text)));
  }
}

/// The phone app's texts come from assets/l10n, in the launchers' format.
void main() {
  tearDown(() => L10n.loadFolder(Directory('assets/l10n')));

  test('the files pass the launchers\' check, and the code has no texts of its own', () {
    final out = StringBuffer();
    expect(
      checkFolder(Directory('assets/l10n'), out),
      0,
      reason: out.toString(),
    );
    expect(out.toString(), contains('tr: 100.0 %'));
    expect(checkSources(Directory('lib')), isEmpty);
  });

  test('Turkish has every English text and no other', () {
    Map<String, Object?> file(String code) =>
        jsonDecode(File('assets/l10n/$code.json').readAsStringSync())
            as Map<String, Object?>;
    expect(file('tr').keys.toSet(), file('en').keys.toSet());
    expect(file('en')[L10n.nameKey], 'English');
    expect(file('tr')[L10n.nameKey], 'Türkçe');
  });

  test('every key the code looks up by name is in en.json', () {
    final english = jsonDecode(
      File('assets/l10n/en.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final pattern = RegExp(r"""(?:lookup|fill)\(\s*'([A-Za-z0-9_.]+)'""");
    final missing = <String>[];
    var found = 0;
    for (final file in Directory('lib').listSync().whereType<File>()) {
      for (final match in pattern.allMatches(file.readAsStringSync())) {
        found++;
        if (!english.containsKey(match.group(1))) missing.add(match.group(1)!);
      }
    }
    expect(found, greaterThan(500));
    expect(missing, isEmpty);
  });

  test('a new file is a new language; a text it lacks is the English one', () async {
    await L10n.load(
      bundle: _Bundle({
        'assets/l10n/en.json':
            '{"languageName": "English", "back": "Back", "found": "%@ found", '
            '"numberGroupSeparator": ",", "numberDecimalSeparator": "."}',
        'assets/l10n/de.json':
            '{"languageName": "Deutsch", "found": "%@ gefunden", '
            '"numberGroupSeparator": ".", "numberDecimalSeparator": ","}',
        'assets/l10n/fr.json': '{"back": ',
        'assets/icon.png': 'not a language',
      }),
    );
    expect(L10n.codes.toSet(), {'en', 'de'});
    final german = Strings.of('de');
    expect(german.language, 'de');
    expect(german.found('Mac'), 'Mac gefunden');
    expect(german.back, 'Back');
    expect(german.number(1234567), '1.234.567');
    expect(german.decimal(2.25, 1), '2,3');
    expect(
      Strings.of('fr'),
      Strings.english,
      reason: 'a broken file is left out',
    );
    expect(Strings.of('xx'), Strings.english);
    expect(Strings.of(null), Strings.english);
    expect(Strings.of('de'), Strings.of('de'));
  });

  test('a file in the old format still works, its name from "@meta"', () {
    final texts = L10n.parse(
      '{"@meta": {"name": "Deutsch", "consoleLanguage": 4}, "back": "Zurück"}',
    )!;
    expect(texts, {'back': 'Zurück', L10n.nameKey: 'Deutsch'});
    expect(L10n.parse('[1, 2]'), isNull);
    expect(L10n.parse('{"back": 7, "ok": "OK"}'), {'ok': 'OK'});
  });

  test('placeholders fill in order, by number, and %% is a percent sign', () {
    expect(L10n.fill('%@ and %@', ['a', 'b']), 'a and b');
    expect(L10n.fill(r'%2$@ ve %1$@', ['a', 'b']), 'b ve a');
    expect(L10n.fill('%d%%', [5]), '5%');
    expect(L10n.fill('%%%d', [5]), '%5');
    expect(L10n.fill('%@ missing', []), ' missing');
  });

  test('numbers, percentages and sizes follow the language', () {
    const usage = StorageUsage(
      used: 5 * 1024 * 1024 + 300000,
      limit: 100 * 1024 * 1024,
      saves: 0,
      media: 0,
    );
    expect(Strings.english.number(12345), '12,345');
    expect(Strings.turkish.number(12345), '12.345');
    expect(Strings.english.percent(80), '80%');
    expect(Strings.turkish.percent(80), '%80');
    expect(Strings.english.rarityPercent(0.012), '1.2%');
    expect(Strings.turkish.rarityPercent(0.012), '%1,2');
    expect(Strings.english.storageUsed(usage), '5.3 MB of 100 MB');
    expect(Strings.turkish.storageUsed(usage), '5,3 MB / 100 MB');
  });
}
