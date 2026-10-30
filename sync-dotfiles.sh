#!/usr/bin/env bash

# ==============================================================================
# hypr-dotfiles Intelligent Synchronization Utility
# Specifically tailored for dx4white
# Interactive dashboard to sync dotfiles, packages, and plugins to repository
# Features: Pre-scan diff preview, selective sync, smart filtering, and semantic git commit
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
substep() { printf "  ${C_CYAN}->${C_RESET} %s\n" "$1"; }
header()  {
    printf "\n${C_CYAN}%s${C_RESET}\n" "=========================================================="
    printf "${C_BOLD}%s${C_RESET}\n" "   $1"
    printf "${C_CYAN}%s${C_RESET}\n\n" "=========================================================="
}

# ------------------------------------------------------------------------------
# 1. User & Environment Detection
# ------------------------------------------------------------------------------
TARGET_USER="${SUDO_USER:-${USER:-dx4white}}"
if [[ "$TARGET_USER" == "root" && -d "/home/dx4white" ]]; then
    TARGET_USER="dx4white"
fi

USER_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6 2>/dev/null || echo "")"
if [[ -z "$USER_HOME" || ! -d "$USER_HOME" ]]; then
    USER_HOME="/home/${TARGET_USER}"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR"
CONFIG_SRC="${USER_HOME}/.config"
CONFIG_DEST="${REPO_DIR}/.config"
LOCAL_BIN_SRC="${USER_HOME}/.local/bin"
LOCAL_BIN_DEST="${REPO_DIR}/.local/bin"

# Verify repository structure
if [[ ! -d "$CONFIG_DEST" || ! -f "${REPO_DIR}/packages-pacman.txt" ]]; then
    error "Cannot find repository dotfiles structure at ${REPO_DIR}."
    exit 1
fi

# ------------------------------------------------------------------------------
# 2. Interactive Input Helpers
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
# 3. CLI Flags & Options
# ------------------------------------------------------------------------------
DRY_RUN=0
VERBOSE=0
DELETE_REMOVED=0
SYNC_PACKAGES=1
SYNC_DOTFILES=1
SYNC_PLUGINS=1
SYNC_WALLPAPERS=0
SYNC_LOCAL_BIN=1
ALL_PACKAGES=0
AUTO_COMMIT=0
COMMIT_MSG=""
CLI_MODE=0
SELECTED_COMPONENTS=()

show_help() {
    cat << EOF
Usage: ./sync-dotfiles.sh [OPTIONS]

Synchronizes host dotfiles, packages, and plugins to this repository.
Target user: ${TARGET_USER} (${USER_HOME})

Options:
  -y, --yes                 Non-interactive mode (use defaults without prompting)
  -n, --dry-run             Simulate sync without modifying any files in the repository
  -v, --verbose             Display detailed file-by-file transfer output
  -d, --diff                Inspect file diffs between host and repository before syncing
      --delete, --prune     Remove files in repo that no longer exist in host ~/.config
      --no-dotfiles         Skip synchronizing ~/.config dotfiles
      --no-packages         Skip synchronizing packages (pacman & AUR lists)
      --no-plugins          Skip synchronizing plugins (hyprpm, vscode)
      --no-bin              Skip synchronizing ~/.local/bin scripts
  -w, --wallpapers          Also sync wallpapers from ~/Pictures/Wallpapers to assets/wallpapers
  -a, --all-packages        Include all explicitly installed pacman packages in sync
  -c, --commit [MSG]        Automatically commit changes to git after sync
  -h, --help                Show this help message and exit

Examples:
  ./sync-dotfiles.sh                    # Interactive sync dashboard & menu
  ./sync-dotfiles.sh -y                 # Unattended full sync with defaults
  ./sync-dotfiles.sh --diff             # Inspect diffs before committing
  ./sync-dotfiles.sh --dry-run          # Preview what changes would be synced
  ./sync-dotfiles.sh -c "sync: update"  # Sync and auto-commit
EOF
}

