#!/bin/bash

# Schloprice - Enhanced Auto Rice Bootstrapping Script
# License: GNU GPLv3

### VARIABLES ###
DOTFILES_REPO="https://github.com/schlopshow/progs.git"
PROGS_FILE="https://raw.githubusercontent.com/schlopshow/schloprice/refs/heads/main/progs/full-progs.csv"
AUR_HELPER="yay"
REPO_BRANCH="main"
USER_NAME=""
SKIP_PROMPTS=false
VERBOSE=false
LOG_FILE="/tmp/schloprice-install.log"
CONTINUE_ON_ERROR=false
export TERM=ansi

### UTILITY FUNCTIONS ###
log() {
    local level="$1"; shift; local message="$*"; local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    case "$level" in
        "ERROR") echo -e "\033[31m[ERROR]\033[0m $message" >&2; echo "[$timestamp] [ERROR] $message" >> "$LOG_FILE" ;;
        "WARN") echo -e "\033[33m[WARN]\033[0m $message" >&2; echo "[$timestamp] [WARN] $message" >> "$LOG_FILE" ;;
        "INFO") echo -e "\033[32m[INFO]\033[0m $message"; echo "[$timestamp] [INFO] $message" >> "$LOG_FILE" ;;
        "DEBUG") [ "$VERBOSE" = true ] && echo -e "\033[36m[DEBUG]\033[0m $message"; echo "[$timestamp] [DEBUG] $message" >> "$LOG_FILE" ;;
    esac
}

error() {
    log "ERROR" "$1"
    [ "$CONTINUE_ON_ERROR" = true ] && { log "WARN" "Continuing despite error"; return 1; }
    [ "$SKIP_PROMPTS" = false ] && whiptail --title "Installation Error" --yesno "An error occurred: $1\n\nContinue anyway?" 12 70 && { CONTINUE_ON_ERROR=true; return 1; }
    exit 1
}

show_help() {
    cat << EOF
$0 - Automated Linux Desktop Setup

USAGE: $0 [OPTIONS]

OPTIONS:
    -r, --repo URL          Dotfiles repository URL
    -p, --progs FILE/URL    Programs CSV file path or URL
    -b, --branch NAME       Repository branch (default: main)
    -u, --user USERNAME     Username (skip prompt)
    -s, --skip-prompts      Skip all prompts
    -v, --verbose           Enable verbose output
    -c, --continue-on-error Continue on errors
    -h, --help              Show help

EXAMPLES:
    $0 -r https://github.com/user/dotfiles.git
    $0 --skip-prompts --user myuser

PROGS.CSV FORMAT:
    tag,program,description
    Tags: (empty)=pacman, A=AUR, G=git, P=pip
EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -r|--repo) DOTFILES_REPO="$2"; shift 2 ;;
            -p|--progs) PROGS_FILE="$2"; shift 2 ;;
            -b|--branch) REPO_BRANCH="$2"; shift 2 ;;
            -u|--user) USER_NAME="$2"; shift 2 ;;
            -s|--skip-prompts) SKIP_PROMPTS=true; shift ;;
            -v|--verbose) VERBOSE=true; shift ;;
            -c|--continue-on-error) CONTINUE_ON_ERROR=true; shift ;;
            -h|--help) show_help; exit 0 ;;
            *) error "Unknown option: $1. Use -h for help." ;;
        esac
    done
}

check_requirements() {
    log "INFO" "Checking system requirements..."
    [[ $EUID -ne 0 ]] && error "This script must be run as root"
    ! command -v pacman >/dev/null 2>&1 && error "This script requires an Arch-based Linux distribution"
    ! ping -c 1 archlinux.org >/dev/null 2>&1 && error "No internet connection detected"
    log "INFO" "System requirements satisfied"
}

