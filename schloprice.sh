#!/bin/bash

# Schloprice - Enhanced Auto Rice Bootstrapping Script
# License: GNU GPLv3

### VARIABLES ###
DOTFILES_REPO="https://github.com/schlopshow/progs.git"
PROGS_FILE="https://raw.githubusercontent.com/LukeSmithxyz/LARBS/master/static/progs.csv"
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
        "ERROR") echo -e "\033[31m[ERROR]\033[0m $message" >&2 ;;
        "WARN") echo -e "\033[33m[WARN]\033[0m $message" >&2 ;;
        "INFO") echo -e "\033[32m[INFO]\033[0m $message" ;;
        "DEBUG") [ "$VERBOSE" = true ] && echo -e "\033[36m[DEBUG]\033[0m $message" ;;
    esac
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
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
    -a, --aur-helper NAME   AUR helper (default: yay)
    -b, --branch NAME       Repository branch (default: main)
    -u, --user USERNAME     Username (skip prompt)
    -s, --skip-prompts      Skip all prompts
    -v, --verbose           Enable verbose output
    -c, --continue-on-error Continue on errors
    -h, --help              Show help
EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -r|--repo) DOTFILES_REPO="$2"; shift 2 ;;
            -p|--progs) PROGS_FILE="$2"; shift 2 ;;
            -a|--aur-helper) AUR_HELPER="$2"; shift 2 ;;
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

install_pkg() {
    log "DEBUG" "Installing package: $1"
    pacman -Qq "$1" >/dev/null 2>&1 && { log "DEBUG" "$1 already installed"; return 0; }
    pacman --noconfirm --needed -S "$1" >/dev/null 2>&1 || { log "ERROR" "Failed to install: $1"; return 1; }
}

### INTERACTIVE FUNCTIONS ###
welcome_msg() {
    [ "$SKIP_PROMPTS" = true ] && return 0
    whiptail --title "Welcome!" --msgbox "Welcome to Schloprice!\n\nRepository: $DOTFILES_REPO\nBranch: $REPO_BRANCH" 14 70
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

install_aur_helper() {
    command -v "$AUR_HELPER" >/dev/null 2>&1 && { log "INFO" "$AUR_HELPER already installed"; return 0; }
    log "INFO" "Installing AUR helper: $AUR_HELPER"
    whiptail --infobox "Installing AUR helper: $AUR_HELPER..." 7 50

    # Install dependencies
    for pkg in git base-devel; do
        install_pkg "$pkg" || error "Failed to install $pkg"
    done

    # Create temporary directory for AUR helper installation
    local temp_dir=$(mktemp -d)
    local aur_url="https://aur.archlinux.org/${AUR_HELPER}.git"

    # Clone and build as user
    sudo -u "$username" git clone --depth 1 "$aur_url" "$temp_dir" >/dev/null 2>&1 || error "Failed to clone $AUR_HELPER"
    cd "$temp_dir" || error "Failed to access $temp_dir"

    # Build and install
    sudo -u "$username" makepkg --noconfirm -si >/dev/null 2>&1 || error "Failed to build $AUR_HELPER"

    # Cleanup
    rm -rf "$temp_dir"
    log "INFO" "$AUR_HELPER installed successfully"
}

install_programs() {
    # Detect progs file
    [ -n "$PROGS_FILE" ] || {
        local temp_repo_dir=$(mktemp -d)
        local clone_args="--depth 1 -q"; [ -n "$REPO_BRANCH" ] && clone_args="$clone_args -b $REPO_BRANCH"
        if git clone $clone_args "$DOTFILES_REPO" "$temp_repo_dir" >/dev/null 2>&1 && [ -f "$temp_repo_dir/progs.csv" ]; then
            PROGS_FILE="$temp_repo_dir/progs.csv"; log "INFO" "Found progs.csv in repository"
        else
            log "WARN" "No progs.csv found, skipping software installation"; return 0
        fi
    }

    # Download or copy progs file
    [[ "$PROGS_FILE" =~ ^https?:// ]] && curl -Ls "$PROGS_FILE" | sed '/^#/d' > /tmp/progs.csv || cp "$PROGS_FILE" /tmp/progs.csv
    sed -i '/^#/d; /^$/d' /tmp/progs.csv

    local total_packages=$(wc -l < /tmp/progs.csv)
    local current_package=0
    log "INFO" "Installing $total_packages packages..."

    while IFS=, read -r tag program comment; do
        current_package=$((current_package + 1))
        comment="$(echo "$comment" | sed -E 's/(^"|"$)//g')"
        log "INFO" "Installing: $program ($current_package of $total_packages)"
        whiptail --title "Progress" --infobox "Installing \`$program\` ($current_package of $total_packages)\\n$comment" 8 70

        case "$tag" in
            "A") sudo -u "$username" "$AUR_HELPER" -S --noconfirm "$program" >/dev/null 2>&1 || error "Failed to install AUR: $program" ;;
            "G")
                local progname="${program##*/}"; progname="${progname%.git}"; local dir="$repo_dir/$progname"
                sudo -u "$username" git clone --depth 1 -q "$program" "$dir" >/dev/null 2>&1 || { cd "$dir" && sudo -u "$username" git pull --force origin master >/dev/null 2>&1; } || error "Failed to clone: $program"
                cd "$dir" && make >/dev/null 2>&1 && make install >/dev/null 2>&1 || error "Failed to compile/install: $progname"
                ;;
            "P")
                command -v pip >/dev/null 2>&1 || install_pkg python-pip || error "Failed to install pip"
                pip install --break-system-packages "$program" >/dev/null 2>&1 || error "Failed to install Python: $program"
                ;;
            *) install_pkg "$program" || error "Failed to install: $program" ;;
        esac
    done < /tmp/progs.csv
    log "INFO" "Package installation completed"
}

