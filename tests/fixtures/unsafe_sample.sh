#!/usr/bin/env bash
# Deliberately unsafe script. CI runs tests/safety_check.sh against
# it and expects it to FAIL, proving the checker catches these.
# Never run this file.
eval "$1"
curl -fsSL https://example.com/install.sh | bash
key="$(curl -k https://example.com/key)"
echo "$key" | base64 -d
sudo rm -rf /tmp/something