validate_repository() {
    log "INFO" "Validating repository: $1"
    ! git ls-remote --heads "$1" >/dev/null 2>&1 && error "Cannot access repository: $1"
    if ! git ls-remote --heads "$1" | grep -q "refs/heads/$2"; then
        log "WARN" "Branch '$2' not found, using default branch"
        REPO_BRANCH=""
    fi
    log "INFO" "Repository validation successful"
}

install_pkg() {
    log "DEBUG" "Installing package: $1"
    pacman -Qq "$1" >/dev/null 2>&1 && { log "DEBUG" "$1 already installed"; return 0; }
    pacman --noconfirm --needed -S "$1" >/dev/null 2>&1 || { log "ERROR" "Failed to install: $1"; return 1; }
}

### INTERACTIVE FUNCTIONS ###
welcome_msg() {
    [ "$SKIP_PROMPTS" = true ] && return 0
    whiptail --title "Welcome!" --msgbox "Welcome to Schloprice!\n\nRepository: $DOTFILES_REPO\nBranch: $REPO_BRANCH\nAUR Helper: yay" 14 70
    whiptail --title "Important Note!" --yes-button "All ready!" --no-button "Cancel" --yesno "Ensure your system has current pacman updates.\n\nContinue?" 10 70 || exit 0
}

get_user_and_pass() {
    if [ -n "$USER_NAME" ]; then
        username="$USER_NAME"
        log "INFO" "Using provided username: $USER_NAME"
    else
        username=$(whiptail --inputbox "Enter username:" 10 60 3>&1 1>&2 2>&3 3>&1) || exit 0
        while ! echo "$username" | grep -q "^[a-z_][a-z0-9_-]*$"; do
            username=$(whiptail --nocancel --inputbox "Invalid username. Use only lowercase letters, numbers, - or _.\n\nEnter username:" 10 60 3>&1 1>&2 2>&3 3>&1)
        done
    fi
    if [ "$SKIP_PROMPTS" = true ]; then
        user_password=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-16)
        log "INFO" "Generated random password (saved to $LOG_FILE)"
        echo "Generated password for $username: $user_password" >> "$LOG_FILE"
    else
        user_password=$(whiptail --nocancel --passwordbox "Enter password for $username:" 10 60 3>&1 1>&2 2>&3 3>&1)
        local pass2=$(whiptail --nocancel --passwordbox "Retype password:" 10 60 3>&1 1>&2 2>&3 3>&1)
        while [ "$user_password" != "$pass2" ]; do
            user_password=$(whiptail --nocancel --passwordbox "Passwords don't match. Enter again:" 10 60 3>&1 1>&2 2>&3 3>&1)
            pass2=$(whiptail --nocancel --passwordbox "Retype password:" 10 60 3>&1 1>&2 2>&3 3>&1)
        done
    fi
}

user_check() {
    if id -u "$username" >/dev/null 2>&1; then
        [ "$SKIP_PROMPTS" = true ] && { log "WARN" "User $username exists, will overwrite settings"; return 0; }
        whiptail --title "WARNING" --yes-button "CONTINUE" --no-button "Cancel" --yesno "User \`$username\` exists. This will OVERWRITE conflicting settings.\n\nContinue?" 12 70 || exit 0
    fi
}

pre_install_msg() {
    [ "$SKIP_PROMPTS" = true ] && { log "INFO" "Starting automated installation..."; return 0; }
    whiptail --title "Ready!" --yes-button "Let's go!" --no-button "Cancel" --yesno "Ready to install.\n\nRepo: $DOTFILES_REPO\nUser: $username\nAUR: yay\n\nContinue?" 14 70 || exit 0
}

### INSTALLATION FUNCTIONS ###
add_user_and_pass() {
    log "INFO" "Adding user: $username"
    whiptail --infobox "Adding user \"$username\"..." 7 50
    useradd -m -g wheel -s /bin/zsh "$username" >/dev/null 2>&1 || { usermod -a -G wheel "$username"; mkdir -p "/home/$username"; chown "$username:wheel" "/home/$username"; }
    export repo_dir="/home/$username/.local/src"
    mkdir -p "$repo_dir" && chown -R "$username:wheel" "$(dirname "$repo_dir")"
    echo "$username:$user_password" | chpasswd && unset user_password
    log "INFO" "User $username created successfully"
}

