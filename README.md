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

With no argument, the script auto-detects the game install by checking the default Steam location and every Steam library listed in `libraryfolders.vdf`.

You can point it at either the Steam install root or the actual data folder — the script tries both:

- `.../Zenless Zone Zero` (Steam install root)
- `.../Zenless Zone Zero/games/ZenlessZoneZero Game/ZenlessZoneZero_Data`