SHOW_DIFF_FIRST=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -y|--yes)
            NON_INTERACTIVE=1
            CLI_MODE=1
            shift
            ;;
        -n|--dry-run)
            DRY_RUN=1
            CLI_MODE=1
            shift
            ;;
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        -d|--diff)
            SHOW_DIFF_FIRST=1
            shift
            ;;
        --delete|--prune)
            DELETE_REMOVED=1
            CLI_MODE=1
            shift
            ;;
        --no-dotfiles)
            SYNC_DOTFILES=0
            CLI_MODE=1
            shift
            ;;
        --no-packages)
            SYNC_PACKAGES=0
            CLI_MODE=1
            shift
            ;;
        --no-plugins)
            SYNC_PLUGINS=0
            CLI_MODE=1
            shift
            ;;
        --no-bin)
            SYNC_LOCAL_BIN=0
            CLI_MODE=1
            shift
            ;;
        -w|--wallpapers)
            SYNC_WALLPAPERS=1
            CLI_MODE=1
            shift
            ;;
        -a|--all-packages)
            ALL_PACKAGES=1
            CLI_MODE=1
            shift
            ;;
        -c|--commit)
            AUTO_COMMIT=1
            CLI_MODE=1
            if [[ $# -gt 1 && ! "$2" =~ ^- ]]; then
                COMMIT_MSG="$2"
                shift 2
            else
                COMMIT_MSG=""
                shift
            fi
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            error "Unknown argument: $1"
            show_help
            exit 1
            ;;
    esac
done

# ------------------------------------------------------------------------------
# 4. Managed Items Definition
# ------------------------------------------------------------------------------
MANAGED_CONFIGS=(
    "43pr"
    "autostart"
    "btop"
    "cava"
    "chrome-flags.conf"
    "code-flags.conf"
    "fastfetch"
    "fish"
    "fontconfig"
    "foot"
    "fuzzel"
    "gtk-3.0"
    "gtk-4.0"
    "gtkrc"
    "gtkrc-2.0"
    "hypr"
    "illogical-impulse"
    "kde-material-you-colors"
    "kitty"
    "Kvantum"
    "matugen"
    "mimeapps.list"
    "mpv"
    "neofetch"
    "nwg-look"
    "quickshell"
    "rofi"
    "sptlrx"
    "starship.toml"
    "thorium-flags.conf"
    "wlogout"
    "xdg-desktop-portal"
    "zshrc.d"
)

RSYNC_EXCLUDES=(
    --exclude="*.bak"
    --exclude="*.new"
    --exclude="*.tmp"
    --exclude="*~"
    --exclude="*.swp"
    --exclude="*.swo"
    --exclude="__pycache__/"
    --exclude="*.pyc"
    --exclude="*.pyo"
    --exclude=".cache/"
    --exclude="*.log"
    --exclude=".git/"
    --exclude="*.sock"
    --exclude="*.pid"
    --exclude="gpu_data.bin"
    --exclude="hyprlandCrashReport*"
    --exclude="blob_storage/"
    --exclude="Session Storage/"
    --exclude="Code Cache/"
    --exclude="GPUCache/"
    --exclude="installed_listfile"
    --exclude="installed_true"
    --exclude="hypridle.conf.new"
    --exclude="hyprlock.conf.new"
)

# ------------------------------------------------------------------------------
# 5. Smart Pre-Scan & Diff Engine
# ------------------------------------------------------------------------------
MODIFIED_ITEMS=()
NEW_HOST_ITEMS=()
NEW_AUR_COUNT=0
NEW_PACMAN_COUNT=0

scan_status() {
    MODIFIED_ITEMS=()
    NEW_HOST_ITEMS=()

    for item in "${MANAGED_CONFIGS[@]}"; do
        local src_p="${CONFIG_SRC}/${item}"
        local dest_p="${CONFIG_DEST}/${item}"

        if [[ -e "$src_p" ]]; then
            if [[ ! -e "$dest_p" ]]; then
                NEW_HOST_ITEMS+=("$item")
            else
                if ! diff -r -q -x "*.bak" -x "*.new" -x "*.tmp" -x "__pycache__" -x "*.pyc" -x ".cache" -x "*.log" "$src_p" "$dest_p" >/dev/null 2>&1; then
                    MODIFIED_ITEMS+=("$item")
                fi
            fi
        fi
    done

    # Check shell dotfiles
    for sh_file in ".zshrc" ".bashrc"; do
        local src_sh="${USER_HOME}/${sh_file}"
        local dest_sh="${CONFIG_DEST}/${sh_file}"
        if [[ -f "$src_sh" && -f "$dest_sh" ]]; then
            if ! diff -q "$src_sh" "$dest_sh" >/dev/null 2>&1; then
                MODIFIED_ITEMS+=("$sh_file")
            fi
        fi
    done

    # Check .local/bin
    if [[ -d "$LOCAL_BIN_SRC" && -d "$LOCAL_BIN_DEST" ]]; then
        if ! diff -r -q -x "*.bak" "$LOCAL_BIN_SRC" "$LOCAL_BIN_DEST" >/dev/null 2>&1; then
            MODIFIED_ITEMS+=(".local/bin")
        fi
    fi

    # Check packages
    if command -v pacman >/dev/null 2>&1; then
        if [[ -f "${REPO_DIR}/packages-aur.txt" ]]; then
            mapfile -t _EXISTING_AUR < <(grep -vE '^\s*(#|$)' "${REPO_DIR}/packages-aur.txt")
            mapfile -t _HOST_AUR < <(pacman -Qqem 2>/dev/null | grep -vE -- '-debug$' || true)
            for p in "${_HOST_AUR[@]}"; do
                printf "%s\n" "${_EXISTING_AUR[@]}" | grep -qxF "$p" || NEW_AUR_COUNT=$((NEW_AUR_COUNT + 1))
            done
        fi
        if [[ -f "${REPO_DIR}/packages-pacman.txt" ]]; then
            mapfile -t _EXISTING_PAC < <(grep -vE '^\s*(#|$)' "${REPO_DIR}/packages-pacman.txt")
            mapfile -t _HOST_PAC < <(pacman -Qqen 2>/dev/null || true)
            for p in "${_HOST_PAC[@]}"; do
                case "$p" in
                    waybar|neovim|firefox|sddm|mpv|htop|mission-center|gnome-text-editor|nautilus|pyside6|python-pillow|otf-font-awesome|hyprpm|seahorse|speedtest-cli|tlp)
                        printf "%s\n" "${_EXISTING_PAC[@]}" | grep -qxF "$p" || NEW_PACMAN_COUNT=$((NEW_PACMAN_COUNT + 1))
                        ;;
                esac
            done
        fi
    fi
}

show_diffs() {
    step "Unified Diff Inspection (Host ~/.config vs Repository)"
    local diffs_found=0

    for item in "${MANAGED_CONFIGS[@]}"; do
        local src_p="${CONFIG_SRC}/${item}"
        local dest_p="${CONFIG_DEST}/${item}"

        if [[ -e "$src_p" && -e "$dest_p" ]]; then
            if ! diff -r -q -x "*.bak" -x "*.new" -x "*.tmp" -x "__pycache__" -x "*.pyc" -x ".cache" -x "*.log" "$dest_p" "$src_p" >/dev/null 2>&1; then
                printf "\n${C_BOLD}${C_YELLOW}--- Diff: %s ---${C_RESET}\n" "$item"
                diff -u -r -x "*.bak" -x "*.new" -x "*.tmp" -x "__pycache__" -x "*.pyc" -x ".cache" -x "*.log" "$dest_p" "$src_p" || true
                diffs_found=$((diffs_found + 1))
            fi
        fi
    done

    if [[ "$diffs_found" -eq 0 ]]; then
        info "All tracked configurations match repository. No file differences found."
    fi
}

# ------------------------------------------------------------------------------
# 6. Interactive Dashboard & Menu
# ------------------------------------------------------------------------------
scan_status

if [[ "$SHOW_DIFF_FIRST" -eq 1 ]]; then
    show_diffs
fi

if [[ "$CLI_MODE" -eq 0 && "$NON_INTERACTIVE" -eq 0 && -t 0 ]]; then
    clear 2>/dev/null || true
    printf "${C_CYAN}%s${C_RESET}\n" "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓"
    printf "${C_CYAN}┃${C_BOLD}${C_WHITE}           HYPR-DOTFILES SYNCHRONIZATION HUB                ${C_CYAN}┃${C_RESET}\n"
    printf "${C_CYAN}┃${C_RESET}       Smart & Accurate Dotfiles & Package Sync Engine      ${C_CYAN}┃${C_RESET}\n"
    printf "${C_CYAN}%s${C_RESET}\n\n" "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛"

    printf "  ${C_CYAN}-> Target User:${C_RESET}   %s (%s)\n" "$TARGET_USER" "$USER_HOME"
    printf "  ${C_CYAN}-> Repository:${C_RESET}    %s\n\n" "$REPO_DIR"

    printf "${C_BOLD}%s${C_RESET}\n" "System Status & Changes Detected:"
    if [[ "${#MODIFIED_ITEMS[@]}" -gt 0 ]]; then
        printf "  ${C_YELLOW}* Modified Configs:${C_RESET} %d item(s) (%s)\n" "${#MODIFIED_ITEMS[@]}" "${MODIFIED_ITEMS[*]}"
    else
        printf "  ${C_GREEN}* Dotfiles:${C_RESET}         All tracked configurations are in sync with repo\n"
    fi

    if [[ "${#NEW_HOST_ITEMS[@]}" -gt 0 ]]; then
        printf "  ${C_CYAN}* New Configs on Host:${C_RESET} %d item(s) (%s)\n" "${#NEW_HOST_ITEMS[@]}" "${NEW_HOST_ITEMS[*]}"
    fi

    if [[ "$NEW_AUR_COUNT" -gt 0 || "$NEW_PACMAN_COUNT" -gt 0 ]]; then
        printf "  ${C_YELLOW}* Packages:${C_RESET}         %d new AUR, %d new Pacman packages detected\n" "$NEW_AUR_COUNT" "$NEW_PACMAN_COUNT"
    else
        printf "  ${C_GREEN}* Packages:${C_RESET}         Tracked package lists are up to date\n"
    fi

    printf "\n${C_BOLD}%s${C_RESET}\n" "Select Sync Operation:"
    printf "  ${C_GREEN}[1] Full Sync${C_RESET}              (Dotfiles + Scripts + Packages + Plugins)\n"
    printf "  ${C_CYAN}[2] Selective Sync${C_RESET}         (Interactively choose components to sync)\n"
    printf "  ${C_YELLOW}[3] Inspect File Diffs${C_RESET}     (Preview line-by-line differences before sync)\n"
    printf "  ${C_MAGENTA}[4] Packages Only${C_RESET}          (Update packages-pacman.txt & packages-aur.txt)\n"
    printf "  ${C_BLUE}[5] Plugins Only${C_RESET}           (Update plugins-hyprpm.txt & plugins-vscode.txt)\n"
    printf "  ${C_WHITE}[6] Wallpapers${C_RESET}             (Sync ~/Pictures/Wallpapers to repo assets)\n"
    printf "  ${C_YELLOW}[7] Dry Run / Test${C_RESET}         (Simulate sync without modifying repository)\n"
    printf "  [q] Cancel & Exit\n\n"

    MENU_CHOICE="$(prompt_input "Enter your choice [1-7, q] (default: 1): " "1")"

    case "$MENU_CHOICE" in
        1)
            SYNC_DOTFILES=1; SYNC_LOCAL_BIN=1; SYNC_PACKAGES=1; SYNC_PLUGINS=1; DRY_RUN=0
            ;;
        2)
            SYNC_DOTFILES=1; SYNC_LOCAL_BIN=1; SYNC_PACKAGES=0; SYNC_PLUGINS=0; DRY_RUN=0
            printf "\n${C_BOLD}%s${C_RESET}\n" "Selective Component Synchronization:"
            SELECTED_COMPONENTS=()
            for comp in hypr quickshell kitty fish rofi fuzzel 43pr autostart sptlrx mpv neofetch .local/bin; do
                if prompt_confirm "  Sync '${comp}'?" "Y"; then
                    SELECTED_COMPONENTS+=("$comp")
                fi
            done
            prompt_confirm "  Sync package lists too?" "Y" && SYNC_PACKAGES=1 || SYNC_PACKAGES=0
            prompt_confirm "  Sync plugin lists too?" "Y" && SYNC_PLUGINS=1 || SYNC_PLUGINS=0
            ;;
        3)
            show_diffs
            printf "\n"
            if prompt_confirm "Proceed with full synchronization now?" "Y"; then
                SYNC_DOTFILES=1; SYNC_LOCAL_BIN=1; SYNC_PACKAGES=1; SYNC_PLUGINS=1; DRY_RUN=0
            else
                exit 0
            fi
            ;;
        4)
            SYNC_DOTFILES=0; SYNC_LOCAL_BIN=0; SYNC_PACKAGES=1; SYNC_PLUGINS=0; DRY_RUN=0
            ;;
        5)
            SYNC_DOTFILES=0; SYNC_LOCAL_BIN=0; SYNC_PACKAGES=0; SYNC_PLUGINS=1; DRY_RUN=0
            ;;
        6)
            SYNC_DOTFILES=0; SYNC_LOCAL_BIN=0; SYNC_PACKAGES=0; SYNC_PLUGINS=0; SYNC_WALLPAPERS=1; DRY_RUN=0
            ;;
        7)
            SYNC_DOTFILES=1; SYNC_LOCAL_BIN=1; SYNC_PACKAGES=1; SYNC_PLUGINS=1; DRY_RUN=1
            ;;
        q|Q)
            info "Aborted by user."
            exit 0
            ;;
        *)
            SYNC_DOTFILES=1; SYNC_LOCAL_BIN=1; SYNC_PACKAGES=1; SYNC_PLUGINS=1; DRY_RUN=0
            ;;
    esac
