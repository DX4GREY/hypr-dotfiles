#!/usr/bin/env bash

# ==============================================================================
# hypr-dotfiles Intelligent Installer
# Dynamic, Resilient & Fully Customizable Hyprland Desktop Environment for Arch Linux
# Supports: Full Install, Coexistence with KDE/GNOME, Custom Modular, Dotfiles Only, & Repair
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
C_MAGENTA="\033[1;35m"
C_WHITE="\033[1;37m"

info()    { printf "${C_BLUE}[INFO]${C_RESET} %s\n" "$1"; }
success() { printf "${C_GREEN}[DONE]${C_RESET} %s\n" "$1"; }
warn()    { printf "${C_YELLOW}[WARN]${C_RESET} %s\n" "$1"; }
error()   { printf "${C_RED}[ERROR]${C_RESET} %s\n" "$1" >&2; }
step()    { printf "\n${C_CYAN}::${C_BOLD} %s${C_RESET}\n" "$1"; }
substep() { printf "  ${C_CYAN}->${C_RESET} %b\n" "$1"; }

# ------------------------------------------------------------------------------
# 1. Pipe / One-Liner Detection & Self-Bootstrap
# ------------------------------------------------------------------------------
SCRIPT_SOURCE="${BASH_SOURCE[0]:-}"
SCRIPT_DIR=""

if [[ -n "$SCRIPT_SOURCE" && -f "$SCRIPT_SOURCE" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"
fi

if [[ -z "$SCRIPT_DIR" || ! -d "${SCRIPT_DIR}/.config" || ! -f "${SCRIPT_DIR}/packages-pacman.txt" ]]; then
    printf "${C_BLUE}[INFO]${C_RESET} Running via one-liner/pipe. Bootstrapping repository to temporary directory...\n"
    
    REPO_URL="${DOTS_REPO_URL:-https://github.com/DX4GREY/hypr-dotfiles.git}"
    TEMP_DIR="$(mktemp -d -t hypr-dotfiles-XXXXXX)"
    
    if ! command -v git >/dev/null 2>&1; then
        sudo pacman -S --needed --noconfirm git
    fi
    
    git clone --depth 1 "$REPO_URL" "$TEMP_DIR/hypr-dotfiles"
    cd "$TEMP_DIR/hypr-dotfiles"
    exec bash install.sh "$@"
fi

# ------------------------------------------------------------------------------
# 2. Target User & Environment Resolution
# ------------------------------------------------------------------------------
# Identify the actual desktop user (even if script is started via sudo)
TARGET_USER="${SUDO_USER:-${USER:-dx4white}}"
if [[ "$TARGET_USER" == "root" ]]; then
    if [[ -d "/home/dx4white" ]]; then
        TARGET_USER="dx4white"
    else
        # Find first non-root user with UID >= 1000
        FIRST_USER="$(awk -F: '$3 >= 1000 && $3 < 60000 {print $1; exit}' /etc/passwd 2>/dev/null || true)"
        if [[ -n "$FIRST_USER" ]]; then
            TARGET_USER="$FIRST_USER"
        fi
    fi
fi

TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6 2>/dev/null || echo "")"
if [[ -z "$TARGET_HOME" || ! -d "$TARGET_HOME" ]]; then
    TARGET_HOME="/home/${TARGET_USER}"
fi

# Helpers to execute commands with correct privileges
run_as_user() {
    if [[ "${EUID}" -eq 0 && "$TARGET_USER" != "root" ]]; then
        su - "$TARGET_USER" -c "$*"
    else
        bash -c "$*"
    fi
}

run_as_root() {
    if [[ "${EUID}" -eq 0 ]]; then
        bash -c "$*"
    else
        sudo bash -c "$*"
    fi
}

# ------------------------------------------------------------------------------
# 3. Interactive Input Helpers
# ------------------------------------------------------------------------------
NON_INTERACTIVE=0

prompt_input() {
    local prompt="$1"
    local default="${2:-}"
    local response=""
    if [[ "$NON_INTERACTIVE" -eq 1 ]]; then
        echo "$default"
        return
    fi

    if [[ -t 0 ]]; then
        read -rp "$prompt" response
    elif [[ -e /dev/tty ]]; then
        read -rp "$prompt" response < /dev/tty
    else
        response="$default"
    fi
    echo "${response:-$default}"
}

prompt_confirm() {
    local prompt="$1"
    local default="${2:-Y}"
    local reply
    if [[ "$NON_INTERACTIVE" -eq 1 ]]; then
        [[ "$default" =~ ^[Yy]$ ]] && return 0 || return 1
    fi
    reply="$(prompt_input "$prompt " "$default")"
    [[ "$reply" =~ ^[Yy]$ ]] && return 0 || return 1
}

# ------------------------------------------------------------------------------
# 4. CLI Arguments & Flags
# ------------------------------------------------------------------------------
TARGET_MODE=""
DEPLOY_METHOD="copy" # "copy" or "symlink"
AUR_HELPER_CHOICE="auto"
CUSTOM_SHELL=""
DRY_RUN=0

INSTALL_OFFICIAL=1
INSTALL_AUR=1
CONFIGURE_GPU=1
SETUP_SDDM=1
DEPLOY_CONFIGS=1
SETUP_PLUGINS=1
SETUP_SHELL=1
DEPLOY_WALLPAPERS=1

show_help() {
    cat << EOF
hypr-dotfiles Intelligent Installer
Tailored for: ${TARGET_USER} (${TARGET_HOME})

Usage: ./install.sh [OPTIONS]

Installation Modes:
  --fresh                  Full installation: packages, GPU, SDDM Astronaut, dotfiles, plugins, shell
  --coexist, --switch      Install alongside existing DE (GNOME/KDE) without replacing DM or shell
  --custom                 Custom modular installation with step-by-step interactive selection
  --dotfiles               Deploy or symlink dotfiles & scripts only (no package manager actions)
  --repair                 Repair configurations, permissions, themes, and hyprpm plugins

Customization Flags:
  -m, --method <copy|symlink> Dotfiles deployment method (default: copy)
  -s, --shell <fish|zsh|bash|keep> Preferred default user shell
  --aur-helper <yay|paru>    Force specific AUR helper (default: auto-detect/build yay)
  --user <username>          Specify target non-root user (default: ${TARGET_USER})
  --no-packages              Skip all official pacman packages
  --no-aur                   Skip AUR package installation
  --no-gpu                   Skip GPU driver and hardware flag configuration
  --no-sddm                  Do not enable SDDM login manager
  --no-plugins               Skip Hyprland plugins (hyprpm) & VS Code extensions
  --no-wallpapers            Do not copy wallpapers to ~/Pictures/Wallpapers
  -n, --dry-run              Simulate installation steps without modifying system or home
  -y, --yes, --non-interactive Run non-interactively with defaults
  -h, --help                 Show this help menu and exit

Examples:
  ./install.sh                           # Interactive selection dashboard
  ./install.sh --fresh -y                # Unattended full Arch install
  ./install.sh --custom --method symlink # Custom install using symlinks for live development
  ./install.sh --dotfiles --method copy  # Standalone dotfiles copy only
  ./install.sh --repair                  # Refresh broken configs, themes, and plugins
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --fresh)                 TARGET_MODE="fresh"; shift ;;
        --coexist|--switch)      TARGET_MODE="switch"; shift ;;
        --custom)                TARGET_MODE="custom"; shift ;;
        --dotfiles)              TARGET_MODE="dotfiles"; shift ;;
        --repair)                TARGET_MODE="repair"; shift ;;
        -m|--method)
            DEPLOY_METHOD="$2"
            shift 2
            ;;
        -s|--shell)
            CUSTOM_SHELL="$2"
            shift 2
            ;;
        --aur-helper)
            AUR_HELPER_CHOICE="$2"
            shift 2
            ;;
        --user)
            TARGET_USER="$2"
            TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6 2>/dev/null || echo "/home/$TARGET_USER")"
            shift 2
            ;;
        --no-packages)           INSTALL_OFFICIAL=0; shift ;;
        --no-aur)                INSTALL_AUR=0; shift ;;
        --no-gpu)                CONFIGURE_GPU=0; shift ;;
        --no-sddm)               SETUP_SDDM=0; shift ;;
        --no-plugins)            SETUP_PLUGINS=0; shift ;;
        --no-wallpapers)         DEPLOY_WALLPAPERS=0; shift ;;
        -n|--dry-run)            DRY_RUN=1; shift ;;
        -y|--yes|--non-interactive) NON_INTERACTIVE=1; shift ;;
        -h|--help)               show_help; exit 0 ;;
        *)
            error "Unknown argument: $1"
            show_help
            exit 1
            ;;
    esac