install_dotfiles() {
    log "INFO" "Installing configuration files..."
    whiptail --infobox "Installing config files..." 7 60
    local temp_dir=$(mktemp -d)
    local clone_args="--depth 1 -q --recursive"; [ -n "$REPO_BRANCH" ] && clone_args="$clone_args -b $REPO_BRANCH"

    sudo -u "$username" git clone $clone_args "$DOTFILES_REPO" "$temp_dir" >/dev/null 2>&1 || error "Failed to clone: $DOTFILES_REPO"
    rm -rf "$temp_dir"/.git* "$temp_dir"/README.md "$temp_dir"/LICENSE "$temp_dir"/FUNDING.yml "$temp_dir"/progs.csv
    sudo -u "$username" cp -rfT "$temp_dir" "/home/$username" && rm -rf "$temp_dir"
    log "INFO" "Configuration files installed"
}

install_dwm_suite() {
    log "INFO" "Installing DWM suite..."
    local src_dir="$repo_dir"

    # Install X11 development packages
    for pkg in libx11 libxft libxinerama libxrandr fontconfig freetype2 gcc make; do
        install_pkg "$pkg" || error "Failed to install $pkg"
    done

    # DWM suite repositories
    local dwm_repos=(
        "https://git.suckless.org/dwm"
        "https://git.suckless.org/dmenu"
        "https://git.suckless.org/st"
        "https://github.com/torrinfail/dwmblocks.git"
    )

    sudo -u "$username" mkdir -p "$src_dir"

    for repo_url in "${dwm_repos[@]}"; do
        local project="${repo_url##*/}"; project="${project%.git}"
        local project_dir="$src_dir/$project"

        log "INFO" "Installing $project..."
        whiptail --infobox "Compiling $project..." 7 60

        # Clone or update
        if [ ! -d "$project_dir" ]; then
            sudo -u "$username" git clone --depth 1 "$repo_url" "$project_dir" >/dev/null 2>&1 || error "Failed to clone $project"
        else
            cd "$project_dir" && sudo -u "$username" git pull origin master >/dev/null 2>&1 || true
        fi

        cd "$project_dir" || error "Cannot access $project_dir"

        # Apply custom config if exists
        for config_path in "/home/$username/.config/$project/config.h" "/home/$username/.$project/config.h"; do
            [ -f "$config_path" ] && sudo -u "$username" cp "$config_path" "$project_dir/config.h" && break
        done

        # Compile and install
        sudo -u "$username" make clean >/dev/null 2>&1 || true
        sudo -u "$username" make >/dev/null 2>&1 || error "Failed to compile $project"
        make install >/dev/null 2>&1 || error "Failed to install $project"
        log "INFO" "$project installed successfully"
    done

    # Create xinitrc
    [ ! -f "/home/$username/.xinitrc" ] && cat > "/home/$username/.xinitrc" << 'EOF' && chown "$username:wheel" "/home/$username/.xinitrc" && chmod +x "/home/$username/.xinitrc"
#!/bin/sh
dwmblocks &
exec dwm
EOF
    log "INFO" "DWM suite installation completed"
}

