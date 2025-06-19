#!/bin/bash

# Schloprice - Simplified Auto Rice Bootstrapping Script
# License: GNU GPLv3

### VARIABLES ###
DOTFILES_REPO="https://github.com/schlopshow/progs.git"
PROGS_FILE="https://raw.githubusercontent.com/schlopshow/schloprice/refs/heads/main/progs/full-progs.csv"
REPO_BRANCH="main"
USER_NAME=""
SKIP_PROMPTS=false

### UTILITY FUNCTIONS ###
error() {
    echo -e "\033[31m[ERROR]\033[0m $1" >&2
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
    -h, --help              Show help

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
            -h|--help) show_help; exit 0 ;;
            *) error "Unknown option: $1. Use -h for help." ;;
        esac
    done
}

check_requirements() {
    [[ $EUID -ne 0 ]] && error "This script must be run as root"
    ! command -v pacman >/dev/null 2>&1 && error "This script requires an Arch-based Linux distribution"
}

install_pkg() {
    pacman -Qq "$1" >/dev/null 2>&1 && return 0
    pacman --noconfirm --needed -S "$1" >/dev/null 2>&1
}

### INTERACTIVE FUNCTIONS ###
welcome_msg() {
    [ "$SKIP_PROMPTS" = true ] && return 0
    whiptail --title "Welcome!" --msgbox "Welcome to Schloprice!\n\nRepository: $DOTFILES_REPO\nBranch: $REPO_BRANCH" 12 70
    whiptail --title "Ready?" --yesno "Continue with installation?" 8 50 || exit 0
}

get_user_and_pass() {
    if [ -n "$USER_NAME" ]; then
        username="$USER_NAME"
    else
        username=$(whiptail --inputbox "Enter username:" 10 60 3>&1 1>&2 2>&3 3>&1) || exit 0
    fi

    if [ "$SKIP_PROMPTS" = true ]; then
        user_password=$(openssl rand -base64 12)
    else
        user_password=$(whiptail --passwordbox "Enter password for $username:" 10 60 3>&1 1>&2 2>&3 3>&1)
    fi
}

user_check() {
    if id -u "$username" >/dev/null 2>&1; then
        [ "$SKIP_PROMPTS" = false ] && whiptail --yesno "User $username exists. Continue?" 8 50 || exit 0
    fi
}

### INSTALLATION FUNCTIONS ###
add_user_and_pass() {
    whiptail --infobox "Adding user \"$username\"..." 7 50
    useradd -m -g wheel -s /bin/zsh "$username" 2>/dev/null || usermod -a -G wheel "$username"
    export repo_dir="/home/$username/.local/src"
    mkdir -p "$repo_dir"
    chown -R "$username:wheel" "$(dirname "$repo_dir")"
    echo "$username:$user_password" | chpasswd
    unset user_password
}

refresh_keys() {
    whiptail --infobox "Refreshing package keys..." 7 40
    case "$(readlink -f /sbin/init)" in
    *systemd*) install_pkg archlinux-keyring ;;
    *) install_pkg artix-keyring
       install_pkg artix-archlinux-support
       ! grep -q "^\[extra\]" /etc/pacman.conf && echo -e "\n[extra]\nInclude = /etc/pacman.d/mirrorlist-arch" >> /etc/pacman.conf
       pacman -Sy --noconfirm >/dev/null 2>&1 ;;
    esac
}

install_yay() {
    command -v yay >/dev/null 2>&1 && return 0
    whiptail --infobox "Installing yay AUR helper..." 7 50

    git clone --depth 1 "https://aur.archlinux.org/yay.git" /tmp/yay
    cd /tmp/yay
    chown -R "$username:wheel" /tmp/yay
    sudo -u "$username" makepkg -si --noconfirm >/dev/null 2>&1
    cd /
    rm -rf /tmp/yay
}

main_install() {
    whiptail --infobox "Installing $1..." 7 50
    install_pkg "$1"
}

git_make_install() {
    local progname="${1##*/}"
    progname="${progname%.git}"
    local dir="$repo_dir/$progname"

    whiptail --infobox "Installing $progname from git..." 7 50
    sudo -u "$username" git -C "$repo_dir" clone --depth 1 -q "$1" "$dir" 2>/dev/null || {
        cd "$dir" && sudo -u "$username" git pull --force origin master >/dev/null 2>&1
    }
    cd "$dir" && make >/dev/null 2>&1 && make install >/dev/null 2>&1
}

aur_install() {
    whiptail --infobox "Installing $1 from AUR..." 7 50
    sudo -u "$username" yay -S --noconfirm "$1" >/dev/null 2>&1
}

pip_install() {
    whiptail --infobox "Installing Python package $1..." 7 50
    command -v pip >/dev/null 2>&1 || install_pkg python-pip
    pip install --break-system-packages "$1" >/dev/null 2>&1
}

