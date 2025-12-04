#!/bin/bash

# ==============================================================================
# 99-apps.sh - Common Applications (Batch Install + No Retry + Failure Log)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/00-utils.sh"

check_root

trap 'echo -e "\n   ${H_YELLOW}>>> Operation cancelled by user (Ctrl+C). Skipping...${NC}"' INT

# ------------------------------------------------------------------------------
# 0. Identify Target User
# ------------------------------------------------------------------------------
section "Phase 5" "Common Applications"

log "Identifying target user..."
DETECTED_USER=$(awk -F: '$3 == 1000 {print $1}' /etc/passwd)

if [ -n "$DETECTED_USER" ]; then
    TARGET_USER="$DETECTED_USER"
else
    read -p "   Please enter the target username: " TARGET_USER
fi
HOME_DIR="/home/$TARGET_USER"
info_kv "Target" "$TARGET_USER"

# ------------------------------------------------------------------------------
# 1. List Selection & Confirmation
# ------------------------------------------------------------------------------
if [ "$DESKTOP_ENV" == "kde" ]; then
    LIST_FILENAME="kde-common-applist.txt"
else
    LIST_FILENAME="common-applist.txt"
fi

echo ""
echo -e "   Selected List: ${BOLD}$LIST_FILENAME${NC} (Based on $DESKTOP_ENV)"
echo -e "   Format: ${DIM}lines starting with 'flatpak:' use Flatpak, others use Yay.${NC}"
echo -e "   ${H_YELLOW}Tip: Press Ctrl+C to cancel current operation.${NC}"
echo ""

read -t 60 -p "$(echo -e "   ${H_CYAN}Install these applications? [Y/n] (Default Y in 60s): ${NC}")" choice
if [ $? -ne 0 ]; then echo ""; fi

choice=${choice:-Y}

if [[ ! "$choice" =~ ^[Yy]$ ]]; then
    log "Skipping application installation."
    trap - INT
    exit 0
fi

# ------------------------------------------------------------------------------
# 2. Parse App List
# ------------------------------------------------------------------------------
log "Parsing application list..."

LIST_FILE="$PARENT_DIR/$LIST_FILENAME"
YAY_APPS=()
FLATPAK_APPS=()
FAILED_PACKAGES=()

if [ -f "$LIST_FILE" ]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
        line=$(echo "$line" | tr -d '\r' | xargs)
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        
        if [[ "$line" == flatpak:* ]]; then
            app_id="${line#flatpak:}"
            FLATPAK_APPS+=("$app_id")
        else
            YAY_APPS+=("$line")
        fi
    done < "$LIST_FILE"
    
    info_kv "Queue" "Yay: ${#YAY_APPS[@]}" "Flatpak: ${#FLATPAK_APPS[@]}"
else
    warn "File $LIST_FILENAME not found. Skipping."
    trap - INT
    exit 0
fi

# ------------------------------------------------------------------------------
# 3. Install Applications (Batch Mode)
# ------------------------------------------------------------------------------

