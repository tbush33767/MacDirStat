#!/bin/bash
# Ensures a stable, self-signed code-signing identity exists in the login
# keychain and prints its name on stdout.
#
# Why: an ad-hoc signature (`codesign -s -`) gives TCC only a cdhash to key
# grants against. macOS then shows Full Disk Access as "on" but silently does
# NOT honor it at runtime, so the app re-prompts forever. A stable self-signed
# certificate yields a persistent designated requirement
#   identifier "com.tyler.MacDirStat" and certificate leaf = H"<cert hash>"
# which depends on the cert (stable) and bundle id — not the cdhash — so a
# single Full Disk Access grant survives both app relaunches and rebuilds.
#
# The identity is created once and reused. Recreating it would change the
# cert hash and invalidate the grant, so this script is strictly idempotent.
set -euo pipefail

IDENTITY="MacDirStat Local Signing"
LOGIN_KC="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
    echo "$IDENTITY"
    exit 0
fi

echo "Creating self-signed signing identity '$IDENTITY'…" >&2
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cfg" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $IDENTITY
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -days 3650 -nodes -config "$TMP/cfg" >/dev/null 2>&1
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/id.p12" -passout pass:mds -name "$IDENTITY" >/dev/null 2>&1

# -A lets codesign use the key without a per-build keychain-access prompt.
security import "$TMP/id.p12" -k "$LOGIN_KC" -P mds -A >/dev/null 2>&1

echo "$IDENTITY"
