import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The app's language files: one JSON object of texts by key per language in assets/l10n, named
/// by its code (de.json is German), the same format as the launchers' (TRANSLATING.md in
/// AnyLauncher-Port). English is the source: a text a language does not have is the English one,
/// and a key English lacks too is shown as itself.
///
/// Placeholders are the launchers' too: %@ a word or a name, %d a number, filled in order;
/// %1$@ names its argument, so a language can put them in another order; %% is a percent sign.
abstract final class L10n {
  static const folder = 'assets/l10n/';
  static const english = 'en';

  /// The key of a language's own name ("Türkçe"), translated like every other text.
  static const nameKey = 'languageName';

  /// Where the name was before the files were made for Weblate: {"@meta": {"name": ...}}. A file
  /// in that format is still read, its name taken from there.
  static const legacyMeta = '@meta';

  static Map<String, Map<String, String>> _texts = const {};

  /// The codes of the languages there are files for.
  static Iterable<String> get codes => _texts.keys;

  static bool has(String code) => _texts.containsKey(code);

  /// The texts of one file, null when it is not a JSON object. Values that are not texts are
  /// left out.
  static Map<String, String>? parse(String source) {
    final Object? json;
    try {
      json = jsonDecode(source);
    } on FormatException {
      return null;
    }
    if (json is! Map<String, Object?>) return null;
    final texts = <String, String>{
      for (final MapEntry(:key, :value) in json.entries)
        if (key != legacyMeta && value is String) key: value,
    };
    final about = json[legacyMeta];
    final name = about is Map<String, Object?> ? about['name'] : null;
    if (!texts.containsKey(nameKey) &&
        name is String &&
        name.trim().isNotEmpty) {
      texts[nameKey] = name.trim();
    }
    return texts;
  }

  /// Reads every assets/l10n/*.json in [bundle]'s manifest. A file that cannot be read is left
  /// out; with no files at all each text is its key.
  static Future<void> load({AssetBundle? bundle}) async {
    final assets = bundle ?? rootBundle;
    final texts = <String, Map<String, String>>{};
    try {
      for (final path in (await AssetManifest.loadFromAssetBundle(
        assets,
      )).listAssets()) {
        if (!path.startsWith(folder) || !path.endsWith('.json')) continue;
        final code = path.substring(
          folder.length,
          path.length - '.json'.length,
        );
        if (code.isEmpty || code.contains('/')) continue;
        final parsed = parse(await assets.loadString(path, cache: false));
        if (parsed == null) {
          debugPrint('[anyps5-remote] the language file $path is left out');
        } else {
          texts[code] = parsed;
        }
      }
    } on Object catch (error) {
      debugPrint('[anyps5-remote] the language files cannot be read: $error');
    }
    _texts = texts;
  }

  /// Reads the files in [directory] (the source tree's assets/l10n for the tests).
  static void loadFolder(Directory directory) {
    final texts = <String, Map<String, String>>{};
    for (final file in directory.listSync().whereType<File>()) {
      final name = file.uri.pathSegments.last;
      if (!name.endsWith('.json')) continue;
      final parsed = parse(file.readAsStringSync());
      if (parsed != null) {
        texts[name.substring(0, name.length - '.json'.length)] = parsed;
      }
    }
    _texts = texts;
  }

  /// The text of [key] in [code], English when the language has none, null when English has
  /// none either.
  static String? textOrNull(String code, String key) =>
      _texts[code]?[key] ?? _texts[english]?[key];

  static String text(String code, String key) => textOrNull(code, key) ?? key;

  /// The text of [key] in [code] with its placeholders filled from [arguments].
  static String format(String code, String key, List<Object?> arguments) =>
      fill(text(code, key), arguments);

  /// [template] with its %@ and %d filled in order, each %1$@ by its number, %% a percent sign.
  static String fill(String template, List<Object?> arguments) {
    final out = StringBuffer();
    var next = 0;
    for (var index = 0; index < template.length; index++) {
      final positional = _positional.matchAsPrefix(template, index);
      if (positional != null) {
        final at = int.parse(positional.group(1)!) - 1;
        if (at >= 0 && at < arguments.length) out.write(arguments[at]);
        index += positional.group(0)!.length - 1;
        continue;
      }
      final char = template[index];
      if (char == '%' && index + 1 < template.length) {
        final kind = template[index + 1];
        if (kind == '%') {
          out.write('%');
          index++;
          continue;
        }
        if (kind == '@' || kind == 'd') {
          if (next < arguments.length) out.write(arguments[next]);
          next++;
          index++;
          continue;
        }
      }
      out.write(char);
    }
    return out.toString();
  }

  static final _positional = RegExp(r'%(\d)\$([@d])');
}
