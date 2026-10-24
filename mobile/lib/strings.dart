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
  String get activityUnlocking => _text('activity.unlocking');
  String get activityUpdating => _text('activity.updating');
  String get activityQueued => _text('activity.queued');
  String get activityStarting => _text('activity.starting');
  String activityStep(String phase) => _text('activity.$phase');
  String get activityReady => _text('activity.ready');
  String percent(int value) => _text('percent').replaceAll('{n}', '$value');
  String get motionDetail => _text('motionDetail');
  String get remotePlay => _text('remotePlay');
  String get remotePlayDetail => _text('remotePlayDetail');
  String get remotePlayNoPermission => _text('remotePlayNoPermission');
  String get together => 'AnyTogether';
  String get togetherIntro => _text('togetherIntro');
  String get togetherSignIn => _text('togetherSignIn');
  String togetherUseMac(String mac) =>
      _text('togetherUseMac').replaceAll('%@', mac);
  String get togetherUseMacDetail => _text('togetherUseMacDetail');
  String togetherWaitingMac(String mac) =>
      _text('togetherWaitingMac').replaceAll('%@', mac);
  String get togetherMacDeclined => _text('togetherMacDeclined');
  String get togetherOrEmail => _text('togetherOrEmail');
  String get togetherEmail => _text('togetherEmail');
  String get togetherSendCode => _text('togetherSendCode');
  String togetherCodeSent(String email) =>
      _text('togetherCodeSent').replaceAll('%@', email);
  String get togetherCode => _text('togetherCode');
  String get togetherOtherEmail => _text('togetherOtherEmail');
  String get togetherSignedIn => _text('togetherSignedIn');
  String get togetherSignOut => _text('togetherSignOut');
  String get togetherUnreachable => _text('togetherUnreachable');
  String togetherMacAsks(String mac, String handle) =>
      _text('togetherMacAsks').replaceAll('%@', mac).replaceAll('%h', handle);
  String get allow => _text('allow');
  String get notNow => _text('notNow');
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
    'searchingDetail': 'Keep AnyPS5 open on the Mac, with the phone and the Mac on the same Wi-Fi, or plug the phone into the Mac with a cable.',
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
    'activity.unlocking': 'Unlocking',
    'activity.updating': 'Updating',
    'activity.queued': 'Waiting',
    'activity.starting': 'Starting',
    'activity.unwrap': 'Opening the game files',
    'activity.relink': 'Converting for Mac',
    'activity.copy': 'Preparing the game',
    'activity.bundle': 'Packaging',
    'activity.finish': 'Finishing touches',
    'activity.wait': 'Another game goes first',
    'activity.launch': 'Opening the game on the Mac',
    'activity.ready': 'Ready',
    'percent': '{n}%',
    'motionDetail':
        "Tilting and turning the phone, as the DualSense's motion sensors",
    'remotePlay': 'Remote Play',
    'remotePlayDetail': 'The game on the phone, behind the pad. Off, the phone is only the controller',
    'togetherIntro':
        'Friends, trophies and play time, on the Mac, the phone and the web',
    'togetherSignIn': 'Sign in',
    'togetherUseMac': "Use %@'s account",
    'togetherUseMacDetail':
        'The Mac, signed in to AnyTogether, approves it at once',
    'togetherWaitingMac': 'Waiting for %@…',
    'togetherMacDeclined':
        'The Mac is not signed in to AnyTogether; use your email',
    'togetherOrEmail': 'or with your email',
    'togetherEmail': 'Email',
    'togetherSendCode': 'Email me a code',
    'togetherCodeSent': 'Code sent to %@',
    'togetherCode': 'Code from the mail',
    'togetherOtherEmail': 'Use another email',
    'togetherSignedIn':
        'Signed in. The Mac can sign in with this account from its settings.',
    'togetherSignOut': 'Sign out',
    'togetherUnreachable': "Couldn't reach AnyTogether",
    'togetherMacAsks': '%@ wants to sign in to AnyTogether as @%h',
    'allow': 'Allow',
    'notNow': 'Not now',
    'remotePlayNoPermission':
        'Allow AnyPS5 to record the screen on the Mac to see the game here',
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
    'searchingDetail': "Mac'te AnyPS5 açık olsun, telefon ile Mac aynı Wi-Fi'da olsun ya da telefonu Mac'e kabloyla tak.",
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
    'activity.unlocking': 'Kilit açılıyor',
    'activity.updating': 'Güncelleniyor',
    'activity.queued': 'Sırada',
    'activity.starting': 'Açılıyor',
    'activity.unwrap': 'Oyun dosyaları açılıyor',
    'activity.relink': 'Mac için çevriliyor',
    'activity.copy': 'Oyun hazırlanıyor',
    'activity.bundle': 'Paketleniyor',
    'activity.finish': 'Son dokunuşlar',
    'activity.wait': 'Önce başka bir oyun',
    'activity.launch': "Oyun Mac'te açılıyor",
    'activity.ready': 'Hazır',
    'percent': '%{n}',
    'motionDetail':
        "Telefonu eğip döndürmek, DualSense'in hareket sensörleri gibi",
    'remotePlay': 'Remote Play',
    'remotePlayDetail':
        'Oyun telefonda, kolun arkasında. Kapalıyken telefon sadece kol',
    'togetherIntro':
        "Arkadaşlar, kupalar ve oynama süresi; Mac'te, telefonda ve webde",
    'togetherSignIn': 'Giriş yap',
    'togetherUseMac': '%@ hesabını kullan',
    'togetherUseMacDetail': "AnyTogether'a giriş yapmış Mac hemen onaylar",
    'togetherWaitingMac': '%@ bekleniyor…',
    'togetherMacDeclined': "Mac AnyTogether'a giriş yapmamış; e-postanla gir",
    'togetherOrEmail': 'ya da e-postanla',
    'togetherEmail': 'E-posta',
    'togetherSendCode': 'Bana kod gönder',
    'togetherCodeSent': 'Kod gönderildi: %@',
    'togetherCode': 'Maildeki kod',
    'togetherOtherEmail': 'Başka bir e-posta',
    'togetherSignedIn':
        'Giriş yapıldı. Mac de ayarlarından bu hesapla girebilir.',
    'togetherSignOut': 'Çıkış yap',
    'togetherUnreachable': "AnyTogether'a ulaşılamadı",
    'togetherMacAsks': "%@, AnyTogether'a @%h olarak girmek istiyor",
    'allow': 'İzin ver',
    'notNow': 'Şimdi değil',
    'remotePlayNoPermission':
        "Oyunu burada görmek için Mac'te AnyPS5'e ekran kaydı izni ver",
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
