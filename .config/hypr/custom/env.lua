

-- Ensure ~/.local/bin is in PATH for Hyprland child processes
local home_dir = os.getenv("HOME") or (HOME or "")
local path_old = os.getenv("PATH") or ""
if not string.find(path_old, home_dir .. "/.local/bin") then
    hl.env("PATH", home_dir .. "/.local/bin:" .. path_old)
end
