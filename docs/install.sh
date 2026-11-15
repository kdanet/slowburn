#!/bin/sh
# Slowburn installer.
#
#   curl -fsSL https://kdanet.github.io/slowburn/install.sh | sh
#
# Builds Slowburn from source on your Mac (nothing prebuilt is downloaded), puts Slowburn.app in
# ~/Applications and starts it. Run it again to update. Needs macOS 14+, git and Swift
# (Xcode or the Command Line Tools).
#
# Settings: SLOWBURN_PREFIX (where the .app goes), SLOWBURN_SRC (where the source lives),
# SLOWBURN_NO_OPEN=1 (don't start the app afterwards).
set -eu

REPO="https://github.com/kdanet/slowburn"
PREFIX="${SLOWBURN_PREFIX:-$HOME/Applications}"
SRC="${SLOWBURN_SRC:-$HOME/.slowburn/src}"
APP="$PREFIX/Slowburn.app"

say() { printf '\033[38;5;209m◔\033[0m %s\n' "$1"; }
fail() { printf '\033[31m✗\033[0m %s\n' "$1" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "Slowburn is a macOS app."
major="$(sw_vers -productVersion | cut -d. -f1)"
[ "$major" -ge 14 ] || fail "Slowburn needs macOS 14 or later (you have $(sw_vers -productVersion))."
command -v git >/dev/null 2>&1 || fail "git is missing. Install the Command Line Tools: xcode-select --install"
command -v swift >/dev/null 2>&1 || fail "Swift is missing. Install the Command Line Tools: xcode-select --install"

if [ -d "$SRC/.git" ]; then
  say "Updating the source in $SRC"
  git -C "$SRC" pull --ff-only --quiet
else
  say "Getting the source into $SRC"
  mkdir -p "$(dirname "$SRC")"
  git clone --quiet --depth 1 "$REPO" "$SRC"
fi

say "Building (a minute or two the first time)"
cd "$SRC"
swift build -c release --product Slowburn >/dev/null
swift build -c release --product quota >/dev/null
BIN="$(swift build -c release --show-bin-path)"

say "Assembling $APP"
# Quit a running copy first, so the new one can take its place in the menu bar.
pkill -x Slowburn 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Slowburn" "$APP/Contents/MacOS/Slowburn"
cp "$BIN/quota" "$APP/Contents/MacOS/quota"
cp "$SRC/Branding/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
VERSION="$(git -C "$SRC" describe --tags --always 2>/dev/null || echo dev)"
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
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# A local ad-hoc signature: the app was built on this Mac, so Gatekeeper has nothing to quarantine.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

say "Installed $APP"
if [ -z "${SLOWBURN_NO_OPEN:-}" ]; then
  open "$APP"
  say "Slowburn is in your menu bar."
fi
printf '\nOptional — the soft brake for Claude Code and Codex:\n  "%s/Contents/MacOS/quota" integrate claude codex\n\n' "$APP"
