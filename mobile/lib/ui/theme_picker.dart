import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../social_strings.dart';
import '../strings.dart';
import '../together/profiles.dart';
import 'profile_look.dart';
import 'together_widgets.dart';

/// Picking a Theme Hub theme to wear on the profile: (theme,) for one, (null,) to take the worn
/// one off, null when nothing changes.
Future<(ProfileTheme?,)?> showThemePicker(
  BuildContext context, {
  required Profiles profiles,
  ProfileTheme? worn,
}) => showDialog<(ProfileTheme?,)>(
  context: context,
  builder: (_) => ThemePickerDialog(profiles: profiles, worn: worn),
);

/// A theme's small still over its own deep to middle colours, which show while it loads or when
/// it cannot.
class ThemeStill extends StatelessWidget {
  const ThemeStill({super.key, required this.theme, this.radius = 10});

  final ProfileTheme theme;
  final double radius;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(theme.colors.deep), Color(theme.colors.middle)],
        ),
      ),
      child: theme.thumb.isEmpty
          ? const SizedBox.expand()
          : SizedBox.expand(child: FadeInPicture(url: theme.thumb)),
    ),
  );
}

class ThemePickerDialog extends StatefulWidget {
  const ThemePickerDialog({super.key, required this.profiles, this.worn});

  final Profiles profiles;
  final ProfileTheme? worn;

  @override
  State<ThemePickerDialog> createState() => _ThemePickerDialogState();
}

class _ThemePickerDialogState extends State<ThemePickerDialog> {
  List<ProfileTheme>? _themes;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final themes = await widget.profiles.themes();
      if (mounted) setState(() => _themes = themes);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  void _pick(ProfileTheme? theme) {
    HapticFeedback.selectionClick();
    Navigator.of(context)
        .pop(theme?.id == widget.worn?.id && theme != null ? null : (theme,));
  }

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    final themes = _themes;
    final worn = widget.worn;
    return Dialog(
      backgroundColor: const Color(0xFF151821),
      insetPadding: const EdgeInsets.symmetric(horizontal: 90, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    texts.profileTheme,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                if (worn != null)
                  TextButton.icon(
                    onPressed: () => _pick(null),
                    icon: const Icon(Icons.layers_clear_rounded, size: 17),
                    label: Text(texts.themeOff),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white70,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: themes == null
                ? Center(
                    child: LoadingOrFailed(error: _error, retry: _load),
                  )
                : themes.isEmpty
                ? Center(
                    child: Text(
                      texts.themesEmpty,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 13.5,
                      ),
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, box) {
                      const most = 210.0, gap = 12.0, side = 16.0;
                      final room = box.maxWidth - side * 2;
                      final columns = ((room + gap) / (most + gap)).ceil();
                      final width = (room - gap * (columns - 1)) / columns;
                      final lines = MediaQuery.textScalerOf(context).scale(40);
                      return GridView(
                        padding: const EdgeInsets.fromLTRB(side, 8, side, 16),
                        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: most,
                          mainAxisSpacing: gap,
                          crossAxisSpacing: gap,
                          mainAxisExtent: (width - 6) * 9 / 16 + 12 + lines,
                        ),
                        children: [
                          for (final theme in themes)
                            _ThemeCell(
                              key: ValueKey('theme-${theme.id}'),
                              theme: theme,
                              worn: theme.id == worn?.id,
                              onTap: () => _pick(theme),
                            ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ThemeCell extends StatelessWidget {
  const _ThemeCell({
    super.key,
    required this.theme,
    required this.worn,
    required this.onTap,
  });

  final ProfileTheme theme;
  final bool worn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Color(theme.colors.accent);
    final maker = theme.makerHandle;
    return Semantics(
      button: true,
      selected: worn,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: AnimatedContainer(
                  duration: motion(context, 160),
                  padding: EdgeInsets.all(worn ? 2.5 : 0),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(13),
                    color: worn ? accent : const Color(0x00000000),
                  ),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ThemeStill(
                          theme: theme,
                          radius: worn ? 10.5 : 13,
                        ),
                      ),
                      if (worn)
                        Positioned(
                          right: 6,
                          top: 6,
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: accent,
                            ),
                            child: const Icon(
                              Icons.check_rounded,
                              size: 15,
                              color: togetherInk,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      theme.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              if (maker != null)
                Padding(
                  padding: const EdgeInsets.only(left: 14),
                  child: Text(
                    '@$maker',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 11.5,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
