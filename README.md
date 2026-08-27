# Popup Translator

Translate highlighted text from Wayland apps in an Omarchy popup.

![Popup Translator](preview.png)

## Install

```bash
omarchy plugin add https://github.com/legibet/omarchy-popup-translator.git --enable
```

Add a shortcut to `~/.config/hypr/bindings.lua`:

```lua
local plugin_dir = os.getenv("HOME") .. "/.config/omarchy/plugins/io.github.legibet.popup-translator"
o.bind("SUPER + ALT + D", "Translate highlighted text", plugin_dir .. "/bin/popup-translator")
```

Highlight text in a Wayland app, then press the shortcut. The app must provide highlighted text through the Wayland primary selection.

## Settings

Click the translation icon in the top bar to choose the target language and provider. Bing works without configuration; AI supports OpenAI and OpenAI-compatible providers.

API keys are stored locally with owner-only permissions and are used only with the Base URL they were saved for.

## Remove

Remove the shortcut from `~/.config/hypr/bindings.lua`, then remove the plugin:

```bash
omarchy plugin remove io.github.legibet.popup-translator
```

Removing the plugin does not delete its saved API key. Delete it separately if you configured one:

```bash
rm -f ~/.config/omarchy-popup-translator/credentials.json
```
