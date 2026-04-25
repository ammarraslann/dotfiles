#!/usr/bin/env bash
# =============================================================================
# bootstrap.sh — Ammar's Arch Linux Setup
#
# Base: fresh Arch Linux via archinstall (GRUB, BTRFS, with Snapper)
# CachyOS repos + kernel added on top of vanilla Arch.
# Run as normal user (not root). Requires internet.
#
# Usage: bash bootstrap.sh
# Logs all failures to ~/bootstrap-errors.log for manual follow-up.
# =============================================================================

# NO set -e — we catch errors per-step and log them, never abort entirely
set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

LOG_FILE="$HOME/bootstrap-errors.log"
echo "Bootstrap started: $(date)" >"$LOG_FILE"

log() { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
fail() {
  echo -e "${RED}[x]${NC} $1"
  echo "[FAILED] $1" >>"$LOG_FILE"
}
section() { echo -e "\n${BLUE}=====================================${NC}\n${CYAN}  $1\n${BLUE}=====================================${NC}"; }

# Safe run: logs failures but never exits the script
run() {
  if ! "$@"; then
    fail "Command failed: $*"
    return 1
  fi
  return 0
}

# =============================================================================
# CONFIGURATION — fill these before running
# =============================================================================

DOTFILES_REPO="https://github.com/ammarraslann/dotfiles"
WALLPAPERS_REPO="https://github.com/ammarraslann/wallpapers"

NAS_IP=""    # e.g. "192.168.1.100"
NAS_SHARE="" # SMB share name e.g. "media"
NAS_USER=""  # NAS username
NAS_MOUNT="/mnt/nas"

# =============================================================================
# PREFLIGHT
# =============================================================================

section "Preflight"

[[ $EUID -eq 0 ]] && {
  fail "Run as your normal user, not root."
  exit 1
}
ping -c 1 archlinux.org &>/dev/null || {
  fail "No internet connection."
  exit 1
}

USERNAME=$(whoami)
log "User: $USERNAME"
log "Internet: OK"

# Detect GPU — used to decide which drivers to install
GPU_VENDOR=""
if lspci 2>/dev/null | grep -qi nvidia; then
  GPU_VENDOR="nvidia"
  log "GPU detected: NVIDIA"
elif lspci 2>/dev/null | grep -qi "amd\|radeon\|advanced micro"; then
  GPU_VENDOR="amd"
  log "GPU detected: AMD"
else
  GPU_VENDOR="unknown"
  warn "GPU vendor not detected — skipping GPU driver install"
fi

# =============================================================================
# STEP 1 — Mirrors + system update
# =============================================================================

section "Mirrors + system update"

run sudo pacman -S --noconfirm --needed reflector rsync || true

# Reflector failure is non-fatal — mirrors may already be fine
if sudo reflector --country US --age 12 --protocol https --sort rate \
  --save /etc/pacman.d/mirrorlist 2>/dev/null; then
  log "Mirrors updated"
else
  warn "Reflector failed — using existing mirrors"
fi

run sudo pacman -Syu --noconfirm && log "System up to date" ||
  fail "System update failed — continuing anyway"

# =============================================================================
# STEP 2 — yay (AUR helper)
# =============================================================================

section "AUR helper (yay)"

if command -v yay &>/dev/null; then
  log "yay already present"
elif pacman -Si yay &>/dev/null 2>&1; then
  # yay is available in repos (CachyOS provides it)
  run sudo pacman -S --noconfirm --needed yay && log "yay installed from repo" ||
    fail "yay install from repo failed"
else
  # Fall back to building from AUR
  run sudo pacman -S --noconfirm --needed git base-devel || true
  if git clone https://aur.archlinux.org/yay.git /tmp/yay 2>/dev/null; then
    cd /tmp/yay && makepkg -si --noconfirm && cd ~ && log "yay built from AUR" ||
      fail "yay build from AUR failed"
  else
    fail "yay unavailable — AUR packages will be skipped"
  fi
fi

# =============================================================================
# STEP 3 — CachyOS repos + kernel
#
# The official script detects CPU instruction set and adds the right repo tier.
# If it fails (URL changed, network issue), we skip and stay on vanilla kernel.
# linux-lts = vanilla Arch fallback, always available regardless of CachyOS.
# =============================================================================

section "CachyOS repos + kernel"

CACHYOS_OK=false

if grep -q "\[cachyos\]" /etc/pacman.conf 2>/dev/null; then
  log "CachyOS repos already present"
  CACHYOS_OK=true
else
  log "Attempting to add CachyOS repos..."
  CACHYOS_SCRIPT_URL="https://mirror.cachyos.org/cachyos-repo.sh"

  if curl -fsSL --connect-timeout 10 "$CACHYOS_SCRIPT_URL" -o /tmp/cachyos-repo.sh 2>/dev/null; then
    if bash /tmp/cachyos-repo.sh; then
      sudo pacman -Sy &>/dev/null || true
      log "CachyOS repos added"
      CACHYOS_OK=true
    else
      fail "CachyOS repo script failed — staying on vanilla Arch kernel"
    fi
  else
    fail "CachyOS repo script URL unreachable — staying on vanilla Arch kernel"
    warn "Manual fix: visit https://cachyos.org/download/ for current install method"
  fi
fi

# Install kernels — only attempt cachyos kernel if repos are present
if [[ "$CACHYOS_OK" == true ]]; then
  run sudo pacman -S --noconfirm --needed \
    linux-cachyos linux-cachyos-headers &&
    log "CachyOS kernel installed" ||
    fail "CachyOS kernel install failed — staying on installed kernel"

  run sudo pacman -S --noconfirm --needed \
    cachyos-gaming-meta &&
    log "CachyOS gaming meta installed" ||
    fail "cachyos-gaming-meta failed — install manually after checking repo"
fi

# LTS kernel is always vanilla Arch — always attempt this
run sudo pacman -S --noconfirm --needed linux-lts linux-lts-headers &&
  log "LTS fallback kernel installed" ||
  fail "LTS kernel install failed"

# =============================================================================
# STEP 4 — Snapper + grub-btrfs (BTRFS snapshot restore points at boot)
#
# This gives you the macOS Time Machine-like boot menu.
# Snapper takes snapshots before/after every pacman transaction via snap-pac.
# grub-btrfs detects those snapshots and adds them to the GRUB boot menu.
# NOTE: Only useful if root filesystem is BTRFS. Skips gracefully on ext4.
# =============================================================================

section "BTRFS snapshots (Snapper + grub-btrfs)"

ROOT_FS=$(findmnt -n -o FSTYPE / 2>/dev/null || echo "unknown")

if [[ "$ROOT_FS" == "btrfs" ]]; then
  log "Root is BTRFS — setting up Snapper"

  run sudo pacman -S --noconfirm --needed snapper snap-pac &&
    log "Snapper installed" ||
    fail "Snapper install failed"

  # grub-btrfs from AUR — adds snapshots to GRUB menu automatically
  if command -v yay &>/dev/null; then
    run yay -S --noconfirm grub-btrfs &&
      log "grub-btrfs installed" ||
      fail "grub-btrfs install failed"
  else
    fail "yay unavailable — install grub-btrfs manually: yay -S grub-btrfs"
  fi

  # Create snapper config for root
  if ! snapper list-configs 2>/dev/null | grep -q "^root"; then
    run sudo snapper -c root create-config / &&
      log "Snapper root config created" ||
      fail "Snapper config failed — run: sudo snapper -c root create-config /"
  else
    log "Snapper root config already exists"
  fi

  # Enable grub-btrfs watcher so GRUB menu updates on new snapshots
  run sudo systemctl enable --now grub-btrfsd &&
    log "grub-btrfsd enabled" ||
    fail "grub-btrfsd enable failed"

  # Rebuild GRUB config to include existing snapshots
  run sudo grub-mkconfig -o /boot/grub/grub.cfg &&
    log "GRUB config rebuilt with snapshot entries" ||
    fail "grub-mkconfig failed"
else
  warn "Root filesystem is $ROOT_FS, not BTRFS — skipping Snapper setup"
  warn "To get snapshot restore points, reinstall with BTRFS root"
fi

# =============================================================================
# STEP 5 — GPU drivers (hardware-detected)
#
# NVIDIA: proprietary nvidia-dkms — required for 1660 Ti (Turing, no open support)
# AMD:    mesa + vulkan-radeon — open source, works out of the box
# Both:   script detects GPU at startup and installs accordingly
# Hardware-agnostic: if neither detected, skips drivers entirely
# =============================================================================

section "GPU drivers ($GPU_VENDOR)"

if [[ "$GPU_VENDOR" == "nvidia" ]]; then

  run sudo pacman -S --noconfirm --needed \
    nvidia-dkms nvidia-utils nvidia-settings lib32-nvidia-utils libva-nvidia-driver &&
    log "NVIDIA drivers installed" ||
    { fail "NVIDIA driver install failed — system may boot to black screen"; }

  # Add NVIDIA modules to initramfs
  # Handles both empty MODULES=() and already-populated MODULES=(something)
  CURRENT_MODULES=$(grep "^MODULES=" /etc/mkinitcpio.conf | sed 's/MODULES=(\(.*\))/\1/')
  if echo "$CURRENT_MODULES" | grep -q "nvidia"; then
    log "NVIDIA modules already in mkinitcpio.conf"
  else
    sudo sed -i "s/^MODULES=(\(.*\))/MODULES=(\1 nvidia nvidia_modeset nvidia_uvm nvidia_drm)/" \
      /etc/mkinitcpio.conf
    # Clean up double spaces if MODULES was empty
    sudo sed -i 's/MODULES=(  /MODULES=(/' /etc/mkinitcpio.conf
    run sudo mkinitcpio -P &&
      log "NVIDIA modules added to initramfs" ||
      fail "mkinitcpio rebuild failed — rerun manually: sudo mkinitcpio -P"
  fi

  # Pacman hook: rebuild DKMS module on kernel updates
  sudo mkdir -p /etc/pacman.d/hooks/
  cat >/tmp/nvidia-dkms.hook <<'EOF'
[Trigger]
Operation = Install
Operation = Upgrade
Operation = Remove
Type = Package
Target = linux
Target = linux-lts
Target = linux-cachyos

[Action]
Description = Rebuilding NVIDIA DKMS module...
When = PostTransaction
Exec = /usr/bin/mkinitcpio -P
EOF
  sudo mv /tmp/nvidia-dkms.hook /etc/pacman.d/hooks/nvidia-dkms.hook
  log "NVIDIA DKMS pacman hook installed"

  # Add cursor fix for NVIDIA Wayland
  if ! grep -q "no_hardware_cursors" ~/.config/hypr/config/input.conf 2>/dev/null; then
    warn "Add 'no_hardware_cursors = true' under cursor {} in input.conf for NVIDIA Wayland"
  fi

elif [[ "$GPU_VENDOR" == "amd" ]]; then

  run sudo pacman -S --noconfirm --needed \
    mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon libva-mesa-driver &&
    log "AMD drivers installed" ||
    fail "AMD driver install failed"

else
  warn "Unknown GPU — skipping driver install. Install manually."
fi

# =============================================================================
# STEP 6 — Hyprland ecosystem
# =============================================================================

section "Hyprland ecosystem"

run sudo pacman -S --noconfirm --needed \
  hyprland \
  hyprlock \
  xdg-desktop-portal-hyprland \
  xdg-desktop-portal-gtk \
  qt5-wayland \
  qt6-wayland \
  waybar \
  mako \
  wofi \
  imagemagick \
  wl-clipboard \
  cliphist \
  grim \
  slurp \
  jq \
  udiskie \
  network-manager-applet \
  hyprpolkitagent \
  swayidle \
  sddm &&
  log "Hyprland ecosystem installed" ||
  fail "Some Hyprland packages failed — check log"

# awww (renamed from swww) — try both names for compatibility
if pacman -Si awww &>/dev/null 2>&1; then
  run sudo pacman -S --noconfirm --needed awww &&
    log "awww (wallpaper daemon) installed" ||
    fail "awww install failed"
elif pacman -Si swww &>/dev/null 2>&1; then
  run sudo pacman -S --noconfirm --needed swww &&
    log "swww installed (awww not found)" ||
    fail "swww install failed"
  warn "Update autostart.conf: change awww-daemon to swww-daemon and awww to swww"
else
  fail "Neither awww nor swww found — install wallpaper daemon manually"
fi

# =============================================================================
# STEP 7 — Audio (PipeWire)
# =============================================================================

section "Audio (PipeWire)"

run sudo pacman -S --noconfirm --needed \
  pipewire pipewire-alsa pipewire-pulse pipewire-audio wireplumber pavucontrol playerctl &&
  log "PipeWire installed" ||
  fail "PipeWire install failed"

# User services — may fail if session not fully initialized, that's OK
systemctl --user enable pipewire pipewire-pulse wireplumber 2>/dev/null &&
  log "PipeWire services enabled" ||
  warn "PipeWire service enable failed — will start on next login"

# =============================================================================
# STEP 8 — OSD (SwayOSD)
# =============================================================================

section "OSD (SwayOSD)"

if command -v yay &>/dev/null; then
  run yay -S --noconfirm swayosd-git &&
    log "SwayOSD installed" ||
    fail "SwayOSD install failed — volume/brightness OSD won't show"

  sudo usermod -aG video "$USERNAME" 2>/dev/null || true

  systemctl --user enable swayosd-server 2>/dev/null &&
    log "SwayOSD server enabled" ||
    warn "SwayOSD server enable failed — will need manual start"
else
  fail "yay unavailable — skipping SwayOSD. Install manually: yay -S swayosd-git"
fi

# =============================================================================
# STEP 9 — Brightness control (DDC/CI for external monitor)
# =============================================================================

section "Brightness control"

run sudo pacman -S --noconfirm --needed brightnessctl ddcutil i2c-tools bc &&
  log "Brightness tools installed" ||
  fail "Brightness tools install failed"

sudo modprobe i2c-dev 2>/dev/null || true
echo "i2c-dev" | sudo tee /etc/modules-load.d/i2c-dev.conf >/dev/null
sudo groupadd -f i2c 2>/dev/null || true
sudo usermod -aG i2c "$USERNAME" 2>/dev/null || true

DDCUTIL_RULES="/usr/share/ddcutil/data/45-ddcutil-i2c.rules"
if [[ -f "$DDCUTIL_RULES" ]]; then
  sudo cp "$DDCUTIL_RULES" /etc/udev/rules.d/
  sudo udevadm control --reload-rules && sudo udevadm trigger
  log "DDC/CI udev rules installed"
else
  fail "ddcutil rules file not found at expected path — run: sudo cp \$(find /usr -name '45-ddcutil*') /etc/udev/rules.d/"
fi

# =============================================================================
# STEP 10 — Terminal + shell (zsh)
# =============================================================================

section "Terminal + shell"

run sudo pacman -S --noconfirm --needed \
  kitty zsh zsh-syntax-highlighting zsh-autosuggestions \
  zsh-history-substring-search starship neovim yazi \
  zoxide fzf ripgrep fd bat eza fastfetch &&
  log "Terminal tools installed" ||
  fail "Some terminal tools failed"

if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
  RUNZSH=no CHSH=no sh -c \
    "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" &&
    log "Oh-My-Zsh installed" ||
    fail "Oh-My-Zsh install failed"
else
  log "Oh-My-Zsh already installed"
fi

if [[ "$SHELL" != "$(which zsh)" ]]; then
  chsh -s "$(which zsh)" &&
    log "Default shell set to zsh" ||
    fail "chsh failed — run manually: chsh -s \$(which zsh)"
fi

# =============================================================================
# STEP 11 — Applications
# =============================================================================

section "Applications"

run sudo pacman -S --noconfirm --needed \
  firefox \
  dolphin dolphin-plugins ffmpegthumbs kdegraphics-thumbnailers kio-extras \
  samba \
  vscodium \
  remmina freerdp \
  kdeconnect \
  ydotoold \
  mpv imv \
  file-roller \
  btop &&
  log "Core applications installed" ||
  fail "Some applications failed to install"

if command -v yay &>/dev/null; then
  run yay -S --noconfirm \
    mullvad-vpn \
    globalprotect-openconnect \
    arch-update \
    zotero-bin \
    bibata-cursor-theme \
    where-is-my-sddm-theme-git &&
    log "AUR packages installed" ||
    fail "Some AUR packages failed — check log and install manually"

  systemctl --user enable --now arch-update.timer 2>/dev/null ||
    warn "arch-update timer failed — run: systemctl --user enable arch-update.timer"
else
  fail "yay unavailable — AUR packages skipped: mullvad, globalprotect, arch-update, zotero, bibata-cursor, sddm-theme"
fi

# =============================================================================
# STEP 12 — Fonts
# =============================================================================

section "Fonts"

run sudo pacman -S --noconfirm --needed \
  ttf-iosevka-nerd ttf-jetbrains-mono-nerd \
  noto-fonts noto-fonts-emoji ttf-font-awesome &&
  log "Fonts installed" ||
  fail "Font install failed"

# =============================================================================
# STEP 13 — GTK + Qt theming
# =============================================================================

section "GTK + Qt theming"

run sudo pacman -S --noconfirm --needed \
  nwg-look qt5ct qt6ct kvantum adw-gtk3 papirus-icon-theme papirus-folders &&
  log "Theming tools installed" ||
  fail "Theming tools install failed"

papirus-folders -C brown --theme Papirus-Dark 2>/dev/null &&
  log "Papirus folders recolored" ||
  warn "papirus-folders color failed — run manually: papirus-folders -C brown --theme Papirus-Dark"

mkdir -p ~/.config/environment.d/
cat >~/.config/environment.d/qt-theme.conf <<'EOF'
QT_QPA_PLATFORMTHEME=qt5ct
QT_AUTO_SCREEN_SCALE_FACTOR=1
EOF

# =============================================================================
# STEP 14 — SDDM
# =============================================================================

section "SDDM"

sudo mkdir -p /etc/sddm.conf.d/

# Use where-is-my-sddm-theme if available, else fall back gracefully
if pacman -Qi where-is-my-sddm-theme-git &>/dev/null 2>&1; then
  printf '[Theme]\nCurrent=where_is_my_sddm_theme\n' |
    sudo tee /etc/sddm.conf.d/theme.conf >/dev/null
  log "SDDM configured with where-is-my-sddm-theme"
else
  printf '[Theme]\nCurrent=\n' |
    sudo tee /etc/sddm.conf.d/theme.conf >/dev/null
  warn "SDDM theme not set — using default. Install: yay -S where-is-my-sddm-theme-git"
fi

run sudo systemctl enable sddm &&
  log "SDDM enabled" ||
  fail "SDDM enable failed"

# =============================================================================
# STEP 15 — System services
# =============================================================================

section "System services"

run sudo systemctl enable NetworkManager &&
  log "NetworkManager enabled" ||
  fail "NetworkManager enable failed"

sudo systemctl enable bluetooth 2>/dev/null &&
  log "Bluetooth enabled" ||
  warn "Bluetooth not available — skipping"

# =============================================================================
# STEP 16 — Dotfiles
# =============================================================================

section "Dotfiles"

DOTFILES_DIR="/tmp/dotfiles-bootstrap"
rm -rf "$DOTFILES_DIR" 2>/dev/null || true

if git clone --depth=1 "$DOTFILES_REPO" "$DOTFILES_DIR"; then
  log "Dotfiles cloned"
else
  fail "Dotfiles clone failed — check internet connection"
fi

if [[ -d "$DOTFILES_DIR" ]]; then
  for conf in hypr waybar kitty nvim wofi mako yazi btop kdeconnect \
    wireplumber environment.d VSCodium; do
    if [[ -d "$DOTFILES_DIR/.config/$conf" ]]; then
      mkdir -p ~/.config/"$conf"
      cp -r "$DOTFILES_DIR/.config/$conf/." ~/.config/"$conf"/
      log "  Restored: ~/.config/$conf"
    fi
  done

  for f in gtk3-settings.ini gtk4-settings.ini kdeglobals mimeapps.list; do
    [[ -f "$DOTFILES_DIR/.config/$f" ]] &&
      cp "$DOTFILES_DIR/.config/$f" ~/.config/ &&
      log "  Restored: $f"
  done

  [[ -d "$DOTFILES_DIR/.local/bin" ]] && {
    mkdir -p ~/.local/bin
    cp -r "$DOTFILES_DIR/.local/bin/." ~/.local/bin/
    chmod +x ~/.local/bin/* 2>/dev/null || true
    log "  Restored: ~/.local/bin"
  }

  for share in applications icons mime sddm; do
    [[ -d "$DOTFILES_DIR/.local/share/$share" ]] && {
      mkdir -p ~/.local/share/"$share"
      cp -r "$DOTFILES_DIR/.local/share/$share/." ~/.local/share/"$share"/
      log "  Restored: ~/.local/share/$share"
    }
  done

  [[ -d "$DOTFILES_DIR/.icons" ]] && {
    mkdir -p ~/.icons
    cp -r "$DOTFILES_DIR/.icons/." ~/.icons/
    log "  Restored: ~/.icons"
  }

  [[ -f "$DOTFILES_DIR/.zshrc" ]] && cp "$DOTFILES_DIR/.zshrc" ~/ && log "  Restored: .zshrc"
  [[ -f "$DOTFILES_DIR/.zshenv" ]] && cp "$DOTFILES_DIR/.zshenv" ~/ && log "  Restored: .zshenv"

  if [[ -f "$DOTFILES_DIR/.mozilla/firefox/user.js" ]]; then
    FIREFOX_PROFILE=$(find ~/.mozilla/firefox -maxdepth 1 \
      \( -name "*.default-release" -o -name "*.default" \) 2>/dev/null | head -1)
    if [[ -n "$FIREFOX_PROFILE" ]]; then
      cp "$DOTFILES_DIR/.mozilla/firefox/user.js" "$FIREFOX_PROFILE/"
      log "  Firefox user.js applied"
    else
      mkdir -p ~/.mozilla/firefox
      cp "$DOTFILES_DIR/.mozilla/firefox/user.js" ~/.mozilla/firefox/
      warn "  Firefox not launched yet — user.js saved, will apply on first run"
    fi
  fi

  [[ -d "$DOTFILES_DIR/.ssh" ]] && {
    cp -r "$DOTFILES_DIR/.ssh" ~/
    chmod 700 ~/.ssh
    chmod 600 ~/.ssh/id_* 2>/dev/null || true
    log "  Restored: SSH keys"
  }
fi

# =============================================================================
# STEP 17 — Wallpapers
# =============================================================================

section "Wallpapers"

mkdir -p ~/Pictures/wallpapers ~/Pictures/Screenshots

if [[ -n "$WALLPAPERS_REPO" ]]; then
  if git clone --depth=1 "$WALLPAPERS_REPO" /tmp/wallpapers-bootstrap 2>/dev/null; then
    find /tmp/wallpapers-bootstrap -type f \
      \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \
      -o -iname "*.webp" -o -iname "*.gif" \) \
      -exec cp {} ~/Pictures/wallpapers/ \;
    log "Wallpapers copied"
  else
    fail "Wallpapers clone failed — add manually to ~/Pictures/wallpapers/"
  fi
fi

# =============================================================================
# STEP 18 — NAS automount
# =============================================================================

section "NAS automount"

if [[ -n "$NAS_IP" && -n "$NAS_SHARE" && -n "$NAS_USER" ]]; then
  sudo mkdir -p "$NAS_MOUNT"

  if ! grep -q "$NAS_IP/$NAS_SHARE" /etc/fstab 2>/dev/null; then
    echo "//$NAS_IP/$NAS_SHARE  $NAS_MOUNT  cifs  noauto,x-systemd.automount,x-systemd.idle-timeout=300,_netdev,credentials=/etc/nas-credentials,uid=$(id -u),gid=$(id -g),iocharset=utf8  0  0" |
      sudo tee -a /etc/fstab >/dev/null
    log "NAS fstab entry added"
  else
    log "NAS already in fstab"
  fi

  if [[ ! -f /etc/nas-credentials ]]; then
    printf 'username=%s\npassword=CHANGE_ME\n' "$NAS_USER" |
      sudo tee /etc/nas-credentials >/dev/null
    sudo chmod 600 /etc/nas-credentials
    warn "Edit /etc/nas-credentials with your real NAS password"
  fi

  sudo systemctl daemon-reload 2>/dev/null || true
  log "NAS configured"
else
  warn "NAS vars not set — skipping"
fi

# =============================================================================
# STEP 19 — Dual-boot clock fix
# =============================================================================

section "Dual-boot clock fix"

sudo timedatectl set-local-rtc 1 --adjust-system-clock 2>/dev/null &&
  log "RTC set to local time" ||
  warn "timedatectl failed — run manually if dual booting Windows"

# =============================================================================
# STEP 20 — Orphan cleanup
# =============================================================================

section "Cleanup"

ORPHANS=$(pacman -Qdtq 2>/dev/null || true)
if [[ -n "$ORPHANS" ]]; then
  sudo pacman -Rns $ORPHANS --noconfirm 2>/dev/null &&
    log "Orphans removed" ||
    warn "Orphan removal failed — run manually: sudo pacman -Rns \$(pacman -Qdtq)"
else
  log "No orphans found"
fi

# =============================================================================
# DONE
# =============================================================================

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Bootstrap complete.${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""

# Show error summary if anything failed
if grep -q "\[FAILED\]" "$LOG_FILE" 2>/dev/null; then
  echo -e "${RED}The following steps failed and need manual attention:${NC}"
  grep "\[FAILED\]" "$LOG_FILE"
  echo ""
  echo "Full log: $LOG_FILE"
  echo ""
else
  echo -e "${GREEN}No failures logged.${NC}"
  echo ""
fi

echo "After reboot — do these in order:"
echo "  1. hyprctl monitors → fill in monitor names in monitor.conf"
echo "  2. ddcutil detect → verify LG DDC/CI (enable in monitor OSD if not found)"
echo "  3. nwg-look → GTK theme: adw-gtk3-dark, icons: Papirus-Dark, cursor: Bibata"
echo "  4. kvantum-manager + qt5ct → Qt theme"
echo "  5. sudo nvim /etc/nas-credentials → set real NAS password"
echo "  6. Firefox → sign into Firefox Sync"
echo "  7. mullvad account login YOUR_ACCOUNT_NUMBER"
echo ""
echo -e "${YELLOW}Groups (video, i2c) require full reboot: sudo reboot${NC}"
