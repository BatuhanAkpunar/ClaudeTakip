#!/bin/bash
# Claude Limit yayın betiği.
#
# İki adım:
#   1) tools/release.sh 0.2.0            sürümü artırır, derler, dist/ altında
#                                        paketler. HİÇBİR ŞEY YAYINLAMAZ.
#   2) sürüm değişikliğini commit + push et
#   3) tools/release.sh 0.2.0 --publish  push'lanmış commit'ten yeniden derleyip
#                                        GitHub'da v0.2.0 release'ini açar.
#
# Ayrım bilinçli: etiket GitHub'daki main'e atılıyor; derlenen kod, etiketlenen
# kodla (sürüm numarası dahil) birebir aynı olmak zorunda.
#
# Ürettikleri (dist/):
#   Claude-Limit-<sürüm>.dmg   ilk kurulum, elle indirme (web sitesindeki bağlantı)
#   Claude-Limit-<sürüm>.zip   otomatik güncelleme arşivi, EdDSA ile imzalı
#   appcast.xml                güncelleme beslemesi
#
# Uygulama beslemeyi şuradan okuyor:
#   https://github.com/BatuhanAkpunar/ClaudeTakip/releases/latest/download/appcast.xml
# "latest" her zaman en yeni release'e yönlendiği için her release kendi
# appcast.xml'ini taşıyor; ayrı bir sunucu ya da dal gerekmiyor.
#
# İmza anahtarı repo DIŞINDA: ~/.config/claude-limit/sparkle_ed25519_private.key
# Kaybolursa mevcut kullanıcılara bir daha otomatik güncelleme gönderilemez
# (uygulama yalnızca gömülü açık anahtarla doğrulanan arşivi kurar). Yedekle.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
MODE="${2:-}"
if [ -z "$VERSION" ]; then
  echo "Kullanım: tools/release.sh <sürüm> [--publish]"; exit 1
fi

REPO="BatuhanAkpunar/ClaudeTakip"
KEY="${SPARKLE_KEY_FILE:-$HOME/.config/claude-limit/sparkle_ed25519_private.key}"
[ -f "$KEY" ] || { echo "İmza anahtarı bulunamadı: $KEY"; exit 1; }

CURRENT=$(sed -nE 's/^ *MARKETING_VERSION: "?([^"]+)"?$/\1/p' project.yml)
BUILD=$(sed -nE 's/^ *CURRENT_PROJECT_VERSION: "?([0-9]+)"?$/\1/p' project.yml)

if [ "$MODE" = "--publish" ]; then
  # Sürüm zaten artırılmış, commit'lenmiş ve push'lanmış olmalı.
  git fetch -q origin
  [ "$CURRENT" = "$VERSION" ] || { echo "project.yml sürümü $CURRENT; önce 'tools/release.sh $VERSION' + commit + push."; exit 1; }
  if [ -n "$(git status --porcelain)" ] || [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]; then
    echo "Yayın için çalışma ağacı temiz ve HEAD = origin/main olmalı (önce commit + push)."; exit 1
  fi
  if gh release view "v$VERSION" -R "$REPO" >/dev/null 2>&1; then
    echo "v$VERSION zaten yayında."; exit 1
  fi
  NEW_BUILD=$BUILD
  echo "▸ yayın: v$VERSION (derleme $BUILD), commit $(git rev-parse --short HEAD)"
else
  # ── 1. Sürüm ───────────────────────────────────────────────────────────────
  if [ "$CURRENT" = "$VERSION" ] || [ "$(printf '%s\n%s\n' "$CURRENT" "$VERSION" | sort -V | tail -1)" != "$VERSION" ]; then
    echo "Yeni sürüm $CURRENT'ten büyük olmalı (verilen: $VERSION)."; exit 1
  fi
  NEW_BUILD=$((BUILD + 1))
  sed -i '' -E "s/^( *MARKETING_VERSION: )\"[^\"]*\"/\1\"$VERSION\"/" project.yml
  sed -i '' -E "s/^( *CURRENT_PROJECT_VERSION: )\"?[0-9]+\"?/\1\"$NEW_BUILD\"/" project.yml
  echo "▸ sürüm $CURRENT → $VERSION (derleme $BUILD → $NEW_BUILD)"
