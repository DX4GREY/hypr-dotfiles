-- Autostart services and plugins
hl.on("hyprland.start", function ()
    hl.exec_cmd("hyprpm reload -n")
    hl.exec_cmd("hyprlock --immediate-render")
    hl.exec_cmd("awww-daemon")
    hl.exec_cmd("sleep 1 && ( [ -f \"$HOME/qs-wallpaper-picker/scripts/restore_wallpaper.sh\" ] && \"$HOME/qs-wallpaper-picker/scripts/restore_wallpaper.sh\" || awww img \"$HOME/Pictures/Wallpapers/hill-house.png\" 2>/dev/null || true )")
end)
