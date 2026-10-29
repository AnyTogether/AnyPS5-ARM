// Checks the language files in assets/l10n and the code in lib (TRANSLATING.md in
// AnyLauncher-Port): dart run tool/check_translations.dart [assets/l10n [lib]]
//
// Every file is one flat JSON object of texts, as Weblate keeps monolingual JSON: no key en.json
// lacks, the same placeholders as English in each text, and the language's own name under
// "languageName". A text not translated yet is fine: the app shows the English one, and the check
// counts it. The code is checked too: no text chosen by comparing the language's code, and no
// Turkish words in it, since those belong in the files. A line that has to compare the code for
// something other than a text says so with the comment "// not a text".
//
// The same file is AnyLauncher-Port's and the phone app's (AnyPS5-ARM's mobile/tool); keep the two
// the same.
import 'dart:convert';
import 'dart:io';

/// The key of a language's own name ("Deutsch"), how Settings lists it.
const nameKey = 'languageName';

/// The object the files had before Weblate: {"@meta": {"name", "consoleLanguage"}}. The launchers
/// still read it from a file in the Languages folder; in the repository it is an error.
const legacyMeta = '@meta';

/// A file's name: a locale code as Weblate writes it, de, pt-BR, zh-Hant, es-419 (or pt_BR).
final localeCode = RegExp(r'^[a-z]{2,3}([-_]([A-Z][a-z]{3}|[A-Z]{2}|[0-9]{3}))?$');

/// What the check found in one language file.
class LanguageReport {
  LanguageReport(this.code, this.problems, this.translated, this.total, [this.notes = const []]);

  final String code;
  final List<String> problems;

  /// Worth knowing, not stopping the pull request: a name not translated yet.
  final List<String> notes;
  final int translated;
  final int total;

  double get coverage => total == 0 ? 100 : translated * 100 / total;
}

/// A text's placeholders as T.format fills them: (argument number, kind) for each %@ and %d,
/// numbered in order, and each %1$@ by its own number; %% is a percent sign, not one.
Set<(int, String)> placeholders(String text) {
  final found = <(int, String)>{};
  var next = 0;
  for (var index = 0; index < text.length; index++) {
    final positional = RegExp(r'%(\d)\$([@d])').matchAsPrefix(text, index);
    if (positional != null) {
      found.add((int.parse(positional.group(1)!), positional.group(2)!));
      index += positional.group(0)!.length - 1;
      continue;
    }
    if (text[index] == '%' && index + 1 < text.length) {
      final kind = text[index + 1];
      if (kind == '%') {
        index++;
      } else if (kind == '@' || kind == 'd') {
        found.add((++next, kind));
        index++;
      }
    }
  }
  return found;
}

String _shown(Set<(int, String)> found) => found.isEmpty
    ? 'none'
    : [for (final (number, kind) in found.toList()..sort((a, b) => a.$1 - b.$1)) '#$number %$kind'].join(', ');

/// The texts of a file, or the problems that keep it from being one flat object of texts.
(Map<String, String>, List<String>) readTexts(String file, String source) {
  final Object? json;
  try {
    json = jsonDecode(source);
  } on FormatException catch (error) {
    return (const {}, ['$file is not valid JSON: ${error.message} (at character ${error.offset})']);
  }
  if (json is! Map<String, Object?>) {
    return (const {}, ['$file has to be one JSON object: { "key": "text", ... }']);
  }
  final problems = <String>[];
  final texts = <String, String>{};
  for (final MapEntry(:key, :value) in json.entries) {
    if (key == legacyMeta) {
      final name = value is Map<String, Object?> ? value['name'] : null;
      problems.add(
        '$file has the old "$legacyMeta" object, which Weblate cannot read: write '
        '"$nameKey": "${name is String ? name : '…'}" instead and leave the console language out (it comes '
        'from the file name now)',
      );
    } else if (value is String) {
      texts[key] = value;
    } else {
      problems.add('$file: "$key" has to be a text in quotes');
    }
  }
  return (texts, problems);
}

/// Checks the file [source] of language [code] against the English texts.
LanguageReport checkLanguage(String code, String source, Map<String, String> english) {
  final file = '$code.json';
  final (texts, problems) = readTexts(file, source);
  if (!localeCode.hasMatch(code)) {
    problems.add('$file has to be named by its language code: de.json, pt-BR.json, zh-Hant.json');
  }
  final notes = <String>[];
  final name = texts[nameKey];
  if (name == null) {
    notes.add('"$nameKey" is not translated yet: Settings lists the language as "$code"');
  } else if (name.trim().isEmpty) {
    problems.add('$file: "$nameKey" is the language\'s own name and cannot be empty');
  }
  var translated = 0;
  for (final MapEntry(:key, :value) in texts.entries) {
    final englishText = english[key];
    if (englishText == null) {
      problems.add('$file: "$key" is not a key of en.json (a typo, or a key English no longer has)');
      continue;
    }
    translated++;
    final want = placeholders(englishText);
    final have = placeholders(value);
    if (want.length != have.length || !want.containsAll(have)) {
      problems.add('$file: "$key" has the placeholders ${_shown(have)}, English has ${_shown(want)}');
    }
  }
  return LanguageReport(code, problems, translated, english.length, notes);
}