done

# ------------------------------------------------------------------------------
# 5. System Validation & Sudo Keepalive
# ------------------------------------------------------------------------------
clear 2>/dev/null || true

printf "${C_CYAN}%s${C_RESET}\n" "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓"
printf "${C_CYAN}┃${C_BOLD}${C_WHITE}           HYPR-DOTFILES INTELLIGENT INSTALLER              ${C_CYAN}┃${C_RESET}\n"
printf "${C_CYAN}┃${C_RESET}       Modern & Dynamic Hyprland Ecosystem for Arch Linux   ${C_CYAN}┃${C_RESET}\n"
printf "${C_CYAN}%s${C_RESET}\n\n" "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛"

if [[ ! -f /etc/os-release ]]; then
    error "/etc/os-release not found. Cannot determine Linux distribution."
    exit 1
fi

# shellcheck disable=SC1091
source /etc/os-release

if [[ "${ID:-}" != "arch" && "${ID_LIKE:-}" != *arch* ]]; then
    error "This installer is tailored strictly for Arch Linux or Arch-based distributions."
    error "Detected system: ${PRETTY_NAME:-unknown}"
    exit 1
fi

if ! command -v pacman >/dev/null 2>&1; then
    error "'pacman' was not found. Arch Linux base installation required."
    exit 1
fi

# Request sudo credentials early if root actions might be needed
SUDO_PID=""
cleanup_sudo() {
    if [[ -n "$SUDO_PID" ]]; then
        kill "$SUDO_PID" 2>/dev/null || true
    fi
}
trap cleanup_sudo EXIT INT TERM

if [[ "${EUID}" -ne 0 ]]; then
    if ! command -v sudo >/dev/null 2>&1; then
        error "'sudo' is required for system configuration. Please install sudo."
        exit 1
    fi
    info "Validating administrative privileges..."
    sudo -v
    while true; do sudo -n true; sleep 50; kill -0 "$$" || exit; done 2>/dev/null &
    SUDO_PID=$!
fi

# ------------------------------------------------------------------------------
# 6. Environment & Hardware Detection Dashboard
# ------------------------------------------------------------------------------
step "Analyzing System Architecture & Environment"
substep "Target User:       ${C_BOLD}${TARGET_USER}${C_RESET} (${TARGET_HOME})"
substep "Distribution:      ${PRETTY_NAME:-Arch Linux}"

# Detect Desktop Environment
DETECTED_DE="None (Pure TTY / Minimal)"
if [[ -n "${XDG_CURRENT_DESKTOP:-}" ]]; then
    DETECTED_DE="${XDG_CURRENT_DESKTOP}"
elif command -v gnome-shell >/dev/null 2>&1; then
    DETECTED_DE="GNOME Desktop"
elif command -v plasmashell >/dev/null 2>&1; then
    DETECTED_DE="KDE Plasma"
elif command -v xfce4-session >/dev/null 2>&1; then
    DETECTED_DE="XFCE Desktop"
elif command -v cinnamon >/dev/null 2>&1; then
    DETECTED_DE="Cinnamon"
fi
substep "Active Desktop:    ${DETECTED_DE}"

