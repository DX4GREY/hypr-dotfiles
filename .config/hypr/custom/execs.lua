-- Autostart services and plugins
hl.on("hyprland.start", function ()
    hl.exec_cmd("hyprpm reload -n || hyprctl plugin load /var/cache/hyprpm/dx4white/HyprGlass/hyprglass.so")
    hl.exec_cmd("hyprlock --immediate-render")
    hl.exec_cmd("awww-daemon")
    hl.exec_cmd("sleep 1 && /home/dx4white/qs-wallpaper-picker/scripts/restore_wallpaper.sh")
    hl.exec_cmd("sleep 2 && " .. (HOME or (os.getenv("HOME") or "")) .. "/.local/bin/quickshell-lyricbar --background")
end)
