import 'package:flutter/material.dart';

import '../social_strings.dart';
import '../strings.dart';
import '../together/notifications.dart';
import '../together/together_hub.dart';
import 'together_widgets.dart';

/// The bell with the unread count; hidden while no one is signed in.
class NotificationBell extends StatelessWidget {
  const NotificationBell({
    super.key,
    required this.hub,
    required this.onPressed,
    this.color = Colors.white70,
    this.compact = false,
  });

  final TogetherHub hub;
  final VoidCallback onPressed;
  final Color color;

  /// Tighter, for the rail beside AnyTogether's name.
  final bool compact;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([hub.notifications, hub.account]),
    builder: (context, _) {
      if (hub.account.user == null) return const SizedBox.shrink();
      final unread = hub.notifications.unread;
      return IconButton(
        tooltip: Texts.of(context).notifications,
        onPressed: onPressed,
        visualDensity: compact ? VisualDensity.compact : null,
        icon: CountBadge(
          count: unread,
          child: Icon(
            unread > 0
                ? Icons.notifications_rounded
                : Icons.notifications_none_rounded,
            color: color,
          ),
        ),
      );
    },
  );
}

/// The list under the bell: newest first, the unread ones lit, a tap reads one and goes where
/// it leads; mark all read; and what to be told about.
class NotificationsPane extends StatefulWidget {
  const NotificationsPane({
    super.key,
    required this.hub,
    this.onOpen,
    this.gameName,
  });

  final TogetherHub hub;

  /// Where a notification leads: the friends, the conversation, the party, a profile.
  final ValueChanged<Notice>? onOpen;
  final String? Function(String titleId)? gameName;

  @override
  State<NotificationsPane> createState() => _NotificationsPaneState();
}

class _NotificationsPaneState extends State<NotificationsPane> {
  late final Notifications _notes = widget.hub.notifications;
  Object? _error;
  bool _settingsShown = false;
  NoticeSettings? _settings;
  bool _older = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      await _notes.refresh();
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  void _failed(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(togetherFailure(Texts.of(context), error))),
    );
  }

  Future<void> _showSettings() async {
    setState(() => _settingsShown = !_settingsShown);
    if (!_settingsShown || _settings != null) return;
    try {
      final settings = await _notes.settings();
      if (mounted) setState(() => _settings = settings);
    } on Object catch (error) {
      _failed(error);
      if (mounted) setState(() => _settingsShown = false);
    }
  }

  Future<void> _set(String key, bool on) async {
    try {
      final saved = await _notes.setting(key, on);
      if (mounted) setState(() => _settings = saved);
    } on Object catch (error) {
      _failed(error);
    }
  }

  void _open(Notice notice) {
    _notes.read(notice).catchError((Object error) => _failed(error));
    widget.onOpen?.call(notice);
  }

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    return ListenableBuilder(
      listenable: _notes,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(22, 14, 14, 18),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _settingsShown ? texts.notifySettings : texts.notifications,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (!_settingsShown && _notes.unread > 0)
                TextButton(
                  onPressed: () =>
                      _notes.readAll().catchError((Object e) => _failed(e)),
                  child: Text(texts.markAllRead),
                ),
              IconButton(
                tooltip: _settingsShown
                    ? texts.notifications
                    : texts.notifySettings,
                onPressed: _showSettings,
                icon: Icon(
                  _settingsShown ? Icons.close_rounded : Icons.tune_rounded,
                  color: Colors.white60,
                  size: 21,
                ),
              ),
            ],
          ),
          Text(
            _settingsShown ? texts.notifySettingsLead : texts.notificationsLead,
            style: const TextStyle(color: Colors.white38, fontSize: 13),
          ),
          const SizedBox(height: 8),
          if (_settingsShown) ..._settingsList(texts) else ..._list(texts),
        ],
      ),
    );
  }

  List<Widget> _list(Strings texts) {
    final items = _notes.items;
    return [
      if (!_notes.loaded && _error == null && items.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(
            child: SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      if (_error != null && items.isEmpty)
        Row(
          children: [
            Expanded(
              child: Text(
                togetherFailure(texts, _error!),
                style: const TextStyle(color: Colors.white54),
              ),
            ),
            TextButton(onPressed: _load, child: Text(texts.retry)),
          ],
        ),
      if (_notes.loaded && items.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            texts.noNotifications,
            style: const TextStyle(color: Colors.white54, fontSize: 14),
          ),
        ),
      for (final notice in items)
        _NoticeRow(
          key: ValueKey(notice.id),
          notice: notice,
          gameName: widget.gameName,
          onTap: () => _open(notice),
        ),
      if (_notes.more)
        Center(
          child: TextButton(
            onPressed: _older
                ? null
                : () async {
                    setState(() => _older = true);
                    await _notes.older().catchError((_) {});
                    if (mounted) setState(() => _older = false);
                  },
            child: Text(texts.loadMore),
          ),
        ),
    ];
  }

  List<Widget> _settingsList(Strings texts) {
    final settings = _settings;
    if (settings == null) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 30),
          child: Center(
            child: SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      ];
    }
    return [
      for (final kind in optionalNoticeKinds)
        _Toggle(
          label: texts.noticeKind(kind),
          value: settings.kinds[kind] ?? true,
          onChanged: (on) => _set(kind.wire, on),
        ),
      _Toggle(
        label: texts.digest,
        detail: settings.canMail ? texts.digestHint : texts.digestNoEmail,
        value: settings.digest,
        onChanged: settings.canMail ? (on) => _set('digest', on) : null,
      ),
      Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(
          texts.noPushYet,
          style: const TextStyle(color: Colors.white38, fontSize: 12),
        ),
      ),
    ];
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.value,
    required this.onChanged,
    this.detail,
  });

  final String label;
  final String? detail;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    dense: true,
    value: value,
    onChanged: onChanged,
    title: Text(
      label,
      style: const TextStyle(color: Colors.white, fontSize: 14.5),
    ),
    subtitle: detail == null
        ? null
        : Text(
            detail!,
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
  );
}

