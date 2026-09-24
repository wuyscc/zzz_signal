#!/usr/bin/env bash

set -u

# ============================================================
# Zenless Zone Zero - Search History URL extractor
#
# Usage:
#   bash signal.sh [options] ["/path/to/Zenless Zone Zero"]
#
# Run with --help for all options.
# ============================================================

prog="signal.sh"

usage() {
    cat <<EOF
Extract your Zenless Zone Zero Search History (gacha log) URL
from the game's web cache and copy it to the clipboard.

Usage:
  $prog [options] [GAME_PATH]

Arguments:
  GAME_PATH         Game install folder (Steam root or ZenlessZoneZero_Data).
                    Auto-detected from your Steam libraries when omitted.

Options:
  -q, --quiet       Only print the final URL (useful for scripts).
      --no-copy     Don't copy the URL to the clipboard.
  -v, --verbose     Show full paths and per-candidate details.
  -h, --help        Show this help and exit.

Through curl, pass options after "-s --":
  curl -fsSL https://raw.githubusercontent.com/wuyscc/zzz_signal/main/signal.sh | bash -s -- --no-copy

Environment:
  NO_COLOR          Disable colored output.
EOF
}

# ------------------------------------------------------------
# Arguments
# ------------------------------------------------------------

quiet=false
verbose=false
copy=true
user_path=""

while (( $# > 0 )); do
    case "$1" in
        -h|--help)    usage; exit 0 ;;
        -q|--quiet)   quiet=true ;;
        -v|--verbose) verbose=true ;;
        --no-copy)    copy=false ;;
        --)           shift; [[ $# -gt 0 ]] && user_path="$1"; break ;;
        -*)
            echo "$prog: unknown option: $1" >&2
            echo "Try '$prog --help' for more information." >&2
            exit 2
            ;;
        *)
            if [[ -n "$user_path" ]]; then
                echo "$prog: only one game path may be given (did you forget quotes around a path with spaces?)" >&2
                exit 2
            fi
            user_path="$1"
            ;;
    esac
    shift
done

# ------------------------------------------------------------
# Output helpers
#
# Progress/status goes to stderr; the final URL goes to stdout,
# so `signal.sh -q | ...` and `url=$(signal.sh)` work cleanly.
# ------------------------------------------------------------

if [[ -t 2 && -z "${NO_COLOR:-}" && "${TERM:-}" != "dumb" ]]; then
    c_red=$'\033[31m'
    c_green=$'\033[32m'
    c_yellow=$'\033[33m'
    c_cyan=$'\033[36m'
    c_bold=$'\033[1m'
    c_dim=$'\033[2m'
    c_reset=$'\033[0m'
else
    c_red="" c_green="" c_yellow="" c_cyan="" c_bold="" c_dim="" c_reset=""
fi

if [[ "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" =~ [Uu][Tt][Ff]-?8 ]]; then
    s_ok="✓" s_fail="✗" s_warn="!" s_dot="•"
else
    s_ok="+" s_fail="x" s_warn="!" s_dot="*"
fi

total_steps=4
say()     { $quiet || printf '%s\n' "$*" >&2; }
step()    { say "${c_bold}${c_cyan}[$1/$total_steps]${c_reset} ${c_bold}$2${c_reset}"; }
ok()      { say "      ${c_green}${s_ok}${c_reset} $*"; }
warn()    { say "      ${c_yellow}${s_warn}${c_reset} $*"; }
detail()  { say "      ${c_dim}$*${c_reset}"; }
vdetail() { $verbose && detail "$@"; return 0; }

# Errors are always shown, even in quiet mode.
fail() {
    printf '\n%s\n' "${c_red}${c_bold}${s_fail} $1${c_reset}" >&2
    shift
    local line
    for line in "$@"; do
        printf '  %s\n' "$line" >&2
    done
    printf '\n' >&2
    exit 1
}

# Shorten $HOME to ~ for display.
pretty_path() {
    local p="$1"
    [[ "$p" == "$HOME"* ]] && p="~${p#"$HOME"}"
    printf '%s' "$p"
}

