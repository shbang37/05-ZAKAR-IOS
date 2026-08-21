#!/bin/bash
# ============================================================
# ZAKAR Mac 배포 패키지 생성 (Developer ID + 공증 + DMG)
#
# 결과물: Tools/MacRelease/build/ZAKAR-Mac-<버전>.dmg
#         → 이 파일 하나만 동역자에게 전달하면 됩니다.
#
# 사전 준비 (최초 1회만, 사용자가 직접):
#   1) developer.apple.com → Certificates → "Developer ID Application" 인증서 생성·설치
#   2) appleid.apple.com → 로그인 및 보안 → 앱 암호 생성
#   3) 아래 명령으로 공증 자격증명 저장 (암호는 본인만 입력)
#      xcrun notarytool store-credentials "zakar-notary" \
#        --apple-id <애플ID> --team-id 3WZ7DUJB2W --password <앱 암호>
#
# 사용: bash Tools/MacRelease/package_mac.sh
# ============================================================
set -euo pipefail

TEAM_ID="3WZ7DUJB2W"
SCHEME="ZAKAR Mac"
KEYCHAIN_PROFILE="zakar-notary"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
ARCHIVE="$BUILD_DIR/ZAKAR-Mac.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"

echo "▶ 0/5 사전 점검"
if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
  echo "❌ 'Developer ID Application' 인증서가 없습니다."
  echo "   developer.apple.com → Certificates 에서 발급·설치한 뒤 다시 실행하세요."
  echo "   (Apple Development / Apple Distribution 인증서로는 외부 배포가 불가능합니다)"
  exit 1
fi
if ! xcrun notarytool history --keychain-profile "$KEYCHAIN_PROFILE" >/dev/null 2>&1; then
  echo "❌ 공증 자격증명 '$KEYCHAIN_PROFILE' 이 없습니다."
  echo "   xcrun notarytool store-credentials \"$KEYCHAIN_PROFILE\" \\"
  echo "     --apple-id <애플ID> --team-id $TEAM_ID --password <앱 암호>"
  exit 1
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "▶ 1/5 아카이브 빌드"
xcodebuild -project "$REPO_DIR/ZAKAR.xcodeproj" \
  -scheme "$SCHEME" -configuration Release \
  -destination 'platform=macOS' \
  -archivePath "$ARCHIVE" archive

echo "▶ 2/5 Developer ID로 내보내기"
cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
  -exportPath "$EXPORT_DIR"

APP="$EXPORT_DIR/$SCHEME.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD_NUM="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Contents/Info.plist")"
echo "   버전 $VERSION (빌드 $BUILD_NUM)"

echo "▶ 3/5 공증 요청 (Apple 서버 처리, 보통 2~10분)"
ZIP="$BUILD_DIR/ZAKAR-Mac-notarize.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$KEYCHAIN_PROFILE" --wait

echo "▶ 4/5 공증 결과 앱에 첨부(staple)"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "▶ 5/5 DMG 생성"
DMG_SRC="$BUILD_DIR/dmg"
DMG="$BUILD_DIR/ZAKAR-Mac-$VERSION.dmg"
mkdir -p "$DMG_SRC"
cp -R "$APP" "$DMG_SRC/"
ln -s /Applications "$DMG_SRC/Applications"   # 드래그해서 설치하도록
hdiutil create -volname "ZAKAR Mac" -srcfolder "$DMG_SRC" -ov -format UDZO "$DMG"

# DMG 자체도 서명·공증해 두면 받는 쪽 경고가 완전히 사라진다
DEV_ID="$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)"/\1/')"
codesign --force --sign "$DEV_ID" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$KEYCHAIN_PROFILE" --wait
xcrun stapler staple "$DMG"

echo ""
echo "✅ 완료 → $DMG"
echo "   이 파일을 카카오톡·구글드라이브·메일 무엇으로 보내든 그대로 실행됩니다."
