# hypr-dotfiles

> **A clean, modular, and dynamic Hyprland desktop environment powered by Quickshell, Hyprlock, Matugen, and Fish/Zsh on Arch Linux.**

Inspired by modern fluid design and the architecture of `end-4/hypr-dotfiles`, this repository bundles a complete, cohesive, and battle-tested Wayland setup into a standalone, reproducible configuration.

---

## 📸 Overview & Architecture

- **Compositor**: [Hyprland](https://hyprland.org) (v0.56+ with native Lua architecture & modular config split)
- **Desktop Widgets & Bar**: [Quickshell](https://git.outfoxxed.me/quickshell/quickshell) (`ii` / illogical-impulse widget ecosystem)
- **Idle & Screen Lock**: `hypridle` & `hyprlock` (with dynamic Material You color integration)
- **Dynamic Theming**: [Matugen](https://github.com/InioX/matugen) (Material 3 palette extraction)
- **App Launchers**: [Rofi-wayland](https://github.com/lbonn/rofi-wayland) & [Fuzzel](https://codeberg.org/dnkl/fuzzel)
- **Terminal Emulators**: [Kitty](https://sw.kovidgoyal.net/kitty/) & [Foot](https://codeberg.org/dnkl/foot)
- **Shells & Prompts**: [Fish](https://fishshell.com/) & [Zsh](https://www.zsh.org/) + [Starship](https://starship.rs/)
- **Wallpaper Daemon**: `awww` / `mpvpaper` with integrated wallpaper selector
- **Audio & Media**: PipeWire + WirePlumber + Playerctl

---

## 📂 Repository Structure

```text
hypr-dotfiles/
├── .config/
│   ├── hypr/                    # Hyprland Lua configuration, hyprlock, hypridle, env.conf
│   ├── quickshell/              # Quickshell widgets, bar, control center, notifications
│   ├── illogical-impulse/       # Shell actions, appearance, and translation profiles
│   ├── kitty/                   # Kitty terminal configuration & Matugen theme hook
│   ├── foot/                    # Foot lightweight terminal configuration
│   ├── rofi/                    # Rofi app launcher styles & dynamic colors
│   ├── fuzzel/                  # Fuzzel minimal Wayland launcher
│   ├── wlogout/                 # Logout / Power dialog layout and CSS
│   ├── matugen/                 # Matugen color template generators
│   ├── fastfetch/               # Fastfetch system info layout & logos
│   ├── fish/                    # Fish shell configurations & aliases
│   ├── zshrc.d/                 # Modular Zsh scripts
│   ├── fontconfig/              # Font rendering configuration
│   ├── cava/                    # CAVA audio visualizer profile
│   ├── btop/                    # Btop system monitor theme & settings
│   ├── gtk-3.0/ & gtk-4.0/      # GTK theming, CSS styling & icons
│   ├── Kvantum/                 # Qt Kvantum themes (Colloid, MaterialAdw)
│   ├── kde-material-you-colors/ # KDE dynamic colors daemon config
│   ├── nwg-look/                # GTK theme switcher state
│   ├── xdg-desktop-portal/      # Wayland portal rules
│   ├── 43pr/                    # Theme coordinator and palette engine
│   ├── starship.toml            # Starship cross-shell prompt
│   └── .zshrc                   # Zsh interactive configuration
├── assets/
│   └── wallpapers/              # Default high-resolution wallpapers (e.g., hill-house.png)
├── packages-pacman.txt          # Official Arch Linux repository dependencies
├── packages-aur.txt             # Arch User Repository (AUR) packages
├── install.sh                   # Robust automated installer
└── README.md                    # Documentation & Keybind cheatsheet
```

---

## 🚀 Installation

### Option 1: One-Liner (Remote Pipe)
Run directly from your terminal:
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/DX4GREY/hypr-dotfiles/main/install.sh)
```
*(The installer automatically detects that it is running via a pipe, clones the repository to `/tmp`, and executes the setup).*

### Option 2: Local Clone
```bash
# 1. Clone the repository
git clone https://github.com/DX4GREY/hypr-dotfiles.git
cd hypr-dotfiles

# 2. Make installer executable & run
chmod +x install.sh
./install.sh
```

### What `install.sh` Does:
1. **Validates Distro**: Confirms that your system is Arch Linux or Arch-compatible.
2. **Bootstraps AUR Helper**: Installs `yay` automatically if neither `yay` nor `paru` is present.
3. **Installs Packages**: Batches all required official (`packages-pacman.txt`) and AUR (`packages-aur.txt`) packages via `yay -S --needed --noconfirm`.
4. **Automated Backup**: Moves any existing configuration to `~/.config/dots_backup_<timestamp>` before writing new files.
5. **Deploys Configs & Wallpapers**: Copies all `.config/` directories and deploys default wallpapers to `~/Pictures/Wallpapers/`.
6. **Configures Services & Cache**: Refreshes font cache (`fc-cache -fv`), applies script permissions (`chmod +x`), and enables PipeWire user services.

---

## ⌨️ Keybindings Cheatsheet

### 🚀 Applications & Launchers
| Keybinding | Action |
| :--- | :--- |
| `Super + T` | Open default terminal (`kitty` / `foot`) |
| `Super + D` | Toggle Rofi application launcher |
| `Super_L` / `Super_R` | Quickshell search menu (or Fuzzel fallback) |
| `Super + E` | Open file manager (`dolphin` / `thunar`) |
| `Super + B` | Launch default web browser |
| `Super + Q` | Close active window |
| `Super + Space` | Toggle floating mode & center window (70% size) |
| `Super + F` | Fullscreen toggle |
| `Super + V` | Open clipboard history manager (`cliphist`) |
| `Super + .` | Open emoji picker |

### 🪟 Window Navigation & Tiling
| Keybinding | Action |
| :--- | :--- |
| `Super + H / J / K / L` | Move focus (Left / Down / Up / Right) |
| `Super + Shift + H / J / K / L` | Move window (Left / Down / Up / Right) |
| `Super + Ctrl + H / J / K / L` | Resize window (pixel delta) |
| `Super + [1-9, 0]` | Switch to workspace 1–10 |
| `Super + Shift + [1-9, 0]` | Move focused window to workspace 1–10 |
| `Super + Mouse Left Click` | Drag & move window |
| `Super + Mouse Right Click`| Drag & resize window |

### 🎨 Desktop Widgets & Theming
| Keybinding | Action |
| :--- | :--- |
| `Super + Tab` | Toggle Quickshell workspaces overview |
| `Super + ~` (`Grave`) | Quickshell power / session menu |
| `Super + I` | Open Quickshell settings dashboard |
| `Super + A` / `Super + O` | Toggle left sidebar widgets |
| `Super + N` | Toggle right notification center |
| `Super + J` / `Super + Shift + W` | Toggle top status bar |
| `Super + /` | Open desktop keybinds cheatsheet |
| `Super + L` | Toggle light / dark mode |
| `Ctrl + Super + T` | Select next wallpaper / change wallpaper |
| `Ctrl + Super + R` | Restart desktop widgets and shell |
| `Super + O` | Change window opacity preset |

### 📸 Utilities & Screenshots
| Keybinding | Action |
| :--- | :--- |
| `Print` | Screenshot entire screen to clipboard |
| `Ctrl + Print` | Save full screenshot to `~/Pictures/Screenshots/` |
| `Super + Shift + S` | Interactive area snip screenshot |
| `Super + Shift + A` | Snip area & search with Google Lens |
| `Super + Shift + X` | Screen OCR (Extract text from screen to clipboard) |
| `Super + Shift + C` | Pick color on screen (`hyprpicker`) |
| `Super + Shift + R` | Record screen area (video) |
| `Ctrl + Alt + R` | Record fullscreen |

### 🔊 Media & System Controls
| Keybinding | Action |
| :--- | :--- |
| `XF86AudioRaiseVolume` | Increase volume (+2%) |
| `XF86AudioLowerVolume` | Decrease volume (-2%) |
| `XF86AudioMute` | Mute audio toggle |
| `XF86AudioPlay` | Play / Pause media |
| `XF86AudioNext` | Next track |
| `XF86AudioPrev` | Previous track |
| `XF86MonBrightnessUp` | Increase display brightness (+5%) |
| `XF86MonBrightnessDown` | Decrease display brightness (-5%) |
| `Super + Tab` / `hyprlock` | Lock screen |
| `Ctrl + Alt + Delete` | Power / Logout menu |
| `Super + Shift + E` | Exit Hyprland session |

---

## ⚙️ Customization & Modular Config

Configurations are cleanly divided into default and user overrides:
- **Environment variables**: Located in `~/.config/hypr/env.conf`. Sourced automatically by `hyprland.lua`.
- **User overrides**: Put your custom Hyprland configs in `~/.config/hypr/custom/` (`execs.lua`, `general.lua`, `keybinds.lua`, `rules.lua`, `variables.lua`).
- **QuickShell config**: Located in `~/.config/quickshell/ii/` and configured via `~/.config/illogical-impulse/config.json`.

---

## 📜 License
Released under the MIT License. Feel free to use, modify, and share!
