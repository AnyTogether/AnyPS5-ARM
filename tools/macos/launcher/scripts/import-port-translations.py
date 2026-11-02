#!/usr/bin/env python3
"""Carries AnyLauncher Port's translations over to the Mac launcher's language files.

    python3 -I scripts/import-port-translations.py <AnyPS5-Desktop checkout> [code ...]

A key whose English text is the same in both launchers' en.json means the same thing, so its
translation fits here too. So does one whose English differs in capitals only (My picture, My
Picture). A key whose English differs otherwise (the Port says PC where the Mac says Mac) is
left out, and the Mac shows its English text instead. With codes (cs zh-Hant) only those
languages are written; without, every one the Port has. Turkish is kept by hand in this
repository and is not touched. A text a Mac translator added for a key only the Mac has stays in
the file. Every file is written in en.json's key order.
"""

import json
import os
import sys
from collections import OrderedDict

HERE = os.path.dirname(os.path.abspath(__file__))
L10N = os.path.join(HERE, "..", "l10n")
SKIPPED = {"en", "tr"}


def read(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle, object_pairs_hook=OrderedDict)


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__.strip().splitlines()[2].strip())
    port = os.path.join(sys.argv[1], "assets", "l10n")
    only = set(sys.argv[2:])
    mac_english = read(os.path.join(L10N, "en.json"))
    port_english = read(os.path.join(port, "en.json"))

    def same(key):
        theirs = port_english.get(key)
        return isinstance(theirs, str) and theirs.casefold() == mac_english[key].casefold()

    shared = [key for key in mac_english if same(key)]
    print(f"{len(shared)} of en.json's {len(mac_english)} keys read the same in the Port's en.json")
    for name in sorted(os.listdir(port)):
        code, extension = os.path.splitext(name)
        if extension != ".json" or code in SKIPPED or (only and code not in only):
            continue
        theirs = read(os.path.join(port, name))
        target = os.path.join(L10N, name)
        own = read(target) if os.path.exists(target) else OrderedDict()
        merged = OrderedDict()
        for key in mac_english:
            if key in shared:
                text = theirs.get(key)
                if isinstance(text, str):
                    merged[key] = text
            elif key not in port_english and isinstance(own.get(key), str):
                merged[key] = own[key]
        with open(target, "w", encoding="utf-8") as handle:
            json.dump(merged, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
        print(f"{name}: {len(merged)} texts")


if __name__ == "__main__":
    main()
