hl.bind("CTRL+SUPER+ALT+Slash", hl.dsp.exec_cmd("xdg-open ~/.config/hypr/custom/keybinds.lua"), {description = "Edit user keybinds"} )
hl.bind("SUPER + SHIFT + W", hl.dsp.exec_cmd("/home/dx4white/qs-wallpaper-picker/scripts/open_picker.sh"), { description = "Wallpaper: Open picker" })




-- Quickshell LyricBar Keybindings
hl.bind("SUPER + Y", hl.dsp.exec_cmd("qs -c lyricbar ipc --any-display call lyricbar toggle"), { description = "LyricBar: Toggle visibility" })
hl.bind("SUPER + ALT + Y", hl.dsp.exec_cmd("qs -c lyricbar ipc --any-display call lyricbar toggleMini"), { description = "LyricBar: Toggle mini pill" })
hl.bind("SUPER + CTRL + Y", hl.dsp.exec_cmd("qs -c lyricbar ipc --any-display call lyricbar toggleSettings"), { description = "LyricBar: Toggle settings" })
