#!/bin/bash
#
# Creates a local, self-signed code-signing certificate for Klack.
#
# Why this exists: ad-hoc signing (`codesign --sign -`) derives the app's
# identity from a hash of the binary, so every rebuild produces a different
# identity. macOS ties the Input Monitoring grant to that identity, so after
# each install the app sits in the menu bar looking perfectly healthy while
# receiving no keystrokes at all. Signing against a fixed certificate keys the
# grant to the certificate instead, and it survives rebuilds.
#
# This certificate is local and self-signed. It is not an Apple Developer ID:
# it does nothing for distribution, Gatekeeper or notarisation. It exists only
# so this machine stops forgetting the permission.
#
# Run once:  ./build-scripts/create-signing-cert.sh
# Then:      ./build-scripts/install.sh   (picks it up automatically)

set -euo pipefail

IDENTITY="Klack Local Dev"
# Ask the system rather than assuming: the login keychain is login.keychain on
# older systems and login.keychain-db on newer ones, and importing into a path
# that doesn't exist fails in a way that's easy to miss.
KEYCHAIN="$(security default-keychain -d user | tr -d ' "')"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [ ! -f "$KEYCHAIN" ]; then
    echo "FAILED   could not locate your login keychain (looked for: $KEYCHAIN)"
    exit 1
fi
echo "==> Using keychain: $KEYCHAIN"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    echo "'$IDENTITY' already exists. Nothing to do."
    echo "Run ./build-scripts/install.sh and it will be used automatically."
    exit 0
fi

echo "==> Generating certificate"
cat > "$WORK/cert.conf" <<'CONF'
[ req ]
distinguished_name = dn
prompt = no
x509_extensions = v3
[ dn ]
CN = Klack Local Dev
O = Klack
[ v3 ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CONF

openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
    -days 3650 -config "$WORK/cert.conf" 2>/dev/null

openssl pkcs12 -export -out "$WORK/klack.p12" \
    -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -name "$IDENTITY" -passout pass: 2>/dev/null

echo "==> Importing into the login keychain"
echo "    (macOS may ask for your login password)"
if ! security import "$WORK/klack.p12" -k "$KEYCHAIN" -P "" \
        -T /usr/bin/codesign -T /usr/bin/security 2>"$WORK/import.err"; then
    echo
    echo "FAILED   the import did not complete. macOS said:"
    sed 's/^/         /' "$WORK/import.err"
    echo
    echo "         Nothing was changed. Paste the above and we'll sort it out."
    exit 1
fi

# Without this, codesign shows a "wants to access key" dialog on every single
# build. Clicking "Always Allow" once does the same thing; this just skips it.
echo "==> Allowing codesign to use the key without prompting"
echo -n "    Login keychain password (or press Return to skip): "
read -rs KEYCHAIN_PASSWORD
echo
if [ -n "$KEYCHAIN_PASSWORD" ]; then
    security set-key-partition-list -S apple-tool:,apple:,codesign: \
        -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null 2>&1 \
        && echo "    Done." \
        || echo "    Could not set partition list -- you'll get a keychain prompt on first sign. Click 'Always Allow'."
else
    echo "    Skipped -- on the first build, click 'Always Allow' in the keychain dialog."
fi

echo
if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
    echo "SUCCESS  '$IDENTITY' is ready."
    echo
    echo "Next:"
    echo "  1. ./build-scripts/install.sh"
    echo "  2. tccutil reset ListenEvent com.vinaypathak.klack"
    echo "  3. Relaunch Klack and click Allow."
    echo
    echo "That is the last time you grant it. Later rebuilds keep the permission."
else
    echo "FAILED   certificate was not found after import."
    exit 1
fi
