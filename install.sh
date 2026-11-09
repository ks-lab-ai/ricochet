#!/bin/bash
# Compile Ricochet depuis les sources et l'installe dans /Applications.
# Usage : ./install.sh          (compile, installe, lance)
#         ./install.sh --build  (compile seulement, dans build/)
set -euo pipefail
cd "$(dirname "$0")"

if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "Outils Apple manquants. Lancez : xcode-select --install, puis relancez ce script." >&2
  exit 1
fi

SDK=$(xcrun --sdk macosx --show-sdk-path)
TARGET="$(uname -m)-apple-macos14.0"
APP=build/Ricochet.app

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp App/Info.plist "$APP/Contents/Info.plist"
cp App/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Le résumé par Apple Intelligence est facultatif : macOS 26 et un SDK récent sont requis.
WEAK=()
if [ -d "$SDK/System/Library/Frameworks/FoundationModels.framework" ]; then
  WEAK=(-Xlinker -weak_framework -Xlinker FoundationModels)
fi

echo "Compilation..."
xcrun swiftc -O -target "$TARGET" -sdk "$SDK" -parse-as-library Sources/*.swift \
  ${WEAK[@]+"${WEAK[@]}"} -o "$APP/Contents/MacOS/Ricochet"

# Signature locale, sans compte développeur.
codesign --force --sign - "$APP"

if [ "${1:-}" = "--build" ]; then
  echo "Compilé : $APP"
  exit 0
fi

pkill -x Ricochet 2>/dev/null || true
rm -rf /Applications/Ricochet.app
cp -R "$APP" /Applications/Ricochet.app
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f -R /Applications/Ricochet.app
open /Applications/Ricochet.app
echo "Ricochet est installé et lancé : son étoile est dans la barre de menus."
