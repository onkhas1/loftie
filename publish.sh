#!/bin/zsh
# Выпуск новой версии Loftie: сборка, релиз на GitHub, обновление рецепта Homebrew.
#   1. Подними версию в Info.plist (CFBundleShortVersionString и CFBundleVersion)
#   2. ./publish.sh "Что нового в этой версии"
# Нужно: gh (вход в onkhas1), рядом папка ../homebrew-tap — клон onkhas1/homebrew-tap.
set -euo pipefail
cd "$(dirname "$0")"
NOTES="${1:-}"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
TAP="../homebrew-tap"

if gh release view "v$VERSION" >/dev/null 2>&1; then
  echo "Релиз v$VERSION уже есть — подними версию в Info.plist" >&2
  exit 1
fi

./build.sh --release
ZIP="dist/Loftie-$VERSION.zip"
SHA=$(shasum -a 256 "$ZIP" | awk '{print $1}')

git add -A
git commit -m "Loftie $VERSION" ${COMMIT_TRAILER:+-m "$COMMIT_TRAILER"} || true
git tag "v$VERSION"
git push origin main --tags

gh release create "v$VERSION" "$ZIP" --title "Loftie $VERSION" --notes "${NOTES:-Loftie $VERSION}"

# Рецепт Homebrew: новая версия и контрольная сумма архива
sed -i '' -E "s/^  version \".*\"/  version \"$VERSION\"/; s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$TAP/Casks/loftie.rb"
git -C "$TAP" add Casks/loftie.rb
git -C "$TAP" commit -m "loftie $VERSION" ${COMMIT_TRAILER:+-m "$COMMIT_TRAILER"}
git -C "$TAP" push origin main

echo "✓ Loftie $VERSION опубликован. brew upgrade loftie подтянет новую версию."