fi
xcodegen generate >/dev/null

# ── 2. Derleme ───────────────────────────────────────────────────────────────
xcodebuild -project ClaudeLimit.xcodeproj -scheme ClaudeLimit -configuration Release \
  -derivedDataPath .build/xcode-rel build 2>/dev/null | tail -1
APP=".build/xcode-rel/Build/Products/Release/Claude Limit.app"
BUILT=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
[ "$BUILT" = "$VERSION" ] || { echo "Derlenen sürüm $BUILT, beklenen $VERSION"; exit 1; }

# ── 3. DMG (uygulamayı yerinde imzalar) ──────────────────────────────────────
tools/make-dmg.sh

# ── 4-5. Güncelleme arşivi + imza ────────────────────────────────────────────
# ZIP, make-dmg'nin imzaladığı uygulamadan: güncellemeyle gelen paket ile
# DMG'deki paket birebir aynı.
ZIP="dist/Claude-Limit-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
SIGN_UPDATE=$(find .build/xcode-rel/SourcePackages/artifacts -path "*/Sparkle/bin/sign_update" -type f | head -1)
SIGNATURE_ATTRS=$("$SIGN_UPDATE" --ed-key-file "$KEY" "$ZIP")
SIGNATURE=$(printf '%s' "$SIGNATURE_ATTRS" | sed -nE 's/.*sparkle:edSignature="([^"]+)".*/\1/p')
"$SIGN_UPDATE" --verify --ed-key-file "$KEY" "$ZIP" "$SIGNATURE" >/dev/null
echo "▸ güncelleme arşivi imzalandı ve doğrulandı: $ZIP"

# ── 6. Besleme ───────────────────────────────────────────────────────────────
cat > dist/appcast.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Claude Limit</title>
    <item>
      <title>$VERSION</title>
      <pubDate>$(LC_ALL=C date -R)</pubDate>
      <sparkle:version>$NEW_BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
      <enclosure url="https://github.com/$REPO/releases/download/v$VERSION/Claude-Limit-$VERSION.zip"
                 type="application/octet-stream" $SIGNATURE_ATTRS/>
    </item>
  </channel>
</rss>
XML
echo "▸ besleme: dist/appcast.xml"

# ── 7. Yayın ─────────────────────────────────────────────────────────────────
if [ "$MODE" = "--publish" ]; then
  # DMG iki adla: sürümlü olan arşiv için, sabit adlı olan web sitesi için.
  # Site "releases/latest/download/Claude-Limit.dmg" bağlantısını kullanırsa
  # her zaman en yeni (kendini güncelleyen) sürümü verir ve bir daha elle
  # güncellenmesi gerekmez. Sürümlü bağlantıda kalırsa yeni kullanıcılar eski
  # sürümü indirir.
  cp "dist/Claude-Limit-$VERSION.dmg" dist/Claude-Limit.dmg
  gh release create "v$VERSION" "dist/Claude-Limit-$VERSION.dmg" dist/Claude-Limit.dmg "$ZIP" dist/appcast.xml \
    -R "$REPO" --target main --title "Claude Limit v$VERSION" \
    --notes "Automatic update: running copies of Claude Limit install this version on their own. New installs: download Claude-Limit-$VERSION.dmg."
  echo "▸ yayınlandı: https://github.com/$REPO/releases/tag/v$VERSION"
else
  echo "▸ YAYINLANMADI. Sürüm değişikliğini (project.yml + xcodeproj) commit + push et, sonra:"
  echo "    tools/release.sh $VERSION --publish"
fi
