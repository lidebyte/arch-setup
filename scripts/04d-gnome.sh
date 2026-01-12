#!/bin/bash

# ==============================================================================
# Setup & Utils
# ==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/00-utils.sh" ]; then
    source "$SCRIPT_DIR/00-utils.sh"
else
    echo "Error: 00-utils.sh not found."
    exit 1
fi
log "Initializing installer..."

check_root

# ==============================================================================
#  Identify User 
# ==============================================================================
log "Identifying user..."
DETECTED_USER=$(awk -F: '$3 == 1000 {print $1}' /etc/passwd)
TARGET_USER="${DETECTED_USER:-$(read -p "Target user: " u && echo $u)}"
HOME_DIR="/home/$TARGET_USER"
info_kv "Target User" "$TARGET_USER"
info_kv "Target Home" "$HOME_DIR"

# ==================================
# Temp sudo without passwd
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

# ==============================================================================
# Helper Function for DBus/Dconf
# ==============================================================================
# 在脚本环境中运行 dconf 需要 dbus 会话
run_dconf() {
    sudo -u "$TARGET_USER" dbus-run-session sh -c "$1"
}

#=================================================
# Step 1: Install Base Packages
#=================================================
section "Step 1" "Install GNOME & Base Pkgs"
log "Installing packages..."

PKGS_LIST=(
    gnome-desktop gnome-backgrounds gnome-tweaks gdm ghostty 
    gnome-control-center gnome-software flatpak file-roller 
    nautilus-python firefox nm-connection-editor pacman-contrib 
    dnsmasq gnome-browser-connector
)

if exe as_user yay -S --noconfirm --needed --answerdiff=None --answerclean=None "${PKGS_LIST[@]}"; then
    log "Packages installed successfully."
else
    log "Installation failed."
    return 1
fi

# Enable GDM
log "Enabling GDM..."
exe systemctl enable gdm

#=================================================
# Step 2: Set Default Terminal
#=================================================
section "Step 2" "Set Default Terminal"
log "Setting Ghostty as default..."

# 使用 dbus-run-session 确保写入用户 dconf
run_dconf "gsettings set org.gnome.desktop.default-applications.terminal exec 'ghostty'"
run_dconf "gsettings set org.gnome.desktop.default-applications.terminal exec-arg '-e'"

#=================================================
# Step 3: Locale
#=================================================
section "Step 3" "Set Locale"
log "Configuring GNOME locale for $TARGET_USER..."
ACCOUNT_FILE="/var/lib/AccountsService/users/$TARGET_USER"
ACCOUNT_DIR=$(dirname "$ACCOUNT_FILE")

mkdir -p "$ACCOUNT_DIR"
cat > "$ACCOUNT_FILE" <<EOF
[User]
Languages=zh_CN.UTF-8
EOF
log "Locale config written to AccountsService."

#=================================================
# Step 4: Shortcuts (Dconf Load)
#=================================================
section "Step 4" "Configure Shortcuts"
log "Restoring shortcuts from dotfiles..."
GNOME_KEY_DIR="$SCRIPT_DIR/gnome-dotfiles/keybinds"

# 定义加载函数
restore_dconf_key() {
    local file="$1"
    local path="$2"
    if [ -f "$file" ]; then
        log "Loading $path..."
        # 管道传递给 dbus-run-session 中的 dconf load
        cat "$file" | sudo -u "$TARGET_USER" dbus-run-session dconf load "$path"
    else
        log "Warning: Config file not found: $file"
    fi
}

restore_dconf_key "$GNOME_KEY_DIR/org.gnome.desktop.wm.keybindings.conf" "/org/gnome/desktop/wm/keybindings/"
restore_dconf_key "$GNOME_KEY_DIR/org.gnome.settings-daemon.plugins.media-keys.conf" "/org/gnome/settings-daemon/plugins/media-keys/"
restore_dconf_key "$GNOME_KEY_DIR/org.gnome.shell.keybindings.conf" "/org/gnome/shell/keybindings/"

# 强制刷新
run_dconf "dconf update"

#=================================================
# Step 5: Extensions
#=================================================
section "Step 5" "Install & Enable Extensions"
log "Installing extensions tool..."

sudo -u "$TARGET_USER" yay -S --noconfirm --needed gnome-extensions-cli

# 移除了 rounded-window-corners (不兼容 GNOME 45+)
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
    "rounded-window-corners@fxgn"
)

log "Downloading extensions..."
sudo -u "$TARGET_USER" dbus-run-session gnome-extensions-cli install --no-enable-on-install "${EXTENSION_LIST[@]}"

#-编译 Schema ---
log "Compiling extension schemas..."
USER_EXT_DIR="/home/$TARGET_USER/.local/share/gnome-shell/extensions"

for ext_path in "$USER_EXT_DIR"/*; do
    if [ -d "$ext_path/schemas" ]; then
        log "Compiling schemas for $(basename "$ext_path")..."
        sudo -u "$TARGET_USER" glib-compile-schemas "$ext_path/schemas"
    fi
done

# --- 关键修复：写入 enabled-extensions ---
log "Enabling extensions via dconf..."
# 获取所有已安装扩展的 UUID 目录名，并格式化为 'uuid1', 'uuid2'
INSTALLED_UUIDS=$(ls -1 "$USER_EXT_DIR" | awk "{print \"'\"\$0\"'\"}" | paste -sd, -)

if [ -n "$INSTALLED_UUIDS" ]; then
    DCONF_ARRAY="[$INSTALLED_UUIDS]"
    log "Setting enabled-extensions to: $DCONF_ARRAY"
    run_dconf "gsettings set org.gnome.shell enabled-extensions \"$DCONF_ARRAY\""
else
    log "No extensions found in directory."
fi

#=================================================
# Step 6: Firefox Integration
#=================================================
section "Step 6" "Firefox Policies"
log "Configuring Firefox policies..."

POL_DIR="/etc/firefox/policies"
exe mkdir -p "$POL_DIR"

# 修复：移除了 Install 数组中最后一个元素的逗号
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
# Step 7: Input Method
#=================================================
section "Step 7" "Input Method Environment"
log "Configuring /etc/environment..."

if ! grep -q "fcitx" /etc/environment; then
    cat << EOT >> /etc/environment
XIM="fcitx"
GTK_IM_MODULE=fcitx
QT_IM_MODULE=fcitx
XMODIFIERS=@im=fcitx
XDG_CURRENT_DESKTOP=GNOME
EOT
    log "Environment variables appended."
else
    log "Fcitx configuration already exists."
fi

#=================================================
# Step 8: Dotfiles
#=================================================
section "Step 8" "Deploy Dotfiles"
log "Deploying config files..."

GNOME_DOTFILES_DIR="$SCRIPT_DIR/gnome-dotfiles"
DEST_CONFIG_DIR="$HOME_DIR/.config"

exe as_user mkdir -p "$DEST_CONFIG_DIR"

# 使用 cp -rfT 或 /. 确保正确复制目录内容
if [ -d "$GNOME_DOTFILES_DIR/.config" ]; then
    cp -rf "$GNOME_DOTFILES_DIR/.config/*" "$DEST_CONFIG_DIR/"
    
    # 修复权限：同时设置 User:Group
    chown -R "$TARGET_USER" "$DEST_CONFIG_DIR"
    log "Configs copied and permissions fixed."
else
    log "Warning: Dotfiles source dir not found."
fi

log "Installing shell tools..."
exe pacman -S --noconfirm --needed thefuck starship eza fish zoxide

log "==========================================="
log " Installation Complete! Please Reboot."
log "==========================================="