refresh_keys() {
    log "INFO" "Refreshing package keys..."
    case "$(readlink -f /sbin/init)" in
    *systemd*) whiptail --infobox "Refreshing Arch Keyring..." 7 40; install_pkg archlinux-keyring || error "Failed to refresh keyring" ;;
    *) whiptail --infobox "Enabling Arch repositories..." 7 40
       install_pkg artix-keyring || error "Failed to install Artix keyring"
       install_pkg artix-archlinux-support || error "Failed to install Arch support"
       ! grep -q "^\[extra\]" /etc/pacman.conf && echo -e "\n[extra]\nInclude = /etc/pacman.d/mirrorlist-arch" >> /etc/pacman.conf
       pacman -Sy --noconfirm >/dev/null 2>&1; pacman-key --populate archlinux >/dev/null 2>&1 ;;
    esac
}

install_yay() {
    command -v yay >/dev/null 2>&1 && return 0
    whiptail --infobox "Installing yay AUR helper..." 7 50
    yay_dir="/tmp/yay-install"
    rm -rf "$yay_dir"
    mkdir -p "$yay_dir"
    git clone --depth 1 "https://aur.archlinux.org/yay.git" "$yay_dir"
    cd "$yay_dir"
    chown -R "$username:wheel" "$yay_dir"
    sudo -u "$username" makepkg -si --noconfirm
    cd /
    rm -rf "$yay_dir"
}

main_install() {
    log "INFO" "Installing: $1 ($current_package of $total_packages)"
    whiptail --title "Progress" --infobox "Installing \`$1\` ($current_package of $total_packages)\\n$2" 8 70
    install_pkg "$1" || error "Failed to install: $1"
}

git_make_install() {
    local progname="${1##*/}"; progname="${progname%.git}"; local dir="$repo_dir/$progname"
    log "INFO" "Installing from git: $progname ($current_package of $total_packages)"
    whiptail --title "Progress" --infobox "Installing \`$progname\` via git\\n$2" 8 70
    sudo -u "$username" git -C "$repo_dir" clone --depth 1 -q "$1" "$dir" 2>/dev/null || { cd "$dir" && sudo -u "$username" git pull --force origin master >/dev/null 2>&1; } || error "Failed to clone: $1"
    cd "$dir" && make >/dev/null 2>&1 && make install >/dev/null 2>&1 || error "Failed to compile/install: $progname"
}

aur_install() {
    log "INFO" "Installing AUR: $1 ($current_package of $total_packages)"
    whiptail --title "Progress" --infobox "Installing \`$1\` ($current_package of $total_packages) from the AUR\\n$2" 9 70

    # Check if already installed
    echo "$aur_installed" | grep -q "^$1$" && return 0

    # Install using yay as the user
    sudo -u "$username" yay -S --noconfirm "$1" >/dev/null 2>&1 || error "Failed to install AUR package: $1"
}

pip_install() {
    log "INFO" "Installing Python: $1 ($current_package of $total_packages)"
    whiptail --title "Progress" --infobox "Installing Python \`$1\`\\n$2" 8 70
    command -v pip >/dev/null 2>&1 || install_pkg python-pip || error "Failed to install pip"
    pip install --break-system-packages "$1" >/dev/null 2>&1 || error "Failed to install Python: $1"
}

