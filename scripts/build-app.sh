#!/usr/bin/env bash
# Construit FaceKey.app (menu bar + fenêtres) et l'installe dans /Applications.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$HERE/scripts/macos-target.sh"
APP="$HERE/build/FaceKey.app"
BUNDLE_ID="com.jjannahm.FaceKey"
DEST="/Applications/FaceKey.app"

echo "== Arrêt d'une instance existante =="
pkill -f "FaceKey.app/Contents/MacOS/FaceKey" 2>/dev/null || true
pkill -f "faceid.daemon" 2>/dev/null || true
sleep 1

echo "== Régénération du glyphe source =="
"$HERE/.venv/bin/python" "$HERE/scripts/make_icon.py"

echo "== Sparkle (auto-update) =="
bash "$HERE/scripts/fetch-sparkle.sh"

echo "== Icône (.icns) =="
"$HERE/.venv/bin/python" "$HERE/scripts/make_appicon.py"
ICONSET="$HERE/build/FaceKey.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
SRC="$HERE/assets/appicon-1024.png"
for sz in 16 32 128 256 512; do
  sips -z $sz $sz     "$SRC" --out "$ICONSET/icon_${sz}x${sz}.png"     >/dev/null
  sips -z $((sz*2)) $((sz*2)) "$SRC" --out "$ICONSET/icon_${sz}x${sz}@2x.png" >/dev/null
done
cp "$SRC" "$ICONSET/icon_512x512@2x.png"
if ! iconutil -c icns "$ICONSET" -o "$HERE/assets/FaceKey.icns"; then
  [ -f "$HERE/assets/FaceKey.icns" ] || exit 1
  echo "Avertissement: iconutil a échoué; réutilisation de assets/FaceKey.icns" >&2
fi

echo "== Assemblage du bundle =="
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>            <string>FaceKey</string>
  <key>CFBundleDisplayName</key>     <string>FaceKey</string>
  <key>CFBundleIdentifier</key>      <string>${BUNDLE_ID}</string>
  <key>CFBundleExecutable</key>      <string>FaceKey</string>
  <key>CFBundleIconFile</key>        <string>FaceKey</string>
  <key>CFBundlePackageType</key>     <string>APPL</string>
  <key>CFBundleShortVersionString</key> <string>1.1.1</string>
  <key>CFBundleVersion</key>         <string>5</string>
  <key>LSUIElement</key>             <true/>
  <key>LSMinimumSystemVersion</key>  <string>${MACOSX_DEPLOYMENT_TARGET}</string>
  <key>SUFeedURL</key>               <string>https://raw.githubusercontent.com/jjannahm/facekey-macos/main/appcast.xml</string>
  <key>SUPublicEDKey</key>           <string>MYs0iwYg/b5lDERYBHVBBiIw8R2awqExOluwOfZlp0w=</string>
  <key>SUEnableAutomaticChecks</key> <true/>
  <key>CFBundleDevelopmentRegion</key> <string>en</string>
  <key>CFBundleLocalizations</key>
  <array>
    <string>en</string><string>fr</string><string>es</string><string>de</string>
    <string>it</string><string>pt-BR</string><string>nl</string><string>ja</string>
    <string>zh-Hans</string><string>ko</string><string>ru</string>
  </array>
  <key>NSCameraUsageDescription</key>
  <string>FaceKey uses the camera for local face enrollment and explicit approvals.</string>
  <key>NSCameraUseContinuityCameraDeviceType</key><false/>
  <key>FaceIDProjectRoot</key>       <string>${HERE}</string>
</dict>
</plist>
PLIST

cp "$HERE/assets/FaceKey.icns" "$APP/Contents/Resources/FaceKey.icns"
cp "$HERE/assets/faceid-icon.png" "$APP/Contents/Resources/faceid-icon.png"
cp "$HERE/assets/menubar-icon.png" "$APP/Contents/Resources/menubar-icon.png"
mkdir -p "$APP/Contents/Frameworks"
cp -R "$HERE/vendor/sparkle/Sparkle.framework" "$APP/Contents/Frameworks/"
# daemon privilégié (SMAppService) : plist du LaunchDaemon
mkdir -p "$APP/Contents/Library/LaunchDaemons"
cp "$HERE/helpertool/com.jjannahm.FaceKey.Helper.plist" "$APP/Contents/Library/LaunchDaemons/"
# module PAM + scripts privilégiés : le daemon les lit depuis Resources (comme la release)
make -C "$HERE/pam" >/dev/null 2>&1 || true
mkdir -p "$APP/Contents/Resources/pam" "$APP/Contents/Resources/scripts"
cp "$HERE/pam/pam_faceid.so" "$APP/Contents/Resources/pam/" 2>/dev/null || true
cp "$HERE/scripts/pam-install-root.sh" "$HERE/scripts/pam-uninstall-root.sh" \
   "$HERE/scripts/diagnose.sh" "$APP/Contents/Resources/scripts/"
mkdir -p "$APP/Contents/Resources/helpers"
cp "$HERE/helpers/action-modal" "$HERE/helpers/builtin-camera" \
   "$APP/Contents/Resources/helpers/" 2>/dev/null || true

echo "== Traductions (.lproj + engine.json) =="
"$HERE/.venv/bin/python" "$HERE/scripts/make_i18n.py"
cp -R "$HERE"/i18n/*.lproj "$APP/Contents/Resources/"
mkdir -p "$APP/Contents/Resources/i18n"
cp "$HERE/i18n/engine.json" "$APP/Contents/Resources/i18n/"

echo "== Compilation de l'app =="
swiftc -O -swift-version 5 \
  -target "$FACEKEY_SWIFT_TARGET" \
  -o "$APP/Contents/MacOS/FaceKey" \
  "$HERE/menubar/Branding.swift" \
  "$HERE/menubar/Onboarding.swift" \
  "$HERE/menubar/SettingsView.swift" \
  "$HERE/menubar/SetupFlow.swift" \
  "$HERE/menubar/SetupSheet.swift" \
  "$HERE/menubar/Uninstaller.swift" \
  "$HERE/menubar/LockPasswordStore.swift" \
  "$HERE/menubar/LockUnlockPolicy.swift" \
  "$HERE/menubar/LockUnlockCoordinator.swift" \
  "$HERE/menubar/HelperManager.swift" \
  "$HERE/helpertool/HelperProtocol.swift" \
  "$HERE/menubar/FaceIDApp.swift" \
  -framework AppKit -framework SwiftUI -framework AVFoundation -framework ApplicationServices -framework ServiceManagement -framework Security \
  -F "$HERE/vendor/sparkle" -framework Sparkle \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks

echo "== Compilation du daemon privilégié (FaceKeyHelper) =="
swiftc -O -swift-version 5 \
  -target "$FACEKEY_SWIFT_TARGET" \
  -o "$APP/Contents/MacOS/FaceKeyHelper" \
  "$HERE/helpertool/main.swift" \
  "$HERE/helpertool/HelperProtocol.swift" \
  "$HERE/helpertool/CodesignCheck.swift" \
  -framework Foundation -framework Security

echo "== Scripts exécutables =="
chmod +x "$HERE"/scripts/*.sh 2>/dev/null || true

echo "== Signature ad-hoc =="
bash "$HERE/scripts/check-macos-compat.sh" "$APP"
codesign --force --deep --sign - "$APP"

echo "== App de démonstration =="
bash "$HERE/scripts/build-demo.sh"

echo "== Installation dans /Applications =="
rm -rf "$DEST"
cp -R "$APP" "$DEST"
echo "   -> $DEST"

echo
echo "FaceKey.app installé. Lance-le :  open \"$DEST\""
