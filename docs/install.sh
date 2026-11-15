#!/bin/sh
# Slowburn installer.
#
#   curl -fsSL https://kdanet.github.io/slowburn/install.sh | sh
#   curl -fsSL https://kdanet.github.io/slowburn/install.sh | sh -s -- --uninstall
#
# Builds Slowburn from source on your Mac (nothing prebuilt is downloaded), puts Slowburn.app in
# ~/Applications, starts it, and starts it again at login. Run it again to update. Needs macOS 14+,
# git and Swift 6 (Xcode 16+ or its Command Line Tools).
#
# Settings: SLOWBURN_PREFIX (where the .app goes), SLOWBURN_SRC (where the source lives),
# SLOWBURN_NO_OPEN=1 (don't start it now), SLOWBURN_NO_LOGIN=1 (don't start it at login).
set -eu

REPO="https://github.com/kdanet/slowburn"
PREFIX="${SLOWBURN_PREFIX:-$HOME/Applications}"
SRC="${SLOWBURN_SRC:-$HOME/.slowburn/src}"
APP="$PREFIX/Slowburn.app"
AGENT="$HOME/Library/LaunchAgents/app.slowburn.plist"

say() { printf '\033[38;5;209m◔\033[0m %s\n' "$1"; }
fail() { printf '\033[31m✗\033[0m %s\n' "$1" >&2; exit 1; }

if [ "${1:-}" = "--uninstall" ]; then
  say "Removing Slowburn"
  if [ -x "$APP/Contents/MacOS/quota" ]; then "$APP/Contents/MacOS/quota" uninstall-hooks >/dev/null 2>&1 || true; fi
  pkill -x Slowburn 2>/dev/null || true
  launchctl bootout "gui/$(id -u)/app.slowburn" 2>/dev/null || true
  rm -f "$AGENT"
  rm -rf "$APP" "$SRC"
  say "Done. Hooks removed, app and source deleted."
  say "Your history stays in ~/Library/Application Support/Slowburn — delete it too if you like."
  exit 0
fi

[ "$(uname -s)" = "Darwin" ] || fail "Slowburn is a macOS app."
major="$(sw_vers -productVersion | cut -d. -f1)"
[ "$major" -ge 14 ] || fail "Slowburn needs macOS 14 or later (you have $(sw_vers -productVersion))."
command -v git >/dev/null 2>&1 || fail "git is missing. Install the Command Line Tools: xcode-select --install"
command -v swift >/dev/null 2>&1 || fail "Swift is missing. Install the Command Line Tools: xcode-select --install"
swift_major="$(swift --version 2>/dev/null | sed -n 's/.*Swift version \([0-9][0-9]*\).*/\1/p' | head -1)"
[ "${swift_major:-0}" -ge 6 ] || fail "Slowburn needs Swift 6 (Xcode 16 or later). Update Xcode or run: softwareupdate --list"

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

if [ -z "${SLOWBURN_NO_LOGIN:-}" ]; then
  # Start at login: a per-user launch agent that opens the app once when you log in.
  mkdir -p "$(dirname "$AGENT")"
  cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>app.slowburn</string>
  <key>ProgramArguments</key><array><string>/usr/bin/open</string><string>-g</string><string>$APP</string></array>
  <key>RunAtLoad</key><true/>
</dict></plist>
PLIST
  say "Slowburn will start at login (remove $AGENT to stop that)"
fi

say "Installed $APP"
if [ -z "${SLOWBURN_NO_OPEN:-}" ]; then
  open "$APP"
  say "Slowburn is in your menu bar."
fi
printf '\nOptional — the soft brake for Claude Code and Codex:\n  "%s/Contents/MacOS/quota" integrate claude codex\n\n' "$APP"
