#!/bin/sh
# Packs a signed, notarized Slowburn.app into a disk image you open and drag to Applications.
#
#   scripts/dmg.sh dist/0.2.1/Slowburn.app dist/0.2.1/Slowburn-0.2.1.dmg
#
# The image is signed with the Developer ID certificate, notarized and stapled, so it opens without a
# Gatekeeper warning even offline. Settings as in release.sh: SLOWBURN_NOTARY_PROFILE, SLOWBURN_SIGN_IDENTITY.
set -eu

APP="${1:-}"; OUT="${2:-}"
[ -d "$APP" ] && [ -n "$OUT" ] || { echo "usage: scripts/dmg.sh <Slowburn.app> <out.dmg>" >&2; exit 1; }
PROFILE="${SLOWBURN_NOTARY_PROFILE:-slowburn}"
IDENTITY="${SLOWBURN_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)}"
[ -n "$IDENTITY" ] || { echo "No Developer ID Application certificate in the Keychain." >&2; exit 1; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/Slowburn.app"
ln -s /Applications "$STAGE/Applications"

rm -f "$OUT"
hdiutil create -quiet -volname Slowburn -srcfolder "$STAGE" -fs HFS+ -format ULFO -ov "$OUT"
codesign --force --timestamp --sign "$IDENTITY" "$OUT"

RES="$(xcrun notarytool submit "$OUT" --keychain-profile "$PROFILE" --wait 2>&1)" || true
echo "$RES" | grep -q "status: Accepted" || {
  echo "$RES" >&2
  ID="$(echo "$RES" | sed -n 's/^ *id: //p' | head -1)"
  [ -n "$ID" ] && xcrun notarytool log "$ID" --keychain-profile "$PROFILE" >&2
  echo "The disk image was not notarized." >&2; exit 1
}
xcrun stapler staple "$OUT" >/dev/null
spctl --assess --type open --context context:primary-signature "$OUT" || { echo "Gatekeeper rejects the disk image." >&2; exit 1; }
