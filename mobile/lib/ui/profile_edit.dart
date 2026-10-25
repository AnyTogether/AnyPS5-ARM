import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../social_strings.dart';
import '../strings.dart';
import '../together/people.dart';
import '../together/profiles.dart';
import '../together/together_account.dart';
import 'avatar_crop.dart';
import 'together_widgets.dart';

/// A picture from the photo library, already made smaller than the server's limits (and turned
/// into a JPEG) by the picker; null when nothing was picked. The system's picker needs no
/// permission to read the whole library.
Future<Uint8List?> pickFromLibrary() async {
  final file = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 2048,
    maxHeight: 2048,
    imageQuality: 90,
    requestFullMetadata: false,
  );
  return file?.readAsBytes();
}

/// Editing your own profile, on its own screen: the picture, name, handle, country and bio on
/// the left, who sees what on the right. Privacy changes as it is picked; the rest with Save.
Future<void> openProfileEdit(
  BuildContext context, {
  required TogetherAccount account,
  Profiles? profiles,
  Future<Uint8List?> Function()? pickPhoto,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => ProfileEditScreen(
      profiles: profiles ?? Profiles(account),
      pickPhoto: pickPhoto ?? pickFromLibrary,
      storage: account.storageEnabled(),
    ),
  ),
);

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({
    super.key,
    required this.profiles,
    required this.pickPhoto,
    this.storage,
  });

  final Profiles profiles;
  final Future<Uint8List?> Function() pickPhoto;

  /// Whether the server keeps files: the gallery's privacy is offered when it does.
  final Future<bool>? storage;

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _name = TextEditingController();
  final _handle = TextEditingController();
  final _bio = TextEditingController();
  OwnProfile? _profile;
  String? _country;
  Privacy _privacy = defaultPrivacy;
  bool _appearOffline = false;
  bool _saving = false;
  bool _picture = false;
  Object? _loadError;
  String? _error;
  String? _handleError;
  String? _pictureError;

  Profiles get _profiles => widget.profiles;

  /// The server keeps files, so the gallery's privacy is offered.
  bool _storage = false;

  @override
  void initState() {
    super.initState();
    _storage = _profiles.account.storage?.enabled ?? false;
    _load();
    widget.storage?.then((on) {
      if (mounted && on != _storage) setState(() => _storage = on);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _handle.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final profile = await _profiles.mine();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _name.text = profile.displayName;
        _handle.text = profile.handle;
        _bio.text = profile.bio ?? '';
        _country = profile.country;
        _privacy = profile.privacy;
        _appearOffline = profile.appearOffline;
      });
    } on Object catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
  }

  String _problem(Strings texts, Object error) => switch (error) {
    TogetherProblem(:final code, :final extra) =>
      texts.profileProblem(code, extra) ?? togetherFailure(texts, error),
    _ => togetherFailure(texts, error),
  };

  Future<void> _save() async {
    final texts = Texts.of(context);
    final profile = _profile;
    if (profile == null || _saving) return;
    final handle = _handle.text.trim().replaceFirst(RegExp('^@'), '');
    final handleChanged = handle.toLowerCase() != profile.handle.toLowerCase();
    final issue = handleChanged ? handleIssue(handle) : null;
    setState(() {
      _error = _name.text.trim().isEmpty ? texts.displayName : null;
      _handleError = issue == null ? null : texts.handleIssue(issue);
    });
    if (_error != null || _handleError != null) return;
    setState(() => _saving = true);
    try {
      await _profiles.save(
        displayName: _name.text,
        bio: _bio.text,
        country: _country,
      );
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = _problem(texts, error);
          _saving = false;
        });
      }
      return;
    }
    if (handleChanged) {
      try {
        await _profiles.changeHandle(handle);
      } on Object catch (error) {
        if (mounted) {
          setState(() {
            _handleError = _problem(texts, error);
            _saving = false;
          });
        }
        return;
      }
    }
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _setPrivacy(PrivacySection section, Audience audience) async {
    final before = _privacy;
    setState(() {
      _privacy = {..._privacy, section: audience};
      _error = null;
    });
    try {
      final saved = await _profiles.setPrivacy(section, audience);
      if (mounted) setState(() => _privacy = saved);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _privacy = before;
          _error = _problem(Texts.of(context), error);
        });
      }
    }
  }

  /// Saved as it is picked; back as it was when the server did not take it.
  Future<void> _setAppearOffline(bool appearOffline) async {
    final texts = Texts.of(context);
    setState(() {
      _appearOffline = appearOffline;
      _error = null;
    });
    try {
      final saved = await _profiles.setAppearOffline(appearOffline);
      if (mounted) setState(() => _appearOffline = saved);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _appearOffline = !appearOffline;
          _error = error is TogetherProblem && error.status == 404
              ? texts.presenceUnavailable
              : _problem(texts, error);
        });
      }
    }
  }

  Future<void> _changePicture() async {
    final texts = Texts.of(context);
    final navigator = Navigator.of(context);
    setState(() => _pictureError = null);
    final Uint8List? bytes;
    try {
      bytes = await widget.pickPhoto();
    } on PlatformException catch (error) {
      if (mounted) {
        setState(
          () => _pictureError = error.code.contains('access_denied')
              ? texts.photoDenied
              : texts.avatarBad,
        );
      }
      return;
    }
    if (bytes == null || !mounted) return;
    switch (avatarIssue(bytes)) {
      case AvatarIssue.tooBig:
        setState(() => _pictureError = texts.avatarTooBig);
        return;
      case AvatarIssue.wrongType:
        setState(() => _pictureError = texts.avatarWrongType);
        return;
      case _:
    }
    final ui.Image image;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      image = (await codec.getNextFrame()).image;
      codec.dispose();
    } on Object {
      if (mounted) setState(() => _pictureError = texts.avatarBad);
      return;
    }
    if (image.width < ProfileLimits.avatarMinSide ||
        image.height < ProfileLimits.avatarMinSide ||
        image.width * image.height > ProfileLimits.avatarMaxPixels) {
      image.dispose();
      if (mounted) setState(() => _pictureError = texts.avatarBad);
      return;
    }
    final square = await navigator.push<Uint8List>(
      MaterialPageRoute(builder: (_) => AvatarCropScreen(image: image)),
    );
    image.dispose();
    if (square == null || !mounted) return;
    if (avatarIssue(square) != null) {
      setState(() => _pictureError = texts.avatarTooBig);
      return;
    }
    setState(() => _picture = true);
    try {
      final url = await _profiles.uploadAvatar(square);
      if (mounted) setState(() => _profile = _profile?.copyWith(avatar: url));
    } on Object catch (error) {
      if (mounted) setState(() => _pictureError = _problem(texts, error));
    }
    if (mounted) setState(() => _picture = false);
  }

  Future<void> _removePicture() async {
    setState(() {
      _picture = true;
      _pictureError = null;
    });
    try {
      await _profiles.removeAvatar();
      if (mounted) {
        setState(() => _profile = _profile?.copyWith(clearAvatar: true));
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _pictureError = _problem(Texts.of(context), error));
      }
    }
    if (mounted) setState(() => _picture = false);
  }

  Future<void> _pickCountry() async {
    final picked = await showDialog<(String?,)>(
      context: context,
      builder: (_) => _CountryDialog(current: _country),
    );
    if (picked != null) setState(() => _country = picked.$1);
  }

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    final profile = _profile;
    return Scaffold(
      backgroundColor: togetherInk,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: texts.back,
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(
                      Icons.chevron_left_rounded,
                      color: Colors.white70,
                    ),
                  ),
                  Text(
                    texts.editProfile,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      _error ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: togetherError,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: profile == null || _saving ? null : _save,
                    child: Text(texts.save),
                  ),
                ],
              ),
            ),
            Expanded(
              child: profile == null
                  ? Center(
                      child: _loadError == null
                          ? const SizedBox.square(
                              dimension: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : TextButton(
                              onPressed: _load,
                              child: Text(texts.retry),
                            ),
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _left(texts, profile)),
                        Expanded(child: _right(texts)),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _left(Strings texts, OwnProfile profile) => ListView(
    padding: const EdgeInsets.fromLTRB(22, 10, 14, 24),
    children: [
      Row(
        children: [
          Avatar(
            person: Person(
              id: '',
              handle: profile.handle,
              displayName: _name.text.isEmpty
                  ? profile.displayName
                  : _name.text,
              avatar: profile.avatar,
            ),
            size: 72,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _picture ? null : _changePicture,
                      icon: _picture
                          ? const SizedBox.square(
                              dimension: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.photo_library_rounded, size: 17),
                      label: Text(texts.changeAvatar),
                    ),
                    if (profile.avatar != null)
                      TextButton(
                        onPressed: _picture ? null : _removePicture,
                        child: Text(
                          texts.removeAvatar,
                          style: const TextStyle(color: Colors.white60),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _pictureError ?? texts.avatarHint,
                  style: TextStyle(
                    color: _pictureError == null
                        ? Colors.white38
                        : togetherError,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 18),
      _Field(
        label: texts.displayName,
        controller: _name,
        maxLength: ProfileLimits.nameMax,
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 12),
      _Field(
        label: texts.handle,
        controller: _handle,
        prefix: '@',
        maxLength: ProfileLimits.handleMax,
        error: _handleError,
        helper: profile.handleChangeAt == null
            ? texts.handleHint
            : texts.handleNextChange(profile.handleChangeAt!),
        enabled: profile.handleChangeAt == null,
      ),
      const SizedBox(height: 12),
      Material(
        color: const Color(0x0FFFFFFF),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _pickCountry,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Text(
                  texts.country,
                  style: const TextStyle(color: Colors.white54, fontSize: 14),
                ),
                const Spacer(),
                Text(
                  _country == null
                      ? texts.noCountry
                      : '${flagOf(_country!)}  $_country',
                  style: const TextStyle(color: Colors.white, fontSize: 14.5),
                ),
                const SizedBox(width: 6),
                const Icon(
                  Icons.expand_more_rounded,
                  color: Colors.white38,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );

  Widget _right(Strings texts) => ListView(
    padding: const EdgeInsets.fromLTRB(14, 10, 22, 24),
    children: [
      _Field(
        label: texts.bio,
        controller: _bio,
        hint: texts.bioPlaceholder,
        maxLength: ProfileLimits.bioMax,
        lines: 3,
      ),
      SectionLabel(texts.privacy),
      Text(
        texts.privacyLead,
        style: const TextStyle(color: Colors.white38, fontSize: 12.5),
      ),
      const SizedBox(height: 8),
      for (final section in PrivacySection.values)
        // The gallery only where the server keeps photos and clips.
        if (section != PrivacySection.gallery || _storage)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  texts.privacySection(section),
                  style: const TextStyle(color: Colors.white70, fontSize: 13.5),
                ),
                const SizedBox(height: 6),
                _AudiencePicker(
                  value: _privacy[section]!,
                  search: section == PrivacySection.search,
                  onChanged: (audience) => _setPrivacy(section, audience),
                ),
                if (section == PrivacySection.search)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      texts.searchHint,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      SectionLabel(texts.presenceMode),
      _TwoWayPicker(
        labels: [texts.presenceOnline, texts.presenceAppearOffline],
        dots: const [togetherAccent, null],
        value: _appearOffline ? 1 : 0,
        onChanged: (index) => _setAppearOffline(index == 1),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          children: [
            if (_appearOffline) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white24),
                ),
                child: Text(
                  texts.appearingOffline,
                  style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                texts.presenceModeHint,
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

/// Two segments, the picked one lit; a segment may carry a status dot (null: a hollow ring).
class _TwoWayPicker extends StatelessWidget {
  const _TwoWayPicker({
    required this.labels,
    required this.dots,
    required this.value,
    required this.onChanged,
  });

  final List<String> labels;
  final List<Color?> dots;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: const Color(0x0FFFFFFF),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        for (var index = 0; index < labels.length; index++)
          Expanded(
            child: Semantics(
              button: true,
              selected: index == value,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: index == value ? null : () => onChanged(index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  decoration: BoxDecoration(
                    color: index == value
                        ? const Color(0x338AB4FF)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: dots[index],
                          border: dots[index] == null
                              ? Border.all(color: Colors.white54, width: 1.5)
                              : null,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          labels[index],
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: index == value
                                ? Colors.white
                                : Colors.white54,
                            fontSize: 13,
                            fontWeight: index == value
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// Everyone, friends, only me: three segments, the picked one lit.
class _AudiencePicker extends StatelessWidget {
  const _AudiencePicker({
    required this.value,
    required this.search,
    required this.onChanged,
  });

  final Audience value;
  final bool search;
  final ValueChanged<Audience> onChanged;

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0x0FFFFFFF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (final audience in Audience.values)
            Expanded(
              child: Semantics(
                button: true,
                selected: audience == value,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: audience == value ? null : () => onChanged(audience),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    decoration: BoxDecoration(
                      color: audience == value
                          ? const Color(0x338AB4FF)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      texts.audience(audience, search: search),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: audience == value
                            ? Colors.white
                            : Colors.white54,
                        fontSize: 13,
                        fontWeight: audience == value
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.prefix,
    this.hint,
    this.helper,
    this.error,
    this.maxLength,
    this.lines = 1,
    this.enabled = true,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final String? prefix;
  final String? hint;
  final String? helper;
  final String? error;
  final int? maxLength;
  final int lines;
  final bool enabled;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    enabled: enabled,
    maxLength: maxLength,
    minLines: lines,
    maxLines: lines,
    autocorrect: prefix == null,
    onChanged: onChanged,
    style: const TextStyle(color: Colors.white, fontSize: 14.5),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white54),
      prefixText: prefix,
      prefixStyle: const TextStyle(color: Colors.white38),
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white30),
      helperText: error == null ? helper : null,
      helperMaxLines: 3,
      helperStyle: const TextStyle(color: Colors.white38, fontSize: 11.5),
      errorText: error,
      errorMaxLines: 3,
      filled: true,
      fillColor: const Color(0x0FFFFFFF),
      counterStyle: const TextStyle(color: Colors.white30, fontSize: 11),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    ),
  );
}

/// Every country by flag and code, filtered as the code or flag is typed; "Not shown" first.
class _CountryDialog extends StatefulWidget {
  const _CountryDialog({required this.current});

  final String? current;

  @override
  State<_CountryDialog> createState() => _CountryDialogState();
}

class _CountryDialogState extends State<_CountryDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    final codes = countryCodes
        .split(' ')
        .where((code) => code.startsWith(_query.toUpperCase().trim()))
        .toList();
    return Dialog(
      backgroundColor: const Color(0xFF151821),
      insetPadding: const EdgeInsets.symmetric(horizontal: 120, vertical: 20),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: TextField(
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: Colors.white38,
                ),
                hintText: texts.searchCountry,
                hintStyle: const TextStyle(color: Colors.white30),
                filled: true,
                fillColor: const Color(0x14FFFFFF),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Expanded(
            child: GridView.extent(
              maxCrossAxisExtent: 110,
              childAspectRatio: 2.4,
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              children: [
                if (_query.isEmpty)
                  _CountryCell(
                    label: texts.noCountry,
                    selected: widget.current == null,
                    onTap: () => Navigator.of(context).pop((null,)),
                  ),
                for (final code in codes)
                  _CountryCell(
                    label: '${flagOf(code)}  $code',
                    selected: widget.current == code,
                    onTap: () => Navigator.of(context).pop((code,)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CountryCell extends StatelessWidget {
  const _CountryCell({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(3),
    child: Material(
      color: selected ? const Color(0x338AB4FF) : const Color(0x0AFFFFFF),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Center(
          child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ),
      ),
    ),
  );
}
