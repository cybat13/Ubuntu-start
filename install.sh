#!/usr/bin/env bash
set -Eeuo pipefail

trap 'echo "[ERROR] Line $LINENO: $BASH_COMMAND" >&2' ERR

log()  { printf "\n==> %s\n" "$1"; }
warn() { printf "[WARN] %s\n" "$1" >&2; }
die()  { printf "[ERROR] %s\n" "$1" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"
}

have_pkg() {
  local candidate
  candidate="$(apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/ {print $2}')"
  [ -n "$candidate" ] && [ "$candidate" != "(none)" ]
}

install_if_available() {
  local ok=()
  local pkg

  for pkg in "$@"; do
    if have_pkg "$pkg"; then
      ok+=("$pkg")
    else
      warn "Package unavailable: $pkg"
    fi
  done

  if [ ${#ok[@]} -gt 0 ]; then
    log "Installing: ${ok[*]}"
    sudo apt-get install -y --no-install-recommends "${ok[@]}"
  fi
}

enable_i386_arch() {
  if ! dpkg --print-foreign-architectures | grep -qx i386; then
    log "Enabling i386 architecture"
    sudo dpkg --add-architecture i386
    sudo apt-get update
  fi
}

detect_cpu_vendor() {
  if grep -qi amd /proc/cpuinfo; then
    echo "amd"
  elif grep -qi intel /proc/cpuinfo; then
    echo "intel"
  else
    echo "unknown"
  fi
}

detect_gpu_vendor() {
  if lspci | grep -Ei 'vga|3d|display' | grep -qi nvidia; then
    echo "nvidia"
  elif lspci | grep -Ei 'vga|3d|display' | grep -qi amd; then
    echo "amd"
  elif lspci | grep -Ei 'vga|3d|display' | grep -qi intel; then
    echo "intel"
  else
    echo "unknown"
  fi
}

install_microcode() {
  case "$(detect_cpu_vendor)" in
    amd)   install_if_available amd64-microcode ;;
    intel) install_if_available intel-microcode ;;
    *)     warn "Unknown CPU vendor, skipping microcode" ;;
  esac
}

install_nvidia_if_needed() {
  if [ "$(detect_gpu_vendor)" = "nvidia" ]; then
    log "NVIDIA GPU detected"
    if command -v ubuntu-drivers >/dev/null 2>&1; then
      sudo ubuntu-drivers autoinstall || warn "ubuntu-drivers autoinstall failed"
    else
      warn "ubuntu-drivers not found, skipping NVIDIA auto install"
    fi
  fi
}

install_core_graphics() {
  log "Installing graphics and Vulkan support"
  install_if_available \
    mesa-utils \
    vulkan-tools \
    libvulkan1 \
    libvulkan1:i386 \
    libgl1-mesa-dri \
    libgl1-mesa-dri:i386 \
    libglx-mesa0 \
    libglx-mesa0:i386 \
    libgbm1 \
    libgbm1:i386 \
    libdrm2 \
    libdrm2:i386
}

install_gaming_stack() {
  log "Installing gaming stack"
  install_if_available \
    steam-installer \
    lutris \
    gamemode \
    libgamemode0 \
    libgamemodeauto0 \
    mangohud \
    wine64 \
    winetricks
}

install_dev_basics() {
  log "Installing dev basics"
  install_if_available \
    git \
    curl \
    wget \
    build-essential \
    cmake \
    ninja-build \
    pkg-config \
    python3 \
    python3-pip \
    python3-venv \
    nodejs \
    npm \
    unzip \
    zip \
    tar \
    xz-utils \
    ripgrep \
    fd-find \
    neovim \
    tmux \
    htop \
    btop \
    fastfetch \
    jq
}

install_useful_bits() {
  log "Installing useful extras"
  install_if_available \
    fwupd \
    flatpak \
    gnome-disk-utility \
    p7zip-full \
    file-roller \
    ca-certificates \
    software-properties-common
}

install_power_profile_tools() {
  log "Installing laptop power profile tools"
  install_if_available power-profiles-daemon
}

setup_flathub() {
  if command -v flatpak >/dev/null 2>&1; then
    log "Adding Flathub"
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || true
  fi
}

