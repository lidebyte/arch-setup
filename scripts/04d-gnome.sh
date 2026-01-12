#!/bin/bash

# 引用工具库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
if [ -f "$SCRIPT_DIR/00-utils.sh" ]; then
    source "$SCRIPT_DIR/00-utils.sh"
else
    echo "Error: 00-utils.sh not found."
    exit 1
fi
log "installing dms..."

check_root
# ==============================================================================
#  Identify User 
# ==============================================================================

log "Identifying user..."
DETECTED_USER=$(awk -F: '$3 == 1000 {print $1}' /etc/passwd)
TARGET_USER="${DETECTED_USER:-$(read -p "Target user: " u && echo $u)}"
HOME_DIR="/home/$TARGET_USER"
info_kv "Target" "$TARGET_USER"

# ==================================
# temp sudo without passwd
# ==================================
SUDO_TEMP_FILE="/etc/sudoers.d/99_shorin_installer_temp"
echo "$TARGET_USER ALL=(ALL) NOPASSWD: ALL" >"$SUDO_TEMP_FILE"
chmod 440 "$SUDO_TEMP_FILE"
log "Temp sudo file created..."

cleanup_sudo() {
    if [ -f "$SUDO_TEMP_FILE" ]; then
        rm -f "$SUDO_TEMP_FILE"
        log "Security: Temporary sudo privileges revoked."
    fi
}

trap cleanup_sudo EXIT INT TERM

#=================================================
# installation
#=================================================
section "Step 1" "Install base pkgs"
log "Installing GNOME ..."
if exe as_user yay -S --noconfirm --needed --answerdiff=None --answerclean=None gnome-desktop gnome-backgrounds gnome-tweaks gdm ghostty gnome-control-center gnome-software flatpak file-roller nautilus-python firefox nm-connection-editor pacman-contrib dnsmasq; then
        log "PKGS intsalled "
else
        log "Installation failed."
        return 1
fi

# start gdm 
log "Enable gdm..."
exe systemctl enable gdm

#=================================================
# set default terminal
#=================================================
section "Step 2" "Set default terminal"
log "set gnome default terminal..."
exe as_user gsettings set org.gnome.desktop.default-applications.terminal exec 'ghostty'
exe as_user gsettings set org.gnome.desktop.default-applications.terminal exec-arg '-e'

#=================================================
# locale
#=================================================
section "Step 3" "Set locale"
log "Configuring GNOME locale for user $TARGET_USER..."
ACCOUNT_FILE="/var/lib/AccountsService/users/$TARGET_USER"
ACCOUNT_DIR=$(dirname "$ACCOUNT_FILE")
# 确保目录存在
mkdir -p "$ACCOUNT_DIR"
# 设置语言为中文
cat > "$ACCOUNT_FILE" <<EOF
[User]
Languages=zh_CN.UTF-8
EOF

#=================================================
# shortcuts
#=================================================
section "Step 4" "Configure Shortcuts"
log "Configuring shortcuts.."
GNOME_KEY_DIR="$PARENT_DIR/gnome-dotfiles/keybinds"
cat "$GNOME_KEY_DIR/org.gnome.desktop.wm.keybindings.conf" | sudo -u $TARGET_USER dconf load /org/gnome/desktop/wm/keybindings/
cat "$GNOME_KEY_DIR/org.gnome.settings-daemon.plugins.media-keys.conf" | sudo -u $TARGET_USER dconf load /org/gnome/settings-daemon/plugins/media-keys/
cat "$GNOME_KEY_DIR/org.gnome.shell.keybindings.conf" | sudo -u $TARGET_USER dconf load /org/gnome/shell/keybindings/

#=================================================
# extensions
#=================================================
section "Step 5" "Install Extensions"
log "Installing Extensions..."

sudo -u $TARGET_USER yay -S --noconfirm --needed --answerdiff=None --answerclean=None gnome-extensions-cli

EXTENSION_LIST=(
    "arch-update@RaphaelRochet"
    "aztaskbar@aztaskbar.gitlab.com"
    "blur-my-shell@aunetx"
    "caffeine@patapon.info"
    "clipboard-indicator@tudmotu.com"
    "color-picker@tuberry"
    "desktop-cube@schneegans.github.com"
    "ding@rastersoft.com"
    "fuzzy-application-search@mkhl.codeberg.page"
    "lockkeys@vaina.lt"
    "middleclickclose@paolo.tranquilli.gmail.com"
    "steal-my-focus-window@steal-my-focus-window"
    "tilingshell@ferrarodomenico.com"
    "user-theme@gnome-shell-extensions.gcampax.github.com"
    "kimpanel@kde.org"
)
log "Downloading extensions..."
sudo -u $TARGET_USER gnome-extensions-cli install ${EXTENSION_LIST[@]}
sudo -u $TARGET_USER gnome-extensions-cli enable ${EXTENSION_LIST[@]}


# === firefox inte ===
log "Configuring Firefox GNOME Integration..."

exe sudo -u $TARGET_USER yay -S --noconfirm --needed --answerdiff=None --answerclean=None gnome-browser-connector

# 配置 Firefox 策略自动安装扩展
POL_DIR="/etc/firefox/policies"
exe mkdir -p "$POL_DIR"

echo '{
  "policies": {
    "Extensions": {
      "Install": [
        "https://addons.mozilla.org/firefox/downloads/latest/gnome-shell-integration/latest.xpi"
      ]
    }
  }
}' > "$POL_DIR/policies.json"

exe chmod 755 "$POL_DIR" && exe chmod 644 "$POL_DIR/policies.json"

log "Firefox policies updated."

#=================================================
# Input Method
#=================================================
section "Step 6" "Input method"
log "Configure input method."

if ! cat "/etc/environment" | grep -q "fcitx" ; then

    cat << EOT >> /etc/environment
XIM="fcitx"
GTK_IM_MODULE=fcitx
QT_IM_MODULE=fcitx
XMODIFIERS=@im=fcitx
XDG_CURRENT_DESKTOP=GNOME
EOT

fi

#=================================================
# dotfiles
#=================================================
log "Deploying dotfiles..."
GNOME_DOTFILES_DIR=$PARENT_DIR/gnome-dotfiles
as_user mkdir -p $HOME_DIR/.config
cp -rf $GNOME_DOTFILES_DIR/.config/* $HOME_DIR/.config/
chown -R $TARGET_USER $HOME_DIR/.config
pacman -S --noconfirm --needed thefuck starship eza fish zoxide

log "Dotfiles deployed and shell tools installed."

