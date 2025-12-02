#!/bin/bash

# ==============================================================================
# 07-grub-theme.sh - GRUB Bootloader Theming (Visual Enhanced & Optional)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/00-utils.sh"

check_root

section "Phase 7" "GRUB Theme Customization"

# ------------------------------------------------------------------------------
# 1. Detect Theme
# ------------------------------------------------------------------------------
log "Detecting theme in 'grub-themes' folder..."

SOURCE_BASE="$PARENT_DIR/grub-themes"
DEST_DIR="/boot/grub/themes"

# Case 1: Repo folder missing
if [ ! -d "$SOURCE_BASE" ]; then
    warn "Directory 'grub-themes' not found in repo."
    warn "Skipping GRUB theme installation (Optional)."
    exit 0
fi

# Case 2: Find first directory
THEME_SOURCE=$(find "$SOURCE_BASE" -mindepth 1 -maxdepth 1 -type d | head -n 1)

if [ -z "$THEME_SOURCE" ]; then
    warn "No theme folder found inside 'grub-themes/'."
    log "Skipping GRUB theme installation."
    exit 0
fi

THEME_NAME=$(basename "$THEME_SOURCE")
info_kv "Detected" "$THEME_NAME"

# Case 3: Verify structure
if [ ! -f "$THEME_SOURCE/theme.txt" ]; then
    error "Invalid theme: 'theme.txt' not found in '$THEME_NAME'."
    warn "Skipping to prevent GRUB errors."
    exit 0
fi

# ------------------------------------------------------------------------------
# 2. Install Theme Files
# ------------------------------------------------------------------------------
log "Installing theme files..."

# Ensure destination exists
if [ ! -d "$DEST_DIR" ]; then
    exe mkdir -p "$DEST_DIR"
fi

# Clean install: Remove old if exists
if [ -d "$DEST_DIR/$THEME_NAME" ]; then
    log "Removing existing version..."
    exe rm -rf "$DEST_DIR/$THEME_NAME"
fi

# Copy
exe cp -r "$THEME_SOURCE" "$DEST_DIR/"

if [ -f "$DEST_DIR/$THEME_NAME/theme.txt" ]; then
    success "Theme installed to $DEST_DIR/$THEME_NAME"
else
    error "Failed to copy theme files."
    exit 1
fi

# ------------------------------------------------------------------------------
# 3. Configure /etc/default/grub
# ------------------------------------------------------------------------------
log "Configuring GRUB settings..."

GRUB_CONF="/etc/default/grub"
THEME_PATH="$DEST_DIR/$THEME_NAME/theme.txt"

if [ -f "$GRUB_CONF" ]; then
    # Update or Append GRUB_THEME
    if grep -q "^GRUB_THEME=" "$GRUB_CONF"; then
        log "Updating existing GRUB_THEME entry..."
        # Use # delimiter to avoid path clashes
        exe sed -i "s|^GRUB_THEME=.*|GRUB_THEME=\"$THEME_PATH\"|" "$GRUB_CONF"
    else
        log "Adding GRUB_THEME entry..."
        echo "GRUB_THEME=\"$THEME_PATH\"" >> "$GRUB_CONF"
        success "Entry appended."
    fi
    
    # Enable graphical output (Comment out console output)
    if grep -q "^GRUB_TERMINAL_OUTPUT=\"console\"" "$GRUB_CONF"; then
        log "Enabling graphical terminal..."
        exe sed -i 's/^GRUB_TERMINAL_OUTPUT="console"/#GRUB_TERMINAL_OUTPUT="console"/' "$GRUB_CONF"
    fi
    
    # Ensure GFXMODE is Auto
    if ! grep -q "^GRUB_GFXMODE=" "$GRUB_CONF"; then
        echo 'GRUB_GFXMODE=auto' >> "$GRUB_CONF"
    fi
    
    success "Configuration updated."
else
    error "$GRUB_CONF not found."
    exit 1
fi

# ------------------------------------------------------------------------------
# 4. Apply Changes
# ------------------------------------------------------------------------------
log "Generating new GRUB configuration..."

# /boot/grub link fix was handled in 02-musthave.sh, safe to use standard path
if exe grub-mkconfig -o /boot/grub/grub.cfg; then
    success "GRUB updated successfully."
else
    error "Failed to update GRUB."
    warn "You may need to run 'grub-mkconfig' manually."
fi

log "Module 07 completed."