# Detect Display Manager
DETECTED_DM="None (Console / TTY)"
if systemctl is-active --quiet sddm 2>/dev/null; then
    DETECTED_DM="SDDM (Active)"
elif systemctl is-active --quiet gdm 2>/dev/null; then
    DETECTED_DM="GDM (Active)"
elif systemctl is-active --quiet lightdm 2>/dev/null; then
    DETECTED_DM="LightDM (Active)"
elif systemctl is-enabled --quiet sddm 2>/dev/null; then
    DETECTED_DM="SDDM (Enabled)"
elif systemctl is-enabled --quiet gdm 2>/dev/null; then
    DETECTED_DM="GDM (Enabled)"
fi
substep "Display Manager:   ${DETECTED_DM}"

# Detect GPU Hardware
GPU_TYPE="Generic / Integrated"
GPU_INFO=""
if command -v lspci >/dev/null 2>&1; then
    GPU_INFO="$(lspci -k 2>/dev/null | grep -EA2 -i "(VGA|3D|Display)" || true)"
elif [[ -d /sys/class/drm ]]; then
    GPU_INFO="$(cat /sys/class/drm/card*/device/vendor 2>/dev/null || true)"
fi

IS_NVIDIA=0
IS_AMD=0
IS_INTEL=0

if grep -qi "nvidia" <<< "$GPU_INFO"; then
    GPU_TYPE="NVIDIA Dedicated GPU"
    IS_NVIDIA=1
elif grep -qi -E "(amd|radeon|advanced micro)" <<< "$GPU_INFO"; then
    GPU_TYPE="AMD Radeon"
    IS_AMD=1
elif grep -qi "intel" <<< "$GPU_INFO"; then
    GPU_TYPE="Intel Graphics"
    IS_INTEL=1
fi
substep "Graphics Card:     ${GPU_TYPE}"

# Detect Virtualization
if command -v systemd-detect-virt >/dev/null 2>&1; then
    VIRT_TYPE="$(systemd-detect-virt 2>/dev/null)" || VIRT_TYPE="none"
    if [[ "$VIRT_TYPE" != "none" && -n "$VIRT_TYPE" ]]; then
        substep "Virtualization:    ${VIRT_TYPE} (VM detected)"
    fi
fi

# Detect Current Shell
CURRENT_USER_SHELL="$(getent passwd "$TARGET_USER" | cut -d: -f7 2>/dev/null || echo "$SHELL")"
substep "Current Shell:     ${CURRENT_USER_SHELL}"

# ------------------------------------------------------------------------------
# 7. Interactive Mode Selection
# ------------------------------------------------------------------------------
if [[ -z "$TARGET_MODE" ]]; then
    printf "\n${C_BOLD}%s${C_RESET}\n" "Select Installation Profile:"
    
    if [[ "$DETECTED_DE" == *"None"* ]]; then
        printf "  ${C_GREEN}[1] Full Fresh Arch Install${C_RESET} ${C_BOLD}(Recommended for your system)${C_RESET}\n"
        printf "      Complete setup: Pacman + AUR packages, GPU drivers, SDDM Astronaut, dotfiles, & plugins.\n"
        printf "  ${C_CYAN}[2] Custom / Modular Install${C_RESET}\n"
        printf "      Full control: Interactively choose individual components, package managers, and deploy method.\n"
        printf "  ${C_YELLOW}[3] Coexist / Switch DE${C_RESET}\n"
        printf "      Install Hyprland alongside existing setups without replacing current Display Manager.\n"
        printf "  ${C_BLUE}[4] Dotfiles Only${C_RESET}\n"
        printf "      Deploy or symlink dotfiles & scripts only (no package manager or system service changes).\n"
        printf "  ${C_MAGENTA}[5] Repair & Health Check${C_RESET}\n"
        printf "      Fix broken configs, regenerate themes, refresh hyprpm plugins, and check permissions.\n"
        DEFAULT_CHOICE="1"
    else
        printf "  ${C_YELLOW}[1] Coexist / Switch DE${C_RESET} ${C_BOLD}(Recommended: %s detected)${C_RESET}\n" "$DETECTED_DE"
        printf "      Safely install Hyprland alongside %s (keeps your current login manager & shell).\n" "$DETECTED_DE"
        printf "  ${C_GREEN}[2] Full Clean Install${C_RESET}\n"
        printf "      Full Hyprland setup including SDDM Astronaut theme (may override existing display manager).\n"
        printf "  ${C_CYAN}[3] Custom / Modular Install${C_RESET}\n"
        printf "      Full control: Interactively choose individual components, package managers, and deploy method.\n"
        printf "  ${C_BLUE}[4] Dotfiles Only${C_RESET}\n"
        printf "      Deploy or symlink dotfiles & scripts only (no package manager changes).\n"
        printf "  ${C_MAGENTA}[5] Repair & Health Check${C_RESET}\n"
        printf "      Refresh dotfiles, theme colors, and plugins without re-downloading packages.\n"
        DEFAULT_CHOICE="1"
    fi

    CHOICE="$(prompt_input "Enter selection [1-5] (default: ${DEFAULT_CHOICE}): " "$DEFAULT_CHOICE")"
    
    if [[ "$DETECTED_DE" == *"None"* ]]; then
        case "$CHOICE" in
            1) TARGET_MODE="fresh" ;;
            2) TARGET_MODE="custom" ;;
            3) TARGET_MODE="switch" ;;
            4) TARGET_MODE="dotfiles" ;;
            5) TARGET_MODE="repair" ;;
            *) TARGET_MODE="fresh" ;;
        esac
    else
        case "$CHOICE" in
            1) TARGET_MODE="switch" ;;
            2) TARGET_MODE="fresh" ;;
            3) TARGET_MODE="custom" ;;
            4) TARGET_MODE="dotfiles" ;;
            5) TARGET_MODE="repair" ;;
            *) TARGET_MODE="switch" ;;
        esac
    fi
