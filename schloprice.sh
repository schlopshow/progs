#!/bin/bash

# Schloprice - Enhanced Auto Rice Bootstrapping Script
# Based on LARBS by Luke Smith, enhanced for flexibility
# License: GNU GPLv3

### OPTIONS AND VARIABLES ###

# Default values - can be overridden via command line arguments
DOTFILES_REPO="https://github.com/lukesmithxyz/voidrice.git"
PROGS_FILE="https://raw.githubusercontent.com/LukeSmithxyz/LARBS/master/static/progs.csv"
AUR_HELPER="yay"
REPO_BRANCH="main"
SCRIPT_NAME="schloprice"
USER_NAME=""
USER_PASS=""
SKIP_PROMPTS=false
VERBOSE=false
LOG_FILE="/tmp/schloprice-install.log"

export TERM=ansi

### UTILITY FUNCTIONS ###

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case "$level" in
        "ERROR")
            echo -e "\033[31m[ERROR]\033[0m $message" >&2
            echo "[$timestamp] [ERROR] $message" >> "$LOG_FILE"
            ;;
        "WARN")
            echo -e "\033[33m[WARN]\033[0m $message" >&2
            echo "[$timestamp] [WARN] $message" >> "$LOG_FILE"
            ;;
        "INFO")
            echo -e "\033[32m[INFO]\033[0m $message"
            echo "[$timestamp] [INFO] $message" >> "$LOG_FILE"
            ;;
        "DEBUG")
            if [ "$VERBOSE" = true ]; then
                echo -e "\033[36m[DEBUG]\033[0m $message"
            fi
            echo "[$timestamp] [DEBUG] $message" >> "$LOG_FILE"
            ;;
    esac
}

error() {
    log "ERROR" "$1"
    exit 1
}

show_help() {
    cat << EOF
$SCRIPT_NAME - Automated Linux Desktop Setup

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -r, --repo URL          Dotfiles repository URL
    -p, --progs FILE/URL    Programs CSV file path or URL
    -a, --aur-helper NAME   AUR helper to use (default: yay)
    -b, --branch NAME       Repository branch (default: main)
    -u, --user USERNAME     Username (skip prompt)
    -s, --skip-prompts      Skip all prompts (use defaults)
    -v, --verbose           Enable verbose output
    -h, --help              Show this help message

EXAMPLES:
    $0 -r https://github.com/user/dotfiles.git
    $0 -r https://github.com/user/dotfiles.git -p https://raw.githubusercontent.com/user/dotfiles/master/progs.csv
    $0 --skip-prompts --user myuser --repo https://github.com/user/dotfiles.git

REPOSITORY STRUCTURE:
    Your repository should contain:
    - Configuration files organized as they appear in home directory
    - progs.csv file with software list (optional)
    - Any custom scripts in .local/bin/

EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -r|--repo)
                DOTFILES_REPO="$2"
                shift 2
                ;;
            -p|--progs)
                PROGS_FILE="$2"
                shift 2
                ;;
            -a|--aur-helper)
                AUR_HELPER="$2"
                shift 2
                ;;
            -b|--branch)
                REPO_BRANCH="$2"
                shift 2
                ;;
            -u|--user)
                USER_NAME="$2"
                shift 2
                ;;
            -s|--skip-prompts)
                SKIP_PROMPTS=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                error "Unknown option: $1. Use -h for help."
                ;;
        esac
    done
}

check_requirements() {
    log "INFO" "Checking system requirements..."

    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
    fi

    # Check if on Arch-based system
    if ! command -v pacman >/dev/null 2>&1; then
        error "This script requires an Arch-based Linux distribution"
    fi

    # Check internet connection
    if ! ping -c 1 archlinux.org >/dev/null 2>&1; then
        error "No internet connection detected"
    fi

    log "INFO" "System requirements satisfied"
}

install_pkg() {
    local package="$1"
    log "DEBUG" "Installing package: $package"
    pacman --noconfirm --needed -S "$package" >/dev/null 2>&1
    return $?
}

### INTERACTIVE FUNCTIONS ###