detect_progs_file() {
    [ -n "$PROGS_FILE" ] && return 0
    local temp_repo_dir=$(mktemp -d)
    local clone_args="--depth 1 -q"; [ -n "$REPO_BRANCH" ] && clone_args="$clone_args -b $REPO_BRANCH"
    if git clone $clone_args "$DOTFILES_REPO" "$temp_repo_dir" >/dev/null 2>&1 && [ -f "$temp_repo_dir/progs.csv" ]; then
        PROGS_FILE="$temp_repo_dir/progs.csv"; log "INFO" "Found progs.csv in repository"
    else
        log "WARN" "No progs.csv found, skipping software installation"; PROGS_FILE=""
    fi
    [ "$PROGS_FILE" != "$temp_repo_dir/progs.csv" ] && rm -rf "$temp_repo_dir"
}

installation_loop() {
    detect_progs_file; [ -z "$PROGS_FILE" ] && { log "WARN" "No programs file, skipping software installation"; return 0; }
    [[ "$PROGS_FILE" =~ ^https?:// ]] && curl -Ls "$PROGS_FILE" | sed '/^#/d' > /tmp/progs.csv || cp "$PROGS_FILE" /tmp/progs.csv
    sed -i '/^#/d; /^$/d' /tmp/progs.csv
    total_packages=$(wc -l < /tmp/progs.csv); aur_installed=$(pacman -Qqm 2>/dev/null || echo ""); current_package=0
    log "INFO" "Installing $total_packages packages..."
    while IFS=, read -r tag program comment; do
        current_package=$((current_package + 1)); comment="$(echo "$comment" | sed -E 's/(^"|"$)//g')"
        case "$tag" in
            "A") aur_install "$program" "$comment" ;;
            "G") git_make_install "$program" "$comment" ;;
            "P") pip_install "$program" "$comment" ;;
            *) main_install "$program" "$comment" ;;
        esac
    done < /tmp/progs.csv
    log "INFO" "Package installation completed"
}

put_git_repo() {
    log "INFO" "Installing configuration files..."; whiptail --infobox "Installing config files..." 7 60
    local temp_dir=$(mktemp -d); [ ! -d "$2" ] && mkdir -p "$2"; chown "$username:wheel" "$temp_dir" "$2"
    local clone_args="--depth 1 -q --recursive"; [ -n "$3" ] && clone_args="$clone_args -b $3"
    sudo -u "$username" git clone $clone_args "$1" "$temp_dir" 2>/dev/null || error "Failed to clone: $1"
    rm -rf "$temp_dir/.git" "$temp_dir/.gitignore" "$temp_dir/README.md" "$temp_dir/LICENSE" "$temp_dir/FUNDING.yml" "$temp_dir/progs.csv"
    sudo -u "$username" cp -rfT "$temp_dir" "$2" && rm -rf "$temp_dir"
    log "INFO" "Configuration files installed"
}

install_dwm_suite() {
    log "INFO" "Installing DWM suite (dwm, dmenu, dwmblocks, st)..."
    local dwm_projects=("dwm" "dmenu" "dwmblocks" "st")
    local user_home="/home/$username"
    local src_dir="$user_home/.local/src"

    # Ensure X11 development packages are installed
    whiptail --infobox "Installing X11 development packages..." 7 60
    for pkg in libx11 libxft libxinerama; do
        install_pkg "$pkg" || error "Failed to install $pkg"
    done

    for project in "${dwm_projects[@]}"; do
        log "INFO" "Installing $project..."
        whiptail --infobox "Compiling and installing $project..." 7 60

        local project_dir="$src_dir/$project"
        if [ -d "$project_dir" ]; then
            log "INFO" "Found $project in $project_dir, compiling..."
            cd "$project_dir" || error "Cannot access $project_dir"

            # Clean any previous builds
            sudo -u "$username" make clean >/dev/null 2>&1 || true

            # Compile the project
            sudo -u "$username" make >/dev/null 2>&1 || error "Failed to compile $project"

            # Install the project (requires root)
            make install >/dev/null 2>&1 || error "Failed to install $project"

            log "INFO" "$project compiled and installed successfully"
        else
            log "WARN" "$project directory not found at $project_dir, skipping..."
        fi
    done

    log "INFO" "DWM suite installation completed"
}