# Hide the authkey value so URLs can be shown (or screenshotted) safely.
mask_url() {
    local url="$1"
    local host="${url#*://}"
    host="${host%%/*}"
    local key
    key="$(grep -oP '[?&]authkey=\K[^&]+' <<<"$url" | head -n1)"
    if [[ -n "$key" && ${#key} -gt 12 ]]; then
        printf '%s  authkey=%s…%s' "$host" "${key:0:6}" "${key: -4}"
    else
        printf '%s' "$host"
    fi
}

say ""
say "${c_bold}ZZZ Signal${c_reset} ${c_dim}${s_dot} Search History URL extractor${c_reset}"
say ""

# ------------------------------------------------------------
# Step 1: Requirements
# ------------------------------------------------------------

step 1 "Checking requirements"

missing=()
for cmd in curl jq python3; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
done

if (( ${#missing[@]} > 0 )); then
    install_hint="Install them with your distro's package manager."
    if command -v pacman >/dev/null 2>&1; then
        install_hint="sudo pacman -S ${missing[*]/python3/python}"
    elif command -v apt-get >/dev/null 2>&1; then
        install_hint="sudo apt install ${missing[*]}"
    elif command -v dnf >/dev/null 2>&1; then
        install_hint="sudo dnf install ${missing[*]}"
    elif command -v zypper >/dev/null 2>&1; then
        install_hint="sudo zypper install ${missing[*]}"
    fi
    fail "Missing required command(s): ${missing[*]}" \
        "Install with:  ${c_bold}${install_hint}${c_reset}"
fi

ok "curl, jq and python3 available"

# ------------------------------------------------------------
# Step 2: Locate game data folder
# ------------------------------------------------------------

step 2 "Locating game install"

steam_roots=(
    "$HOME/.local/share/Steam"
    "$HOME/.steam/steam"
    "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"
)

# Reads libraryfolders.vdf to find every Steam library the user
# added (external drives, second disks, etc.), not just the
# default one.
steam_library_paths() {
    local root vdf
    for root in "${steam_roots[@]}"; do
        vdf="$root/steamapps/libraryfolders.vdf"
        [[ -f "$vdf" ]] || continue
        grep -oP '"path"\s*"\K[^"]+' "$vdf" | sed 's/\\\\/\//g'
    done
}

base_paths=()

if [[ -n "$user_path" ]]; then
    base_paths=("$user_path")
else
    detail "No path given, searching Steam libraries..."
    for root in "${steam_roots[@]}"; do
        base_paths+=("$root/steamapps/common/Zenless Zone Zero")
    done
    while IFS= read -r lib; do
        [[ -n "$lib" ]] || continue
        base_paths+=("$lib/steamapps/common/Zenless Zone Zero")
    done < <(steam_library_paths)

    # De-duplicate (the same library is often reachable via symlinks).
    declare -A seen=()
    unique=()
    for p in "${base_paths[@]}"; do
        key="$(realpath -m "$p" 2>/dev/null || printf '%s' "$p")"
        [[ -n "${seen[$key]:-}" ]] && continue
        seen[$key]=1
        unique+=("$p")
    done
    base_paths=("${unique[@]}")
fi

# Steam installs put webCaches under this sub-folder.
steam_subpath="games/ZenlessZoneZero Game/ZenlessZoneZero_Data"
game_path=""

for base_path in "${base_paths[@]}"; do
    base_path="${base_path%/}"
    for candidate in "$base_path" "$base_path/$steam_subpath"; do
        if [[ -d "$candidate/webCaches" ]]; then
            game_path="$candidate"
            break 2
        fi
    done
done

if [[ -z "$game_path" ]]; then
    lines=("Looked for a 'webCaches' folder in:")
    for base_path in "${base_paths[@]}"; do
        lines+=("  ${c_dim}${s_dot}${c_reset} $(pretty_path "${base_path%/}")")
    done
    lines+=("")

    if [[ -n "$user_path" && ! -d "$user_path" ]]; then
        lines+=("The path you gave does not exist. Check the spelling and quote it if it has spaces.")
    elif [[ -n "$user_path" ]]; then
        lines+=("The folder exists but has no webCaches. Point at the game's install root," \
                "or open the in-game Search History once so the cache gets created.")
    else
        lines+=("Pass your install folder explicitly:" \
                "  ${c_bold}bash signal.sh \"/path/to/Zenless Zone Zero\"${c_reset}" \
                "  ${c_dim}(via curl: ... | bash -s -- \"/path/to/Zenless Zone Zero\")${c_reset}")
    fi
    fail "Could not find the game's web cache." "${lines[@]}"
fi

web_caches="$game_path/webCaches"
ok "Found game data"
detail "$(pretty_path "$game_path")"

# ------------------------------------------------------------
# Step 3: Find newest cache and extract URLs
# ------------------------------------------------------------

step 3 "Reading web cache"

max_a=0 max_b=0 max_c=0 max_d=0
max_folder=""

for folder in "$web_caches"/*; do
    [[ -d "$folder" ]] || continue
    name="$(basename "$folder")"

    [[ "$name" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || continue

    # Strip leading zeroes safely.
    a=$((10#${BASH_REMATCH[1]}))
    b=$((10#${BASH_REMATCH[2]}))
    c=$((10#${BASH_REMATCH[3]}))
    d=$((10#${BASH_REMATCH[4]}))

    if (( a > max_a )) ||
       (( a == max_a && b > max_b )) ||
       (( a == max_a && b == max_b && c > max_c )) ||
       (( a == max_a && b == max_b && c == max_c && d >= max_d )); then
        max_a=$a max_b=$b max_c=$c max_d=$d
        max_folder="$name"
    fi
done

if [[ -n "$max_folder" ]]; then
    cache_path="$web_caches/$max_folder/Cache/Cache_Data/data_2"
    cache_label="cache version $max_folder"
else
    # Try non-versioned cache directory.
    cache_path="$web_caches/Cache/Cache_Data/data_2"
    cache_label="unversioned cache"
fi

if [[ ! -f "$cache_path" ]]; then
    lines=("Expected: $(pretty_path "$cache_path")")
    mapfile -t others < <(find "$web_caches" -maxdepth 4 -type f -name "data_2" 2>/dev/null)
    if (( ${#others[@]} > 0 )); then
        lines+=("" "Other cache files that exist:")
        for o in "${others[@]}"; do
            lines+=("  ${c_dim}${s_dot}${c_reset} $(pretty_path "$o")")
        done
    else
        lines+=("" "Open the Search History in-game once so the cache gets created, then retry.")
    fi
    fail "Cache file not found in $cache_label." "${lines[@]}"
fi

cache_age=""
age=0
if mtime="$(stat -c %Y "$cache_path" 2>/dev/null)"; then
    age=$(( $(date +%s) - mtime ))
    if   (( age < 3600 ));  then cache_age="$(( age / 60 )) min ago"
    elif (( age < 86400 )); then cache_age="$(( age / 3600 )) h ago"
    else                         cache_age="$(( age / 86400 )) days ago"
    fi
fi

ok "Using $cache_label${cache_age:+ ${c_dim}(updated $cache_age)${c_reset}}"
vdetail "$(pretty_path "$cache_path")"

# Reads $cache_path directly (read-only, no copy needed even
# while the game has the file open) and prints one unique URL
# per line, newest first.
mapfile -t urls < <(python3 - "$cache_path" <<'PY'
import sys

with open(sys.argv[1], "rb") as f:
    data = f.read()

seen = set()

# Entries are separated by "1/0/"; search newest -> oldest.
for part in reversed(data.split(b"1/0/")):
    if not part.startswith(b"http") or b"getGachaLog" not in part:
        continue

    url = part.split(b"\0", 1)[0].decode("utf-8", errors="ignore").strip()

    if url and url not in seen:
        seen.add(url)
        print(url)
PY
)

candidate_count="${#urls[@]}"

if (( candidate_count == 0 )); then
    fail "No Search History URLs found in the cache." \
        "To fix this:" \
        "  1. Start Zenless Zone Zero" \
        "  2. Open the Search History in-game" \
        "  3. Wait for it to load" \
        "  4. Close the game and run this script again"
fi

if (( candidate_count == 1 )); then
    ok "Found 1 candidate URL"
else
    ok "Found $candidate_count candidate URLs"
fi

if (( age > 86400 )); then
    warn "Cache is old; if validation fails, reopen the Search History in-game."
fi

# ------------------------------------------------------------
# Step 4: Validate candidates (newest first)
# ------------------------------------------------------------

step 4 "Validating with HoYoverse API"

valid_url=""
number=0

for url in "${urls[@]}"; do
    number=$((number + 1))
    label="#$number"

    vdetail "$label $(mask_url "$url")"

    curl_err_file="$(mktemp)"
    response="$(curl \
        --silent \
        --show-error \
        --fail \
        --location \
        --max-time 20 \
        -H "Content-Type: application/json" \
        "$url" 2>"$curl_err_file")"
    status=$?
    curl_err="$(sed 's/^curl: ([0-9]*) //' "$curl_err_file" | head -n1)"
    rm -f "$curl_err_file"

    if (( status != 0 )); then
        say "      ${c_red}${s_fail}${c_reset} $label request failed ${c_dim}(${curl_err:-curl exit $status})${c_reset}"
        continue
    fi

    if ! jq -e . >/dev/null 2>&1 <<<"$response"; then
        say "      ${c_red}${s_fail}${c_reset} $label server returned invalid JSON"
        continue
    fi

    retcode="$(jq -r '.retcode // empty' <<<"$response")"
    message="$(jq -r '.message // empty' <<<"$response")"

    if [[ "$retcode" != "0" ]]; then
        reason="retcode ${retcode:-missing}${message:+: $message}"
        [[ "$retcode" == "-101" ]] && reason="expired: $message"
        say "      ${c_red}${s_fail}${c_reset} $label rejected ${c_dim}($reason)${c_reset}"
        continue
    fi

    ok "$label is valid"
    valid_url="$url"
    break
done

if [[ -z "$valid_url" ]]; then
    lines=("None of the $candidate_count cached URL(s) were accepted.")
    lines+=("Search History links expire after about 24 hours. To get a fresh one:" \
            "  1. Start the game and open the Search History" \
            "  2. Wait for it to load, close the game" \
            "  3. Run this script again")
    fail "No valid Search History URL found." "${lines[@]}"
fi

# ------------------------------------------------------------
# Clean URL: keep only the parameters trackers need.
# ------------------------------------------------------------

final_url="$(python3 - "$valid_url" <<'PY'
import sys
from urllib.parse import urlsplit, urlunsplit, parse_qsl, urlencode

parsed = urlsplit(sys.argv[1])

required = {"authkey", "authkey_ver", "sign_type", "game_biz", "lang"}

params = [
    (key, value)
    for key, value in parse_qsl(parsed.query, keep_blank_values=True)
    if key in required
]

print(urlunsplit((parsed.scheme, parsed.netloc, parsed.path, urlencode(params), "")))
PY
)"

# ------------------------------------------------------------
# Clipboard
# ------------------------------------------------------------

copy_tool=""
copied=false

if $copy; then
    if [[ -n "${WAYLAND_DISPLAY:-}" ]] && command -v wl-copy >/dev/null 2>&1; then
        copy_tool="wl-copy"
        printf '%s' "$final_url" | wl-copy 2>/dev/null && copied=true
    elif [[ -n "${DISPLAY:-}" ]] && command -v xclip >/dev/null 2>&1; then
        copy_tool="xclip"
        printf '%s' "$final_url" | xclip -selection clipboard 2>/dev/null && copied=true
    elif [[ -n "${DISPLAY:-}" ]] && command -v xsel >/dev/null 2>&1; then
        copy_tool="xsel"
        printf '%s' "$final_url" | xsel --clipboard --input 2>/dev/null && copied=true
    fi
fi

# ------------------------------------------------------------
# Result
# ------------------------------------------------------------

say ""
say "${c_green}${c_bold}${s_ok} Search History URL ready${c_reset}"
say ""

# The URL itself always goes to stdout.
if $quiet || [[ ! -t 1 ]]; then
    printf '%s\n' "$final_url"
else
    printf '%s\n' "$final_url" >&2
fi

say ""
if $copied; then
    say "${c_green}${s_ok}${c_reset} Copied to clipboard ${c_dim}(via $copy_tool)${c_reset}. Paste it into your tracker."
elif ! $copy; then
    say "${c_dim}Clipboard copy skipped (--no-copy).${c_reset}"
elif [[ -n "$copy_tool" ]]; then
    say "${c_yellow}${s_warn}${c_reset} Copying with $copy_tool failed. Select the URL above and copy it manually."
else
    say "${c_yellow}${s_warn}${c_reset} No clipboard tool found. Copy the URL above manually,"
    say "  or install ${c_bold}wl-clipboard${c_reset} (Wayland) or ${c_bold}xclip${c_reset} (X11)."
fi
say ""

exit 0
