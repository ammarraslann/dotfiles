#!/usr/bin/env bash
# =============================================================================
# bootstrap.sh — Ammar's Arch Linux Setup
#
# Base: fresh Arch Linux via archinstall (Hyprland profile, Limine, BTRFS)
# CachyOS repos + kernel added on top of vanilla Arch.
# Run as normal user (not root). Requires internet.
#
# Usage: bash bootstrap.sh
# =============================================================================

set -e
set -u

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

log()     { echo -e "${GREEN}[+]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
error()   { echo -e "${RED}[x]${NC} $1"; exit 1; }
section() { echo -e "\n${BLUE}=====================================${NC}\n${CYAN}  $1\n${BLUE}=====================================${NC}"; }

# =============================================================================
# CONFIGURATION — fill these before running
# =============================================================================

DOTFILES_REPO="https://github.com/ammarraslann/dotfiles"
WALLPAPERS_REPO="https://github.com/ammarraslann/wallpapers"

NAS_IP=""            # e.g. "192.168.1.100"
NAS_SHARE=""         # SMB share name e.g. "media"
NAS_USER=""          # NAS username
NAS_MOUNT="/mnt/nas"

# =============================================================================
# PREFLIGHT
# =============================================================================

section "Preflight"

[[ $EUID -eq 0 ]] && error "Run as your normal user, not root."
ping -c 1 archlinux.org &>/dev/null || error "No internet connection."

USERNAME=$(whoami)
log "User: $USERNAME"
log "Internet: OK"

# =============================================================================
# STEP 1 — Mirrors + system update
# =============================================================================

section "Mirrors + system update"

sudo pacman -S --noconfirm --needed reflector rsync
sudo reflector --country US --age 12 --protocol https --sort rate \
  --save /etc/pacman.d/mirrorlist
sudo pacman -Syu --noconfirm
log "System up to date"

# =============================================================================
# STEP 2 — yay (AUR helper)
# =============================================================================

section "AUR helper (yay)"

if ! command -v yay &>/dev/null; then
  sudo pacman -S --noconfirm --needed git base-devel
  git clone https://aur.archlinux.org/yay.git /tmp/yay
  cd /tmp/yay && makepkg -si --noconfirm
  cd ~
  log "yay installed"
else
  log "yay already present"
fi

# =============================================================================
# STEP 3 — CachyOS repos + kernel
#
# Official CachyOS script detects CPU instruction set and adds the right repos.
# Result: vanilla Arch + CachyOS-optimized kernel.
# linux-lts = plain vanilla Arch LTS kernel — boring, stable, fallback only.
# =============================================================================

section "CachyOS repos + kernel"

if ! grep -q "\[cachyos\]" /etc/pacman.conf; then
  log "Adding CachyOS repos..."
  curl -fsSL https://mirror.cachyos.org/cachyos-repo.sh -o /tmp/cachyos-repo.sh
  bash /tmp/cachyos-repo.sh
  sudo pacman -Sy
  log "CachyOS repos added"
else
  log "CachyOS repos already present"
fi

sudo pacman -S --noconfirm --needed \
  linux-cachyos \
  linux-cachyos-headers \
  linux-lts \
  linux-lts-headers \
  cachyos-gaming-meta

log "Kernels installed (cachyos = main, lts = fallback)"
warn "Add both kernels as Limine entries after first boot"

# =============================================================================
# STEP 4 — NVIDIA drivers (1660 Ti)
#
# nvidia-dkms rebuilds for every kernel automatically via pacman hook below.
# nvidia-open does NOT support Turing (1660 Ti) — proprietary only.
# =============================================================================

section "NVIDIA drivers (1660 Ti)"

sudo pacman -S --noconfirm --needed \
  nvidia-dkms \
  nvidia-utils \
  nvidia-settings \
  lib32-nvidia-utils \
  libva-nvidia-driver

# Add nvidia modules to initramfs — prevents black screen on boot
sudo sed -i 's/^MODULES=(\(.*\))/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' \
  /etc/mkinitcpio.conf
sudo mkinitcpio -P
log "NVIDIA modules added to initramfs"

# Pacman hook: auto-rebuild nvidia-dkms on every kernel update
sudo mkdir -p /etc/pacman.d/hooks/
cat > /tmp/nvidia-dkms.hook << 'EOF'
[Trigger]
Operation = Install
Operation = Upgrade
Operation = Remove
Type = Package
Target = linux-cachyos
Target = linux-lts

[Action]
Description = Rebuilding NVIDIA DKMS module...
When = PostTransaction
Exec = /usr/bin/mkinitcpio -P
EOF
sudo mv /tmp/nvidia-dkms.hook /etc/pacman.d/hooks/nvidia-dkms.hook
log "NVIDIA DKMS pacman hook installed"

# =============================================================================
# STEP 5 — Hyprland ecosystem
# =============================================================================

section "Hyprland ecosystem"

sudo pacman -S --noconfirm --needed \
  hyprland \
  hyprlock \
  xdg-desktop-portal-hyprland \
  xdg-desktop-portal-gtk \
  qt5-wayland \
  qt6-wayland \
  waybar \
  mako \
  wofi \
  awww \
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
  sddm

log "Hyprland ecosystem installed"

# =============================================================================
# STEP 6 — Audio (PipeWire + WirePlumber)
#
# WirePlumber fix (auto-move streams on sink change) lives in dotfiles at:
# .config/wireplumber/wireplumber.conf.d/51-follow-default.conf
# Restored from dotfiles in step 11.
# =============================================================================

section "Audio (PipeWire)"

sudo pacman -S --noconfirm --needed \
  pipewire \
  pipewire-alsa \
  pipewire-pulse \
  pipewire-audio \
  wireplumber \
  pavucontrol \
  playerctl

systemctl --user enable --now pipewire pipewire-pulse wireplumber
log "PipeWire services enabled"

# =============================================================================
# STEP 7 — OSD (SwayOSD)
#
# Handles volume + brightness on-screen display.
# Shows on focused monitor in multi-monitor setups.
# =============================================================================

section "OSD (SwayOSD)"

yay -S --noconfirm swayosd-git
sudo usermod -aG video "$USERNAME"
systemctl --user enable --now swayosd-server
log "SwayOSD installed"

# =============================================================================
# STEP 8 — Brightness control
#
# Internal display : brightnessctl
# External LG      : ddcutil over DDC/CI (i2c bus)
#
# brightness-adjust script lives in dotfiles at .local/bin/brightness-adjust
# and is restored in step 11. This step sets up the system-level permissions.
#
# After reboot: run `ddcutil detect` to verify LG is accessible.
# If not found: enable DDC/CI in the LG monitor's OSD menu.
# =============================================================================

section "Brightness control (internal + DDC/CI)"

sudo pacman -S --noconfirm --needed \
  brightnessctl \
  ddcutil \
  i2c-tools \
  bc

sudo modprobe i2c-dev
echo "i2c-dev" | sudo tee /etc/modules-load.d/i2c-dev.conf > /dev/null
sudo groupadd -f i2c
sudo usermod -aG i2c "$USERNAME"
sudo cp /usr/share/ddcutil/data/45-ddcutil-i2c.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules && sudo udevadm trigger
log "DDC/CI permissions configured"
warn "Run 'ddcutil detect' after reboot to verify LG monitor"

# =============================================================================
# STEP 9 — Applications
# =============================================================================

section "Applications"

sudo pacman -S --noconfirm --needed \
  firefox \
  dolphin \
  dolphin-plugins \
  ffmpegthumbs \
  kdegraphics-thumbnailers \
  kio-extras \
  samba \
  vscodium \
  remmina \
  freerdp \
  kdeconnect \
  ydotoold \
  mpv \
  imv \
  file-roller \
  btop \
  fastfetch \
  neovim \
  yazi \
  zoxide \
  fzf \
  ripgrep \
  fd \
  bat \
  eza

yay -S --noconfirm \
  mullvad-vpn \
  globalprotect-openconnect \
  arch-update \
  zotero-bin \
  bibata-cursor-theme \
  sddm-astronaut-theme

log "Applications installed"

# Enable arch-update timer
systemctl --user enable --now arch-update.timer 2>/dev/null \
  || warn "arch-update timer will start on next login"

# =============================================================================
# STEP 10 — Shell (zsh + Oh-My-Zsh)
# =============================================================================

section "Shell (zsh)"

sudo pacman -S --noconfirm --needed \
  zsh \
  zsh-syntax-highlighting \
  zsh-autosuggestions \
  zsh-history-substring-search \
  starship

if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
  log "Installing Oh-My-Zsh..."
  RUNZSH=no CHSH=no sh -c \
    "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

if [[ "$SHELL" != "$(which zsh)" ]]; then
  chsh -s "$(which zsh)"
  log "Default shell set to zsh"
fi

# =============================================================================
# STEP 11 — Terminal (kitty)
# =============================================================================

section "Terminal (kitty)"

sudo pacman -S --noconfirm --needed kitty
log "kitty installed"

# =============================================================================
# STEP 12 — Fonts
# =============================================================================

section "Fonts"

sudo pacman -S --noconfirm --needed \
  ttf-iosevka-nerd \
  ttf-jetbrains-mono-nerd \
  noto-fonts \
  noto-fonts-emoji \
  ttf-font-awesome

log "Fonts installed"

# =============================================================================
# STEP 13 — GTK + Qt theming (clean, no KDE deps)
#
# nwg-look   : GTK theme manager for Wayland
# kvantum    : Qt theme engine — one config applies to all Qt apps
# adw-gtk3   : Modern GTK3 scrollbars/menus
# papirus    : Icon theme — folders recolored to match autumn palette
# =============================================================================

section "GTK + Qt theming"

sudo pacman -S --noconfirm --needed \
  nwg-look \
  qt5ct \
  qt6ct \
  kvantum \
  adw-gtk3 \
  papirus-icon-theme \
  papirus-folders

# Recolor Papirus folders to warm brown matching autumn palette
papirus-folders -C brown --theme Papirus-Dark
log "Papirus folders recolored to brown"

mkdir -p ~/.config/environment.d/
cat > ~/.config/environment.d/qt-theme.conf << 'EOF'
QT_QPA_PLATFORMTHEME=qt5ct
QT_AUTO_SCREEN_SCALE_FACTOR=1
EOF

log "GTK + Qt theming tools installed"
warn "After first boot: run nwg-look (GTK) and kvantum-manager (Qt)"

# =============================================================================
# STEP 14 — Cursor theme (.icons/default handled by dotfiles)
# =============================================================================

section "Cursor"

# bibata-cursor-theme installed in step 9 via AUR
# .icons/default/index.theme is restored from dotfiles in step 15
log "Cursor theme installed via AUR in step 9"

# =============================================================================
# STEP 15 — SDDM
# =============================================================================

section "SDDM"

sudo mkdir -p /etc/sddm.conf.d/
printf '[Theme]\nCurrent=sddm-astronaut-theme\n' \
  | sudo tee /etc/sddm.conf.d/theme.conf > /dev/null
sudo systemctl enable sddm
log "SDDM enabled with astronaut theme"

# =============================================================================
# STEP 16 — System services
# =============================================================================

section "System services"

sudo systemctl enable NetworkManager
sudo systemctl enable bluetooth 2>/dev/null \
  || warn "Bluetooth not found, skipping"
log "System services enabled"

# =============================================================================
# STEP 17 — Dotfiles
#
# Clones dotfiles repo and copies all configs into place.
# Configs are NOT generated by this script — they live in the repo.
#
# Expected repo structure:
#   .config/hypr/           hyprland.conf + config/ + scripts/
#   .config/waybar/         config + style.css + colors.css + modules/
#   .config/kitty/          kitty.conf
#   .config/nvim/           LazyVim setup
#   .config/wofi/           config + style.css
#   .config/mako/           config
#   .config/yazi/           yazi configs
#   .config/btop/           btop.conf
#   .config/VSCodium/User/  settings.json
#   .config/kdeconnect/     paired device configs (no keys)
#   .config/wireplumber/    wireplumber.conf.d/51-follow-default.conf
#   .config/environment.d/  qt-theme.conf
#   .local/bin/             brightness-adjust
#   .local/share/           applications/, icons/, mime/, sddm/
#   .icons/default/         index.theme (cursor)
#   .zshrc
#   .zshenv (optional)
#   .mozilla/firefox/       user.js
# =============================================================================

section "Dotfiles"

log "Cloning dotfiles from $DOTFILES_REPO..."
git clone --depth=1 "$DOTFILES_REPO" /tmp/dotfiles

# .config entries
for conf in hypr waybar kitty nvim wofi mako yazi btop kdeconnect \
            wireplumber environment.d VSCodium; do
  if [[ -d "/tmp/dotfiles/.config/$conf" ]]; then
    mkdir -p ~/.config/"$conf"
    cp -r "/tmp/dotfiles/.config/$conf/." ~/.config/"$conf"/
    log "  Restored: ~/.config/$conf"
  else
    warn "  Not found in dotfiles: $conf"
  fi
done

# Loose .config files
for f in gtk3-settings.ini gtk4-settings.ini kdeglobals mimeapps.list; do
  [[ -f "/tmp/dotfiles/.config/$f" ]] \
    && cp "/tmp/dotfiles/.config/$f" ~/.config/ \
    && log "  Restored: $f"
done

# .local/bin (scripts)
if [[ -d /tmp/dotfiles/.local/bin ]]; then
  mkdir -p ~/.local/bin
  cp -r /tmp/dotfiles/.local/bin/. ~/.local/bin/
  chmod +x ~/.local/bin/* 2>/dev/null || true
  log "  Restored: ~/.local/bin"
fi

# .local/share
for share in applications icons mime sddm; do
  if [[ -d "/tmp/dotfiles/.local/share/$share" ]]; then
    mkdir -p ~/.local/share/"$share"
    cp -r "/tmp/dotfiles/.local/share/$share/." ~/.local/share/"$share"/
    log "  Restored: ~/.local/share/$share"
  fi
done

# Cursor default theme
if [[ -d /tmp/dotfiles/.icons ]]; then
  mkdir -p ~/.icons
  cp -r /tmp/dotfiles/.icons/. ~/.icons/
  log "  Restored: ~/.icons (cursor)"
fi

# Shell
[[ -f /tmp/dotfiles/.zshrc  ]] && cp /tmp/dotfiles/.zshrc  ~/ && log "  Restored: .zshrc"
[[ -f /tmp/dotfiles/.zshenv ]] && cp /tmp/dotfiles/.zshenv ~/ && log "  Restored: .zshenv"

# Firefox user.js
if [[ -f /tmp/dotfiles/.mozilla/firefox/user.js ]]; then
  FIREFOX_PROFILE=$(find ~/.mozilla/firefox -maxdepth 1 \
    \( -name "*.default-release" -o -name "*.default" \) 2>/dev/null | head -1)
  if [[ -n "$FIREFOX_PROFILE" ]]; then
    cp /tmp/dotfiles/.mozilla/firefox/user.js "$FIREFOX_PROFILE/"
    log "  Firefox user.js applied to $FIREFOX_PROFILE"
  else
    warn "  Firefox profile not found — launch Firefox once then re-run this block"
    mkdir -p ~/.mozilla/firefox
    cp /tmp/dotfiles/.mozilla/firefox/user.js ~/.mozilla/firefox/
  fi
fi

# SSH keys
if [[ -d /tmp/dotfiles/.ssh ]]; then
  cp -r /tmp/dotfiles/.ssh ~/
  chmod 700 ~/.ssh
  chmod 600 ~/.ssh/id_* 2>/dev/null || true
  log "  Restored: SSH keys"
fi

# =============================================================================
# STEP 18 — Wallpapers
# =============================================================================

section "Wallpapers"

mkdir -p ~/Pictures/wallpapers
mkdir -p ~/Pictures/Screenshots

if [[ -n "$WALLPAPERS_REPO" ]]; then
  log "Cloning wallpapers from $WALLPAPERS_REPO..."
  git clone --depth=1 "$WALLPAPERS_REPO" /tmp/wallpapers
  find /tmp/wallpapers -type f \
    \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \
       -o -iname "*.webp" -o -iname "*.gif" \) \
    -exec cp {} ~/Pictures/wallpapers/ \;
  log "Wallpapers copied to ~/Pictures/wallpapers"
fi

# =============================================================================
# STEP 19 — NAS automount (CIFS/SMB via fstab)
#
# Uses noauto,x-systemd.automount,_netdev so it:
#   - Does NOT mount at boot (no boot delay if NAS is off)
#   - Mounts on first access (transparent to apps including non-KDE)
#   - Requires network before attempting (_netdev)
#   - Times out gracefully if NAS unreachable
# =============================================================================

section "NAS automount"

if [[ -n "$NAS_IP" && -n "$NAS_SHARE" && -n "$NAS_USER" ]]; then
  sudo mkdir -p "$NAS_MOUNT"

  if ! grep -q "$NAS_IP/$NAS_SHARE" /etc/fstab; then
    echo "//$NAS_IP/$NAS_SHARE  $NAS_MOUNT  cifs  noauto,x-systemd.automount,x-systemd.idle-timeout=300,_netdev,credentials=/etc/nas-credentials,uid=$(id -u),gid=$(id -g),iocharset=utf8  0  0" \
      | sudo tee -a /etc/fstab > /dev/null
    log "NAS fstab entry added"
  fi

  if [[ ! -f /etc/nas-credentials ]]; then
    printf 'username=%s\npassword=CHANGE_ME\n' "$NAS_USER" \
      | sudo tee /etc/nas-credentials > /dev/null
    sudo chmod 600 /etc/nas-credentials
    warn "Edit /etc/nas-credentials and set your real NAS password"
  fi

  sudo systemctl daemon-reload
  log "NAS mount configured (mounts on first access, not at boot)"
else
  warn "NAS vars not set — skipping NAS mount"
  warn "Set NAS_IP, NAS_SHARE, NAS_USER at the top of this script"
fi

# =============================================================================
# STEP 20 — Dual-boot Windows clock fix
# =============================================================================

section "Dual-boot clock fix"

sudo timedatectl set-local-rtc 1 --adjust-system-clock
log "RTC set to local time (prevents Windows clock drift)"

# =============================================================================
# STEP 21 — Orphan cleanup
# =============================================================================

section "Cleanup"

ORPHANS=$(pacman -Qdtq 2>/dev/null || true)
if [[ -n "$ORPHANS" ]]; then
  log "Removing orphaned packages..."
  sudo pacman -Rns $ORPHANS --noconfirm
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
echo "After reboot — do these in order:"
echo ""
echo "  1. hyprctl monitors"
echo "     → Fill in your monitor names in ~/.config/hypr/config/monitor.conf"
echo ""
echo "  2. ddcutil detect"
echo "     → Verify LG external monitor DDC/CI works for brightness control"
echo "     → If not found: enable DDC/CI in LG OSD menu"
echo ""
echo "  3. nwg-look"
echo "     → Set GTK theme to adw-gtk3-dark"
echo "     → Set icon theme to Papirus-Dark"
echo "     → Set cursor to Bibata-Modern-Classic"
echo ""
echo "  4. kvantum-manager"
echo "     → Set Qt theme to match autumn palette"
echo "     → Then open qt5ct and set style to kvantum"
echo ""
echo "  5. Edit /etc/nas-credentials"
echo "     → Replace CHANGE_ME with your real NAS password"
echo ""
echo "  6. Firefox → sign into Firefox Sync"
echo "     → Extensions, bookmarks, passwords restore automatically"
echo ""
echo "  7. mullvad account login YOUR_ACCOUNT_NUMBER"
echo ""
echo "  8. Add Limine entries for both kernels:"
echo "     Main:     linux-cachyos  (vmlinuz-linux-cachyos)"
echo "     Fallback: linux-lts      (vmlinuz-linux-lts)"
echo ""
warn "Groups (video, i2c) need a full reboot to take effect"
warn "sudo reboot"
