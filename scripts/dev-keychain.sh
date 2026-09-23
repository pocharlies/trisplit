# Shared by scripts/dev-cert.sh and build.sh (sourced, not executed).
# Paths and search-list helpers for the dedicated "trisplit dev" keychain.

DEV_NAME="trisplit dev"
DEV_DIR="$HOME/Library/Application Support/trisplit-dev"
DEV_KC="$DEV_DIR/trisplit-dev.keychain-db"
DEV_PW="$DEV_DIR/keychain-password"

# One keychain path per line, as `security` reports it.
dev_search_list() {
    security list-keychains -d user | sed -e 's/^[[:space:]]*"//' -e 's/"[[:space:]]*$//'
}

dev_in_search_list() { dev_search_list | grep -Fxq "$DEV_KC"; }

# Appends the dev keychain to the user search list, keeping existing entries
# and their order. codesign only finds identities in searched keychains.
# Idempotent; never touches the default keychain.
dev_add_to_search_list() {
    dev_in_search_list && return 0
    local kcs=() l
    while IFS= read -r l; do [ -n "$l" ] && kcs+=("$l"); done < <(dev_search_list)
    security list-keychains -d user -s ${kcs[@]+"${kcs[@]}"} "$DEV_KC"
}

dev_remove_from_search_list() {
    dev_in_search_list || return 0
    local kcs=() l
    while IFS= read -r l; do
        [ -n "$l" ] && [ "$l" != "$DEV_KC" ] && kcs+=("$l")
    done < <(dev_search_list)
    security list-keychains -d user -s ${kcs[@]+"${kcs[@]}"}
}

dev_identity_sha() {
    security find-identity -p codesigning "$DEV_KC" 2>/dev/null \
        | awk -v n="\"$DEV_NAME\"" 'index($0, n) { print $2; exit }'
}
