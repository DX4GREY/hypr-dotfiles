local home_dir = os.getenv("HOME")

-- Load env.conf if it exists
local env_conf_path = home_dir .. "/.config/hypr/env.conf"
local f = io.open(env_conf_path, "r")
if f then
    for line in f:lines() do
        local key, val = line:match("^%s*env%s*=%s*([%w_]+)%s*,%s*(.-)%s*$")
        if key and val then
            -- Expand $HOME
            val = val:gsub("%$HOME", home_dir)
            hl.env(key, val)
        end
    end
    f:close()
else
    -- Fallbacks
    hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
    local xdg_data_dirs_old = os.getenv("XDG_DATA_DIRS") or ""
    hl.env("XDG_DATA_DIRS", home_dir .. "/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/usr/local/share:/usr/share:" .. xdg_data_dirs_old)
    hl.env("QT_QPA_PLATFORM", "wayland;xcb")
    hl.env("QT_QPA_PLATFORMTHEME", "kde")
    hl.env("XDG_MENU_PREFIX", "plasma-")
    hl.env("ILLOGICAL_IMPULSE_VIRTUAL_ENV", home_dir .. "/.local/state/quickshell/.venv")
end
