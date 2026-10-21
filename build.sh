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

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Bacheca</string>
  <key>CFBundleDisplayName</key><string>Bacheca</string>
  <key>CFBundleIdentifier</key><string>local.bacheca.lockwidgets</string>
  <key>CFBundleExecutable</key><string>Bacheca</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
  <key>NSCalendarsFullAccessUsageDescription</key><string>Bacheca mostra il tuo prossimo evento sulla schermata di blocco.</string>
  <key>NSRemindersFullAccessUsageDescription</key><string>Bacheca mostra i tuoi promemoria da fare sulla schermata di blocco.</string>
  <key>NSAppleEventsUsageDescription</key><string>Bacheca legge il brano in riproduzione e il punto in cui sei, per mostrare musica e testi sincronizzati.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Creata $APP"
