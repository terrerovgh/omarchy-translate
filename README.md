# omarchy-translate

An [Omarchy](https://omarchy.org/) shell plugin that translates the text you have selected.
Select text in any app, press **SUPER + ALT + T**, and a card in your current theme shows the translation.

- **Source language: automatic.** Google detects it.
- **Target: Spanish.** If the text is already in Spanish, it is translated to English.
- **No API key.** It uses Google Translate's public endpoint.
- You don't need to copy first: it reads the primary selection, the text highlighted with the mouse, and falls back to the clipboard when nothing is selected.

| Key | Action |
|---|---|
| `SUPER + ALT + T` | Translate the selection |
| `Enter` / `Ctrl + C` | Copy the translation and close the card |
| `Esc` / click outside | Close the card |
| `↑` `↓` / `j` `k` | Scroll long translations |

## Installation

```bash
omarchy plugin add https://github.com/terrerovgh/omarchy-translate --enable
ln -sf ~/.config/omarchy/plugins/terrerov.translate/bin/omarchy-translate-selection ~/.local/bin/
```

Add the shortcut to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + ALT + T", "Translate selection", os.getenv("HOME") .. "/.local/bin/omarchy-translate-selection")
```

Validate it with `hyprctl reload && hyprctl configerrors`.

Requirements: `wl-clipboard`, `jq`, and `python3`. All three ship with Omarchy.

## Changing the languages

In `Translate.qml`:

```qml
readonly property string targetLang: "es"   // default target language
readonly property string altLang: "en"      // used when the text is already in targetLang
```

## Using it from the terminal

```bash
./translate.py "Good morning"                          # {"ok": true, "source": "en", "target": "es", "text": "Buen día"}
./translate.py --to es --alt en "Buenos días"          # {"ok": true, "source": "es", "target": "en", ...}
echo "Ich habe Hunger" | ./translate.py
```

## Files

| File | Purpose |
|---|---|
| `manifest.json` | `overlay` plugin manifest |
| `Translate.qml` | The overlay card (Quickshell) |
| `translate.py` | Translator, Python stdlib only |
| `bin/omarchy-translate-selection` | Reads the selection and opens the plugin through `omarchy-shell` |
| `i18n/` | Interface strings (`en`, `es`) |

## Privacy

Every text you translate is sent to Google (`clients5.google.com`, with `translate.googleapis.com` as a fallback).
The text is passed as an argument, never interpolated into a shell, and is always shown as plain text.
