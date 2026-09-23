#!/usr/bin/env bash
# Creates (once) a self-signed code-signing identity "trisplit dev" in a dedicated
# keychain, so rebuilds keep the same signature and macOS keeps the Accessibility
# grant. Idempotent: re-running only unlocks the keychain and prints the SHA-1.
#
# The dedicated keychain is appended to the user keychain search list (codesign
# only uses searched keychains); existing entries and their order are kept and the
# default keychain (login) is left alone. The cert is not trusted and the login
# keychain is not modified. build.sh signs with: codesign --keychain "$KC" -s <SHA-1>.
#
#   scripts/dev-cert.sh              create / unlock, print SHA-1
#   scripts/dev-cert.sh --uninstall  drop it from the search list, delete keychain + dir
set -euo pipefail

# shellcheck source=scripts/dev-keychain.sh
. "$(dirname "$0")/dev-keychain.sh"
NAME="$DEV_NAME"
DIR="$DEV_DIR"
KC="$DEV_KC"
PWFILE="$DEV_PW"

case "${1:-}" in
    "") ;;
    --uninstall)
        echo "removing $KC from the user keychain search list"
        dev_remove_from_search_list
        if [ -f "$KC" ]; then
            echo "deleting keychain $KC"
            security delete-keychain "$KC" 2>/dev/null || rm -f "$KC"
        fi
        if [ -d "$DIR" ]; then
            echo "deleting $DIR"
            rm -rf "$DIR"
        fi
        exit 0
        ;;
    *) echo "usage: $0 [--uninstall]" >&2; exit 2 ;;
esac

mkdir -p "$DIR"
chmod 700 "$DIR"

if [ -f "$KC" ]; then
    if [ ! -f "$PWFILE" ]; then
        echo "error: $KC exists but $PWFILE is missing; remove '$DIR' and re-run" >&2
        exit 1
    fi
    PW="$(cat "$PWFILE")"
else
    PW="$(openssl rand -base64 32 | tr -d '\n')"
    (umask 077; printf '%s' "$PW" >"$PWFILE")
    security create-keychain -p "$PW" "$KC"
fi
chmod 600 "$PWFILE"
security set-keychain-settings "$KC"          # no auto-lock timeout, no lock on sleep
security unlock-keychain -p "$PW" "$KC"
dev_add_to_search_list

SHA="$(dev_identity_sha)"
if [ -z "$SHA" ]; then
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
    cat >"$TMP/req.cnf" <<EOF
[req]
distinguished_name = dn
prompt = no
x509_extensions = v3
[dn]
CN = $NAME
[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
EOF
    openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 3650 \
        -config "$TMP/req.cnf" -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null

    # OpenSSL 3 defaults to PBKDF2/AES pkcs12, which `security import` rejects.
    LEGACY=()
    case "$(openssl version)" in OpenSSL\ [3-9]*) LEGACY=(-legacy) ;; esac
    P12PW="$(openssl rand -hex 16)"
    P12PW="$P12PW" openssl pkcs12 -export ${LEGACY[@]+"${LEGACY[@]}"} -name "$NAME" \
        -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/id.p12" -passout env:P12PW

    security import "$TMP/id.p12" -k "$KC" -f pkcs12 -P "$P12PW" -T /usr/bin/codesign >/dev/null
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PW" "$KC" >/dev/null
    rm -rf "$TMP"

    SHA="$(dev_identity_sha)"
    [ -n "$SHA" ] || { echo "error: identity '$NAME' not found after import" >&2; exit 1; }
    echo "created identity '$NAME' in $KC"
else
    echo "identity '$NAME' already present in $KC"
fi

echo "SHA-1: $SHA"
