import 'package:flutter/material.dart';

import '../discover_strings.dart';
import '../social_strings.dart';
import '../strings.dart';
import '../together/discover.dart';
import '../together/profiles.dart';
import '../together/together_hub.dart';
import 'find_players_view.dart';
import 'together_widgets.dart';

/// People: whether the reader shows in discovery and the languages they play in on the left;
/// people they may know, and why, with a friend request each, on the right.
class DiscoverPeoplePane extends StatefulWidget {
  const DiscoverPeoplePane({
    super.key,
    required this.hub,
    this.gameName,
    this.onProfile,
  });

  final TogetherHub hub;
  final String? Function(String titleId)? gameName;
  final ValueChanged<String>? onProfile;

  @override
  State<DiscoverPeoplePane> createState() => _DiscoverPeoplePaneState();
}

class _DiscoverPeoplePaneState extends State<DiscoverPeoplePane> {
  Object? _error;

  Discover get _discover => widget.hub.discover;

  @override
  void initState() {
    super.initState();
    _discover.loadDiscovery().catchError((Object error) {
      if (mounted) setState(() => _error = error);
    });
  }

  Future<void> _try(Future<void> Function() step) async {
    final texts = Texts.of(context);
    try {
      await step();
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(SnackBar(content: Text(togetherFailure(texts, error))));
      }
    }
  }

  Future<void> _add(Suggestion suggestion) => _try(() async {
    await widget.hub.friends.add(suggestion.person.handle);
    _discover.requested(suggestion.person.id);
  });

  String _reason(Strings texts, SuggestionReason reason) => switch (reason) {
    GameReason(:final game) => texts.reasonGame(
      widget.gameName?.call(game.titleId) ?? game.name(texts.language),
    ),
    FriendsReason(:final count) => texts.reasonFriends(count),
    LanguageReason(:final language) => texts.reasonLanguage(language),
  };

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 270, child: _settings(texts)),
        const VerticalDivider(width: 1, color: Color(0x14FFFFFF)),
        Expanded(child: _suggestions(texts)),
      ],
    );
  }

  Widget _settings(Strings texts) {
    final discovery = _discover.discovery;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 0, 14, 16),
      children: [
        SectionLabel(texts.showInDiscovery),
        if (discovery == null)
          _error == null
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              : DiscoverFailure(
                  error: _error!,
                  retry: () {
                    setState(() => _error = null);
                    _discover.loadDiscovery().catchError((Object error) {
                      if (mounted) setState(() => _error = error);
                    });
                  },
                )
        else ...[
          ChoiceRow(
            children: [
              for (final (choice, label) in [
                (null, texts.discoveryFollow),
                (true, texts.discoveryOn),
                (false, texts.discoveryOff),
              ])
                ChoicePill(
                  label: label,
                  selected: discovery.chosen == choice,
                  onTap: () => _try(() => _discover.setDiscoverable(choice)),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              discovery.discoverable
                  ? texts.discoveryShown
                  : texts.discoveryHidden,
              style: TextStyle(
                color: discovery.discoverable
                    ? togetherPlaying
                    : Colors.white54,
                fontSize: 12.5,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              texts.discoveryLead,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ),
          SectionLabel(texts.languagesYouPlay),
          ChoiceRow(
            children: [
              for (final code in {...discovery.languages, ...offeredLanguages})
                ChoicePill(
                  label: texts.languageName(code),
                  selected: discovery.languages.contains(code),
                  onTap: discovery.languages.contains(code)
                      ? () => _try(
                          () => _discover.setLanguages(
                            discovery.languages
                                .where((l) => l != code)
                                .toList(),
                          ),
                        )
                      : discovery.languages.length <
                            DiscoverySettings.maxLanguages
                      ? () => _try(
                          () => _discover.setLanguages([
                            ...discovery.languages,
                            code,
                          ]),
                        )
                      : null,
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              texts.languagesHint,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ),
        ],
      ],
    );
  }

  Widget _suggestions(Strings texts) {
    final discover = _discover;
    return RefreshIndicator(
      onRefresh: discover.loadSuggestions,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          SectionLabel(texts.suggestions),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              texts.peopleLead,
              style: const TextStyle(color: Colors.white38, fontSize: 12.5),
            ),
          ),
          if (!discover.suggestionsLoaded)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          if (discover.suggestionsLoaded && discover.suggestions.isEmpty)
            DiscoverEmpty(texts.noSuggestions),
          for (final suggestion in discover.suggestions)
            Padding(
              key: ValueKey(suggestion.person.id),
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.onProfile == null
                          ? null
                          : () => widget.onProfile!(suggestion.person.handle),
                      child: Row(
                        children: [
                          Avatar(
                            person: suggestion.person,
                            presence: suggestion.presence?.state,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  suggestion.person.displayName,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  suggestion.reasons.isEmpty
                                      ? '@${suggestion.person.handle}'
                                      : suggestion.reasons
                                            .map((r) => _reason(texts, r))
                                            .join(' · '),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  switch (suggestion.friendship) {
                    Friendship.none => FilledButton.tonalIcon(
                      onPressed: () => _add(suggestion),
                      icon: const Icon(
                        Icons.person_add_alt_1_rounded,
                        size: 18,
                      ),
                      label: Text(texts.addFriend),
                    ),
                    Friendship.pendingIn => FilledButton(
                      onPressed: () => _try(() async {
                        await widget.hub.friends.answer(
                          suggestion.person.id,
                          accept: true,
                        );
                        await discover.loadSuggestions();
                      }),
                      child: Text(texts.accept),
                    ),
                    Friendship.pendingOut => Text(
                      texts.requested,
                      style: const TextStyle(color: Colors.white38),
                    ),
                    Friendship.friends || Friendship.me => Text(
                      texts.areFriends,
                      style: const TextStyle(color: togetherPlaying),
                    ),
                  },
                ],
              ),
            ),
        ],
      ),
    );
  }
}