installation_loop() {
    # Download or copy progs file
    if [[ "$PROGS_FILE" =~ ^https?:// ]]; then
        curl -Ls "$PROGS_FILE" | sed '/^#/d' > /tmp/progs.csv
    else
        cp "$PROGS_FILE" /tmp/progs.csv
    fi

    sed -i '/^#/d; /^$/d' /tmp/progs.csv

    while IFS=, read -r tag program comment; do
        case "$tag" in
            "A") aur_install "$program" ;;
            "G") git_make_install "$program" ;;
            "P") pip_install "$program" ;;
            *) main_install "$program" ;;
        esac
    done < /tmp/progs.csv
}

put_git_repo() {
    whiptail --infobox "Installing config files..." 7 60

    git clone --depth 1 --recursive ${3:+-b "$3"} "$1" /tmp/dotfiles
    rm -rf /tmp/dotfiles/.git /tmp/dotfiles/.gitignore /tmp/dotfiles/README.md /tmp/dotfiles/LICENSE /tmp/dotfiles/progs.csv

    mkdir -p "$2"
    chown "$username:wheel" "$2"
    sudo -u "$username" cp -rfT /tmp/dotfiles "$2"
    rm -rf /tmp/dotfiles
}

install_dwm_suite() {
    whiptail --infobox "Installing DWM suite..." 7 50

    # Install X11 development packages
    for pkg in libx11 libxft libxinerama; do
        install_pkg "$pkg"
    done

    # Compile and install DWM components
    for project in dwm dmenu dwmblocks st; do
        local project_dir="$repo_dir/$project"
        if [ -d "$project_dir" ]; then
            cd "$project_dir"
            sudo -u "$username" make clean >/dev/null 2>&1
            sudo -u "$username" make >/dev/null 2>&1
            make install >/dev/null 2>&1
        fi
    done
}

setup_shell() {
    chsh -s /bin/zsh "$username" >/dev/null 2>&1
    sudo -u "$username" mkdir -p "/home/$username/.cache/zsh/" "/home/$username/.config" "/home/$username/.local/bin"
    command -v dash >/dev/null 2>&1 && ln -sfT /bin/dash /bin/sh
}

system_optimizations() {
    # Pacman optimizations
    ! grep -q "ILoveCandy" /etc/pacman.conf && sed -i "/#VerbosePkgLists/a ILoveCandy" /etc/pacman.conf
    sed -Ei "s/^#(ParallelDownloads).*/\1 = 5/;/^#Color$/s/#//" /etc/pacman.conf
    sed -i "s/-j2/-j$(nproc)/;/^#MAKEFLAGS/s/^#//" /etc/makepkg.conf

    # Disable PC speaker
    rmmod pcspkr 2>/dev/null
    echo "blacklist pcspkr" > /etc/modprobe.d/nobeep.conf
}

setup_permissions() {
    echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/00-wheel-can-sudo
    cat > /etc/sudoers.d/01-cmds-without-password << 'EOF'
%wheel ALL=(ALL:ALL) NOPASSWD: /usr/bin/shutdown,/usr/bin/reboot,/usr/bin/systemctl suspend,/usr/bin/mount,/usr/bin/umount,/usr/bin/pacman -Syu,/usr/bin/pacman -Syyu,/usr/bin/loadkeys,/usr/bin/yay
EOF
    echo "Defaults editor=/usr/bin/nvim" > /etc/sudoers.d/02-visudo-editor
    echo "kernel.dmesg_restrict = 0" > /etc/sysctl.d/dmesg.conf
}

finalize() {
    rm -f /etc/sudoers.d/schloprice-temp

    cat > "/home/$username/installation-report.txt" << EOF
Schloprice Installation completed: $(date)
Repository: $DOTFILES_REPO
User: $username

DWM Suite installed:
- dwm (window manager)
- dmenu (application launcher)
- dwmblocks (status bar)
- st (terminal)

To start: Log in as '$username' and run 'startx'
EOF

    chown "$username:wheel" "/home/$username/installation-report.txt"
    [ "$SKIP_PROMPTS" = false ] && whiptail --msgbox "Installation completed!\n\nLog in as '$username' and run 'startx'." 10 50
}

cleanup() {
    rm -f /tmp/progs.csv /etc/sudoers.d/schloprice-temp
}

trap cleanup EXIT

### MAIN ###
main() {
    parse_arguments "$@"
    check_requirements

    install_pkg libnewt
    welcome_msg
    get_user_and_pass
    user_check

    refresh_keys
    for pkg in curl base-devel git zsh; do
        install_pkg "$pkg"
    done

    add_user_and_pass
    echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/schloprice-temp

    install_yay
    installation_loop
    setup_shell
    put_git_repo "$DOTFILES_REPO" "/home/$username" "$REPO_BRANCH"
    install_dwm_suite
    system_optimizations
    setup_permissions
    finalize
}

main "$@"