# --- A. Install Yay Apps ---
if [ ${#YAY_APPS[@]} -gt 0 ]; then
    section "Step 1/2" "System Packages (Yay)"
    
    # Configure NOPASSWD for seamless batch install
    SUDO_TEMP_FILE="/etc/sudoers.d/99_shorin_installer_apps"
    echo "$TARGET_USER ALL=(ALL) NOPASSWD: ALL" > "$SUDO_TEMP_FILE"
    chmod 440 "$SUDO_TEMP_FILE"
    
    BATCH_LIST="${YAY_APPS[*]}"
    log "Executing batch install for Yay packages..."
    
    # Try Batch Install First
    if exe runuser -u "$TARGET_USER" -- yay -Syu --noconfirm --needed --answerdiff=None --answerclean=None $BATCH_LIST; then
        success "Yay batch install successful."
    else
        warn "Batch install encountered issues. Attempting to install remaining packages individually..."
        
        # Fallback: Install individually to catch failures (NO RETRY on individual fail)
        for pkg in "${YAY_APPS[@]}"; do
            # Check if installed first to save time
            if ! pacman -Qi "$pkg" &>/dev/null; then
                log "Installing '$pkg'..."
                if ! exe runuser -u "$TARGET_USER" -- yay -Syu --noconfirm --needed --answerdiff=None --answerclean=None "$pkg"; then
                    ret=$?
                    if [ $ret -eq 130 ]; then
                        warn "Skipped '$pkg' (User Cancelled)."
                    else
                        error "Failed to install: $pkg"
                        FAILED_PACKAGES+=("yay:$pkg")
                    fi
                else
                    success "Installed $pkg"
                fi
            else
                log "Package '$pkg' is already installed."
            fi
        done
    fi
    
    rm -f "$SUDO_TEMP_FILE"
fi

# --- B. Install Flatpak Apps ---
if [ ${#FLATPAK_APPS[@]} -gt 0 ]; then
    section "Step 2/2" "Flatpak Packages"
    
    log "Executing batch install for Flatpak packages..."
    
    # Convert array to space-separated string for batch command
    FLATPAK_BATCH_LIST="${FLATPAK_APPS[*]}"
    
    # Execute Batch Install
    # -y: non-interactive yes
    if exe flatpak install -y flathub $FLATPAK_BATCH_LIST; then
        success "Flatpak batch install successful."
    else
        warn "Flatpak batch install returned error. Checking for failed packages..."
        
        # Check which ones failed
        for app in "${FLATPAK_APPS[@]}"; do
            if ! flatpak list --app --columns=application | grep -q "^$app$"; then
                # Double check installation individually if batch failed (Optional, or just mark as failed)
                # To strictly follow "no retry", we just mark it as failed if it's not present.
                # However, usually batch fail means some installed, some didn't. 
                # Let's try to install the missing ones ONCE individually to be sure it's a real failure 
                # and not just a side effect of another package failing the batch transaction.
                
                log "Retrying individual install for missed app: $app"
                if ! exe flatpak install -y flathub "$app"; then
                     ret=$?
                     if [ $ret -eq 130 ]; then
                         warn "Skipped '$app' (User Cancelled)."
                     else
                         error "Failed to install: $app"
                         FAILED_PACKAGES+=("flatpak:$app")
                     fi
                else
                     success "Installed $app"
                fi
            fi
        done
    fi
fi

# ------------------------------------------------------------------------------
# 3.5 Generate Failure Report
# ------------------------------------------------------------------------------
if [ ${#FAILED_PACKAGES[@]} -gt 0 ]; then
    DOCS_DIR="$HOME_DIR/Documents"
    REPORT_FILE="$DOCS_DIR/安装失败的软件.txt"
    
    if [ ! -d "$DOCS_DIR" ]; then runuser -u "$TARGET_USER" -- mkdir -p "$DOCS_DIR"; fi
    
    # Append to report
    echo -e "\n--- Phase 5 (Common Apps - $DESKTOP_ENV) Failures [$(date)] ---" >> "$REPORT_FILE"
    printf "%s\n" "${FAILED_PACKAGES[@]}" >> "$REPORT_FILE"
    chown "$TARGET_USER:$TARGET_USER" "$REPORT_FILE"
    
    warn "Some applications failed to install. List saved to:"
    echo -e "   ${BOLD}$REPORT_FILE${NC}"
else
    success "All applications installed successfully."
fi

# ------------------------------------------------------------------------------
# 4. Steam Locale Fix
# ------------------------------------------------------------------------------
section "Post-Install" "Game Environment Tweaks"

STEAM_desktop_modified=false

# Method 1: Native Steam
NATIVE_DESKTOP="/usr/share/applications/steam.desktop"
if [ -f "$NATIVE_DESKTOP" ]; then
    log "Checking Native Steam..."
    if ! grep -q "env LANG=zh_CN.UTF-8" "$NATIVE_DESKTOP"; then
        exe sed -i 's|^Exec=/usr/bin/steam|Exec=env LANG=zh_CN.UTF-8 /usr/bin/steam|' "$NATIVE_DESKTOP"
        exe sed -i 's|^Exec=steam|Exec=env LANG=zh_CN.UTF-8 steam|' "$NATIVE_DESKTOP"
        success "Patched Native Steam .desktop."
        STEAM_desktop_modified=true
    else
        log "Native Steam already patched."
    fi
fi

# Method 2: Flatpak Steam
# Re-check installed flatpaks to see if Steam is present
if flatpak list | grep -q "com.valvesoftware.Steam"; then
    log "Checking Flatpak Steam..."
    exe flatpak override --env=LANG=zh_CN.UTF-8 com.valvesoftware.Steam
    success "Applied Flatpak Steam override."
    STEAM_desktop_modified=true
fi

if [ "$STEAM_desktop_modified" = false ]; then
    log "Steam not found or already configured. Skipping fix."
fi

# Reset Trap
trap - INT

log "Module 99-apps completed."