#!/bin/sh
# Builds, signs, notarizes and publishes a Slowburn release.
#
#   scripts/release.sh 0.2.0
#
# 1. a universal build (Apple silicon + Intel), signed with the Developer ID certificate in your Keychain;
# 2. notarized by Apple and stapled, so it opens without a Gatekeeper warning;
# 3. signed for Sparkle with the EdDSA key in your Keychain (made by Sparkle's generate_keys);
# 4. published as a GitHub release (Slowburn-<version>.zip, plus Slowburn.zip for the installer's "latest");
# 5. announced in docs/appcast.xml, which the app checks once a day.
#
# What's new goes in release-notes/<version>.en.md and .ru.md: a few "- " lines in plain words. The update
# window shows them (in the Mac's language), and so does the GitHub release.
#
# Once per Mac, store the notarization password (an app-specific one from account.apple.com):
#   xcrun notarytool store-credentials slowburn --apple-id <your Apple ID> --team-id D5WGUAD34M
#
# Settings: SLOWBURN_NOTARY_PROFILE (default "slowburn"), SLOWBURN_SIGN_IDENTITY (default: the first
# "Developer ID Application" certificate), SLOWBURN_DRY_RUN=1 (build, sign and notarize; publish nothing).
set -eu

VERSION="${1:-}"
[ -n "$VERSION" ] || { echo "usage: scripts/release.sh <version>, e.g. 0.2.0" >&2; exit 1; }
echo "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || { echo "version must look like 1.2.3" >&2; exit 1; }

cd "$(dirname "$0")/.."
REPO="kdanet/slowburn"
TAG="v$VERSION"
PROFILE="${SLOWBURN_NOTARY_PROFILE:-slowburn}"
DIST="dist/$VERSION"
APP="$DIST/Slowburn.app"
ZIP="$DIST/Slowburn-$VERSION.zip"
SPARKLE_BIN=".build/artifacts/sparkle/Sparkle/bin"

say() { printf '\033[38;5;209m◔\033[0m %s\n' "$1"; }
fail() { printf '\033[31m✗\033[0m %s\n' "$1" >&2; exit 1; }

# --- Preflight: nothing gets published from a dirty or stale tree, or without notes.
python3 scripts/notes.py appcast "$VERSION" >/dev/null || fail "Write release-notes/$VERSION.en.md and release-notes/$VERSION.ru.md first."
if [ -z "${SLOWBURN_DRY_RUN:-}" ]; then
  [ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || fail "Release from main."
  [ -z "$(git status --porcelain)" ] || fail "Commit or stash your changes first."
  git fetch --quiet origin main
  [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || fail "main differs from origin/main: push or pull first."
  if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then fail "$TAG already exists."; fi
  gh auth status >/dev/null 2>&1 || fail "Log in to GitHub: gh auth login"
fi
IDENTITY="${SLOWBURN_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)}"
[ -n "$IDENTITY" ] || fail "No Developer ID Application certificate in the Keychain."
xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 \
  || fail "No notarization credentials \"$PROFILE\". Run: xcrun notarytool store-credentials $PROFILE --apple-id <Apple ID> --team-id D5WGUAD34M"

# --- Build and sign.
BUILD="$(git rev-list --count HEAD)"
say "Slowburn $VERSION (build $BUILD), signed by $IDENTITY"
say "Testing"
SLOWBURN_LANG=ru swift test >/dev/null 2>&1 || fail "Tests fail: run SLOWBURN_LANG=ru swift test"
say "Building for Apple silicon and Intel"
swift build -c release --arch arm64 --arch x86_64 --product Slowburn >/dev/null
swift build -c release --arch arm64 --arch x86_64 --product quota >/dev/null
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
rm -rf "$DIST"; mkdir -p "$DIST"
scripts/bundle.sh "$BIN" "$APP" "$VERSION" "$BUILD" "$IDENTITY" >/dev/null 2>&1 || scripts/bundle.sh "$BIN" "$APP" "$VERSION" "$BUILD" "$IDENTITY"

# --- Notarize and staple.
say "Notarizing (usually a few minutes)"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/notarize.zip"
OUT="$(xcrun notarytool submit "$DIST/notarize.zip" --keychain-profile "$PROFILE" --wait 2>&1)" || true
echo "$OUT" | grep -q "status: Accepted" || {
  echo "$OUT" >&2
  ID="$(echo "$OUT" | sed -n 's/^ *id: //p' | head -1)"
  [ -n "$ID" ] && xcrun notarytool log "$ID" --keychain-profile "$PROFILE" >&2
  fail "Notarization was not accepted."
}
rm "$DIST/notarize.zip"
xcrun stapler staple "$APP" >/dev/null
spctl --assess --type execute "$APP" || fail "Gatekeeper rejects the stapled app."
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
cp "$ZIP" "$DIST/Slowburn.zip"
say "Notarized: $ZIP"

# --- Sparkle signature and the appcast entry.
SIG="$("$SPARKLE_BIN/sign_update" --account slowburn "$ZIP")"   # sparkle:edSignature="…" length="…"
URL="https://github.com/$REPO/releases/download/$TAG/Slowburn-$VERSION.zip"
python3 - "$VERSION" "$BUILD" "$URL" "$SIG" "$(python3 scripts/notes.py appcast "$VERSION")" <<'PY'
import sys, re, email.utils, pathlib
version, build, url, sig, notes = sys.argv[1:]
path = pathlib.Path("docs/appcast.xml")
item = f"""    <item>
      <title>Slowburn {version}</title>
      <pubDate>{email.utils.formatdate(usegmt=True)}</pubDate>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
{notes.rstrip()}
      <enclosure url="{url}" type="application/octet-stream" {sig.strip()}/>
    </item>
"""
xml = path.read_text()
path.write_text(xml.replace("    <!-- releases -->\n", "    <!-- releases -->\n" + item, 1))
PY

if [ -n "${SLOWBURN_DRY_RUN:-}" ]; then
  git checkout -- docs/appcast.xml
  say "Dry run: $APP is signed, notarized and stapled. Nothing was published."
  exit 0
fi

# --- Publish: the release first, so the appcast never points at a file that is not there yet.
say "Publishing $TAG on GitHub"
git tag -a "$TAG" -m "Slowburn $VERSION"
git push --quiet origin "$TAG"
gh release create "$TAG" "$ZIP" "$DIST/Slowburn.zip" --repo "$REPO" --title "Slowburn $VERSION" \
  --notes "$(python3 scripts/notes.py github "$VERSION")"
git add docs/appcast.xml
git commit --quiet -m "Release $VERSION: appcast"
git push --quiet origin main
say "Done. Installed copies pick up $VERSION within a day; the installer serves it now."
