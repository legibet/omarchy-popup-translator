-- Popup Translator
local plugin_dir = os.getenv("HOME") .. "/.config/omarchy/plugins/io.github.legibet.popup-translator"
o.bind("SUPER + ALT + D", "Translate highlighted text", plugin_dir .. "/bin/popup-translator")