fi

step "Active Installation Profile: ${TARGET_MODE^^}"

# Assign mode behaviors
case "$TARGET_MODE" in
    fresh)
        INSTALL_OFFICIAL=1
        INSTALL_AUR=1
        CONFIGURE_GPU=1
        SETUP_SDDM=1
        DEPLOY_CONFIGS=1
        SETUP_PLUGINS=1
        SETUP_SHELL=1
        DEPLOY_WALLPAPERS=1
        ;;
    switch)
        INSTALL_OFFICIAL=1
        INSTALL_AUR=1
        CONFIGURE_GPU=1
        SETUP_SDDM=0  # Preserve existing DM
        DEPLOY_CONFIGS=1
        SETUP_PLUGINS=1
        SETUP_SHELL=0  # Preserve existing shell
        DEPLOY_WALLPAPERS=1
        ;;
    dotfiles)
        INSTALL_OFFICIAL=0
        INSTALL_AUR=0
        CONFIGURE_GPU=0
        SETUP_SDDM=0
        DEPLOY_CONFIGS=1
        SETUP_PLUGINS=0
        SETUP_SHELL=0
        DEPLOY_WALLPAPERS=1
        ;;
    repair)
        INSTALL_OFFICIAL=0
        INSTALL_AUR=0
        CONFIGURE_GPU=1
        SETUP_SDDM=0
        DEPLOY_CONFIGS=1
        SETUP_PLUGINS=1
        SETUP_SHELL=0
        DEPLOY_WALLPAPERS=0
        ;;
    custom)
        printf "\n${C_BOLD}%s${C_RESET}\n" "Modular Component Customization:"
        prompt_confirm "  [+] Install Official Pacman Packages?" "Y" && INSTALL_OFFICIAL=1 || INSTALL_OFFICIAL=0
        prompt_confirm "  [+] Install AUR Packages (yay/paru)?" "Y" && INSTALL_AUR=1 || INSTALL_AUR=0
        prompt_confirm "  [+] Configure GPU Hardware Drivers & Wayland Flags?" "Y" && CONFIGURE_GPU=1 || CONFIGURE_GPU=0
        
        printf "\n  ${C_BOLD}Display Manager Configuration:${C_RESET}\n"
        printf "    [1] Enable SDDM with Astronaut Theme\n"
        printf "    [2] Keep Current Display Manager (%s)\n" "$DETECTED_DM"
        printf "    [3] Do not enable any Display Manager (TTY / startx)\n"
        DM_SEL="$(prompt_input "    Select DM option [1-3] (default: 2): " "2")"
        case "$DM_SEL" in
            1) SETUP_SDDM=1 ;;
            *) SETUP_SDDM=0 ;;
        esac

        printf "\n  ${C_BOLD}Dotfiles Deployment Method:${C_RESET}\n"
        printf "    [1] Standalone Copy (Recommended - safe independent clone in ~/.config)\n"
        printf "    [2] Symlink (Best for dotfiles developers - live sync from this repository)\n"
        METHOD_SEL="$(prompt_input "    Select method [1-2] (default: 1): " "1")"
        case "$METHOD_SEL" in
            2) DEPLOY_METHOD="symlink" ;;
            *) DEPLOY_METHOD="copy" ;;
        esac

        prompt_confirm "  [+] Deploy Dotfiles & .local/bin Scripts?" "Y" && DEPLOY_CONFIGS=1 || DEPLOY_CONFIGS=0
        prompt_confirm "  [+] Deploy Wallpapers to ~/Pictures/Wallpapers?" "Y" && DEPLOY_WALLPAPERS=1 || DEPLOY_WALLPAPERS=0
        prompt_confirm "  [+] Install Hyprland Plugins (hyprpm) & VS Code Extensions?" "Y" && SETUP_PLUGINS=1 || SETUP_PLUGINS=0
        prompt_confirm "  [+] Configure Default User Shell (Fish / Zsh / Bash)?" "Y" && SETUP_SHELL=1 || SETUP_SHELL=0
        ;;
esac

# ------------------------------------------------------------------------------
# 8. AUR Helper Setup (yay / paru)
# ------------------------------------------------------------------------------
AUR_HELPER=""

if [[ "$INSTALL_AUR" -eq 1 ]]; then
    if [[ "$AUR_HELPER_CHOICE" == "paru" ]] && command -v paru >/dev/null 2>&1; then
        AUR_HELPER="paru"
    elif [[ "$AUR_HELPER_CHOICE" == "yay" ]] && command -v yay >/dev/null 2>&1; then
        AUR_HELPER="yay"
    elif command -v yay >/dev/null 2>&1; then
        AUR_HELPER="yay"
    elif command -v paru >/dev/null 2>&1; then
        AUR_HELPER="paru"
    else
        step "Bootstrapping AUR Helper ('yay')"
        info "Installing base-devel and git..."
        run_as_root "pacman -S --needed --noconfirm base-devel git"
        
        YAY_BUILD_DIR="$(mktemp -d -t yay-build-XXXXXX)"
        chown -R "${TARGET_USER}:${TARGET_USER}" "$YAY_BUILD_DIR"
        
        info "Cloning and building yay as user ${TARGET_USER}..."
        run_as_user "git clone https://aur.archlinux.org/yay.git '${YAY_BUILD_DIR}' && cd '${YAY_BUILD_DIR}' && makepkg -si --noconfirm"
        
        rm -rf "$YAY_BUILD_DIR"
        AUR_HELPER="yay"
        success "'yay' successfully installed."
    fi
    info "Active AUR helper: ${AUR_HELPER}"
fi