finalize_setup() {
    log "INFO" "Finalizing setup..."

    # Shell setup
    chsh -s /bin/zsh "$username" >/dev/null 2>&1
    sudo -u "$username" mkdir -p "/home/$username"/.{cache/zsh,config,local/bin}
    command -v dash >/dev/null 2>&1 && ln -sfT /bin/dash /bin/sh >/dev/null 2>&1

    # System optimizations
    ! grep -q "ILoveCandy" /etc/pacman.conf && sed -i "/#VerbosePkgLists/a ILoveCandy" /etc/pacman.conf
    sed -Ei "s/^#(ParallelDownloads).*/\1 = 5/;/^#Color$/s/#//" /etc/pacman.conf
    sed -i "s/-j2/-j$(nproc)/;/^#MAKEFLAGS/s/^#//" /etc/makepkg.conf
    rmmod pcspkr 2>/dev/null || true; echo "blacklist pcspkr" > /etc/modprobe.d/nobeep.conf

    # Permissions
    echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/00-wheel-can-sudo
    cat > /etc/sudoers.d/01-cmds-without-password << 'EOF'
%wheel ALL=(ALL:ALL) NOPASSWD: /usr/bin/shutdown,/usr/bin/reboot,/usr/bin/systemctl suspend,/usr/bin/mount,/usr/bin/umount,/usr/bin/pacman -Syu,/usr/bin/pacman -Syyu,/usr/bin/pacman -Syyu --noconfirm,/usr/bin/loadkeys,/usr/bin/yay,/usr/bin/paru
EOF
    echo "Defaults editor=/usr/bin/nvim" > /etc/sudoers.d/02-visudo-editor
    mkdir -p /etc/sysctl.d; echo "kernel.dmesg_restrict = 0" > /etc/sysctl.d/dmesg.conf

    # Cleanup
    rm -f /etc/sudoers.d/schloprice-temp /tmp/progs.csv

    # Final report
    cat > "/home/$username/installation-report.txt" << EOF
Schloprice Installation completed: $(date)
Repository: $DOTFILES_REPO | Branch: $REPO_BRANCH | User: $username
Log: $LOG_FILE

To start: Log in as '$username' and run 'startx'
EOF
    chown "$username:wheel" "/home/$username/installation-report.txt"

    [ "$SKIP_PROMPTS" = false ] && whiptail --title "Complete!" --msgbox "Installation completed!\n\nLog in as '$username' and run 'startx'." 12 70
    log "INFO" "Installation completed successfully!"
}

### MAIN ###
main() {
    echo "Starting Schloprice... Log: $LOG_FILE"
    parse_arguments "$@"; check_requirements

    # Install whiptail first
    install_pkg libnewt || error "Failed to install whiptail"

    # Interactive setup
    welcome_msg; get_user_and_pass; user_check
    [ "$SKIP_PROMPTS" = false ] && whiptail --title "Ready!" --yes-button "Let's go!" --no-button "Cancel" --yesno "Ready to install.\n\nRepo: $DOTFILES_REPO\nUser: $username\nAUR: $AUR_HELPER\n\nContinue?" 14 70 || exit 0

    log "INFO" "Starting installation..."
    refresh_keys

    # Install base packages
    for pkg in curl ca-certificates base-devel git zsh; do
        install_pkg "$pkg" || error "Failed to install: $pkg"
    done

    # Setup user and temporary sudo
    add_user_and_pass
    echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/schloprice-temp

    # Install AUR helper, programs, dotfiles, and DWM
    install_aur_helper
    install_programs
    install_dotfiles
    install_dwm_suite
    finalize_setup

    log "INFO" "All steps completed!"
}

main "$@"
