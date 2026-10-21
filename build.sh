#!/bin/zsh
# Builds Bacheca.app in ./build (ad-hoc signed, for this Mac only).
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Bacheca"

APP="build/Bacheca.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Bacheca"
# Icon drawn by scripts/make-icon.swift.
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Bacheca</string>
  <key>CFBundleDisplayName</key><string>Bacheca</string>
  <key>CFBundleIdentifier</key><string>local.bacheca.lockwidgets</string>
  <key>CFBundleExecutable</key><string>Bacheca</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>it</string></array>
  <key>NSCalendarsFullAccessUsageDescription</key><string>Bacheca shows your next event on the lock screen.</string>
  <key>NSRemindersFullAccessUsageDescription</key><string>Bacheca shows your open reminders on the lock screen.</string>
  <key>NSAppleEventsUsageDescription</key><string>Bacheca reads the playing track and its position to show music and synced lyrics.</string>
</dict>
</plist>
PLIST

# Permission prompts in Italian; English comes from Info.plist above.
mkdir -p "$APP/Contents/Resources/en.lproj" "$APP/Contents/Resources/it.lproj"
touch "$APP/Contents/Resources/en.lproj/InfoPlist.strings"
cat > "$APP/Contents/Resources/it.lproj/InfoPlist.strings" <<'STRINGS'
"NSCalendarsFullAccessUsageDescription" = "Bacheca mostra il tuo prossimo evento sulla schermata di blocco.";
"NSRemindersFullAccessUsageDescription" = "Bacheca mostra i tuoi promemoria da fare sulla schermata di blocco.";
"NSAppleEventsUsageDescription" = "Bacheca legge il brano in riproduzione e il punto in cui sei, per mostrare musica e testi sincronizzati.";
STRINGS

codesign --force --sign - "$APP"
echo "Built $APP"