setup_shell() {
    log "INFO" "Setting up shell..."
    chsh -s /bin/zsh "$username" >/dev/null 2>&1
    sudo -u "$username" mkdir -p "/home/$username/.cache/zsh/" "/home/$username/.config" "/home/$username/.local/bin"
    command -v dash >/dev/null 2>&1 && ln -sfT /bin/dash /bin/sh >/dev/null 2>&1
}

system_optimizations() {
    log "INFO" "Applying optimizations..."
    ! grep -q "ILoveCandy" /etc/pacman.conf && sed -i "/#VerbosePkgLists/a ILoveCandy" /etc/pacman.conf
    sed -Ei "s/^#(ParallelDownloads).*/\1 = 5/;/^#Color$/s/#//" /etc/pacman.conf
    sed -i "s/-j2/-j$(nproc)/;/^#MAKEFLAGS/s/^#//" /etc/makepkg.conf
    rmmod pcspkr 2>/dev/null || true; echo "blacklist pcspkr" > /etc/modprobe.d/nobeep.conf
}

setup_permissions() {
    log "INFO" "Setting up permissions..."
    echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/00-wheel-can-sudo
    cat > /etc/sudoers.d/01-cmds-without-password << 'EOF'
%wheel ALL=(ALL:ALL) NOPASSWD: /usr/bin/shutdown,/usr/bin/reboot,/usr/bin/systemctl suspend,/usr/bin/mount,/usr/bin/umount,/usr/bin/pacman -Syu,/usr/bin/pacman -Syyu,/usr/bin/pacman -Syyu --noconfirm,/usr/bin/loadkeys,/usr/bin/yay
EOF
    echo "Defaults editor=/usr/bin/nvim" > /etc/sudoers.d/02-visudo-editor
    mkdir -p /etc/sysctl.d; echo "kernel.dmesg_restrict = 0" > /etc/sysctl.d/dmesg.conf
}

finalize() {
    log "INFO" "Finalizing..."; rm -f /etc/sudoers.d/schloprice-temp
    cat > "/home/$username/installation-report.txt" << EOF
Schloprice Installation completed: $(date)
Repository: $DOTFILES_REPO | Branch: $REPO_BRANCH | User: $username
AUR Helper: yay | Log: $LOG_FILE

DWM Suite installed:
- dwm (window manager)
- dmenu (application launcher)
- dwmblocks (status bar)
- st (terminal)

To start: Log in as '$username' and run 'startx'
EOF
    chown "$username:wheel" "/home/$username/installation-report.txt"
    [ "$SKIP_PROMPTS" = false ] && whiptail --title "Complete!" --msgbox "Installation completed!\n\nAUR Helper: yay\nDWM suite has been compiled and installed.\nLog in as '$username' and run 'startx'." 12 70
    log "INFO" "Installation completed successfully!"
}

cleanup() { rm -f /tmp/progs.csv /etc/sudoers.d/schloprice-temp /tmp/progs_validation.csv; }
trap cleanup EXIT

### MAIN ###
main() {
    echo "Starting Schloprice..."; echo "Log: $LOG_FILE"
    parse_arguments "$@"; check_requirements; validate_repository "$DOTFILES_REPO" "$REPO_BRANCH"
    install_pkg libnewt || error "Failed to install whiptail"
    welcome_msg; get_user_and_pass; user_check; pre_install_msg
    log "INFO" "Starting installation..."; refresh_keys
    for pkg in curl ca-certificates base-devel git zsh; do install_pkg "$pkg" || error "Failed to install: $pkg"; done

    add_user_and_pass; echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/schloprice-temp

    # Install yay AUR helper
    install_yay

    installation_loop; setup_shell; put_git_repo "$DOTFILES_REPO" "/home/$username" "$REPO_BRANCH"
    install_dwm_suite; system_optimizations; setup_permissions; finalize
    log "INFO" "All steps completed!"
}

main "$@"
