#!/bin/sh
# Draws the app icon (tool/icon.swift) and writes every size Android and iOS ask for.
#     tool/make_icons.sh
set -eu
cd "$(dirname "$0")/.."
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
for kind in full background foreground tile; do swift tool/icon.swift "$work/$kind.png" "$kind"; done

res=android/app/src/main/res
# Android: the tile before 8.0, the adaptive icon's two layers (108 dp) after.
for pair in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
    density=${pair%%:*}
    side=${pair##*:}
    layer=$((side * 9 / 4))
    sips -z "$side" "$side" "$work/tile.png" --out "$res/mipmap-$density/ic_launcher.png" >/dev/null
    sips -z "$layer" "$layer" "$work/background.png" --out "$res/mipmap-$density/ic_launcher_background.png" >/dev/null
    sips -z "$layer" "$layer" "$work/foreground.png" --out "$res/mipmap-$density/ic_launcher_foreground.png" >/dev/null
done
mkdir -p "$res/mipmap-anydpi-v26"
cat > "$res/mipmap-anydpi-v26/ic_launcher.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
XML

# iOS: the square at every size the asset catalog names; iOS rounds the corners.
icons=ios/Runner/Assets.xcassets/AppIcon.appiconset
for file in "$icons"/Icon-App-*.png; do
    name=$(basename "$file" .png)
    points=${name#Icon-App-}
    points=${points%%x*}
    factor=${name##*@}
    factor=${factor%x}
    side=$(echo "$points * $factor" | bc | cut -d. -f1)
    sips -z "$side" "$side" "$work/full.png" --out "$file" >/dev/null
done
# The About sheet shows the icon itself.
mkdir -p assets
sips -z 256 256 "$work/full.png" --out assets/icon.png >/dev/null
echo "icons written"
