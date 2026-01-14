#!/bin/bash
# 04e-illogical-impulse-end4-quickshell.sh

# 1. 引用工具库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
if [ -f "$SCRIPT_DIR/00-utils.sh" ]; then
    source "$SCRIPT_DIR/00-utils.sh"
else
    echo "Error: 00-utils.sh not found."
    exit 1
fi
log "installing Illogical Impulse End4 (Quickshell)..."

# ==============================================================================
#  Identify User & DM Check
# ==============================================================================
log "Identifying user..."
DETECTED_USER=$(awk -F: '$3 == 1000 {print $1}' /etc/passwd)
TARGET_USER="${DETECTED_USER:-$(read -p "Target user: " u && echo $u)}"
HOME_DIR="/home/$TARGET_USER"
info_kv "Target" "$TARGET_USER"

# DM Check
KNOWN_DMS=("gdm" "sddm" "lightdm" "lxdm" "slim" "xorg-xdm" "ly" "greetd")
SKIP_AUTOLOGIN=false
DM_FOUND=""
for dm in "${KNOWN_DMS[@]}"; do
  if pacman -Q "$dm" &>/dev/null; then
    DM_FOUND="$dm"
    break
  fi
done

if [ -n "$DM_FOUND" ]; then
  info_kv "Conflict" "${H_RED}$DM_FOUND${NC}"
  SKIP_AUTOLOGIN=true
else
  read -t 20 -p "$(echo -e "   ${H_CYAN}Enable TTY auto-login? [Y/n] (Default Y): ${NC}")" choice || true
  [[ "${choice:-Y}" =~ ^[Yy]$ ]] && SKIP_AUTOLOGIN=false || SKIP_AUTOLOGIN=true
fi

log "Target user for End4 installation: $TARGET_USER"

# 下载并执行安装脚本
INSTALLER_SCRIPT="/tmp/end4_install.sh"
II_URL="https://ii.clsty.link/get"

log "Downloading Illogical Impulse installer wrapper..."
if curl -fsSL "$II_URL" -o "$INSTALLER_SCRIPT"; then
    
    chmod +x "$INSTALLER_SCRIPT"
    chown "$TARGET_USER" "$INSTALLER_SCRIPT"

    log "Executing End4 installer as user ($TARGET_USER)..."
    log "NOTE: If the installer asks for input, this script might hang."
    
    if runuser -u "$TARGET_USER" -- bash -c "cd ~ && $INSTALLER_SCRIPT"; then
        success "Illogical Impulse End4 installed successfully."
    else
        # 安装失败不应该导致整个系统安装退出，所以只警告
        warn "End4 installer returned an error code. You may need to install it manually."
    fi
    rm -f "$INSTALLER_SCRIPT"
else
    warn "Failed to download installer script from $II_URL."
fi

# ==============================================================================
#  autologin
# ==============================================================================
section "Config" "autostart"

SVC_DIR="$HOME_DIR/.config/systemd/user"
SVC_FILE="$SVC_DIR/end4-autostart.service"
LINK="$SVC_DIR/default.target.wants/end4-autostart.service"

# 确保目录存在
as_user mkdir -p "$SVC_DIR/default.target.wants"

# tty自动登录
if [ "$SKIP_AUTOLOGIN" = false ]; then

    log "Configuring TTY Auto-login..."
    
    # 1. 配置 TTY 自动登录
    mkdir -p "/etc/systemd/system/getty@tty1.service.d"
    echo -e "[Service]\nExecStart=\nExecStart=-/sbin/agetty --noreset --noclear --autologin $TARGET_USER - \${TERM}" >"/etc/systemd/system/getty@tty1.service.d/autologin.conf"
fi

if [ "$SKIP_AUTOLOGIN" = false ] && command -v hyprland &>/dev/null; then

    cat <<EOT >"$SVC_FILE"
[Unit]
Description=Hyprland End4 Session Autostart
After=graphical-session-pre.target
StartLimitIntervalSec=60
StartLimitBurst=3
[Service]
ExecStart=/usr/bin/start-hyprland
Restart=on-failure
RestartSec=2
Environment=XDG_CURRENT_DESKTOP=hyprland
Environment=XDG_SESSION_TYPE=wayland

[Install]
WantedBy=default.target

EOT
    # 启用服务
    as_user ln -sf "$SVC_FILE" "$LINK"
    # 确保权限
    chown -R "$TARGET_USER" "$SVC_DIR"
    success "Hyprland End4 auto-start enabled."

fi

log "Module 04e (End4) completed."