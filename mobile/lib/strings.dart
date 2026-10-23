import 'package:flutter/widgets.dart';

import 'ui/pad_layout.dart';

/// Every text the app shows, in English (the default) and Turkish. The launcher's language
/// picks one once connected; before that the last one it picked is used.
class Strings {
  const Strings._(this.language, this._table);

  static const english = Strings._('en', _english);
  static const turkish = Strings._('tr', _turkish);

  static Strings of(String? language) => language == 'tr' ? turkish : english;

  final String language;
  final Map<String, String> _table;

  String _text(String key) => _table[key] ?? _english[key] ?? key;

  String get welcomeTitle => _text('welcomeTitle');
  String get welcomeText => _text('welcomeText');
  String get stepOpen => _text('stepOpen');
  String get stepWifi => _text('stepWifi');
  String get stepAllow => _text('stepAllow');
  String get start => _text('start');
  String found(String mac) => _text('found').replaceAll('%@', mac);
  String get searching => _text('searching');
  String get searchingDetail => _text('searchingDetail');
  String get busy => _text('busy');
  String get refused => _text('refused');
  String get allowOnMac => _text('allowOnMac');
  String get sameCode => _text('sameCode');
  String get ready => _text('ready');
  String get opening => _text('opening');
  String get retry => _text('retry');
  String get notFound => _text('notFound');
  String get startFailed => _text('startFailed');
  String get play => _text('play');
  String get resume => _text('resume');
  String get update => _text('update');
  String get unlock => _text('unlock');
  String get cancel => _text('cancel');
  String get closeGame => _text('closeGame');
  String get starting => _text('starting');
  String get unavailable => _text('unavailable');
  String get noGames => _text('noGames');
  String get playing => _text('playing');
  String get trophies => _text('trophies');
  String get about => _text('about');
  String get aboutText => _text('aboutText');
  String get madeBy => _text('madeBy');
  String get sourceCode => _text('sourceCode');
  String get builtOn => _text('builtOn');
  String get vibration => _text('vibration');
  String get vibrationDetail => _text('vibrationDetail');
  String get motion => _text('motion');
  String get trophyEarned => _text('trophyEarned');
  String get motionDetail => _text('motionDetail');
  String get editLayout => _text('editLayout');
  String get done => _text('done');
  String get editHint => _text('editHint');
  String get resetAll => _text('resetAll');
  String get reset => _text('reset');
  String get hide => _text('hide');
  String behavior(ButtonBehavior behavior) =>
      _text('behavior.${behavior.name}');

  static const _english = {
    'welcomeTitle': 'Your phone is a DualSense',
    'welcomeText':
        'Play the games you open with AnyPS5 on your Mac from this phone.',
    'stepOpen': 'Open AnyPS5 on the Mac',
    'stepWifi': 'Join the same Wi-Fi',
    'stepAllow': 'Allow it on the Mac',
    'start': 'Start',
    'found': '%@ found',
    'searching': 'Looking for AnyPS5 on the Mac',
    'searchingDetail': 'Keep AnyPS5 open on the Mac, with the phone and the Mac on the same Wi-Fi.',
    'busy': 'Another phone is connected',
    'refused': 'The Mac refused the connection',
    'allowOnMac': 'Allow it on the Mac',
    'sameCode': 'The Mac shows the same code: press Allow.',
    'ready': 'Ready',
    'opening': 'Opening the launcher…',
    'retry': 'Try Again',
    'notFound':
        "Not found? Check that AnyPS5 with phone support is open on the Mac and that both are on the same Wi-Fi. Or type the Mac's address "
        '(System Settings → Wi-Fi → Details → IP address).',
    'startFailed': 'AnyPS5 Remote could not start:',
    'play': 'Play',
    'resume': 'Back to Game',
    'update': 'Update',
    'unlock': 'Unlock',
    'cancel': 'Cancel',
    'closeGame': 'Close Game',
    'starting': 'Starting…',
    'unavailable': 'Unreadable',
    'noGames': 'No games on the Mac yet',
    'playing': 'Playing',
    'trophies': 'Trophies',
    'about': 'About',
    'aboutText':
        'Your phone as a DualSense for the PS5 games AnyPS5 runs on your Mac.',
    'madeBy': 'Made by',
    'sourceCode': 'Source code',
    'builtOn': 'Built on AnyPS5',
    'vibration': 'Vibration',
    'vibrationDetail': "The game's rumble and trigger effects on the phone",
    'motion': 'Motion',
    'trophyEarned': 'Trophy earned',
    'motionDetail':
        "Tilting and turning the phone, as the DualSense's motion sensors",
    'editLayout': 'Edit Layout',
    'done': 'Done',
    'editHint': 'Drag a control to move it, tap it to change it',
    'resetAll': 'Reset All',
    'reset': 'Reset',
    'hide': 'Hide',
    'behavior.normal': 'Normal',
    'behavior.toggle': 'Toggle',
    'behavior.turbo': 'Turbo',
  };