welcome_msg() {
    if [ "$SKIP_PROMPTS" = true ]; then
        log "INFO" "Skipping welcome message (non-interactive mode)"
        return 0
    fi

    whiptail --title "Welcome!" \
        --msgbox "Welcome to Schloprice - Enhanced Auto-Rice Bootstrapping Script!\\n\\nThis script will automatically install a fully-featured Linux desktop using your custom configuration.\\n\\nRepository: $DOTFILES_REPO" 12 70

    whiptail --title "Important Note!" --yes-button "All ready!" \
        --no-button "Return..." \
        --yesno "Be sure the computer you are using has current pacman updates and refreshed Arch keyrings.\\n\\nIf it does not, the installation of some programs might fail." 8 70
}

get_user_and_pass() {
    if [ -n "$USER_NAME" ]; then
        log "INFO" "Using provided username: $USER_NAME"
        username="$USER_NAME"
    else
        username=$(whiptail --inputbox "Enter a username for the new user account:" 10 60 3>&1 1>&2 2>&3 3>&1) || exit 1
        while ! echo "$username" | grep -q "^[a-z_][a-z0-9_-]*$"; do
            username=$(whiptail --nocancel --inputbox "Username not valid. Use only lowercase letters, numbers, - or _." 10 60 3>&1 1>&2 2>&3 3>&1)
        done
    fi

    if [ "$SKIP_PROMPTS" = true ]; then
        # Generate a random password for non-interactive mode
        user_password=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-16)
        log "INFO" "Generated random password for user (saved to $LOG_FILE)"
        echo "Generated password for $username: $user_password" >> "$LOG_FILE"
    else
        user_password=$(whiptail --nocancel --passwordbox "Enter a password for $username:" 10 60 3>&1 1>&2 2>&3 3>&1)
        local pass2
        pass2=$(whiptail --nocancel --passwordbox "Retype password:" 10 60 3>&1 1>&2 2>&3 3>&1)
        while ! [ "$user_password" = "$pass2" ]; do
            unset pass2
            user_password=$(whiptail --nocancel --passwordbox "Passwords do not match. Enter password again:" 10 60 3>&1 1>&2 2>&3 3>&1)
            pass2=$(whiptail --nocancel --passwordbox "Retype password:" 10 60 3>&1 1>&2 2>&3 3>&1)
        done
    fi
}

user_check() {
    if id -u "$username" >/dev/null 2>&1; then
        if [ "$SKIP_PROMPTS" = true ]; then
            log "WARN" "User $username already exists, will overwrite settings"
            return 0
        fi

        whiptail --title "WARNING" --yes-button "CONTINUE" \
            --no-button "No wait..." \
            --yesno "The user \`$username\` already exists. This will OVERWRITE any conflicting settings/dotfiles.\\n\\nYour personal files (documents, videos, etc.) will NOT be touched.\\n\\nContinue?" 12 70
    fi
}

pre_install_msg() {
    if [ "$SKIP_PROMPTS" = true ]; then
        log "INFO" "Starting automated installation..."
        return 0
    fi

    whiptail --title "Ready to Install!" --yes-button "Let's go!" \
        --no-button "Cancel" \
        --yesno "Ready to begin automated installation.\\n\\nRepository: $DOTFILES_REPO\\nBranch: $REPO_BRANCH\\nUser: $username\\n\\nThis will take some time. Continue?" 12 70 || {
        clear
        exit 1
    }
}

### INSTALLATION FUNCTIONS ###

add_user_and_pass() {
    log "INFO" "Adding user: $username"
    whiptail --infobox "Adding user \"$username\"..." 7 50

    useradd -m -g wheel -s /bin/zsh "$username" >/dev/null 2>&1 ||
        usermod -a -G wheel "$username" && mkdir -p "/home/$username" && chown "$username:wheel" "/home/$username"

    export repo_dir="/home/$username/.local/src"
    mkdir -p "$repo_dir"
    chown -R "$username:wheel" "$(dirname "$repo_dir")"
    echo "$username:$user_password" | chpasswd
    unset user_password

    log "INFO" "User $username created successfully"
}