# ------------------------------------------------------------------------------
# 9. Hardware & GPU Specific Packages
# ------------------------------------------------------------------------------
if [[ "$CONFIGURE_GPU" -eq 1 && "$INSTALL_OFFICIAL" -eq 1 && "$DRY_RUN" -eq 0 ]]; then
    step "Configuring Graphics Hardware Support"

    if [[ "$IS_NVIDIA" -eq 1 ]]; then
        info "NVIDIA GPU detected. Checking drivers..."
        if ! pacman -Qs "nvidia" >/dev/null 2>&1; then
            if prompt_confirm "Install NVIDIA proprietary drivers (DKMS) & Wayland VA-API patches?" "Y"; then
                run_as_root "pacman -S --needed --noconfirm linux-headers nvidia-dkms nvidia-utils libva-nvidia-driver"
                success "NVIDIA drivers installed."
            fi
        else
            info "NVIDIA driver already present on system."
        fi
    elif [[ "$IS_AMD" -eq 1 ]]; then
        info "AMD Radeon detected. Ensuring Mesa & Vulkan packages..."
        run_as_root "pacman -S --needed --noconfirm mesa vulkan-radeon libva-mesa-driver"
        success "AMD graphics packages verified."
    elif [[ "$IS_INTEL" -eq 1 ]]; then
        info "Intel Graphics detected. Ensuring Mesa & Intel media drivers..."
        run_as_root "pacman -S --needed --noconfirm mesa vulkan-intel intel-media-driver"
        success "Intel graphics packages verified."
    fi
fi

# ------------------------------------------------------------------------------
# 10. Resilient Package Installation (Official & AUR)
# ------------------------------------------------------------------------------
# Helper for resilient pacman batch install with single-package fallback
resilient_pacman_install() {
    local -a pkgs=("$@")
    if [[ "${#pkgs[@]}" -eq 0 ]]; then return 0; fi

    info "Attempting batch installation of ${#pkgs[@]} packages..."
    if run_as_root "pacman -S --needed --noconfirm ${pkgs[*]}"; then
        success "Batch package installation succeeded."
        return 0
    fi

    warn "Batch installation encountered errors. Falling back to resilient package-by-package installation..."
    local failed_pkgs=()
    local success_count=0

    for pkg in "${pkgs[@]}"; do
        if run_as_root "pacman -S --needed --noconfirm '$pkg'" 2>/dev/null; then
            success_count=$((success_count + 1))
        else
            warn "Could not install pacman package: '$pkg' (skipping)"
            failed_pkgs+=("$pkg")
        fi
    done

    info "Resilient installation complete: ${success_count} installed, ${#failed_pkgs[@]} skipped."
    if [[ "${#failed_pkgs[@]}" -gt 0 ]]; then
        warn "Skipped packages: ${failed_pkgs[*]}"
    fi
}

resilient_aur_install() {
    local helper="$1"
    shift
    local -a pkgs=("$@")
    if [[ "${#pkgs[@]}" -eq 0 || -z "$helper" ]]; then return 0; fi

    info "Attempting AUR batch installation of ${#pkgs[@]} packages via ${helper}..."
    if run_as_user "$helper -S --needed --noconfirm ${pkgs[*]}"; then
        success "AUR batch package installation succeeded."
        return 0
    fi

    warn "AUR batch encountered warnings or errors. Retrying packages individually..."
    local failed_aur=()
    local success_aur=0

    for pkg in "${pkgs[@]}"; do
        if run_as_user "$helper -S --needed --noconfirm '$pkg'" 2>/dev/null; then
            success_aur=$((success_aur + 1))
        else
            warn "Could not install AUR package: '$pkg' (skipping)"
            failed_aur+=("$pkg")
        fi
    done

    info "Resilient AUR installation complete: ${success_aur} installed, ${#failed_aur[@]} skipped."
}

if [[ "$INSTALL_OFFICIAL" -eq 1 ]]; then
    step "Installing Official Repository Packages (pacman)"
    PACMAN_PKG_FILE="${SCRIPT_DIR}/packages-pacman.txt"
    
    if [[ -f "$PACMAN_PKG_FILE" ]]; then
        mapfile -t PACMAN_PACKAGES < <(grep -vE '^\s*(#|$)' "$PACMAN_PKG_FILE")
        if [[ "${#PACMAN_PACKAGES[@]}" -gt 0 ]]; then
            if [[ "$DRY_RUN" -eq 0 ]]; then
                resilient_pacman_install "${PACMAN_PACKAGES[@]}"
            else
                info "[DRY-RUN] Would install ${#PACMAN_PACKAGES[@]} official packages."
            fi
        fi
    fi
fi

if [[ "$INSTALL_AUR" -eq 1 && -n "$AUR_HELPER" ]]; then
    step "Installing AUR Packages (${AUR_HELPER})"
    AUR_PKG_FILE="${SCRIPT_DIR}/packages-aur.txt"
    
    if [[ -f "$AUR_PKG_FILE" ]]; then
        mapfile -t AUR_PACKAGES < <(grep -vE '^\s*(#|$)' "$AUR_PKG_FILE")
        if [[ "${#AUR_PACKAGES[@]}" -gt 0 ]]; then
            if [[ "$DRY_RUN" -eq 0 ]]; then
                resilient_aur_install "$AUR_HELPER" "${AUR_PACKAGES[@]}"
            else
                info "[DRY-RUN] Would install ${#AUR_PACKAGES[@]} AUR packages."
            fi
        fi
    fi
fi

# ------------------------------------------------------------------------------
# 11. Display Manager (SDDM Astronaut Theme) Setup
# ------------------------------------------------------------------------------
if [[ "$SETUP_SDDM" -eq 1 && "$DRY_RUN" -eq 0 ]]; then
    step "Configuring Display Manager (SDDM)"
    
    if ! command -v sddm >/dev/null 2>&1; then
        info "Installing sddm package..."
        run_as_root "pacman -S --needed --noconfirm sddm"
    fi

    # Disable conflicting DMs
    for dm in gdm lightdm lxdm ly; do
        if systemctl is-enabled "$dm.service" 2>/dev/null; then
            warn "Disabling conflicting display manager: $dm.service"
            run_as_root "systemctl disable $dm.service" 2>/dev/null || true
        fi
    done

    run_as_root "systemctl enable sddm.service" 2>/dev/null || true
    success "SDDM service enabled."

    SDDM_THEME_DIR="/usr/share/sddm/themes/sddm-astronaut-theme"
    if [[ -d "$SDDM_THEME_DIR" ]]; then
        info "Activating sddm-astronaut-theme..."
        run_as_root "mkdir -p /etc/sddm.conf.d"
        cat << 'EOF' | run_as_root "tee /etc/sddm.conf.d/theme.conf >/dev/null"