fi

header "hypr-dotfiles Sync Engine (Target: ${TARGET_USER})"
info "User Home Directory: ${USER_HOME}"
info "Repository Directory: ${REPO_DIR}"
if [[ "$DRY_RUN" -eq 1 ]]; then
    warn "DRY RUN MODE: No files will be modified."
fi

# Track synced components for semantic git commit
TOUCHED_AREAS=()

# ------------------------------------------------------------------------------
# 7. Synchronize Dotfiles (.config)
# ------------------------------------------------------------------------------
if [[ "$SYNC_DOTFILES" -eq 1 ]]; then
    header "1. Synchronizing Dotfiles (~/.config & shell)"

    if ! command -v rsync >/dev/null 2>&1; then
        error "rsync is required for synchronizing dotfiles. Please install rsync."
        exit 1
    fi

    RSYNC_OPTS=(-aL "${RSYNC_EXCLUDES[@]}")
    if [[ "$DELETE_REMOVED" -eq 1 ]]; then RSYNC_OPTS+=(--delete); fi
    if [[ "$VERBOSE" -eq 1 ]]; then RSYNC_OPTS+=(-v); fi
    if [[ "$DRY_RUN" -eq 1 ]]; then RSYNC_OPTS+=(--dry-run); fi

    SYNC_LIST=("${MANAGED_CONFIGS[@]}")
    if [[ "${#SELECTED_COMPONENTS[@]}" -gt 0 ]]; then
        SYNC_LIST=()
        for sel in "${SELECTED_COMPONENTS[@]}"; do
            [[ "$sel" != ".local/bin" ]] && SYNC_LIST+=("$sel")
        done
    fi

    for item in "${SYNC_LIST[@]}"; do
        src_path="${CONFIG_SRC}/${item}"
        dest_path="${CONFIG_DEST}/${item}"

        if [[ -d "$src_path" ]]; then
            info "Syncing directory: ~/.config/${item} -> .config/${item}"
            if [[ "$DRY_RUN" -eq 0 ]]; then
                mkdir -p "$dest_path"
            fi
            rsync "${RSYNC_OPTS[@]}" "${src_path}/" "${dest_path}/"
            TOUCHED_AREAS+=("$item")
        elif [[ -f "$src_path" ]]; then
            info "Syncing file: ~/.config/${item} -> .config/${item}"
            if [[ "$DRY_RUN" -eq 0 ]]; then
                cp -L "$src_path" "$dest_path"
            fi
            TOUCHED_AREAS+=("$item")
        else
            warn "Config item not found on host: ~/.config/${item} (skipping)"
        fi
    done

    # Synchronize shell configs
    if [[ "${#SELECTED_COMPONENTS[@]}" -eq 0 || " ${SELECTED_COMPONENTS[*]} " =~ " fish " || " ${SELECTED_COMPONENTS[*]} " =~ " zsh " ]]; then
        if [[ -f "${USER_HOME}/.zshrc" ]]; then
            info "Syncing ~/.zshrc -> .config/.zshrc"
            if [[ "$DRY_RUN" -eq 0 ]]; then
                cp -L "${USER_HOME}/.zshrc" "${CONFIG_DEST}/.zshrc"
            fi
            TOUCHED_AREAS+=("zsh")
        fi

        if [[ -f "${USER_HOME}/.bashrc" ]]; then
            info "Syncing ~/.bashrc -> .config/.bashrc"
            if [[ "$DRY_RUN" -eq 0 ]]; then
                cp -L "${USER_HOME}/.bashrc" "${CONFIG_DEST}/.bashrc"
            fi
            TOUCHED_AREAS+=("bash")
        fi
    fi

    # Fix script permissions
    if [[ "$DRY_RUN" -eq 0 ]]; then
        find "${CONFIG_DEST}/hypr" "${CONFIG_DEST}/quickshell" "${CONFIG_DEST}/43pr" \
            -type f \( -name "*.sh" -o -name "*.py" \) -exec chmod +x {} + 2>/dev/null || true
    fi

    success "Dotfiles synchronization finished."
