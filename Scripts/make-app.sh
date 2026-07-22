#!/usr/bin/env bash
# Costruisce Mosaico.app dalla build release e produce Mosaico.zip
# pronto per la distribuzione.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
APP="$ROOT/dist/Mosaico.app"

echo "==> swift build -c release"
swift build -c release

echo "==> assemblo bundle"
rm -rf "$ROOT/dist"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/.build/release/Mosaico" "$APP/Contents/MacOS/Mosaico"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

# Firma con "Mosaico Dev" se presente nel keychain (identità stabile:
# il permesso Accessibilità sopravvive ai rebuild), altrimenti ad-hoc.
if security find-identity -v -p codesigning 2>/dev/null | grep -q "Mosaico Dev"; then
  echo "==> codesign (Mosaico Dev)"
  codesign --force --options runtime --sign "Mosaico Dev" "$APP"
else
  echo "==> codesign (ad-hoc — permesso Accessibilità da ridare a ogni build)"
  codesign --force --options runtime --sign - "$APP"
fi

echo "==> zip"
ditto -c -k --keepParent "$APP" "$ROOT/dist/Mosaico.zip"

echo
echo "Fatto: $APP"
echo "Zip:   $ROOT/dist/Mosaico.zip"
echo
echo "NOTA Gatekeeper (build non notarizzata): al primo avvio da download"
echo "serve tasto destro → Apri → Apri, oppure:"
echo "  xattr -dr com.apple.quarantine /Applications/Mosaico.app"