[Theme]
Current=sddm-astronaut-theme

[General]
InputMethod=qtvirtualkeyboard
EOF
        success "SDDM configured with Astronaut theme."
    fi
fi

# Ensure Wayland desktop session entry exists
if [[ "$DRY_RUN" -eq 0 && ! -f /usr/share/wayland-sessions/hyprland.desktop ]]; then
    run_as_root "mkdir -p /usr/share/wayland-sessions"
    cat << 'EOF' | run_as_root "tee /usr/share/wayland-sessions/hyprland.desktop >/dev/null"
[Desktop Entry]
Name=Hyprland
Comment=An intelligent dynamic tiling Wayland compositor
Exec=Hyprland
Type=Application
EOF
fi

# ------------------------------------------------------------------------------
# 12. Backup Existing User Configurations
# ------------------------------------------------------------------------------
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="${TARGET_HOME}/.config-backups/backup_${TIMESTAMP}"
BACKUP_CREATED=0

backup_item() {
    local target="$1"
    local rel_name="$2"
    if [[ -e "$target" || -L "$target" ]]; then
        if [[ "$BACKUP_CREATED" -eq 0 ]]; then
            step "Backing Up Existing Configurations"
            info "Destination: ${BACKUP_DIR}"
            mkdir -p "$BACKUP_DIR"
            BACKUP_CREATED=1
        fi
        local dest_parent
        dest_parent="$(dirname "$BACKUP_DIR/$rel_name")"
        mkdir -p "$dest_parent"
        cp -a "$target" "$BACKUP_DIR/$rel_name" 2>/dev/null || mv "$target" "$BACKUP_DIR/$rel_name"
    fi
}