else
    info "Skipping dotfiles synchronization."
fi

# ------------------------------------------------------------------------------
# 8. Synchronize .local/bin Scripts
# ------------------------------------------------------------------------------
if [[ "$SYNC_LOCAL_BIN" -eq 1 ]]; then
    if [[ "${#SELECTED_COMPONENTS[@]}" -eq 0 || " ${SELECTED_COMPONENTS[*]} " =~ " .local/bin " ]]; then
        header "2. Synchronizing Executable Scripts (~/.local/bin)"
        
        if [[ -d "$LOCAL_BIN_SRC" ]]; then
            mkdir -p "$LOCAL_BIN_DEST"
            
            # Sync key helper scripts
            for helper in "quickshell-lyricbar"; do
                if [[ -f "${LOCAL_BIN_SRC}/${helper}" ]]; then
                    info "Syncing script: ~/.local/bin/${helper} -> .local/bin/${helper}"
                    if [[ "$DRY_RUN" -eq 0 ]]; then
                        cp -L "${LOCAL_BIN_SRC}/${helper}" "${LOCAL_BIN_DEST}/${helper}"
                        chmod +x "${LOCAL_BIN_DEST}/${helper}"
                    fi
                    TOUCHED_AREAS+=("scripts")
                fi
            done
            success "Script synchronization finished."
        fi
    fi
