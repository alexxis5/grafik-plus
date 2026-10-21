#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
APP="$ROOT/dist/График Плюс.app"
BIN="$APP/Contents/MacOS/GrafikPlus"

rm -rf "$ROOT/dist"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

echo "Компиляция График Плюс…"
swiftc -parse-as-library -O \
  -target arm64-apple-macosx14.0 \
  -sdk "$SDK" \
  -framework SwiftUI \
  -framework AppKit \
  -framework Combine \
  -framework UniformTypeIdentifiers \
  -o "$BIN" \
  "$ROOT"/Sources/*.swift

chmod +x "$BIN"
echo "Готово: $APP"