if [[ "$DEPLOY_CONFIGS" -eq 1 && "$DRY_RUN" -eq 0 ]]; then
    for item in "${SCRIPT_DIR}/.config"/*; do
        name="$(basename "$item")"
        if [[ -e "${TARGET_HOME}/.config/$name" || -L "${TARGET_HOME}/.config/$name" ]]; then
            backup_item "${TARGET_HOME}/.config/$name" "$name"
        fi
    done

    for sh_file in ".zshrc" ".bashrc"; do
        if [[ -e "${TARGET_HOME}/${sh_file}" || -L "${TARGET_HOME}/${sh_file}" ]]; then
            backup_item "${TARGET_HOME}/${sh_file}" "${sh_file}"
        fi
    done

    if [[ "$BACKUP_CREATED" -eq 1 ]]; then
        chown -R "${TARGET_USER}:${TARGET_USER}" "$BACKUP_DIR" 2>/dev/null || true
        success "Pre-install backup safely created at: ${BACKUP_DIR}"
    fi
fi

# ------------------------------------------------------------------------------
# 13. Deploy Dotfiles & .local/bin Scripts
# ------------------------------------------------------------------------------
if [[ "$DEPLOY_CONFIGS" -eq 1 ]]; then
    step "Deploying Configurations & Scripts (Method: ${DEPLOY_METHOD^^})"
    
    if [[ "$DRY_RUN" -eq 0 ]]; then
        mkdir -p "${TARGET_HOME}/.config"
        mkdir -p "${TARGET_HOME}/.local/bin"

        # 1. Deploy .config items
        for src_item in "${SCRIPT_DIR}/.config"/*; do
            item_name="$(basename "$src_item")"
            dest_item="${TARGET_HOME}/.config/${item_name}"

            if [[ "$DEPLOY_METHOD" == "symlink" ]]; then
                ln -sfn "$src_item" "$dest_item"
            else
                rm -rf "$dest_item"
                cp -rL "$src_item" "$dest_item"
            fi
        done

        # 2. Deploy .local/bin scripts (e.g. quickshell-lyricbar)
        if [[ -d "${SCRIPT_DIR}/.local/bin" ]]; then
            for bin_file in "${SCRIPT_DIR}/.local/bin"/*; do
                bname="$(basename "$bin_file")"
                dest_bin="${TARGET_HOME}/.local/bin/${bname}"
                if [[ "$DEPLOY_METHOD" == "symlink" ]]; then
                    ln -sfn "$bin_file" "$dest_bin"
                else
                    cp -L "$bin_file" "$dest_bin"
                fi
                chmod +x "$dest_bin"
            done
            success "Installed helper executables into ~/.local/bin."
        fi

        # 3. Deploy shell dotfiles
        if [[ -f "${SCRIPT_DIR}/.config/.zshrc" ]]; then
            if [[ "$DEPLOY_METHOD" == "symlink" ]]; then
                ln -sfn "${SCRIPT_DIR}/.config/.zshrc" "${TARGET_HOME}/.zshrc"
            else
                cp -L "${SCRIPT_DIR}/.config/.zshrc" "${TARGET_HOME}/.zshrc"
            fi
        fi

        if [[ -f "${SCRIPT_DIR}/.config/.bashrc" ]]; then
            if [[ "$DEPLOY_METHOD" == "symlink" ]]; then
                ln -sfn "${SCRIPT_DIR}/.config/.bashrc" "${TARGET_HOME}/.bashrc"
            else
                cp -L "${SCRIPT_DIR}/.config/.bashrc" "${TARGET_HOME}/.bashrc"
            fi
        fi

        # 4. Ensure ~/.local/bin is in PATH across all shells
        # Fish path
        mkdir -p "${TARGET_HOME}/.config/fish/conf.d"
        echo 'fish_add_path -g $HOME/.local/bin' > "${TARGET_HOME}/.config/fish/conf.d/paths.fish"

        # Bash path
        if [[ -f "${TARGET_HOME}/.bashrc" ]] && ! grep -q '\.local/bin' "${TARGET_HOME}/.bashrc"; then
            echo 'export PATH="${HOME}/.local/bin:${PATH}"' >> "${TARGET_HOME}/.bashrc"
        fi

        # 5. NVIDIA specific Wayland environment flags
        if [[ "$IS_NVIDIA" -eq 1 ]]; then
            NVIDIA_ENV_FILE="${TARGET_HOME}/.config/hypr/custom/env.lua"
            if [[ -f "$NVIDIA_ENV_FILE" ]]; then
                if ! grep -q "LIBVA_DRIVER_NAME" "$NVIDIA_ENV_FILE"; then
                    info "Injecting NVIDIA Wayland environment variables into custom/env.lua..."
                    cat << 'EOF' >> "$NVIDIA_ENV_FILE"

-- NVIDIA Dedicated GPU Wayland optimizations
hl.env("LIBVA_DRIVER_NAME", "nvidia")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
hl.env("NVD_BACKEND", "direct")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
EOF
                    success "NVIDIA Wayland flags applied."
                fi
            fi
        fi

        # Restore file permissions
        find "${TARGET_HOME}/.config/hypr" "${TARGET_HOME}/.config/quickshell" "${TARGET_HOME}/.config/43pr" \
            -type f \( -name "*.sh" -o -name "*.py" \) -exec chmod +x {} + 2>/dev/null || true
        chmod +x "${TARGET_HOME}/.local/bin"/* 2>/dev/null || true
        chown -R "${TARGET_USER}:${TARGET_USER}" "${TARGET_HOME}/.config" "${TARGET_HOME}/.local" "${TARGET_HOME}/.zshrc" "${TARGET_HOME}/.bashrc" 2>/dev/null || true
        success "Dotfiles deployed successfully."
    else
        info "[DRY-RUN] Would deploy dotfiles and scripts to ~/.config and ~/.local/bin (${DEPLOY_METHOD})."
    fi
fi

# ------------------------------------------------------------------------------
# 14. Deploy Wallpapers
# ------------------------------------------------------------------------------
WALLPAPER_DEST="${TARGET_HOME}/Pictures/Wallpapers"

if [[ "$DEPLOY_WALLPAPERS" -eq 1 && "$DRY_RUN" -eq 0 ]]; then
    step "Deploying Default Wallpapers"
    mkdir -p "$WALLPAPER_DEST"

    if [[ -d "${SCRIPT_DIR}/assets/wallpapers" ]]; then
        cp -rn "${SCRIPT_DIR}/assets/wallpapers"/* "$WALLPAPER_DEST/" 2>/dev/null || true
        ln -sfn "$WALLPAPER_DEST" "${TARGET_HOME}/Wallpapers"
        chown -R "${TARGET_USER}:${TARGET_USER}" "$WALLPAPER_DEST" "${TARGET_HOME}/Wallpapers" 2>/dev/null || true
        success "Default wallpaper assets deployed to ${WALLPAPER_DEST}."
    fi
fi

# ------------------------------------------------------------------------------
# 15. Plugin Installation (hyprpm & VS Code)
# ------------------------------------------------------------------------------
if [[ "$SETUP_PLUGINS" -eq 1 && "$DRY_RUN" -eq 0 ]]; then
    step "Configuring Desktop Plugins & Extensions"

    # Hyprland Plugins (hyprpm)
    HYPRPM_TXT="${SCRIPT_DIR}/plugins-hyprpm.txt"
    if command -v hyprpm >/dev/null 2>&1 && [[ -f "$HYPRPM_TXT" ]]; then
        info "Configuring Hyprland plugins (hyprpm) for ${TARGET_USER}..."
        run_as_user "hyprpm update 2>/dev/null || true"
        
        while read -r repo_url plugin_name status; do
            [[ -z "$repo_url" || "$repo_url" =~ ^# ]] && continue
            info "Adding plugin: ${plugin_name} (${repo_url})..."
            run_as_user "hyprpm add '$repo_url' 2>/dev/null || true"
            if [[ "$status" == "enabled" ]]; then
                run_as_user "hyprpm enable '$plugin_name' 2>/dev/null || true"
            fi
        done < "$HYPRPM_TXT"
        
        run_as_user "hyprpm reload 2>/dev/null || true"
        success "Hyprland plugins installed and enabled."
    fi

    # Visual Studio Code Extensions
    VSCODE_TXT="${SCRIPT_DIR}/plugins-vscode.txt"
    VSCODE_CMD=""
    if command -v code >/dev/null 2>&1; then
        VSCODE_CMD="code"
    elif command -v code-oss >/dev/null 2>&1; then
        VSCODE_CMD="code-oss"
    fi

    if [[ -n "$VSCODE_CMD" && -f "$VSCODE_TXT" ]]; then
        INSTALL_EXT=1
        if [[ "$NON_INTERACTIVE" -eq 0 ]]; then
            prompt_confirm "Install VS Code extensions from repository?" "Y" || INSTALL_EXT=0
        fi

        if [[ "$INSTALL_EXT" -eq 1 ]]; then
            info "Installing VS Code extensions via ${VSCODE_CMD}..."
            while read -r ext; do
                [[ -z "$ext" || "$ext" =~ ^# ]] && continue
                run_as_user "$VSCODE_CMD --install-extension '$ext' --force 2>/dev/null || true"
            done < "$VSCODE_TXT"
            success "VS Code extensions configured."
        fi
    fi
fi

# ------------------------------------------------------------------------------
# 16. User Shell Selection
# ------------------------------------------------------------------------------
if [[ "$SETUP_SHELL" -eq 1 && "$DRY_RUN" -eq 0 ]]; then
    step "Configuring Default User Shell"
    
    if [[ -z "$CUSTOM_SHELL" && "$NON_INTERACTIVE" -eq 0 ]]; then
        printf "  [1] Fish (Interactive, fast, autosuggestions + fastfetch)\n"
        printf "  [2] Zsh  (Starship prompt + custom profile)\n"
        printf "  [3] Bash (Standard login shell)\n"
        printf "  [4] Keep current shell (%s)\n" "${CURRENT_USER_SHELL}"
        
        SHELL_CHOICE="$(prompt_input "Select preferred default shell [1-4] (default: 1): " "1")"
        case "$SHELL_CHOICE" in
            1) CUSTOM_SHELL="fish" ;;
            2) CUSTOM_SHELL="zsh" ;;
            3) CUSTOM_SHELL="bash" ;;
            *) CUSTOM_SHELL="keep" ;;
        esac
    fi

    case "${CUSTOM_SHELL:-keep}" in
        fish)
            if command -v fish >/dev/null 2>&1; then
                run_as_root "chsh -s '$(which fish)' '$TARGET_USER'" 2>/dev/null || true
                success "Default shell set to Fish for ${TARGET_USER}."
            fi
            ;;
        zsh)
            if command -v zsh >/dev/null 2>&1; then
                run_as_root "chsh -s '$(which zsh)' '$TARGET_USER'" 2>/dev/null || true
                success "Default shell set to Zsh for ${TARGET_USER}."
            fi
            ;;
        bash)
            if command -v bash >/dev/null 2>&1; then
                run_as_root "chsh -s '$(which bash)' '$TARGET_USER'" 2>/dev/null || true
                success "Default shell set to Bash for ${TARGET_USER}."
            fi
            ;;
        keep|*)
            info "Preserved current shell: ${CURRENT_USER_SHELL}"
            ;;
    esac
fi

# ------------------------------------------------------------------------------
# 17. System Services, Fonts & Theming Finalization
# ------------------------------------------------------------------------------
step "Finalizing Services, Permissions & Theming"

if [[ "$DRY_RUN" -eq 0 ]]; then
    # Refresh fonts & XDG
    if command -v xdg-user-dirs-update >/dev/null 2>&1; then
        run_as_user "xdg-user-dirs-update" 2>/dev/null || true
    fi
    if command -v fc-cache >/dev/null 2>&1; then
        run_as_user "fc-cache -fv >/dev/null 2>&1 || true"
        success "Font cache refreshed."
    fi

    # Papirus folders style
    if command -v papirus-folders >/dev/null 2>&1; then
        run_as_root "papirus-folders -C white >/dev/null 2>&1 || true"
    fi

    # Core system services
    if [[ "$TARGET_MODE" == "fresh" ]]; then
        if systemctl list-unit-files | grep -q "NetworkManager.service"; then
            run_as_root "systemctl enable --now NetworkManager.service" 2>/dev/null || true
        fi
        if systemctl list-unit-files | grep -q "bluetooth.service"; then
            run_as_root "systemctl enable --now bluetooth.service" 2>/dev/null || true
        fi
    fi

    # Enable user audio stack
    info "Enabling user audio services (PipeWire & WirePlumber)..."
    run_as_user "systemctl --user enable --now pipewire.service pipewire-pulse.service wireplumber.service 2>/dev/null || true"

    # Compile dynamic Material 3 palette
    THEME_PY="${TARGET_HOME}/.config/43pr/bin/theme.py"
    if [[ -f "$THEME_PY" ]] && command -v python3 >/dev/null 2>&1; then
        info "Compiling initial Material 3 palette..."
        run_as_user "python3 '$THEME_PY' apply >/dev/null 2>&1 || true"
        success "Theme palette compiled."
    fi

    # Initialize wallpaper daemon if awww is installed
    if command -v awww >/dev/null 2>&1 && [[ -f "$WALLPAPER_DEST/hill-house.png" ]]; then
        run_as_user "awww-daemon >/dev/null 2>&1 & sleep 0.5 && awww img '$WALLPAPER_DEST/hill-house.png' >/dev/null 2>&1 || true"
    fi
fi

# ------------------------------------------------------------------------------
# 18. Installation Summary & Launch Instructions
# ------------------------------------------------------------------------------
printf "\n"
printf "${C_GREEN}%s${C_RESET}\n" "=========================================================="
printf "${C_BOLD}${C_GREEN}%s${C_RESET}\n" "        HYPR-DOTFILES INSTALLATION COMPLETED              "
printf "${C_GREEN}%s${C_RESET}\n" "=========================================================="
printf "\n"

printf "  -> Target User: %s\n" "$TARGET_USER"
printf "  -> Configs:     %s\n" "${TARGET_HOME}/.config"
printf "  -> Scripts:     %s\n" "${TARGET_HOME}/.local/bin"
printf "  -> Method:      %s\n" "${DEPLOY_METHOD^^}"
if [[ "$DEPLOY_WALLPAPERS" -eq 1 ]]; then
    printf "  -> Wallpapers:  %s\n" "$WALLPAPER_DEST"
fi
if [[ "$BACKUP_CREATED" -eq 1 ]]; then
    printf "  -> Backup:      %s\n" "$BACKUP_DIR"
fi

printf "\n${C_BOLD}%s${C_RESET}\n" "How to launch Hyprland:"
if [[ "$SETUP_SDDM" -eq 1 ]]; then
    printf "  [+] SDDM login manager is enabled. Simply reboot your system:\n"
    printf "      ${C_CYAN}sudo reboot${C_RESET}\n"
elif [[ "$TARGET_MODE" == "switch" ]]; then
    printf "  [+] Log out of your current session, select ${C_BOLD}'Hyprland'${C_RESET} in your login screen.\n"
else
    printf "  [+] Launch directly from your TTY console by typing:\n"
    printf "      ${C_CYAN}Hyprland${C_RESET}\n"
fi
printf "\n"
