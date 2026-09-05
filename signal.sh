#!/usr/bin/env bash

set -u

# ============================================================
# Zenless Zone Zero - Search History URL extractor
#
# Usage:
#   bash signal.sh "/path/to/Zenless Zone Zero"
#
# Example:
#   bash signal.sh "/home/${USER}/.local/share/Steam/steamapps/common/Zenless Zone Zero"
# ============================================================

# ------------------------------------------------------------
# Colors (only when attached to a terminal, respecting NO_COLOR)
# ------------------------------------------------------------

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    c_red=$'\033[31m'
    c_green=$'\033[32m'
    c_bold=$'\033[1m'
    c_reset=$'\033[0m'
else
    c_red=""
    c_green=""
    c_bold=""
    c_reset=""
fi

err() { echo "${c_red}ERROR: $*${c_reset}"; }
ok()  { echo "${c_green}$*${c_reset}"; }

echo "${c_bold}Attempting to locate Search History url!${c_reset}"
echo

# ------------------------------------------------------------
# Requirements
# ------------------------------------------------------------

missing=()
for cmd in curl jq python3; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
done

if (( ${#missing[@]} > 0 )); then
    err "Missing required command(s): ${missing[*]}"
    echo
    echo "Please install these packages using your distro's package manager: ${missing[*]}"
    exit 1
fi

# ------------------------------------------------------------
# Game path
# ------------------------------------------------------------

# ------------------------------------------------------------
# Steam library paths (for auto-detection when no arg is given)
#
# Reads libraryfolders.vdf to find every Steam library the user
# added (external drives, second disks, etc.), not just the
# default one.
# ------------------------------------------------------------

steam_library_paths() {
    local vdf
    for vdf in \
        "$HOME/.local/share/Steam/steamapps/libraryfolders.vdf" \
        "$HOME/.steam/steam/steamapps/libraryfolders.vdf"
    do
        [[ -f "$vdf" ]] || continue
        grep -oP '"path"\s*"\K[^"]+' "$vdf" | sed 's/\\\\/\//g'
        break
    done
}

base_paths=()

if [[ $# -ge 1 ]]; then
    base_paths=("$1")
else
    base_paths=("$HOME/.local/share/Steam/steamapps/common/Zenless Zone Zero")

    while IFS= read -r lib; do
        [[ -n "$lib" ]] || continue
        base_paths+=("$lib/steamapps/common/Zenless Zone Zero")
    done < <(steam_library_paths)

    echo "No game path supplied, searching known Steam library locations..."
    echo
fi

# ------------------------------------------------------------
# Resolve real data folder (Steam installs put webCaches under
# "games/ZenlessZoneZero Game/ZenlessZoneZero_Data").
# ------------------------------------------------------------

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
    err "Could not find webCaches under any of:"
    for base_path in "${base_paths[@]}"; do
        base_path="${base_path%/}"
        echo "  $base_path"
        echo "  $base_path/$steam_subpath"
    done
    echo

    if [[ ${#base_paths[@]} -eq 1 && -d "${base_paths[0]%/}" ]]; then
        echo "Contents of game directory:"
        ls -la "${base_paths[0]%/}"
    else
        echo "Usage:"
        echo "  $0 \"/path/to/Zenless Zone Zero\""
    fi
    exit 1
fi

echo "Game path:"
echo "$game_path"
echo

web_caches="$game_path/webCaches"

ok "webCaches found:"
echo "$web_caches"
echo

# ------------------------------------------------------------
# Find newest cache version
# ------------------------------------------------------------

cache_path=""

max_a=0
max_b=0
max_c=0
max_d=0
max_folder=""

for folder in "$web_caches"/*; do

    [[ -d "$folder" ]] || continue

    name="$(basename "$folder")"

    if [[ "$name" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then

        a="${BASH_REMATCH[1]}"
        b="${BASH_REMATCH[2]}"
        c="${BASH_REMATCH[3]}"
        d="${BASH_REMATCH[4]}"

        # Strip leading zeroes safely.
        a=$((10#$a))
        b=$((10#$b))
        c=$((10#$c))
        d=$((10#$d))

        newer=false

        if (( a > max_a )); then
            newer=true
        elif (( a == max_a && b > max_b )); then
            newer=true
        elif (( a == max_a && b == max_b && c > max_c )); then
            newer=true
        elif (( a == max_a && b == max_b && c == max_c && d >= max_d )); then
            newer=true
        fi

        if [[ "$newer" == true ]]; then
            max_a=$a
            max_b=$b
            max_c=$c
            max_d=$d
            max_folder="$name"
        fi
    fi
done

# ------------------------------------------------------------
# Select cache
# ------------------------------------------------------------

if [[ -n "$max_folder" ]]; then

    cache_path="$web_caches/$max_folder/Cache/Cache_Data/data_2"

    echo "Latest cache version:"
    echo "$max_folder"

else

    # Try non-versioned cache directory.
    cache_path="$web_caches/Cache/Cache_Data/data_2"

    echo "No versioned cache directory found."
fi

echo
echo "Cache file:"
echo "$cache_path"
echo

# ------------------------------------------------------------
# Verify cache
# ------------------------------------------------------------

if [[ ! -f "$cache_path" ]]; then

    err "Could not find cache file:"
    echo "$cache_path"
    echo
    echo "Available webCaches directories:"
    find "$web_caches" -maxdepth 4 -type f -name "data_2" -print 2>/dev/null

    exit 1
fi

ok "Cache file found."
echo

# ------------------------------------------------------------
# Extract candidate URLs
#
# Reads $cache_path directly (read-only, no copy needed even
# while the game has the file open) and prints one URL per line.
# ------------------------------------------------------------

echo "Searching cache for getGachaLog URLs..."
echo

mapfile -t urls < <(python3 - "$cache_path" <<'PY'
import sys

input_file = sys.argv[1]

with open(input_file, "rb") as f:
    data = f.read()

# Same separator used by the PowerShell script:
#
# $cache_data -split '1/0/'
#
parts = data.split(b"1/0/")

# Search newest -> oldest.
for part in reversed(parts):

    # Equivalent to:
    # $line.StartsWith('http')
    if not part.startswith(b"http"):
        continue

    # Equivalent to:
    # $line.Contains("getGachaLog")
    if b"getGachaLog" not in part:
        continue

    # Equivalent to:
    # ($line -split "\0")[0]
    url = part.split(b"\0", 1)[0]

    url = url.decode("utf-8", errors="ignore").strip()

    if url:
        print(url)
PY
)

candidate_count="${#urls[@]}"

echo "Candidate URLs found: $candidate_count"
echo

if [[ "$candidate_count" -eq 0 ]]; then
    echo "Could not locate any getGachaLog URLs."
    echo
    echo "Please make sure to:"
    echo "  1. Start Zenless Zone Zero"
    echo "  2. Open the Search History"
    echo "  3. Wait for it to load"
    echo "  4. Close the game"
    echo "  5. Run this script again"
    exit 1
fi

# ------------------------------------------------------------
# Check candidate URLs
# ------------------------------------------------------------

number=0

for url in "${urls[@]}"; do

    [[ -n "$url" ]] || continue

    number=$((number + 1))

    echo "============================================================"
    echo "Candidate #$number"
    echo "============================================================"
    echo "$url"
    echo

    echo "Requesting..."

    response="$(curl \
        --silent \
        --show-error \
        --fail \
        --location \
        --max-time 20 \
        -H "Content-Type: application/json" \
        "$url" 2>/dev/null)"

    status=$?

    if (( status != 0 )); then
        echo "Request failed."
        echo
        continue
    fi

    # Verify JSON.
    if ! echo "$response" | jq empty >/dev/null 2>&1; then
        echo "Server returned invalid JSON."
        echo
        continue
    fi

    retcode="$(echo "$response" | jq -r '.retcode // empty')"

    echo "retcode: ${retcode:-<missing>}"

    if [[ "$retcode" != "0" ]]; then
        echo "URL is invalid."
        echo
        continue
    fi

    echo
    ok "VALID URL FOUND!"
    echo

    # --------------------------------------------------------
    # Clean URL
    # --------------------------------------------------------

    latest_url="$(python3 - "$url" <<'PY'
import sys
from urllib.parse import urlsplit, urlunsplit, parse_qsl, urlencode

url = sys.argv[1]

parsed = urlsplit(url)

required = {
    "authkey",
    "authkey_ver",
    "sign_type",
    "game_biz",
    "lang",
}

params = parse_qsl(
    parsed.query,
    keep_blank_values=True
)

filtered = [
    (key, value)
    for key, value in params
    if key in required
]

new_query = urlencode(filtered)

result = urlunsplit((
    parsed.scheme,
    parsed.netloc,
    parsed.path,
    new_query,
    ""
))

print(result)
PY
)"

    echo "Search History Url Found!"
    echo "$latest_url"
    echo

    # --------------------------------------------------------
    # Clipboard
    # --------------------------------------------------------

    if command -v wl-copy >/dev/null 2>&1; then

        printf '%s' "$latest_url" | wl-copy
        echo "Search History Url has been saved to clipboard."

    elif command -v xclip >/dev/null 2>&1; then

        printf '%s' "$latest_url" | xclip -selection clipboard
        echo "Search History Url has been saved to clipboard."

    elif command -v xsel >/dev/null 2>&1; then

        printf '%s' "$latest_url" | xsel --clipboard --input
        echo "Search History Url has been saved to clipboard."

    else

        echo "WARNING: No clipboard utility found."
        echo "URL was not copied to clipboard."

    fi

    echo
    exit 0

done

# ------------------------------------------------------------
# Nothing worked
# ------------------------------------------------------------

err "Could not locate Search History Url."
echo
echo "Please make sure to open the Search history before running the script."

exit 1