fi

# ------------------------------------------------------------------------------
# 9. Synchronize Packages (pacman & AUR)
# ------------------------------------------------------------------------------
if [[ "$SYNC_PACKAGES" -eq 1 ]]; then
    header "3. Synchronizing Packages (pacman & AUR)"

    if ! command -v pacman >/dev/null 2>&1; then
        warn "pacman not found on this system. Skipping package synchronization."
    else
        PACMAN_FILE="${REPO_DIR}/packages-pacman.txt"
        AUR_FILE="${REPO_DIR}/packages-aur.txt"

        # --- A. AUR Packages Synchronization ---
        info "Inspecting explicitly installed AUR packages..."
        mapfile -t CURRENT_AUR < <(pacman -Qqem 2>/dev/null | grep -vE -- '-debug$' | sort)

        EXISTING_AUR=()
        if [[ -f "$AUR_FILE" ]]; then
            mapfile -t EXISTING_AUR < <(grep -vE '^\s*(#|$)' "$AUR_FILE" | sort)
        fi

        NEW_AUR=()
        for pkg in "${CURRENT_AUR[@]}"; do
            if ! printf "%s\n" "${EXISTING_AUR[@]}" | grep -qxF "$pkg"; then
                NEW_AUR+=("$pkg")
            fi
        done

        if [[ "${#NEW_AUR[@]}" -gt 0 ]]; then
            info "Found ${#NEW_AUR[@]} new AUR packages installed locally:"
            for pkg in "${NEW_AUR[@]}"; do
                printf "  ${C_GREEN}+${C_RESET} %s\n" "$pkg"
            done

            SHOULD_APPEND_AUR=1
            if [[ "$CLI_MODE" -eq 0 && "$NON_INTERACTIVE" -eq 0 ]]; then
                prompt_confirm "Append these new AUR packages to packages-aur.txt?" "Y" || SHOULD_APPEND_AUR=0
            fi

            if [[ "$SHOULD_APPEND_AUR" -eq 1 ]]; then
                if [[ "$DRY_RUN" -eq 0 ]]; then
                    {
                        printf "\n# Automatically synced from %s on %s\n" "$TARGET_USER" "$(date +%Y-%m-%d)"
                        for pkg in "${NEW_AUR[@]}"; do
                            printf "%s\n" "$pkg"
                        done
                    } >> "$AUR_FILE"
                    success "Added new AUR packages to packages-aur.txt."
                    TOUCHED_AREAS+=("aur-packages")
                else
                    info "[DRY-RUN] Would append ${#NEW_AUR[@]} packages to packages-aur.txt."
                fi
            fi
        else
            success "AUR packages list is already up to date (${#EXISTING_AUR[@]} tracked)."
        fi

        # --- B. Official Pacman Packages Synchronization ---
        info "Inspecting official repository packages..."
        mapfile -t CURRENT_PACMAN < <(pacman -Qqen 2>/dev/null | sort)

        EXISTING_PACMAN=()
        if [[ -f "$PACMAN_FILE" ]]; then
            mapfile -t EXISTING_PACMAN < <(grep -vE '^\s*(#|$)' "$PACMAN_FILE" | sort)
        fi

        # Identify newly installed desktop/system packages
        NEW_PACMAN=()
        for pkg in "${CURRENT_PACMAN[@]}"; do
            if ! printf "%s\n" "${EXISTING_PACMAN[@]}" | grep -qxF "$pkg"; then
                if [[ "$ALL_PACKAGES" -eq 1 ]]; then
                    NEW_PACMAN+=("$pkg")
                else
                    case "$pkg" in
                        waybar|neovim|firefox|sddm|mpv|htop|mission-center|gnome-text-editor|nautilus|pyside6|python-pillow|otf-font-awesome|hyprpm|seahorse|speedtest-cli|tlp|auto-cpufreq)
                            NEW_PACMAN+=("$pkg")
                            ;;
                    esac
                fi
            fi
        done

        if [[ "${#NEW_PACMAN[@]}" -gt 0 ]]; then
            info "Found ${#NEW_PACMAN[@]} new relevant official packages installed locally:"
            for pkg in "${NEW_PACMAN[@]}"; do
                printf "  ${C_GREEN}+${C_RESET} %s\n" "$pkg"
            done

            SHOULD_APPEND_PACMAN=1
            if [[ "$CLI_MODE" -eq 0 && "$NON_INTERACTIVE" -eq 0 ]]; then
                prompt_confirm "Append these new official packages to packages-pacman.txt?" "Y" || SHOULD_APPEND_PACMAN=0
            fi

            if [[ "$SHOULD_APPEND_PACMAN" -eq 1 ]]; then
                if [[ "$DRY_RUN" -eq 0 ]]; then
                    {
                        printf "\n# Automatically synced from %s on %s\n" "$TARGET_USER" "$(date +%Y-%m-%d)"
                        for pkg in "${NEW_PACMAN[@]}"; do
                            printf "%s\n" "$pkg"
                        done
                    } >> "$PACMAN_FILE"
                    success "Added new official packages to packages-pacman.txt."
                    TOUCHED_AREAS+=("pacman-packages")
                else
                    info "[DRY-RUN] Would append ${#NEW_PACMAN[@]} packages to packages-pacman.txt."
                fi
            fi
        else
            success "Official packages list is up to date (${#EXISTING_PACMAN[@]} tracked)."
        fi
    fi