enable_trim_if_ssd() {
  if lsblk -d -o rota | tail -n +2 | grep -q '^0$'; then
    log "SSD detected, enabling fstrim.timer"
    sudo systemctl enable fstrim.timer >/dev/null 2>&1 || true
    sudo systemctl start fstrim.timer >/dev/null 2>&1 || true
  else
    warn "No SSD detected, skipping fstrim.timer"
  fi
}

set_light_tunables() {
  log "Applying lightweight system tuning"

  sudo tee /etc/sysctl.d/99-ubuntu-gaming.conf >/dev/null <<'EOF'
vm.swappiness=10
vm.vfs_cache_pressure=50
EOF

  sudo sysctl --system >/dev/null || true
}

set_default_power_mode() {
  if command -v powerprofilesctl >/dev/null 2>&1; then
    log "Enabling power-profiles-daemon"
    sudo systemctl enable --now power-profiles-daemon >/dev/null 2>&1 || true

    log "Setting default power mode to balanced"
    powerprofilesctl set balanced || true
  else
    warn "powerprofilesctl not found, skipping default power mode"
  fi
}

create_power_toggle_scripts() {
  log "Creating power mode helper scripts"

  mkdir -p "$HOME/.local/bin"

  cat > "$HOME/.local/bin/power-battery" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if command -v powerprofilesctl >/dev/null 2>&1; then
  powerprofilesctl set power-saver
  echo "Switched to: power-saver"
else
  echo "powerprofilesctl not found"
  exit 1
fi
EOF

  cat > "$HOME/.local/bin/power-balanced" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if command -v powerprofilesctl >/dev/null 2>&1; then
  powerprofilesctl set balanced
  echo "Switched to: balanced"
else
  echo "powerprofilesctl not found"
  exit 1
fi
EOF

  cat > "$HOME/.local/bin/power-performance" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if command -v powerprofilesctl >/dev/null 2>&1; then
  powerprofilesctl set performance
  echo "Switched to: performance"
else
  echo "powerprofilesctl not found"
  exit 1
fi
EOF

  chmod +x \
    "$HOME/.local/bin/power-battery" \
    "$HOME/.local/bin/power-balanced" \
    "$HOME/.local/bin/power-performance"

  if ! echo "$PATH" | tr ':' '\n' | grep -qx "$HOME/.local/bin"; then
    warn "~/.local/bin is not in PATH for this shell"
    warn "Add this to ~/.bashrc or ~/.zshrc:"
    warn 'export PATH="$HOME/.local/bin:$PATH"'
  fi
}

system_update() {
  log "Updating package lists"
  sudo apt-get update

  log "Upgrading system"
  sudo apt-get dist-upgrade -y

  log "Fixing package issues if needed"
  sudo apt-get -f install -y || true
}

cleanup_system() {
  log "Cleaning up"
  sudo apt-get autoremove -y
  sudo apt-get autoclean -y
}

show_notes() {
  cat <<'EOF'

========================================
Done.

Installed:
- graphics + Vulkan userspace
- Steam + Lutris + Wine + Winetricks
- GameMode + MangoHud
- firmware updater
- lightweight dev tools
- Flatpak support
- mild system tuning
- laptop power mode helpers

Power helper commands:
  power-battery
  power-balanced
  power-performance

Check current power mode:
  powerprofilesctl get

Recommended next steps:
1. Reboot
2. Open Steam and enable Proton for all titles
3. Test GameMode:
     gamemoded -t
4. Test Vulkan:
     vulkaninfo | less
5. Steam launch options:
     mangohud gamemoderun %command%

Notes:
- Use power-performance while plugged in and gaming
- Use power-balanced for normal daily use
- Use power-battery when on battery
- On some laptops, "performance" may not be available

Optional installs you can add later:
- OBS Studio
- Heroic Games Launcher
- Bottles
- VS Code
- Discord

EOF
}

main() {
  require_cmd sudo
  require_cmd apt-get
  require_cmd apt-cache
  require_cmd lspci
  require_cmd dpkg
  require_cmd lsblk

  log "Starting lightweight Ubuntu gaming setup"

  enable_i386_arch
  system_update
  install_microcode
  install_nvidia_if_needed
  install_core_graphics
  install_gaming_stack
  install_dev_basics
  install_useful_bits
  install_power_profile_tools
  setup_flathub
  enable_trim_if_ssd
  set_light_tunables
  set_default_power_mode
  create_power_toggle_scripts
  cleanup_system
  show_notes
}

main "$@"