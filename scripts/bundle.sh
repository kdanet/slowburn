#!/bin/sh
# Assembles Slowburn.app from built products and signs it.
#
#   scripts/bundle.sh <bin dir> <out .app> <version> <build> [identity]
#
# identity: a "Developer ID Application" certificate for releases (hardened runtime, timestamp), or "-"
# (the default) for a local ad-hoc signature. Used by scripts/release.sh and by the installer's source build.
set -eu

BIN="$1"; APP="$2"; VERSION="$3"; BUILD="$4"; IDENTITY="${5:--}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
FEED="https://kdanet.github.io/slowburn/appcast.xml"
ED_KEY="aflMkgqfdsiJl8/rA67InI4YdhA6Wnt/16Vo9i0DWN0="

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN/Slowburn" "$APP/Contents/MacOS/Slowburn"
cp "$BIN/quota" "$APP/Contents/MacOS/quota"
ditto "$BIN/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
cp "$HERE/Branding/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Slowburn</string>
  <key>CFBundleDisplayName</key><string>Slowburn</string>
  <key>CFBundleIdentifier</key><string>app.slowburn</string>
  <key>CFBundleExecutable</key><string>Slowburn</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
  <key>SUFeedURL</key><string>$FEED</string>
  <key>SUPublicEDKey</key><string>$ED_KEY</string>
  <key>SUEnableAutomaticChecks</key><true/>
  <key>SUAutomaticallyUpdate</key><true/>
  <key>SUScheduledCheckInterval</key><integer>86400</integer>
</dict></plist>
PLIST

# Inside out: Sparkle's helpers, the framework, our CLI, then the app itself.
if [ "$IDENTITY" = "-" ]; then
  sign() { codesign --force --sign - "$@"; }
else
  sign() { codesign --force --sign "$IDENTITY" --options runtime --timestamp "$@"; }
fi
FW="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
sign "$FW/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$FW/XPCServices/Downloader.xpc"
sign "$FW/Autoupdate"
sign "$FW/Updater.app"
sign "$APP/Contents/Frameworks/Sparkle.framework"
sign "$APP/Contents/MacOS/quota"
sign "$APP"
codesign --verify --deep --strict "$APP"