else
    info "Skipping package synchronization."
fi

# ------------------------------------------------------------------------------
# 10. Synchronize Plugins (hyprpm & VS Code)
# ------------------------------------------------------------------------------
if [[ "$SYNC_PLUGINS" -eq 1 ]]; then
    header "4. Synchronizing Plugins (hyprpm & VS Code)"

    # --- A. Hyprland Plugins (hyprpm) ---
    HYPRPM_FILE="${REPO_DIR}/plugins-hyprpm.txt"
    HYPRPM_CACHE="/var/cache/hyprpm/${TARGET_USER}"
    PLUGINS_FOUND=0

    info "Inspecting Hyprland plugins (hyprpm)..."
    TEMP_HYPRPM="$(mktemp)"

    cat << 'EOF' > "$TEMP_HYPRPM"
# ==============================================================================
# Hyprland Plugins (managed via hyprpm)
# Install & Enable:
#   hyprpm add <repository_url>
#   hyprpm enable <plugin_name>
# ==============================================================================
EOF

    if [[ -d "$HYPRPM_CACHE" ]]; then
        for repo_dir in "$HYPRPM_CACHE"/*; do
            if [[ -d "$repo_dir" && -f "${repo_dir}/state.toml" ]]; then
                repo_url="$(sed -nE "s/^[[:space:]]*url[[:space:]]*=[[:space:]]*['\"]([^'\"]+)['\"].*/\1/p" "${repo_dir}/state.toml" | head -n1)"
                repo_name="$(sed -nE "s/^[[:space:]]*name[[:space:]]*=[[:space:]]*['\"]([^'\"]+)['\"].*/\1/p" "${repo_dir}/state.toml" | head -n1)"
                
                while IFS= read -r line; do
                    if [[ "$line" =~ ^\[(.*)\]$ ]]; then
                        section="${BASH_REMATCH[1]}"
                        if [[ "$section" != "repository" && "$section" != "state" ]]; then
                            plugin_name="$section"
                            printf "%s %s enabled\n" "${repo_url:-$repo_name}" "$plugin_name" >> "$TEMP_HYPRPM"
                            printf "  ${C_GREEN}[+]${C_RESET} Hyprland plugin: %s (%s)\n" "$plugin_name" "${repo_url:-$repo_name}"
                            PLUGINS_FOUND=$((PLUGINS_FOUND + 1))
                        fi
                    fi
                done < "${repo_dir}/state.toml"
            fi
        done
    fi

    if [[ "$PLUGINS_FOUND" -gt 0 ]]; then
        if [[ "$DRY_RUN" -eq 0 ]]; then
            mv "$TEMP_HYPRPM" "$HYPRPM_FILE"
            success "Recorded ${PLUGINS_FOUND} Hyprland plugin(s) to plugins-hyprpm.txt."
            TOUCHED_AREAS+=("hyprpm")
        else
            rm -f "$TEMP_HYPRPM"
            info "[DRY-RUN] Would update plugins-hyprpm.txt with ${PLUGINS_FOUND} plugin(s)."
        fi
    else
        rm -f "$TEMP_HYPRPM"
        info "No active hyprpm plugins detected in cache."
    fi

    # --- B. Visual Studio Code Extensions ---
    VSCODE_FILE="${REPO_DIR}/plugins-vscode.txt"
    VSCODE_CMD=""

    if command -v code >/dev/null 2>&1; then
        VSCODE_CMD="code"
    elif command -v code-oss >/dev/null 2>&1; then
        VSCODE_CMD="code-oss"
    fi

    if [[ -n "$VSCODE_CMD" ]]; then
        info "Inspecting VS Code extensions via ${VSCODE_CMD}..."
        
        EXTENSIONS=()
        if [[ "${EUID}" -eq 0 && "$TARGET_USER" != "root" ]]; then
            mapfile -t EXTENSIONS < <(su - "$TARGET_USER" -c "$VSCODE_CMD --list-extensions 2>/dev/null" | sort || true)
        else
            mapfile -t EXTENSIONS < <("$VSCODE_CMD" --list-extensions 2>/dev/null | sort || true)
        fi

        if [[ "${#EXTENSIONS[@]}" -gt 0 ]]; then
            info "Found ${#EXTENSIONS[@]} VS Code extensions installed."
            if [[ "$DRY_RUN" -eq 0 ]]; then
                {
                    cat << 'EOF'
# ==============================================================================
# Visual Studio Code Extensions
# Install via: code --install-extension <extension_id>
# ==============================================================================
EOF
                    for ext in "${EXTENSIONS[@]}"; do
                        printf "%s\n" "$ext"
                    done
                } > "$VSCODE_FILE"
                success "Saved ${#EXTENSIONS[@]} VS Code extensions to plugins-vscode.txt."
                TOUCHED_AREAS+=("vscode-plugins")
            else
                info "[DRY-RUN] Would save ${#EXTENSIONS[@]} VS Code extensions to plugins-vscode.txt."
            fi
        fi
    fi

    success "Plugin synchronization finished."