class _NoticeRow extends StatelessWidget {
  const _NoticeRow({
    super.key,
    required this.notice,
    required this.onTap,
    this.gameName,
  });

  final Notice notice;
  final VoidCallback onTap;
  final String? Function(String titleId)? gameName;

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    final line = texts.notice(notice, gameName: gameName);
    final name = notice.actor?.displayName ?? texts.someone;
    final at = line.indexOf('{name}');
    final spans = at < 0
        ? [TextSpan(text: line)]
        : [
            TextSpan(text: line.substring(0, at)),
            TextSpan(
              text: name,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(text: line.substring(at + '{name}'.length)),
          ];
    final extra = switch (notice.kind) {
      NoticeKind.message => notice.data['text'] as String?,
      NoticeKind.gameInvite => texts.gameInviteHint,
      NoticeKind.lfgAccepted => texts.lfgAcceptedHint(notice),
      NoticeKind.warning when notice.data['reason'] != null =>
        texts.warningReason('${notice.data['reason']}'),
      _ => null,
    };
    final icon = switch (notice.kind) {
      NoticeKind.friendRequest => Icons.person_add_alt_1_rounded,
      NoticeKind.friendAccepted => Icons.how_to_reg_rounded,
      NoticeKind.message => Icons.chat_bubble_rounded,
      NoticeKind.partyInvite => Icons.celebration_rounded,
      NoticeKind.gameInvite => Icons.sports_esports_rounded,
      NoticeKind.missedCall => Icons.phone_missed_rounded,
      NoticeKind.lfgRequest => Icons.travel_explore_rounded,
      NoticeKind.lfgAccepted => Icons.how_to_reg_rounded,
      NoticeKind.warning => Icons.gpp_maybe_rounded,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: notice.read ? Colors.transparent : const Color(0x128AB4FF),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 10, 8),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    if (notice.actor case final actor?)
                      Avatar(person: actor, size: 38)
                    else
                      const SizedBox.square(
                        dimension: 38,
                        child: Icon(
                          Icons.gpp_maybe_rounded,
                          color: togetherAway,
                        ),
                      ),
                    Positioned(
                      right: -4,
                      bottom: -4,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: togetherPanel,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          icon,
                          size: 12,
                          color: notice.kind == NoticeKind.missedCall
                              ? togetherError
                              : togetherAccent,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(children: spans),
                        style: TextStyle(
                          color: notice.read ? Colors.white60 : Colors.white,
                          fontSize: 14,
                          height: 1.3,
                        ),
                      ),
                      if (extra != null && extra.isNotEmpty)
                        Text(
                          extra,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12.5,
                          ),
                        ),
                      Text(
                        texts.ago(notice.updatedAt),
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!notice.read)
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(left: 8),
                    decoration: const BoxDecoration(
                      color: togetherAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
