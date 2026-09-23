#!/usr/bin/env bash
# Creates (once) a self-signed code-signing identity "trisplit dev" in a dedicated
# keychain, so rebuilds keep the same signature and macOS keeps the Accessibility
# grant. Idempotent: re-running only unlocks the keychain and prints the SHA-1.
#
# Does NOT trust the cert, touch the login keychain or change the keychain search
# list. build.sh signs with: codesign --keychain "$KC" -s <SHA-1>.
set -euo pipefail

NAME="trisplit dev"
DIR="$HOME/Library/Application Support/trisplit-dev"
KC="$DIR/trisplit-dev.keychain-db"
PWFILE="$DIR/keychain-password"

identity_sha() {
    security find-identity -p codesigning "$KC" 2>/dev/null \
        | awk -v n="\"$NAME\"" 'index($0, n) { print $2; exit }'
}

# Snapshot the user search list so it can be restored verbatim if
# `security create-keychain` appends the new keychain to it.
search_list() { security list-keychains -d user | sed -e 's/^[[:space:]]*"//' -e 's/"[[:space:]]*$//'; }
BEFORE="$(search_list)"
restore_search_list() {
    if [ "$(search_list)" != "$BEFORE" ]; then
        local kcs=()
        while IFS= read -r l; do [ -n "$l" ] && kcs+=("$l"); done <<<"$BEFORE"
        security list-keychains -d user -s "${kcs[@]}"
    fi
}

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
    restore_search_list
fi
chmod 600 "$PWFILE"
security set-keychain-settings "$KC"          # no auto-lock timeout, no lock on sleep
security unlock-keychain -p "$PW" "$KC"

SHA="$(identity_sha)"
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

    SHA="$(identity_sha)"
    [ -n "$SHA" ] || { echo "error: identity '$NAME' not found after import" >&2; exit 1; }
    echo "created identity '$NAME' in $KC"
else
    echo "identity '$NAME' already present in $KC"
fi

restore_search_list
echo "$SHA"