else
    info "Skipping plugin synchronization."
fi

# ------------------------------------------------------------------------------
# 11. Optional Wallpapers Synchronization
# ------------------------------------------------------------------------------
if [[ "$SYNC_WALLPAPERS" -eq 1 ]]; then
    header "5. Synchronizing Wallpapers"
    WP_SRC="${USER_HOME}/Pictures/Wallpapers"
    WP_DEST="${REPO_DIR}/assets/wallpapers"
    if [[ -d "$WP_SRC" ]]; then
        info "Syncing wallpapers from ${WP_SRC} to ${WP_DEST}..."
        if [[ "$DRY_RUN" -eq 0 ]]; then
            mkdir -p "$WP_DEST"
            rsync -a --update "${WP_SRC}/" "${WP_DEST}/"
            success "Wallpapers synchronized."
            TOUCHED_AREAS+=("wallpapers")
        fi
    fi
fi

# ------------------------------------------------------------------------------
# 12. Permissions Restoration
# ------------------------------------------------------------------------------
if [[ "$DRY_RUN" -eq 0 ]]; then
    if [[ "${EUID}" -eq 0 && "$TARGET_USER" != "root" ]]; then
        chown -R "${TARGET_USER}:${TARGET_USER}" "$REPO_DIR" 2>/dev/null || true
    fi
    find "${CONFIG_DEST}/hypr" "${CONFIG_DEST}/quickshell" "${CONFIG_DEST}/43pr" \
        -type f \( -name "*.sh" -o -name "*.py" \) -exec chmod +x {} + 2>/dev/null || true
    chmod +x "${REPO_DIR}/install.sh" "${REPO_DIR}/sync-dotfiles.sh" 2>/dev/null || true
    chmod +x "${REPO_DIR}/.local/bin"/* 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# 13. Git Status Review & Semantic Commit
# ------------------------------------------------------------------------------
header "6. Git Status & Review"

if command -v git >/dev/null 2>&1 && [[ -d "${REPO_DIR}/.git" ]]; then
    CHANGES="$(git -C "$REPO_DIR" status --short)"
    if [[ -z "$CHANGES" ]]; then
        success "Repository working tree is clean. Everything is fully synchronized."
    else
        info "Modified / Added files in repository:"
        git -C "$REPO_DIR" status --short
        
        # Build smart semantic commit message if not explicitly given
        if [[ -z "$COMMIT_MSG" ]]; then
            # Deduplicate touched areas
            mapfile -t UNIQUE_AREAS < <(printf "%s\n" "${TOUCHED_AREAS[@]}" | sort -u | grep -v '^$' || true)
            if [[ "${#UNIQUE_AREAS[@]}" -gt 0 ]]; then
                AREAS_STR="$(IFS=,; echo "${UNIQUE_AREAS[*]}")"
                COMMIT_MSG="sync(${AREAS_STR}): automated dotfiles, packages, and plugins update"
            else
                COMMIT_MSG="sync: automated dotfiles and configurations update"
            fi
        fi

        if [[ "$AUTO_COMMIT" -eq 1 && "$DRY_RUN" -eq 0 ]]; then
            info "Auto-committing changes to git..."
            git -C "$REPO_DIR" add -A
            git -C "$REPO_DIR" commit -m "$COMMIT_MSG"
            success "Committed successfully: '${COMMIT_MSG}'"
        elif [[ "$CLI_MODE" -eq 0 && "$NON_INTERACTIVE" -eq 0 && "$DRY_RUN" -eq 0 ]]; then
            printf "\n"
            if prompt_confirm "Would you like to commit these changes to git now?" "Y"; then
                CUSTOM_MSG="$(prompt_input "Enter commit message (press enter for default): " "$COMMIT_MSG")"
                git -C "$REPO_DIR" add -A
                git -C "$REPO_DIR" commit -m "$CUSTOM_MSG"
                success "Committed changes to git with message: '${CUSTOM_MSG}'"
            else
                printf "\n${C_BOLD}%s${C_RESET}\n" "To review and commit manually later:"
                printf "  ${C_CYAN}git diff${C_RESET}\n"
                printf "  ${C_CYAN}git add -A && git commit -m \"${COMMIT_MSG}\"${C_RESET}\n\n"
            fi
        else
            printf "\n${C_BOLD}%s${C_RESET}\n" "To review and commit your synchronized dotfiles:"
            printf "  ${C_CYAN}git diff${C_RESET}\n"
            printf "  ${C_CYAN}git add -A && git commit -m \"${COMMIT_MSG}\"${C_RESET}\n\n"
        fi
    fi
else
    warn "Not a git repository or git command missing."
fi

header "Sync Process Completed Successfully!"
