#!/bin/bash
# Claude Takip DMG paketleyici.
# Kullanım: tools/make-dmg.sh [imza-kimliği]
#   argüman verilmezse ad-hoc imza (Apple Developer hesabı gerekmez).
set -euo pipefail
cd "$(dirname "$0")/.."

APP=".build/xcode-rel/Build/Products/Release/Claude Takip.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
SIGN_ID="${1:--}"   # varsayılan: ad-hoc "-"
OUT="dist/Claude-Takip-$VERSION.dmg"
# `dist/` git'e girmiyor; temiz bir klonda yok ve hdiutil klasörü kendisi açmıyor.
mkdir -p dist

echo "▸ imzalanıyor ($([ "$SIGN_ID" = "-" ] && echo ad-hoc || echo "$SIGN_ID"))"
if [ "$SIGN_ID" = "-" ]; then
  # Ad-hoc imzada hardened runtime YOK. Hardened runtime'ın kütüphane
  # doğrulaması, uygulamanın içine gömülü ayrı imzalı kütüphaneleri
  # (Sparkle.framework) "farklı Team ID" diye reddediyor; ad-hoc imzada Team
  # ID olmadığı için eşleşme hiç sağlanamıyor ve uygulama AÇILMIYOR (dyld:
  # "mapping process and mapped file have different Team IDs"). Hardened
  # runtime yalnızca notarizasyon için gerekli, o da Developer ID ister.
  codesign --force --deep --sign - "$APP"
else
  # Gerçek kimlikte her şey aynı Team ID ile imzalanıyor; notarizasyon için
  # hardened runtime şart.
  codesign --force --deep --options runtime --sign "$SIGN_ID" "$APP"
fi
codesign --verify --deep --strict "$APP" && echo "  imza geçerli"

STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/OKU BENI.txt" <<'TXT'
Claude Takip kurulumu
=====================

1) Claude Takip'i soldaki Applications klasörüne sürükle.

2) İlk açılışta "tanımlanamayan geliştirici" ya da "hasarlı" uyarısı
   çıkarsa (uygulama imzalı ama Apple tarafından notarize edilmediği
   için bu normaldir):

   - Applications içinde Claude Takip'e SAĞ TIKLA -> Aç -> Aç
     (izin bir kez verilir, sonrasında normal açılır)

   ya da Terminal'de:

     xattr -cr "/Applications/Claude Takip.app"

3) Uygulama menü çubuğunda açılır, Dock'ta görünmez.
   Çıkmak için: menü çubuğu simgesi -> güç düğmesi.
TXT

rm -f "$OUT"
hdiutil create -volname "Claude Takip" -srcfolder "$STAGE" \
  -ov -format UDZO "$OUT" >/dev/null
rm -rf "$STAGE"
SIZE=$(du -h "$OUT" | cut -f1)
echo "▸ DMG hazır: $OUT ($SIZE)"
