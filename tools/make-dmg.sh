#!/bin/bash
# Claude Limit DMG paketleyici.
# Kullanım: tools/make-dmg.sh [imza-kimliği]
#   argüman verilmezse ad-hoc imza (Apple Developer hesabı gerekmez).
set -euo pipefail
cd "$(dirname "$0")/.."

APP=".build/xcode-rel/Build/Products/Release/Claude Limit.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
SIGN_ID="${1:--}"   # varsayılan: ad-hoc "-"
OUT="dist/Claude-Limit-$VERSION.dmg"
# `dist/` git'e girmiyor; temiz bir klonda yok ve hdiutil klasörü kendisi açmıyor.
mkdir -p dist

echo "▸ imzalanıyor ($([ "$SIGN_ID" = "-" ] && echo ad-hoc || echo "$SIGN_ID"))"
codesign --force --deep --options runtime --sign "$SIGN_ID" "$APP" 2>/dev/null \
  || codesign --force --deep --sign "$SIGN_ID" "$APP"
codesign --verify --deep --strict "$APP" && echo "  imza geçerli"

STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/OKU BENI.txt" <<'TXT'
Claude Limit kurulumu
=====================

1) Claude Limit'i soldaki Applications klasörüne sürükle.

2) İlk açılışta "tanımlanamayan geliştirici" ya da "hasarlı" uyarısı
   çıkarsa (uygulama imzalı ama Apple tarafından notarize edilmediği
   için bu normaldir):

   - Applications içinde Claude Limit'e SAĞ TIKLA -> Aç -> Aç
     (izin bir kez verilir, sonrasında normal açılır)

   ya da Terminal'de:

     xattr -cr "/Applications/Claude Limit.app"

3) Uygulama menü çubuğunda açılır, Dock'ta görünmez.
   Çıkmak için: menü çubuğu simgesi -> güç düğmesi.
TXT

rm -f "$OUT"
hdiutil create -volname "Claude Limit" -srcfolder "$STAGE" \
  -ov -format UDZO "$OUT" >/dev/null
rm -rf "$STAGE"
SIZE=$(du -h "$OUT" | cut -f1)
echo "▸ DMG hazır: $OUT ($SIZE)"
