#!/bin/sh
# Запасная установка Loftie, если нет Homebrew:
#   curl -fsSL onkhas1.github.io/loftie/install | sh
# (основной способ: brew install onkhas1/tap/loftie)
# Скачивает последний релиз с GitHub, кладёт в /Applications (или ~/Applications) и запускает.
set -eu

REPO="onkhas1/loftie"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

if [ -n "${LOFTIE_ZIP:-}" ]; then
  cp "$LOFTIE_ZIP" "$TMP/Loftie.zip"
else
  echo "→ Ищу последнюю версию Loftie…"
  URL=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
    | grep -o '"browser_download_url": *"[^"]*\.zip"' | head -1 | sed -E 's/.*"(https[^"]+)"/\1/')
  if [ -z "$URL" ]; then
    echo "Не нашёл релиз на github.com/$REPO" >&2
    exit 1
  fi
  echo "→ Скачиваю $URL"
  curl -fsSL "$URL" -o "$TMP/Loftie.zip"
fi

ditto -x -k "$TMP/Loftie.zip" "$TMP"

DEST="${LOFTIE_DEST:-/Applications}"
if [ ! -w "$DEST" ]; then DEST="$HOME/Applications"; fi
mkdir -p "$DEST"

pkill -x Loftie 2>/dev/null || true
rm -rf "$DEST/Loftie.app"
mv "$TMP/Loftie.app" "$DEST/"
# Приложение бесплатное и без платной подписи Apple, поэтому снимаем пометку «скачано из интернета»
xattr -dr com.apple.quarantine "$DEST/Loftie.app" 2>/dev/null || true

echo "✓ Loftie установлен в $DEST"
if [ -z "${LOFTIE_NO_OPEN:-}" ]; then open "$DEST/Loftie.app"; fi