/// Checks every language file in [folder], writing one line per language to [out]; 0 when they
/// all pass, 1 when one has a problem. With [annotate] the problems are GitHub Actions errors
/// too, shown on the file in the pull request.
int checkFolder(Directory folder, StringSink out, {bool annotate = false}) {
  void error(String file, String problem) =>
      out.writeln(annotate ? '::error file=${folder.path}/$file::$problem' : '  error: $problem');
  final Map<String, String> english;
  final List<String> englishProblems;
  try {
    (english, englishProblems) = readTexts('en.json', File('${folder.path}/en.json').readAsStringSync());
  } on FileSystemException catch (failure) {
    out.writeln('en.json cannot be read: ${failure.message}');
    return 1;
  }
  out.writeln('en: ${english.length} texts');
  var failed = englishProblems.isNotEmpty;
  for (final problem in englishProblems) {
    error('en.json', problem);
  }
  if (english[nameKey] == null) {
    error('en.json', 'en.json needs "$nameKey": "English"');
    failed = true;
  }
  final files = folder.listSync().whereType<File>().where((file) => file.path.endsWith('.json')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in files) {
    final name = file.uri.pathSegments.last;
    final code = name.substring(0, name.length - '.json'.length);
    if (code == 'en') continue;
    final report = checkLanguage(code, file.readAsStringSync(), english);
    final missing = report.total - report.translated;
    out.writeln(
      '$code: ${report.coverage.toStringAsFixed(1)} % translated (${report.translated} of ${report.total}'
      '${missing > 0 ? ', $missing shown in English' : ''})',
    );
    for (final note in report.notes) {
      out.writeln('  note: $note');
    }
    for (final problem in report.problems) {
      error(name, problem);
    }
    failed |= report.problems.isNotEmpty;
  }
  return failed ? 1 : 0;
}

/// A text the code picks by the language instead of reading it from the files.
final _languageBranch = RegExp(r"""\b(language\.code|languageCode)\s*[!=]=\s*'|==\s*'tr'|\bturkish\s*\?""");

/// Letters only Turkish (of the languages the apps have) writes, in a string literal.
final _turkishLiteral = RegExp('\'[^\'\n]*[ğĞışŞİ][^\'\n]*\'|"[^"\n]*[ğĞışŞİ][^"\n]*"');

/// Lines allowed to name a language in itself: the console languages, each in its own words.
const _allowed = {'lib/core/game_settings.dart': 'ConsoleLanguage'};

/// Checks the Dart files in [lib] for texts that are not in the language files: a branch on the
/// language's code, or a Turkish word. English literals are not checked: in code they cannot be
/// told apart from file names, keys and log lines. Returns the problems, one per line found.
List<String> checkSources(Directory lib) {
  final problems = <String>[];
  for (final file in lib.listSync(recursive: true).whereType<File>().where((file) => file.path.endsWith('.dart'))) {
    final relative = 'lib/${file.path.substring(lib.path.length + 1).replaceAll(r'\', '/')}';
    var allowedBlock = false;
    final lines = file.readAsLinesSync();
    for (var number = 0; number < lines.length; number++) {
      final line = lines[number];
      final code = line.trimLeft();
      if (_allowed[relative] case final marker? when line.contains('class $marker')) allowedBlock = true;
      if (allowedBlock && line.startsWith('}')) allowedBlock = false;
      if (code.startsWith('//') || allowedBlock || line.contains('// not a text')) continue;
      final withoutComment = line.split(' // ').first;
      if (_languageBranch.hasMatch(withoutComment)) {
        problems.add('$relative:${number + 1}: a text chosen by the language\'s code; put it in assets/l10n');
      } else if (_turkishLiteral.hasMatch(withoutComment)) {
        problems.add('$relative:${number + 1}: a Turkish text in the code; put it in assets/l10n');
      }
    }
  }
  return problems;
}

void main(List<String> arguments) {
  final annotate = Platform.environment['GITHUB_ACTIONS'] == 'true';
  var failed = checkFolder(Directory(arguments.isEmpty ? 'assets/l10n' : arguments.first), stdout, annotate: annotate);
  final lib = Directory(arguments.length > 1 ? arguments[1] : 'lib');
  if (lib.existsSync()) {
    final problems = checkSources(lib);
    stdout.writeln(
      'lib: ${problems.isEmpty ? 'no texts outside the language files' : '${problems.length} texts outside the language files'}',
    );
    for (final problem in problems) {
      final at = problem.indexOf(': ');
      final location = problem.substring(0, at).split(':');
      stdout.writeln(
        annotate
            ? '::error file=${location[0]},line=${location[1]}::${problem.substring(at + 2)}'
            : '  error: $problem',
      );
    }
    if (problems.isNotEmpty) failed = 1;
  }
  exitCode = failed;
}
