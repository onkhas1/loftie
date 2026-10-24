#!/bin/zsh
# Сборка Loftie.app.
#   ./build.sh            — локальная сборка, подпись сертификатом разработчика (разрешения macOS не слетают)
#   ./build.sh --install  — то же и установка в ~/Applications с запуском
#   ./build.sh --release  — универсальная сборка (Apple Silicon + Intel), ad-hoc подпись, архив в dist/
set -euo pipefail
cd "$(dirname "$0")"
MODE="${1:-}"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)

if [[ "$MODE" == "--release" ]]; then
  swift build -c release --arch arm64 --arch x86_64
  BIN=.build/apple/Products/Release/Loftie
else
  swift build -c release
  BIN=.build/release/Loftie
fi

APP="build/Loftie.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
cp Icon/AppIcon.icns "$APP/Contents/Resources/"
# Мост к «Сейчас играет»: библиотека для системного perl
clang -dynamiclib -fobjc-arc -framework Foundation -arch arm64 -arch x86_64 -O2 \
  -o "$APP/Contents/Resources/libloftienp.dylib" Bridge/nowplaying.m
cp Bridge/nowplaying.pl "$APP/Contents/Resources/"

if [[ "$MODE" == "--release" ]]; then
  # Для раздачи: ad-hoc подпись без личного сертификата
  codesign --force --deep --sign - "$APP"
  mkdir -p dist
  rm -f "dist/Loftie-$VERSION.zip"
  ditto -c -k --keepParent "$APP" "dist/Loftie-$VERSION.zip"
  # Короткий адрес для curl раздаётся через GitHub Pages из папки docs
  cp install.sh docs/install
  echo "Готово: dist/Loftie-$VERSION.zip"
  exit 0
fi

# Подпись постоянным сертификатом, чтобы macOS не забывала выданные разрешения
IDENTITY=$(security find-identity -p codesigning -v | awk -F'"' '/Apple Development/{print $2; exit}')
codesign --force --deep --sign "${IDENTITY:--}" "$APP"

if [[ "$MODE" == "--install" ]]; then
  pkill -x Loftie || true
  pkill -x NotchPanel || true
  sleep 1
  mkdir -p ~/Applications
  # Старые имена до 1.0
  rm -rf ~/Applications/Chelka.app ~/Applications/Loftie.app
  cp -R "$APP" ~/Applications/
  open ~/Applications/Loftie.app
fi
