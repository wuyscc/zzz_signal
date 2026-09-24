#!/usr/bin/env bash
#
# Functional tests for signal.sh.
#
# Builds a fake Steam install with a fake web cache and puts a mock
# `curl` first in PATH, so no real network request is ever made.
#
# Usage: bash tests/test_signal.sh

set -u

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$root/signal.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

passed=0
failed=0

pass() { passed=$((passed + 1)); printf '  ok   %s\n' "$1"; }
fail() { failed=$((failed + 1)); printf '  FAIL %s\n' "$1"; }

# True when $2 does not contain the fixed string $1.
lacks() { ! grep -qF -- "$1" <<<"$2"; }

check() {
    local name="$1"
    shift
    if "$@"; then pass "$name"; else fail "$name"; fi
}

# ------------------------------------------------------------
# Fixtures
# ------------------------------------------------------------

home="$work/home"
data_dir="$home/.local/share/Steam/steamapps/common/Zenless Zone Zero/games/ZenlessZoneZero Game/ZenlessZoneZero_Data"
cache_dir="$data_dir/webCaches/2.0.0.1/Cache/Cache_Data"
cache="$cache_dir/data_2"
mkdir -p "$cache_dir" "$work/bin"

api="https://public-operation-nap-sg.hoyoverse.com/common/gacha_record/api/getGachaLog"
valid_key="VALIDKEYaaaaaaaaaaaaaaaaaaaaaaaa"
expired_key="EXPIREDKEYbbbbbbbbbbbbbbbbbbbbbb"
evil_key="EVILKEYccccccccccccccccccccccccc"

url_for() {
    printf '%s?authkey_ver=1&sign_type=2&authkey=%s&lang=en&game_biz=nap_global&extra=drop_me' "$2" "$1"
}

# Writes cache entries oldest -> newest, in the on-disk format.
write_cache() {
    : >"$cache"
    local url
    for url in "$@"; do
        printf 'junk1/0/%s\0trailing' "$url" >>"$cache"
    done
}

# Mock curl: logs every URL it is asked for and answers based on
# the authkey, like the real API would.
cat >"$work/bin/curl" <<'EOF'
#!/usr/bin/env bash
for arg in "$@"; do url="$arg"; done
printf '%s\n' "$url" >>"$CURL_LOG"
case "$url" in
    *VALIDKEY*)   echo '{"retcode":0,"message":"OK","data":{}}' ;;
    *EXPIREDKEY*) echo '{"retcode":-101,"message":"authkey timeout","data":null}' ;;
    *)            echo '{"retcode":-100,"message":"authkey error","data":null}' ;;
esac
EOF
chmod +x "$work/bin/curl"

export CURL_LOG="$work/curl.log"

# Runs signal.sh with the fake HOME and mock curl.
# Sets: rc, out (stdout), err (stderr).
run() {
    : >"$CURL_LOG"
    HOME="$home" PATH="$work/bin:$PATH" NO_COLOR=1 \
        WAYLAND_DISPLAY="" DISPLAY="" \
        bash "$script" "$@" >"$work/out" 2>"$work/err" </dev/null
    rc=$?
    out="$(cat "$work/out")"
    err="$(cat "$work/err")"
}

expected_url="$api?authkey_ver=1&sign_type=2&authkey=$valid_key&lang=en&game_biz=nap_global"

# ------------------------------------------------------------
# Tests
# ------------------------------------------------------------

echo "CLI"
run --help
check "--help exits 0"                 test "$rc" -eq 0
check "--help prints usage"            grep -q "Usage:" "$work/out"

run --definitely-not-an-option
check "unknown option exits 2"         test "$rc" -eq 2

run "/path/one" "/path/two"
check "two paths exits 2"              test "$rc" -eq 2

echo "Happy path"
write_cache "$(url_for "$valid_key" "$api")" "$(url_for "$expired_key" "$api")"
before="$(sha256sum "$cache")"
run --no-copy
check "exits 0 when a URL is valid"    test "$rc" -eq 0
check "prints the cleaned URL"         grep -qxF "$expected_url" <<<"$out$err"
check "drops extra query params"       lacks "extra=drop_me" "$out$err"
check "tries newest URL first"         test "$(head -n1 "$CURL_LOG")" = "$(url_for "$expired_key" "$api")"
check "does not print expired authkey" lacks "$expired_key" "$err"
check "reports expiry reason"          grep -q "authkey timeout" <<<"$err"
check "cache file left unchanged"      test "$(sha256sum "$cache")" = "$before"

run -q --no-copy
check "--quiet exits 0"                test "$rc" -eq 0
check "--quiet stdout is only the URL" test "$out" = "$expected_url"
check "--quiet stderr is empty"        test -z "$err"

run --no-copy "$home/.local/share/Steam/steamapps/common/Zenless Zone Zero"
check "explicit install root works"    test "$rc" -eq 0

run --no-copy "$data_dir/"
check "explicit data folder works"     test "$rc" -eq 0

echo "Safety"
write_cache \
    "$(url_for "$valid_key" "$api")" \
    "$(url_for "$evil_key" "https://evil.example.com/getGachaLog")" \
    "$(url_for "$evil_key" "https://hoyoverse.com.evil.example/getGachaLog")" \
    "$(url_for "$evil_key" "http://public-operation-nap-sg.hoyoverse.com/common/gacha_record/api/getGachaLog")"
run -q --no-copy
check "untrusted hosts are skipped"    test "$rc" -eq 0
check "never requests untrusted URLs"  lacks "EVILKEY" "$(cat "$CURL_LOG")"

echo "Failures"
write_cache "$(url_for "$expired_key" "$api")"
run --no-copy
check "all expired exits 1"            test "$rc" -eq 1
check "explains how to refresh"        grep -q "Search History" <<<"$err"

write_cache
run --no-copy
check "empty cache exits 1"            test "$rc" -eq 1
check "no requests on empty cache"     test ! -s "$CURL_LOG"

run --no-copy "$work/does-not-exist"
check "bad path exits 1"               test "$rc" -eq 1
check "says path does not exist"       grep -q "does not exist" <<<"$err"

HOME="$work/empty-home" PATH="$work/bin:$PATH" NO_COLOR=1 bash "$script" >/dev/null 2>&1 </dev/null
check "no install found exits 1"       test "$?" -eq 1

echo "Missing dependencies"
# A PATH with every usual command except jq.
nojq="$work/nojq-bin"
mkdir -p "$nojq"
for dir in /usr/local/bin /usr/bin /bin; do
    for cmd in "$dir"/*; do
        name="${cmd##*/}"
        [[ "$name" == jq || -e "$nojq/$name" ]] || ln -s "$cmd" "$nojq/$name"
    done
done
ln -sf "$work/bin/curl" "$nojq/curl"
: >"$CURL_LOG"
HOME="$home" PATH="$nojq" NO_COLOR=1 bash "$script" --no-copy >"$work/out" 2>"$work/err" </dev/null
rc=$?
err="$(cat "$work/err")"
check "missing jq exits 1"             test "$rc" -eq 1
check "names the missing package"      grep -q "jq" <<<"$err"
check "does not suggest sudo"          lacks "sudo" "$err"
check "makes no requests"              test ! -s "$CURL_LOG"

echo
echo "$passed passed, $failed failed"
(( failed == 0 ))
