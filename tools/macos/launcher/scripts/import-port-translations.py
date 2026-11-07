#!/usr/bin/env python3
"""Carries AnyPS5 Desktop's translations over to the Mac launcher's language files.

    python3 -I scripts/import-port-translations.py <AnyPS5-Desktop checkout> [code ...]

A Mac text takes Desktop's translation when both launchers' English says the same thing:

1. The same key whose English reads the same in both en.json files (capitals aside: My picture,
   My Picture).
2. A key listed in SAME_MEANING, worded otherwise on Desktop but meaning the same.
3. Otherwise another Desktop key whose English reads the same (capitals and a final full stop
   aside): the Mac's "Remove the music" is Desktop's "Remove the music" under whatever key. Where
   the Mac leaves the full stop out, the translation's is left out too. Where several Desktop keys
   read the same and their translations differ, the one most of them use is taken.

A translation whose placeholders (%@, %d, %1$@) are not the Mac English's is left out. A text the
Mac says in its own words (Mac where Desktop says PC) matches nothing and shows in English, unless
a translator wrote it here: a text the Mac's file has for a key only the Mac has stays in the
file (the Mac's own words get a key of their own, phoneServerDetailMac beside Desktop's
phoneServerDetail). LEFT_OUT names Desktop translations that read wrong for the Mac (a
mistranslation) and are never carried over. With codes (cs zh-Hant) only those languages are
written; without, every one Desktop has. Turkish is kept by hand in this repository and is not
touched. Every file is written in en.json's key order.
"""

import json
import os
import re
import sys
from collections import Counter, OrderedDict

HERE = os.path.dirname(os.path.abspath(__file__))
L10N = os.path.join(HERE, "..", "l10n")
SKIPPED = {"en", "tr"}

# Desktop translations that are wrong here, by language: key, and why.
LEFT_OUT = {
    # "Checks the remote" read as a remote control (пульт).
    "ru": {"engineGitBeforePlayDetail"},
}

# Keys whose English the two launchers word differently but mean the same by (cancelled and
# withdrawn, quit and close, Wheel ↑ and Wheel up): Desktop's translation fits the Mac too. A
# count Desktop fills with %@ where the Mac has %d takes the Mac's.
SAME_MEANING = {
    "settingsSearchNone", "linkCopied", "friendsCancelRequest", "friendsRequestCancelled", "wheelUp", "wheelDown",
    "profilePictureSaved", "profilePictureRemove", "padFinding_bluetoothPairing", "engineReady", "familyLeftToday",
    "familyNoLimitToday", "familyTimeUp", "fontsLatin", "shortcutsGameButtons", "screenshotFailed", "partyRequestWithCode",
    "preparingPaused", "reportOpenIssue", "sharePlayWatchDetail", "challengeGone", "challengeJoined",
    "challengeTrophiesValue", "challengeEntrants", "steamRunningDetail", "steamCloseAndAdd", "steamCloseAndRemove",
    "steamClosing", "steamWouldNotClose", "engineGitRunning", "engineGitBuiltAt", "engineGitRelinkAll",
}

# A final full stop in the scripts the files use.
STOPS = (".", "。", "।", "။", "።", "۔", "។")

PLACEHOLDER = re.compile(r"%(?:(\d+)\$)?[-+#0-9.]*([hlqLzjt]*[@dDiuUxXoOfFeEgGcCsSpaA])")


def read(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle, object_pairs_hook=OrderedDict)


def placeholders(text):
    """(number, kind) for each placeholder, as LanguageFiles.placeholders reads them."""
    found = set()
    following = 0
    for match in PLACEHOLDER.finditer(text.replace("%%", "")):
        if match.group(1):
            found.add((int(match.group(1)), match.group(2)))
        else:
            following += 1
            found.add((following, match.group(2)))
    return found


def plain(text):
    """English for matching: capitals and a final full stop aside."""
    text = text.strip().casefold()
    return text[:-1].rstrip() if text.endswith(".") else text


def fitted(translation, english, port_english):
    """The translation with its final stop taken off where the Mac's English has none and
    Desktop's has one."""
    if port_english.strip().endswith(".") and not english.strip().endswith("."):
        stripped = translation.rstrip()
        if stripped.endswith(STOPS):
            return stripped[:-1].rstrip()
    return translation


def retyped(translation, english):
    """A single %@ made the Mac English's single %d."""
    if placeholders(english) == {(1, "d")} and placeholders(translation) == {(1, "@")}:
        return translation.replace("%@", "%d")
    return translation


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__.strip().splitlines()[2].strip())
    port = os.path.join(sys.argv[1], "assets", "l10n")
    only = set(sys.argv[2:])
    mac_english = read(os.path.join(L10N, "en.json"))
    port_english = read(os.path.join(port, "en.json"))

    def same_key(key):
        theirs = port_english.get(key)
        return isinstance(theirs, str) and theirs.casefold() == mac_english[key].casefold()

    by_text = {}
    for key, text in port_english.items():
        if isinstance(text, str) and key != "languageName":
            by_text.setdefault(plain(text), []).append(key)

    shared = [key for key in mac_english if same_key(key)]
    matched = {key: by_text[plain(mac_english[key])] for key in mac_english
               if key not in shared and key != "languageName" and plain(mac_english[key]) in by_text}
    print(f"{len(shared)} of en.json's {len(mac_english)} keys read the same in Desktop's en.json, "
          f"{len(matched)} more read as another Desktop key")
    for name in sorted(os.listdir(port)):
        code, extension = os.path.splitext(name)
        if extension != ".json" or code in SKIPPED or (only and code not in only):
            continue
        theirs = read(os.path.join(port, name))
        target = os.path.join(L10N, name)
        own = read(target) if os.path.exists(target) else OrderedDict()
        left_out = LEFT_OUT.get(code, set())
        merged = OrderedDict()
        for key, english in mac_english.items():
            text = None
            if key in shared:
                text = theirs.get(key) if key not in left_out else None
            elif key in SAME_MEANING and isinstance(theirs.get(key), str) and key not in left_out:
                text = retyped(fitted(theirs[key], english, port_english[key]), english)
            elif key not in port_english and isinstance(own.get(key), str):
                # A key only the Mac has, translated here.
                text = own[key]
            elif key in matched:
                found = Counter()
                for other in matched[key]:
                    translation = theirs.get(other)
                    if isinstance(translation, str) and other not in left_out:
                        found[fitted(translation, english, port_english[other])] += 1
                if found:
                    text = found.most_common(1)[0][0]
            if isinstance(text, str) and placeholders(text) == placeholders(english):
                merged[key] = text
        with open(target, "w", encoding="utf-8") as handle:
            json.dump(merged, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
        print(f"{name}: {len(merged)} of {len(mac_english)} texts ({100 * len(merged) // len(mac_english)}%)")


if __name__ == "__main__":
    main()