  static const _turkish = {
    'welcomeTitle': 'Telefonun DualSense olsun',
    'welcomeText': "Mac'te AnyPS5 ile açtığın oyunları bu telefonla oyna.",
    'stepOpen': "Mac'te AnyPS5'i aç",
    'stepWifi': "Aynı Wi-Fi'a bağlan",
    'stepAllow': "Mac'te izin ver",
    'start': 'Başla',
    'found': '%@ bulundu',
    'searching': "Mac'teki AnyPS5 aranıyor",
    'searchingDetail':
        "Mac'te AnyPS5 açık olsun, telefon ile Mac aynı Wi-Fi'da olsun.",
    'busy': 'Başka bir telefon bağlı',
    'refused': 'Mac bağlantıyı reddetti',
    'allowOnMac': "Mac'te izin ver",
    'sameCode': "Mac'te aynı kod görünüyor: İzin Ver'e bas.",
    'ready': 'Hazır',
    'opening': 'Launcher açılıyor…',
    'retry': 'Tekrar Dene',
    'notFound':
        "Bulunamadı mı? Mac'te telefon destekli AnyPS5 açık mı, iki cihaz aynı Wi-Fi'da mı bak. Ya da Mac'in adresini yaz "
        '(Sistem Ayarları → Wi-Fi → Ayrıntılar → IP adresi).',
    'startFailed': 'AnyPS5 Remote açılamadı:',
    'play': 'Oyna',
    'resume': 'Oyuna Dön',
    'update': 'Güncelle',
    'unlock': 'Kilidi Aç',
    'cancel': 'Vazgeç',
    'closeGame': 'Oyunu Kapat',
    'starting': 'Açılıyor…',
    'unavailable': 'Okunamıyor',
    'noGames': "Mac'te henüz oyun yok",
    'playing': 'Oynanıyor',
    'trophies': 'Kupalar',
    'about': 'Hakkında',
    'aboutText': "Mac'te AnyPS5 ile çalışan PS5 oyunları için telefonun DualSense olsun.",
    'madeBy': 'Geliştiren',
    'sourceCode': 'Kaynak kodu',
    'builtOn': 'AnyPS5 üzerine kurulu',
    'vibration': 'Titreşim',
    'vibrationDetail': 'Oyunun titreşimi ve tetik efektleri telefonda',
    'motion': 'Hareket',
    'trophyEarned': 'Kupa kazanıldı',
    'motionDetail':
        "Telefonu eğip döndürmek, DualSense'in hareket sensörleri gibi",
    'editLayout': 'Düzeni Düzenle',
    'done': 'Bitti',
    'editHint': 'Taşımak için sürükle, değiştirmek için dokun',
    'resetAll': 'Hepsini Sıfırla',
    'reset': 'Sıfırla',
    'hide': 'Gizle',
    'behavior.normal': 'Normal',
    'behavior.toggle': 'Kilitle',
    'behavior.turbo': 'Turbo',
  };
}

/// The texts in the language the launcher uses, for every screen under it.
class Texts extends InheritedWidget {
  const Texts({super.key, required this.strings, required super.child});

  final Strings strings;

  static Strings of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Texts>()?.strings ??
      Strings.english;

  @override
  bool updateShouldNotify(Texts old) => old.strings != strings;
}
