#!/usr/bin/env bash
#
# Static safety checks for signal.sh.
#
# People run this script with `curl ... | bash`, so it must never
# do anything beyond reading the game cache and calling the API.
# This fails if risky patterns show up in the script.
#
# Usage: bash tests/safety_check.sh [file...]

set -u

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if (( $# == 0 )); then
    set -- "$root/signal.sh"
fi

# pattern @@ reason
# shellcheck disable=SC2016  # patterns are regexes, not expansions
rules=(
    '\beval\b @@ eval runs arbitrary strings as code'
    '^\s*sudo\b @@ the script must never escalate privileges'
    '\brm\s+-[a-zA-Z]*r @@ recursive delete is not needed'
    '(curl|wget)[^#]*\|\s*(ba|z|da)?sh\b @@ piping downloads into a shell'
    'base64\s+(-d|--decode) @@ decoding hidden payloads'
    '/dev/(tcp|udp)/ @@ raw network sockets'
    '\bchmod\b @@ changing file permissions is not needed'
    '\bcrontab\b @@ persistence is not allowed'
    '(>|>>)\s*"?\$HOME/\.(bashrc|profile|zshrc) @@ editing shell startup files'
    '\bexec\s+[0-9]*<> @@ opening read/write file descriptors'
    'curl[^#]*(-k\b|--insecure) @@ disabling TLS verification'
    'curl[^#]*(-d\b|--data|-F\b|--form|-T\b|--upload-file) @@ sending local data out'
    '\bexec\( @@ dynamic Python exec'
    '\bos\.system\(|\bsubprocess\b @@ Python shelling out'
)

status=0

for file in "$@"; do
    echo "Checking $file"

    # Copy of the file with comments and plain-text here-docs (help
    # text) blanked out, keeping line numbers, so only code is scanned.
    code="$(mktemp)"
    python3 - "$file" >"$code" <<'PY'
import re, sys

delim = None
for line in open(sys.argv[1]):
    line = line.rstrip("\n")
    if delim is not None:
        if line == delim:
            delim = None
        print("")
        continue
    m = re.search(r"<<-?'?([A-Z]+)'?", line)
    if m and m.group(1) != "PY":
        delim = m.group(1)
    print("" if line.lstrip().startswith("#") else line)
PY

    for rule in "${rules[@]}"; do
        pattern="${rule%% @@ *}"
        reason="${rule#* @@ }"
        if matches="$(grep -nP -- "$pattern" "$code")"; then
            echo "  FAIL: $reason"
            printf '%s\n' "$matches" | sed 's/^/        /'
            status=1
        fi
    done

    # Every network request must enforce a timeout.
    while IFS=: read -r line _; do
        if ! sed -n "${line},$((line + 12))p" "$file" | grep -q -- '--max-time'; then
            echo "  FAIL: curl call on line $line has no --max-time"
            status=1
        fi
    done < <(grep -nP '^\s*[^#]*\$\(curl\b|^\s*curl\b' "$code")
    rm -f "$code"

    # Embedded Python blocks must at least compile.
    python3 - "$file" <<'PY' || status=1
import re, sys

src = open(sys.argv[1]).read()
blocks = re.findall(r"<<'PY'\n(.*?)\nPY\n", src, re.S)

for i, block in enumerate(blocks, 1):
    try:
        compile(block, f"python block {i}", "exec")
    except SyntaxError as e:
        print(f"  FAIL: python block {i} does not compile: {e}")
        sys.exit(1)

print(f"  ok   {len(blocks)} embedded python block(s) compile")
PY
done

if (( status == 0 )); then
    echo "All safety checks passed."
fi
exit "$status"