refresh_keys() {
    log "INFO" "Refreshing package keys..."
    case "$(readlink -f /sbin/init)" in
    *systemd*)
        whiptail --infobox "Refreshing Arch Keyring..." 7 40
        install_pkg archlinux-keyring
        ;;
    *)
        whiptail --infobox "Enabling Arch repositories..." 7 40
        install_pkg artix-keyring
        install_pkg artix-archlinux-support

        if ! grep -q "^\[extra\]" /etc/pacman.conf; then
            echo -e "\n[extra]\nInclude = /etc/pacman.d/mirrorlist-arch" >> /etc/pacman.conf
        fi

        pacman -Sy --noconfirm >/dev/null 2>&1
        pacman-key --populate archlinux >/dev/null 2>&1
        ;;
    esac
}

manual_install() {
    local package="$1"

    if pacman -Qq "$package" >/dev/null 2>&1; then
        log "DEBUG" "$package already installed"
        return 0
    fi

    log "INFO" "Manually installing: $package"
    whiptail --infobox "Installing \"$package\" manually..." 7 50

    sudo -u "$username" mkdir -p "$repo_dir/$package"
    sudo -u "$username" git -C "$repo_dir" clone --depth 1 --single-branch \
        --no-tags -q "https://aur.archlinux.org/$package.git" "$repo_dir/$package" || {
        cd "$repo_dir/$package" || return 1
        sudo -u "$username" git pull --force origin master
    }

    cd "$repo_dir/$package" || return 1
    sudo -u "$username" makepkg --noconfirm -si >/dev/null 2>&1
}

main_install() {
    local package="$1"
    local description="$2"
    log "INFO" "Installing: $package ($current_package of $total_packages)"
    whiptail --title "Installation Progress" --infobox "Installing \`$package\` ($current_package of $total_packages)\\n$description" 8 70
    install_pkg "$package"
}

git_make_install() {
    local url="$1"
    local description="$2"
    local progname="${url##*/}"
    progname="${progname%.git}"
    local dir="$repo_dir/$progname"

    log "INFO" "Installing from git: $progname ($current_package of $total_packages)"
    whiptail --title "Installation Progress" \
        --infobox "Installing \`$progname\` ($current_package of $total_packages) via git and make\\n$description" 8 70

    sudo -u "$username" git -C "$repo_dir" clone --depth 1 --single-branch \
        --no-tags -q "$url" "$dir" || {
        cd "$dir" || return 1
        sudo -u "$username" git pull --force origin master
    }

    cd "$dir" || return 1
    make >/dev/null 2>&1
    make install >/dev/null 2>&1
    cd /tmp || return 1
}

aur_install() {
    local package="$1"
    local description="$2"

    log "INFO" "Installing from AUR: $package ($current_package of $total_packages)"
    whiptail --title "Installation Progress" \
        --infobox "Installing \`$package\` ($current_package of $total_packages) from AUR\\n$description" 8 70

    echo "$aur_installed" | grep -q "^$package$" && return 0
    sudo -u "$username" "$AUR_HELPER" -S --noconfirm "$package" >/dev/null 2>&1
}

pip_install() {
    local package="$1"
    local description="$2"

    log "INFO" "Installing Python package: $package ($current_package of $total_packages)"
    whiptail --title "Installation Progress" \
        --infobox "Installing Python package \`$package\` ($current_package of $total_packages)\\n$description" 8 70

    [ -x "$(command -v pip)" ] || install_pkg python-pip
    yes | pip install "$package" >/dev/null 2>&1
}

detect_progs_file() {
    if [ -n "$PROGS_FILE" ]; then
        log "INFO" "Using specified programs file: $PROGS_FILE"
        return 0
    fi

    # Try to find progs.csv in the repository
    local temp_repo_dir
    temp_repo_dir=$(mktemp -d)

    log "DEBUG" "Checking repository for progs.csv file"

    if git clone --depth 1 --single-branch -b "$REPO_BRANCH" "$DOTFILES_REPO" "$temp_repo_dir" >/dev/null 2>&1; then
        if [ -f "$temp_repo_dir/progs.csv" ]; then
            PROGS_FILE="$temp_repo_dir/progs.csv"
            log "INFO" "Found progs.csv in repository"
        else
            log "WARN" "No progs.csv found in repository, skipping software installation"
            PROGS_FILE=""
        fi
    else
        log "WARN" "Could not access repository to check for progs.csv"
    fi

    rm -rf "$temp_repo_dir"
}

