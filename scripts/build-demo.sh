#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$HERE/scripts/macos-target.sh"
APP="$HERE/build/FaceKey Checkout Demo.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -swift-version 5 -target "$FACEKEY_SWIFT_TARGET" \
  -o "$APP/Contents/MacOS/FaceKeyCheckoutDemo" \
  "$HERE/sdk/Sources/FaceKeyKit/FaceKeyKit.swift" \
  "$HERE/demo/FaceKeyCheckoutDemo.swift" \
  -framework SwiftUI -framework AppKit
/usr/libexec/PlistBuddy -c 'Add :CFBundleName string FaceKey Checkout Demo' \
  -c 'Add :CFBundleDisplayName string FaceKey Checkout Demo' \
  -c 'Add :CFBundleIdentifier string com.jjannahm.FaceKey.Demo' \
  -c 'Add :CFBundleExecutable string FaceKeyCheckoutDemo' \
  -c 'Add :CFBundlePackageType string APPL' \
  -c 'Add :LSMinimumSystemVersion string 14.0' \
  "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"
echo "Built $APP"
