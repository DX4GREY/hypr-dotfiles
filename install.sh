#!/usr/bin/env bash

# ==============================================================================
# hypr-dotfiles Modular Installer
# Compatible with Arch Linux & Arch-based distributions
# ==============================================================================

set -euo pipefail

# Visual styling
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_BLUE="\033[1;34m"
C_GREEN="\033[1;32m"
C_YELLOW="\033[1;33m"
C_RED="\033[1;31m"
C_CYAN="\033[1;36m"

info()    { printf "${C_BLUE}[INFO]${C_RESET} %s\n" "$1"; }
success() { printf "${C_GREEN}[DONE]${C_RESET} %s\n" "$1"; }
warn()    { printf "${C_YELLOW}[WARN]${C_RESET} %s\n" "$1"; }
error()   { printf "${C_RED}[ERROR]${C_RESET} %s\n" "$1" >&2; }

# ------------------------------------------------------------------------------
# 1. Pipe / One-Liner Detection & Self-Bootstrap
# ------------------------------------------------------------------------------
SCRIPT_SOURCE="${BASH_SOURCE[0]:-}"
SCRIPT_DIR=""

if [[ -n "$SCRIPT_SOURCE" && -f "$SCRIPT_SOURCE" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"
fi

# If executed via curl | bash or from outside the repo structure
if [[ -z "$SCRIPT_DIR" || ! -d "${SCRIPT_DIR}/.config" || ! -f "${SCRIPT_DIR}/packages-pacman.txt" ]]; then
    info "Running via one-liner/pipe. Bootstrapping repository to temporary directory..."
    
    REPO_URL="${DOTS_REPO_URL:-https://github.com/DX4GREY/hypr-dotfiles.git}"
    TEMP_DIR="$(mktemp -d -t hypr-dotfiles-XXXXXX)"
    
    if ! command -v git >/dev/null 2>&1; then
        info "Installing git..."
        sudo pacman -S --needed --noconfirm git
    fi
    
    info "Cloning ${REPO_URL} into ${TEMP_DIR}..."
    git clone --depth 1 "$REPO_URL" "$TEMP_DIR/hypr-dotfiles"
    
    cd "$TEMP_DIR/hypr-dotfiles"
    exec bash install.sh "$@"
fi

# ------------------------------------------------------------------------------
# 2. Distro & Environment Validation
# ------------------------------------------------------------------------------
printf "${C_CYAN}%s${C_RESET}\n" "=========================================================="
printf "${C_BOLD}%s${C_RESET}\n" "           hypr-dotfiles Automated Installer             "
printf "${C_CYAN}%s${C_RESET}\n" "=========================================================="

if [[ "${EUID}" -eq 0 ]]; then
    error "Please do not run this script as root / via sudo directly."
    error "Run as a normal user. The script will request sudo when required."
    exit 1
fi

if [[ ! -f /etc/os-release ]]; then
    error "/etc/os-release not found. Cannot determine Linux distribution."
    exit 1
fi

# shellcheck disable=SC1091
source /etc/os-release

if [[ "${ID:-}" != "arch" && "${ID_LIKE:-}" != *arch* ]]; then
    error "This installer is tailored strictly for Arch Linux or Arch-based systems."
    error "Detected: ${PRETTY_NAME:-unknown}"
    exit 1
fi

if ! command -v sudo >/dev/null 2>&1; then
    error "sudo is required to install packages."
    exit 1
fi

if ! command -v pacman >/dev/null 2>&1; then
    error "pacman was not found. This installer requires Arch Linux."
    exit 1
fi

info "Detected Distribution: ${PRETTY_NAME:-Arch Linux}"

# ------------------------------------------------------------------------------
# 3. AUR Helper Detection & Installation
# ------------------------------------------------------------------------------
AUR_HELPER=""

if command -v yay >/dev/null 2>&1; then
    AUR_HELPER="yay"
elif command -v paru >/dev/null 2>&1; then
    AUR_HELPER="paru"
else
    info "No AUR helper (yay/paru) detected. Bootstrapping 'yay'..."
    
    info "Installing base-devel and git..."
    sudo pacman -S --needed --noconfirm base-devel git
    
    YAY_BUILD_DIR="$(mktemp -d -t yay-build-XXXXXX)"
    info "Cloning yay AUR repository to ${YAY_BUILD_DIR}..."
    git clone https://aur.archlinux.org/yay.git "$YAY_BUILD_DIR"
    
    (
        cd "$YAY_BUILD_DIR"
        makepkg -si --noconfirm
    )
    
    rm -rf "$YAY_BUILD_DIR"
    AUR_HELPER="yay"
    success "'yay' successfully installed."
fi

info "Using AUR helper: ${AUR_HELPER}"

# ------------------------------------------------------------------------------
# 4. Package Installation
# ------------------------------------------------------------------------------
PACMAN_PKG_FILE="${SCRIPT_DIR}/packages-pacman.txt"
AUR_PKG_FILE="${SCRIPT_DIR}/packages-aur.txt"

if [[ -f "$PACMAN_PKG_FILE" ]]; then
    info "Reading official repository packages..."
    mapfile -t PACMAN_PACKAGES < <(grep -vE '^\s*(#|$)' "$PACMAN_PKG_FILE")
    
    if [[ "${#PACMAN_PACKAGES[@]}" -gt 0 ]]; then
        info "Installing ${#PACMAN_PACKAGES[@]} official packages via pacman..."
        sudo pacman -S --needed --noconfirm "${PACMAN_PACKAGES[@]}"
        success "Official repository packages installed."
    fi
else
    warn "packages-pacman.txt not found. Skipping pacman batch installation."
fi

if [[ -f "$AUR_PKG_FILE" ]]; then
    info "Reading AUR packages..."
    mapfile -t AUR_PACKAGES < <(grep -vE '^\s*(#|$)' "$AUR_PKG_FILE")
    
    if [[ "${#AUR_PACKAGES[@]}" -gt 0 ]]; then
        info "Installing ${#AUR_PACKAGES[@]} AUR packages via ${AUR_HELPER}..."
        "$AUR_HELPER" -S --needed --noconfirm "${AUR_PACKAGES[@]}"
        success "AUR packages installed."
    fi
else
    warn "packages-aur.txt not found. Skipping AUR batch installation."
fi

# ------------------------------------------------------------------------------
# 5. Automated Backup Mechanism
# ------------------------------------------------------------------------------
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="$HOME/.config/dots_backup_${TIMESTAMP}"
BACKUP_CREATED=0

backup_item() {
    local target="$1"
    local rel_path="$2"
    if [[ -e "$target" || -L "$target" ]]; then
        if [[ "$BACKUP_CREATED" -eq 0 ]]; then
            info "Backing up existing configurations to ${BACKUP_DIR}..."
            mkdir -p "$BACKUP_DIR"
            BACKUP_CREATED=1
        fi
        local dest_parent
        dest_parent="$(dirname "$BACKUP_DIR/$rel_path")"
        mkdir -p "$dest_parent"
        mv "$target" "$BACKUP_DIR/$rel_path"
    fi
}

info "Checking for existing configuration files to backup..."

for item in "${SCRIPT_DIR}/.config"/*; do
    name="$(basename "$item")"
    backup_item "$HOME/.config/$name" "$name"
done

# Check ~/.zshrc
if [[ -f "${SCRIPT_DIR}/.config/.zshrc" && -e "$HOME/.zshrc" ]]; then
    backup_item "$HOME/.zshrc" ".zshrc"
fi

if [[ "$BACKUP_CREATED" -eq 1 ]]; then
    success "Backup completed at: ${BACKUP_DIR}"
else
    info "No conflicting configurations found. Backup directory was not needed."
fi

# ------------------------------------------------------------------------------
# 6. Deploy Configuration Files & Assets
# ------------------------------------------------------------------------------
info "Deploying dotfiles to ~/.config..."
mkdir -p "$HOME/.config"

# Copy all configuration directories and files
cp -r "${SCRIPT_DIR}/.config"/* "$HOME/.config/"

# Link or copy ~/.zshrc
if [[ -f "$HOME/.config/.zshrc" ]]; then
    cp "$HOME/.config/.zshrc" "$HOME/.zshrc"
    success "Configured ~/.zshrc."
fi

# Deploy wallpapers
WALLPAPER_DEST="$HOME/Pictures/Wallpapers"
info "Deploying wallpapers to ${WALLPAPER_DEST}..."
mkdir -p "$WALLPAPER_DEST"

if [[ -d "${SCRIPT_DIR}/assets/wallpapers" ]]; then
    cp -r "${SCRIPT_DIR}/assets/wallpapers"/* "$WALLPAPER_DEST/"
    # Symlink ~/Wallpapers for convenience
    ln -sfn "$WALLPAPER_DEST" "$HOME/Wallpapers"
    success "Wallpapers installed."
fi

# ------------------------------------------------------------------------------
# 7. Post-Installation Configuration & Permissions
# ------------------------------------------------------------------------------
info "Ensuring executable permissions on scripts..."
find "$HOME/.config/hypr" "$HOME/.config/quickshell" "$HOME/.config/43pr" -type f \( -name "*.sh" -o -name "*.py" \) -exec chmod +x {} + 2>/dev/null || true

info "Updating XDG user directories..."
if command -v xdg-user-dirs-update >/dev/null 2>&1; then
    xdg-user-dirs-update
fi

info "Refreshing font cache..."
if command -v fc-cache >/dev/null 2>&1; then
    fc-cache -fv >/dev/null 2>&1 || true
    success "Font cache refreshed."
fi

# Configure papirus folders if available
if command -v papirus-folders >/dev/null 2>&1; then
    info "Setting Papirus folder style..."
    papirus-folders -C white >/dev/null 2>&1 || true
fi

# Enable systemd user services
info "Enabling user audio services..."
if command -v systemctl >/dev/null 2>&1; then
    systemctl --user enable --now pipewire.service 2>/dev/null || true
    systemctl --user enable --now pipewire-pulse.service 2>/dev/null || true
    systemctl --user enable --now wireplumber.service 2>/dev/null || true
fi

# Generate initial dynamic theme if theme generator is present
if [[ -f "$HOME/.config/43pr/bin/theme.py" ]] && command -v python3 >/dev/null 2>&1; then
    info "Generating initial theme colors..."
    python3 "$HOME/.config/43pr/bin/theme.py" apply >/dev/null 2>&1 || true
fi

# Initial wallpaper apply if awww is installed
if command -v awww >/dev/null 2>&1 && [[ -f "$WALLPAPER_DEST/hill-house.png" ]]; then
    info "Initializing wallpaper daemon configuration..."
    awww-daemon >/dev/null 2>&1 &
    sleep 0.5
    awww img "$WALLPAPER_DEST/hill-house.png" >/dev/null 2>&1 || true
fi

# ------------------------------------------------------------------------------
# 8. Completion Notice
# ------------------------------------------------------------------------------
printf "\n"
printf "${C_GREEN}%s${C_RESET}\n" "=========================================================="
printf "${C_BOLD}${C_GREEN}%s${C_RESET}\n" "       hypr-dotfiles Installation Finished Successfully!   "
printf "${C_GREEN}%s${C_RESET}\n" "=========================================================="
printf "\n"
printf "  • Configurations: %s\n" "$HOME/.config"
printf "  • Wallpapers:     %s\n" "$WALLPAPER_DEST"
if [[ "$BACKUP_CREATED" -eq 1 ]]; then
    printf "  • Backup:         %s\n" "$BACKUP_DIR"
fi
printf "\n"
info "You can now start Hyprland by logging in via your display manager or running:"
printf "  ${C_CYAN}Hyprland${C_RESET}\n\n"
