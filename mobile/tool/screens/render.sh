#!/bin/sh
set -e
cd "$(dirname "$0")/../.."
flutter test tool/screens/render_test.dart
for png in build/screens/*.png; do
  name=$(basename "$png" .png)
  sips -s format jpeg -s formatOptions 82 -z 824 1200 "$png" --out "../docs/screenshots/$name.jpg" >/dev/null
  echo "docs/screenshots/$name.jpg"
done