installation_loop() {
    detect_progs_file

    if [ -z "$PROGS_FILE" ]; then
        log "WARN" "No programs file specified or found, skipping software installation"
        return 0
    fi

    # Get the programs file
    if [[ "$PROGS_FILE" =~ ^https?:// ]]; then
        curl -Ls "$PROGS_FILE" | sed '/^#/d' > /tmp/progs.csv
    else
        cp "$PROGS_FILE" /tmp/progs.csv
    fi

    # Remove comments and empty lines
    sed -i '/^#/d; /^$/d' /tmp/progs.csv

    total_packages=$(wc -l < /tmp/progs.csv)
    aur_installed=$(pacman -Qqm)
    current_package=0

    log "INFO" "Installing $total_packages packages..."

    while IFS=, read -r tag program comment; do
        current_package=$((current_package + 1))

        # Clean up comment field
        comment="$(echo "$comment" | sed -E 's/(^"|"$)//g')"

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
    local repo_url="$1"
    local destination="$2"
    local branch="$3"

    log "INFO" "Downloading and installing configuration files..."
    whiptail --infobox "Downloading and installing config files..." 7 60

    [ -z "$branch" ] && branch="$REPO_BRANCH"
    local temp_dir
    temp_dir=$(mktemp -d)

    [ ! -d "$destination" ] && mkdir -p "$destination"
    chown "$username:wheel" "$temp_dir" "$destination"

    if sudo -u "$username" git clone --depth 1 --single-branch --no-tags -q \
        --recursive -b "$branch" --recurse-submodules "$repo_url" "$temp_dir"; then

        # Remove git-related files
        rm -rf "$temp_dir/.git" "$temp_dir/.gitignore" "$temp_dir/README.md" \
               "$temp_dir/LICENSE" "$temp_dir/FUNDING.yml" "$temp_dir/progs.csv"

        sudo -u "$username" cp -rfT "$temp_dir" "$destination"
        log "INFO" "Configuration files installed successfully"
    else
        error "Failed to clone repository: $repo_url"
    fi

    rm -rf "$temp_dir"
}

setup_shell() {
    log "INFO" "Setting up shell environment..."

    # Make zsh the default shell
    chsh -s /bin/zsh "$username" >/dev/null 2>&1

    # Create necessary directories
    sudo -u "$username" mkdir -p "/home/$username/.cache/zsh/"
    sudo -u "$username" mkdir -p "/home/$username/.config"
    sudo -u "$username" mkdir -p "/home/$username/.local/bin"

    # Make dash the default /bin/sh if available
    if command -v dash >/dev/null 2>&1; then
        ln -sfT /bin/dash /bin/sh >/dev/null 2>&1
    fi
}

system_optimizations() {
    log "INFO" "Applying system optimizations..."

    # Make pacman more pleasant
    if ! grep -q "ILoveCandy" /etc/pacman.conf; then
        sed -i "/#VerbosePkgLists/a ILoveCandy" /etc/pacman.conf
    fi
    sed -Ei "s/^#(ParallelDownloads).*/\1 = 5/;/^#Color$/s/#//" /etc/pacman.conf

    # Use all cores for compilation
    sed -i "s/-j2/-j$(nproc)/;/^#MAKEFLAGS/s/^#//" /etc/makepkg.conf

    # Disable PC speaker beep
    rmmod pcspkr 2>/dev/null
    echo "blacklist pcspkr" > /etc/modprobe.d/nobeep.conf

    log "INFO" "System optimizations applied"
}

setup_permissions() {
    log "INFO" "Setting up user permissions..."

    # Allow wheel users to sudo with password
    echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/00-wheel-can-sudo

    # Allow specific commands without password
    cat > /etc/sudoers.d/01-cmds-without-password << 'EOF'
%wheel ALL=(ALL:ALL) NOPASSWD: /usr/bin/shutdown,/usr/bin/reboot,/usr/bin/systemctl suspend,/usr/bin/mount,/usr/bin/umount,/usr/bin/pacman -Syu,/usr/bin/pacman -Syyu,/usr/bin/pacman -Syyu --noconfirm,/usr/bin/loadkeys
EOF

    # Set default editor
    echo "Defaults editor=/usr/bin/nvim" > /etc/sudoers.d/02-visudo-editor

    # Allow dmesg for users
    mkdir -p /etc/sysctl.d
    echo "kernel.dmesg_restrict = 0" > /etc/sysctl.d/dmesg.conf
}

finalize() {
    log "INFO" "Finalizing installation..."

    # Cleanup temporary sudo permissions
    rm -f /etc/sudoers.d/schloprice-temp

    # Generate final report
    cat > "/home/$username/installation-report.txt" << EOF
Schloprice Installation completed at: $(date)
Repository: $DOTFILES_REPO
Branch: $REPO_BRANCH
User: $username
AUR Helper: $AUR_HELPER
Log file: $LOG_FILE

To start your new desktop environment:
1. Log out and log back in as '$username'
2. Run 'startx' to start the graphical environment

Configuration files have been installed to your home directory.
Check the log file for any errors or warnings.
EOF

    chown "$username:wheel" "/home/$username/installation-report.txt"

    if [ "$SKIP_PROMPTS" = false ]; then
        whiptail --title "Installation Complete!" \
            --msgbox "Schloprice installation completed successfully!\\n\\nA report has been saved to your home directory.\\n\\nTo start the graphical environment, log in as '$username' and run 'startx'." 10 70
    fi

    log "INFO" "Schloprice installation completed successfully!"
    log "INFO" "Report saved to: /home/$username/installation-report.txt"
}

### MAIN SCRIPT ###

main() {
    echo "Starting Schloprice - Enhanced Auto Rice Bootstrapping Script..."
    echo "Log file: $LOG_FILE"

    # Parse command line arguments
    parse_arguments "$@"

    # Check system requirements
    check_requirements

    # Install whiptail for dialogs
    install_pkg libnewt || error "Failed to install whiptail"

    # Show welcome message
    welcome_msg || error "User cancelled installation"

    # Get user credentials
    get_user_and_pass || error "User cancelled installation"

    # Check if user exists
    user_check || error "User cancelled installation"

    # Final confirmation
    pre_install_msg || error "User cancelled installation"

    log "INFO" "Starting automated installation process..."

    # Refresh package keys
    refresh_keys || error "Failed to refresh package keys"

    # Install essential packages
    log "INFO" "Installing essential packages..."
    for pkg in curl ca-certificates base-devel git ntp zsh; do
        whiptail --infobox "Installing essential package: $pkg" 7 50
        install_pkg "$pkg" || log "WARN" "Failed to install $pkg"
    done

    # Sync system time
    whiptail --infobox "Synchronizing system time..." 7 50
    ntpd -q -g >/dev/null 2>&1

    # Add user
    add_user_and_pass || error "Failed to add user"

    # Setup temporary sudo permissions for installation
    trap 'rm -f /etc/sudoers.d/schloprice-temp' HUP INT QUIT TERM PWR EXIT
    cat > /etc/sudoers.d/schloprice-temp << 'EOF'
%wheel ALL=(ALL) NOPASSWD: ALL
Defaults:%wheel,root runcwd=*
EOF

    # Apply system optimizations
    system_optimizations

    # Install AUR helper
    manual_install "$AUR_HELPER" || error "Failed to install AUR helper"

    # Enable development package updates for AUR helper
    sudo -u "$username" "$AUR_HELPER" -Y --save --devel 2>/dev/null || true

    # Install packages from list
    installation_loop

    # Install dotfiles
    put_git_repo "$DOTFILES_REPO" "/home/$username" "$REPO_BRANCH"

    # Setup shell environment
    setup_shell

    # Setup user permissions
    setup_permissions

    # Finalize installation
    finalize
}

# Run main function with all arguments
main "$@"
