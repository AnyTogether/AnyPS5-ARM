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
  String get goLive => _text('goLive');
  String get endBroadcast => _text('endBroadcast');
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

  /// [text] in capitals the way the language writes them: Turkish keeps the dot on İ.
  String upper(String text) => language == 'tr'
      ? text.replaceAll('i', 'İ').toUpperCase()
      : text.toUpperCase();
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
  String get friends => _text('friends');
  String get friendsHandle => _text('friendsHandle');
  String get friendsAdd => _text('friendsAdd');
  String friendsRequested(String handle) =>
      _text('friendsRequested').replaceAll('%h', handle);
  String friendsAdded(String handle) =>
      _text('friendsAdded').replaceAll('%h', handle);
  String get friendsRequests => _text('friendsRequests');
  String get friendsSent => _text('friendsSent');
  String get friendsWaiting => _text('friendsWaiting');
  String get friendsNone => _text('friendsNone');
  String get friendsRemove => _text('friendsRemove');
  String get accept => _text('accept');
  String get decline => _text('decline');
  String presencePlaying(String game) =>
      _text('presencePlaying').replaceAll('%@', game);
  String get presenceOnline => _text('presenceOnline');
  String get presenceAway => _text('presenceAway');
  String get presenceOffline => _text('presenceOffline');
  String get togetherLive => _text('togetherLive');
  String get togetherConnecting => _text('togetherConnecting');
  String get togetherNotFound => _text('togetherNotFound');
  String get back => _text('back');
  String get voice => _text('voice');
  String get voiceJoin => _text('voiceJoin');
  String get voiceLeave => _text('voiceLeave');
  String get voiceMute => _text('voiceMute');
  String get voiceUnmute => _text('voiceUnmute');
  String get voiceMicDenied => _text('voiceMicDenied');
  String get voiceFailed => _text('voiceFailed');
  String get voiceAlone => _text('voiceAlone');
  String get voicePad => _text('voicePad');
  String voiceConnected(int n) =>
      _text('voiceConnected').replaceAll('{n}', '$n');
  String voiceConnecting(int n) =>
      _text('voiceConnecting').replaceAll('{n}', '$n');
  String voiceInCall(int n) => _text('voiceInCall').replaceAll('{n}', '$n');
  String get party => _text('party');
  String get partyIntro => _text('partyIntro');
  String get partyStart => _text('partyStart');
  String get partyInvites => _text('partyInvites');
  String get partyJoin => _text('partyJoin');
  String get shareTitle => _text('shareTitle');
  String get shareWatch => _text('shareWatch');
  String get shareLeave => _text('shareLeave');
  String get shareWatching => _text('shareWatching');
  String get shareFull => _text('shareFull');
  String get shareFailed => _text('shareFailed');
  String get shareTaken => _text('shareTaken');
  String shareInvited(String name, String game) =>
      _text('shareInvited').replaceAll('%@', name).replaceAll('%s', game);
  String shareSharing(String game) =>
      _text('shareSharing').replaceAll('%@', game);
  String shareViewers(int count, int most) =>
      _text('shareViewers')
          .replaceAll('%@', '$count')
          .replaceAll('%s', '$most');
  String sharePlayer(int number) =>
      _text('sharePlayer').replaceAll('%@', '$number');
  String shareConnecting(String name) =>
      _text('shareConnecting').replaceAll('%@', name);
  String shareEnded(String name) => _text('shareEnded').replaceAll('%@', name);
  String shareRemoved(String name) =>
      _text('shareRemoved').replaceAll('%@', name);
  String get partyLeave => _text('partyLeave');
  String get partyInvite => _text('partyInvite');
  String get partyInvited => _text('partyInvited');
  String get partyInviteFriends => _text('partyInviteFriends');
  String get partyNoFriends => _text('partyNoFriends');
  String get partyOpen => _text('partyOpen');
  String get partyOpenDetail => _text('partyOpenDetail');
  String get partyLeader => _text('partyLeader');
  String get partyFriendsParties => _text('partyFriendsParties');
  String get partyKicked => _text('partyKicked');
  String get partyFull => _text('partyFull');
  String get partyKick => _text('partyKick');
  String get partyMembers => _text('partyMembers');
  String partyInviteFrom(String name, int size) =>
      _text('partyInviteFrom')
          .replaceAll('%@', name)
          .replaceAll('{n}', '$size');
  String get messages => _text('messages');
  String get messagesNone => _text('messagesNone');
  String get messagesPick => _text('messagesPick');
  String get messagesWrite => _text('messagesWrite');
  String get messagesSend => _text('messagesSend');
  String get messagesDeleted => _text('messagesDeleted');
  String get messagesFailed => _text('messagesFailed');
  String get messagesEarlier => _text('messagesEarlier');
  String get messagesYou => _text('messagesYou');
  String get messagesEdited => _text('messagesEdited');
  String get togetherServer => _text('togetherServer');
  String get togetherServerChange => _text('togetherServerChange');
  String get togetherServerUse => _text('togetherServerUse');
  String togetherServerMac(String mac, String server) =>
      _text('togetherServerMac').replaceAll('%@', mac).replaceAll('%s', server);
  String get togetherServerDetail => _text('togetherServerDetail');
  String get togetherServerInvalid => _text('togetherServerInvalid');
  String get allow => _text('allow');
  String get notNow => _text('notNow');
  String get editLayout => _text('editLayout');
  String get done => _text('done');
  String get editHint => _text('editHint');
  String get resetAll => _text('resetAll');
  String get smaller => _text('smaller');
  String get larger => _text('larger');
  String get opacity => _text('opacity');
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
    'goLive': 'Go Live',
    'endBroadcast': 'End Broadcast',
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
    'friends': 'Friends',
    'friendsHandle': 'Their handle',
    'friendsAdd': 'Add',
    'friendsRequested': 'Asked @%h to be friends',
    'friendsAdded': 'You and @%h are friends now',
    'friendsRequests': 'Friend requests',
    'friendsSent': 'Waiting for them',
    'friendsWaiting': 'Waiting',
    'friendsNone': 'No friends here yet. Add someone by their handle.',
    'friendsRemove': 'Remove friend',
    'accept': 'Accept',
    'decline': 'Decline',
    'presencePlaying': 'Playing %@',
    'presenceOnline': 'Online',
    'presenceAway': 'Away',
    'presenceOffline': 'Offline',
    'togetherLive': 'Live',
    'togetherConnecting': 'Connecting…',
    'togetherNotFound': 'No one with that handle',
    'back': 'Back',
    'voice': 'Voice',
    'voiceJoin': 'Join voice',
    'voiceLeave': 'Leave voice',
    'voiceMute': 'Mute',
    'voiceUnmute': 'Unmute',
    'voiceMicDenied':
        'Allow the microphone for AnyPS5 Remote in Settings to talk',
    'voiceFailed': 'Couldn\'t join the voice',
    'voiceAlone': 'No one else is in voice yet',
    'voicePad': 'The phone stays the controller while you talk',
    'voiceConnected': 'Talking with {n}',
    'voiceConnecting': 'Connecting to {n}…',
    'voiceInCall': '{n} in voice',
    'party': 'Party',
    'partyIntro': 'Talk while you play, up to eight of you. The phone stays the controller.',
    'partyStart': 'Start a party',
    'partyInvites': 'Party invites',
    'partyJoin': 'Join',
    'shareTitle': 'Share play',
    'shareWatch': 'Watch',
    'shareLeave': 'Stop watching',
    'shareWatching': 'Watching',
    'shareFull': 'Nobody else can watch right now',
    'shareFailed': 'Could not watch',
    'shareTaken': 'The host took the pad back',
    'shareInvited': '%@ shares %s with you',
    'shareSharing': 'Sharing %@',
    'shareViewers': '%@ of %s watching',
    'sharePlayer': 'Player %@',
    'shareConnecting': 'Connecting to %@…',
    'shareEnded': '%@ stopped sharing',
    'shareRemoved': '%@ took you out',
    'partyLeave': 'Leave party',
    'partyInvite': 'Invite',
    'partyInvited': 'Invited',
    'partyInviteFriends': 'Invite friends',
    'partyNoFriends': 'Every friend is here or invited',
    'partyOpen': 'Friends can join',
    'partyOpenDetail': 'Your friends join without an invite',
    'partyLeader': 'Leader',
    'partyFriendsParties': 'Friends\' open parties',
    'partyKicked': 'The leader took you out of the party',
    'partyFull': 'The party is full',
    'partyKick': 'Remove from party',
    'partyMembers': 'Members',
    'partyInviteFrom': '%@ · {n} in the party',
    'messages': 'Messages',
    'messagesNone': 'No conversations yet. Write to a friend from Friends.',
    'messagesPick': 'Pick a conversation, or write to a friend from Friends.',
    'messagesWrite': 'Message',
    'messagesSend': 'Send',
    'messagesDeleted': 'Message removed',
    'messagesFailed': 'Not sent. Tap to try again',
    'messagesEarlier': 'Earlier messages',
    'messagesYou': 'You',
    'messagesEdited': 'edited',
    'togetherServer': 'Server',
    'togetherServerChange': 'Change',
    'togetherServerUse': 'Use',
    'togetherServerMac': '%@ uses %s',
    'togetherServerDetail': 'Another AnyTogether server, one you or your friends host. Changing it signs you out.',
    'togetherServerInvalid':
        'An https:// address, or http:// on your home network',
    'allow': 'Allow',
    'notNow': 'Not now',
    'remotePlayNoPermission':
        'Allow AnyPS5 to record the screen on the Mac to see the game here',
    'editLayout': 'Edit Layout',
    'done': 'Done',
    'editHint': 'Drag a control to move it, tap it to change it',
    'resetAll': 'Reset All',
    'smaller': 'Smaller',
    'larger': 'Larger',
    'opacity': 'Opacity',
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
    'goLive': 'Yayına Başla',
    'endBroadcast': 'Yayını Bitir',
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
    'friends': 'Arkadaşlar',
    'friendsHandle': 'Kullanıcı adı',
    'friendsAdd': 'Ekle',
    'friendsRequested': '@%h kişisine arkadaşlık isteği gönderildi',
    'friendsAdded': '@%h ile artık arkadaşsınız',
    'friendsRequests': 'Arkadaşlık istekleri',
    'friendsSent': 'Yanıt bekleniyor',
    'friendsWaiting': 'Bekliyor',
    'friendsNone': 'Burada henüz arkadaş yok. Birini kullanıcı adıyla ekle.',
    'friendsRemove': 'Arkadaşlıktan çıkar',
    'accept': 'Kabul et',
    'decline': 'Reddet',
    'presencePlaying': '%@ oynuyor',
    'presenceOnline': 'Çevrimiçi',
    'presenceAway': 'Uzakta',
    'presenceOffline': 'Çevrimdışı',
    'togetherLive': 'Canlı',
    'togetherConnecting': 'Bağlanıyor…',
    'togetherNotFound': 'Bu kullanıcı adıyla kimse yok',
    'back': 'Geri',
    'voice': 'Sesli sohbet',
    'voiceJoin': 'Sesliye katıl',
    'voiceLeave': 'Sesliden ayrıl',
    'voiceMute': 'Sessize al',
    'voiceUnmute': 'Sesi aç',
    'voiceMicDenied':
        'Konuşmak için Ayarlar\'dan AnyPS5 Remote\'a mikrofon izni ver',
    'voiceFailed': 'Sesliye katılınamadı',
    'voiceAlone': 'Seslide henüz başka kimse yok',
    'voicePad': 'Konuşurken telefon kol olmaya devam eder',
    'voiceConnected': '{n} kişiyle konuşuluyor',
    'voiceConnecting': '{n} kişiye bağlanıyor…',
    'voiceInCall': 'Seslide {n} kişi',
    'party': 'Parti',
    'partyIntro':
        'Oynarken konuşun, en fazla sekiz kişi. Telefon kol olmaya devam eder.',
    'partyStart': 'Parti başlat',
    'partyInvites': 'Parti davetleri',
    'partyJoin': 'Katıl',
    'shareTitle': 'Oyun paylaşımı',
    'shareWatch': 'İzle',
    'shareLeave': 'İzlemeyi bırak',
    'shareWatching': 'İzliyorsun',
    'shareFull': 'Şu anda başka kimse izleyemez',
    'shareFailed': 'İzlenemedi',
    'shareTaken': 'Ev sahibi kolu geri aldı',
    'shareInvited': '%@ seninle %s paylaşıyor',
    'shareSharing': '%@ oyununu paylaşıyor',
    'shareViewers': '%s kişiden %@ izliyor',
    'sharePlayer': 'Oyuncu %@',
    'shareConnecting': '%@ ile bağlanılıyor…',
    'shareEnded': '%@ paylaşımı durdurdu',
    'shareRemoved': '%@ seni çıkardı',
    'partyLeave': 'Partiden ayrıl',
    'partyInvite': 'Davet et',
    'partyInvited': 'Davet edildi',
    'partyInviteFriends': 'Arkadaşlarını davet et',
    'partyNoFriends': 'Bütün arkadaşların burada ya da davetli',
    'partyOpen': 'Arkadaşlar katılabilir',
    'partyOpenDetail': 'Arkadaşların davetsiz katılır',
    'partyLeader': 'Lider',
    'partyFriendsParties': 'Arkadaşların açık partileri',
    'partyKicked': 'Lider seni partiden çıkardı',
    'partyFull': 'Parti dolu',
    'partyKick': 'Partiden çıkar',
    'partyMembers': 'Üyeler',
    'partyInviteFrom': '%@ · partide {n} kişi',
    'messages': 'Mesajlar',
    'messagesNone': 'Henüz konuşma yok. Arkadaşlar\'dan bir arkadaşına yaz.',
    'messagesPick': 'Bir konuşma seç ya da Arkadaşlar\'dan bir arkadaşına yaz.',
    'messagesWrite': 'Mesaj',
    'messagesSend': 'Gönder',
    'messagesDeleted': 'Mesaj kaldırıldı',
    'messagesFailed': 'Gönderilemedi. Tekrar denemek için dokun',
    'messagesEarlier': 'Önceki mesajlar',
    'messagesYou': 'Sen',
    'messagesEdited': 'düzenlendi',
    'togetherServer': 'Sunucu',
    'togetherServerChange': 'Değiştir',
    'togetherServerUse': 'Kullan',
    'togetherServerMac': '%@, %s kullanıyor',
    'togetherServerDetail': 'Senin ya da arkadaşlarının barındırdığı başka bir AnyTogether sunucusu. Değiştirmek oturumu kapatır.',
    'togetherServerInvalid':
        'https:// ile başlayan bir adres ya da ev ağında http://',
    'allow': 'İzin ver',
    'notNow': 'Şimdi değil',
    'remotePlayNoPermission':
        "Oyunu burada görmek için Mac'te AnyPS5'e ekran kaydı izni ver",
    'editLayout': 'Düzeni Düzenle',
    'done': 'Bitti',
    'editHint': 'Taşımak için sürükle, değiştirmek için dokun',
    'resetAll': 'Hepsini Sıfırla',
    'smaller': 'Küçült',
    'larger': 'Büyüt',
    'opacity': 'Saydamlık',
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

/// The old table, for the test that checks assets/l10n against it.
@visibleForTesting
Map<String, Map<String, String>> oldTables() => {
  "en": Strings._english,
  "tr": Strings._turkish,
};
