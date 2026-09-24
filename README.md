# ZZZ Signal

Extracts your Zenless Zone Zero Search History (gacha log) URL from the game's local web cache on Linux, validates it, and copies it to your clipboard.

## Requirements

Install these packages with your distro's package manager:

- `curl`
- `jq`
- `python3`

Optional, for clipboard support (one of):

- `wl-copy` (Wayland)
- `xclip` or `xsel` (X11)

## Usage

Open the in-game Search History, let it load, close the game, then run:

```bash
curl -fsSL https://raw.githubusercontent.com/wuyscc/zzz_signal/main/signal.sh | bash
```

If your install lives somewhere the auto-detect can't find (a non-Steam launcher, an unusual library path, etc.), pass the install folder explicitly. Since the script is being piped into `bash`, put the arguments after `-s --`:

```bash
curl -fsSL https://raw.githubusercontent.com/wuyscc/zzz_signal/main/signal.sh | bash -s -- "/path/to/Zenless Zone Zero"
```

With no argument, the script auto-detects the game install by checking the default Steam locations (including Flatpak Steam) and every Steam library listed in `libraryfolders.vdf`.

You can point it at either the Steam install root or the actual data folder — the script tries both:

- `.../Zenless Zone Zero` (Steam install root)
- `.../Zenless Zone Zero/games/ZenlessZoneZero Game/ZenlessZoneZero_Data`

## Options

| Option | Description |
| --- | --- |
| `-q`, `--quiet` | Print only the final URL (errors are still shown) |
| `--no-copy` | Don't copy the URL to the clipboard |
| `-v`, `--verbose` | Show full cache paths and a masked view of each candidate URL |
| `-h`, `--help` | Show help |

Progress messages go to stderr and the URL goes to stdout, so you can capture it in a variable:

```bash
url="$(bash signal.sh -q --no-copy)"
```

Set `NO_COLOR=1` to turn off colored output.

## Development

Every push and pull request runs the [Validate](.github/workflows/validate.yml) workflow:

- **Syntax**: `bash -n` on every shell script
- **ShellCheck**: lint `signal.sh` and the test scripts
- **Safety**: `tests/safety_check.sh` rejects risky patterns (`eval`, `sudo`, `rm -r`, piping downloads into a shell, turning off TLS checks, uploading data, requests with no timeout) and makes sure the embedded Python compiles
- **Functional tests**: `tests/test_signal.sh` runs the script against a fake install with a mocked `curl`, so no real network requests are made

Run the same checks locally:

```bash
bash -n signal.sh
shellcheck -x signal.sh tests/*.sh
bash tests/safety_check.sh
bash tests/test_signal.sh
```
