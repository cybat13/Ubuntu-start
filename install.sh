#!/usr/bin/env bash
set -Eeuo pipefail

trap 'printf "[ERROR] Line %s: %s\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

#######################################
# Constants / defaults
#######################################

readonly SCRIPT_NAME="$(basename "$0")"
readonly SYSCTL_FILE="/etc/sysctl.d/99-ubuntu-gaming.conf"
readonly LOCAL_BIN_DIR="${HOME}/.local/bin"

APT_ENV=(DEBIAN_FRONTEND=noninteractive)
APT_INSTALL_OPTS=(-y --no-install-recommends)
APT_UPGRADE_OPTS=(-y)

DO_UPDATE=1
DO_MICROCODE=1
DO_NVIDIA=1
DO_GRAPHICS=1
DO_GAMING=1
DO_DEVTOOLS=1
DO_EXTRAS=1
DO_POWER=1
DO_FLATHUB=1
DO_TRIM=1
DO_TUNING=1
DO_CLEANUP=1

MINIMAL_MODE=0
DRY_RUN=0

#######################################
# Package groups
#######################################

GRAPHICS_PACKAGES=(
  mesa-utils
  vulkan-tools
  libvulkan1
  libvulkan1:i386
  libgl1-mesa-dri
  libgl1-mesa-dri:i386
  libglx-mesa0
  libglx-mesa0:i386
  libgbm1
  libgbm1:i386
  libdrm2
  libdrm2:i386
)

GAMING_PACKAGES=(
  lutris
  gamemode
  libgamemode0
  libgamemodeauto0
  mangohud
)

WINE_PACKAGES=(
  wine
  wine64
  wine32
  winetricks
)

DEV_PACKAGES=(
  git
  curl
  wget
  build-essential
  cmake
  ninja-build
  pkg-config
  python3
  python3-pip
  python3-venv
  nodejs
  npm
  unzip
  zip
  tar
  xz-utils
  ripgrep
  fd-find
  neovim
  tmux
  htop
  btop
  fastfetch
  jq
)

EXTRA_PACKAGES=(
  pciutils
  fwupd
  flatpak
  gnome-disk-utility
  p7zip-full
  file-roller
  ca-certificates
  software-properties-common
)

POWER_PACKAGES=(
  power-profiles-daemon
)

#######################################
# Logging / helpers
#######################################

log()  { printf "\n==> %s\n" "$1"; }
warn() { printf "[WARN] %s\n" "$1" >&2; }
die()  { printf "[ERROR] %s\n" "$1" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"
}

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[DRY-RUN] '
    printf '%q ' "$@"
    printf '\n'
  else
    "$@"
  fi
}

run_sudo() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[DRY-RUN] sudo '
    printf '%q ' "$@"
    printf '\n'
  else
    sudo "$@"
  fi
}

try_run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[DRY-RUN] '
    printf '%q ' "$@"
    printf '\n'
    return 0
  fi

  if ! "$@"; then
    warn "Command failed: $*"
    return 1
  fi
}

try_run_sudo() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[DRY-RUN] sudo '
    printf '%q ' "$@"
    printf '\n'
    return 0
  fi

  if ! sudo "$@"; then
    warn "Command failed: sudo $*"
    return 1
  fi
}

is_installed() {
  dpkg -s "$1" >/dev/null 2>&1
}

have_pkg() {
  local candidate
  candidate="$(apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/ {print $2}')"
  [ -n "$candidate" ] && [ "$candidate" != "(none)" ]
}

apt_install() {
  [ $# -gt 0 ] || return 0

  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[DRY-RUN] sudo env DEBIAN_FRONTEND=noninteractive apt-get install '
    printf '%q ' "${APT_INSTALL_OPTS[@]}"
    printf '%q ' "$@"
    printf '\n'
  else
    sudo env "${APT_ENV[@]}" apt-get install "${APT_INSTALL_OPTS[@]}" "$@"
  fi
}

install_if_available() {
  local to_install=()
  local pkg

  for pkg in "$@"; do
    if ! have_pkg "$pkg"; then
      warn "Package unavailable: $pkg"
    elif is_installed "$pkg"; then
      log "Already installed: $pkg"
    else
      to_install+=("$pkg")
    fi
  done

  [ ${#to_install[@]} -gt 0 ] || return 0

  log "Installing: ${to_install[*]}"
  apt_install "${to_install[@]}"
}

install_first_available() {
  local pkg
  for pkg in "$@"; do
    if have_pkg "$pkg"; then
      install_if_available "$pkg"
      return 0
    fi
  done
  return 1
}

write_file_with_mode() {
  local mode="$1"
  local target="$2"
  local tmp

  tmp="$(mktemp)"
  cat > "$tmp"

  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[DRY-RUN] install -m %s %s %s\n' "$mode" "$tmp" "$target"
    rm -f "$tmp"
    return 0
  fi

  install -m "$mode" "$tmp" "$target"
  rm -f "$tmp"
}

#######################################
# Usage / args
#######################################

print_usage() {
  cat <<EOF
Usage:
  $SCRIPT_NAME [options]

Options:
  --dry-run            Show what would run, but do not make changes
  --minimal            Install a smaller core set only
  --full               Enable all default sections
  --no-update          Skip apt update/upgrade
  --skip-microcode     Skip CPU microcode installation
  --skip-nvidia        Skip NVIDIA driver auto-install
  --skip-graphics      Skip Mesa/Vulkan userspace packages
  --skip-gaming        Skip Steam/Lutris/Wine/GameMode/MangoHud
  --skip-devtools      Skip developer tools
  --skip-extras        Skip useful extras
  --skip-power         Skip power-profiles-daemon and helper scripts
  --skip-flathub       Skip Flathub setup
  --skip-trim          Skip fstrim.timer enablement
  --skip-tuning        Skip sysctl tuning
  --skip-cleanup       Skip apt autoremove/autoclean
  --help, -h           Show this help

Examples:
  ./$SCRIPT_NAME
  ./$SCRIPT_NAME --minimal
  ./$SCRIPT_NAME --dry-run --skip-devtools
  ./$SCRIPT_NAME --skip-nvidia --skip-power
EOF
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run)        DRY_RUN=1 ;;
      --minimal)        MINIMAL_MODE=1 ;;
      --full)           MINIMAL_MODE=0 ;;
      --no-update)      DO_UPDATE=0 ;;
      --skip-microcode) DO_MICROCODE=0 ;;
      --skip-nvidia)    DO_NVIDIA=0 ;;
      --skip-graphics)  DO_GRAPHICS=0 ;;
      --skip-gaming)    DO_GAMING=0 ;;
      --skip-devtools)  DO_DEVTOOLS=0 ;;
      --skip-extras)    DO_EXTRAS=0 ;;
      --skip-power)     DO_POWER=0 ;;
      --skip-flathub)   DO_FLATHUB=0 ;;
      --skip-trim)      DO_TRIM=0 ;;
      --skip-tuning)    DO_TUNING=0 ;;
      --skip-cleanup)   DO_CLEANUP=0 ;;
      --help|-h)
        print_usage
        exit 0
        ;;
      *)
        die "Unknown option: $1"
        ;;
    esac
    shift
  done

  if [ "$MINIMAL_MODE" -eq 1 ]; then
    DO_DEVTOOLS=0
    DO_EXTRAS=0
    DO_FLATHUB=0
    DO_POWER=0
    DO_TUNING=0
  fi
}

#######################################
# Platform / environment checks
#######################################

is_ubuntu() {
  [ -r /etc/os-release ] || return 1
  . /etc/os-release
  [ "${ID:-}" = "ubuntu" ]
}

preflight() {
  require_cmd sudo
  require_cmd apt-get
  require_cmd apt-cache
  require_cmd dpkg
  require_cmd lsblk
  require_cmd awk
  require_cmd grep

  is_ubuntu || die "This script currently supports Ubuntu only"
}

init_sudo() {
  [ "$DRY_RUN" -eq 1 ] && return 0
  log "Requesting sudo access"
  sudo -v || die "Failed to obtain sudo privileges"
}

#######################################
# Hardware detection
#######################################

detect_cpu_vendor() {
  if grep -qi 'AuthenticAMD\|amd' /proc/cpuinfo; then
    echo "amd"
  elif grep -qi 'GenuineIntel\|intel' /proc/cpuinfo; then
    echo "intel"
  else
    echo "unknown"
  fi
}

has_nvidia_gpu() {
  command -v lspci >/dev/null 2>&1 &&
    lspci | grep -Ei 'vga|3d|display' | grep -qi nvidia
}

has_amd_gpu() {
  command -v lspci >/dev/null 2>&1 &&
    lspci | grep -Ei 'vga|3d|display' | grep -Eqi 'amd|advanced micro devices|ati'
}

has_intel_gpu() {
  command -v lspci >/dev/null 2>&1 &&
    lspci | grep -Ei 'vga|3d|display' | grep -qi intel
}

ensure_pciutils_if_possible() {
  if ! command -v lspci >/dev/null 2>&1; then
    log "lspci not found, attempting to install pciutils"
    install_if_available pciutils
  fi
}

#######################################
# System / repo setup
#######################################

enable_i386_arch() {
  if ! dpkg --print-foreign-architectures | grep -qx i386; then
    log "Enabling i386 architecture"
    run_sudo dpkg --add-architecture i386
    run_sudo env "${APT_ENV[@]}" apt-get update
  else
    log "i386 architecture already enabled"
  fi
}

system_update() {
  [ "$DO_UPDATE" -eq 1 ] || return 0

  log "Updating package lists"
  run_sudo env "${APT_ENV[@]}" apt-get update

  log "Upgrading installed packages"
  run_sudo env "${APT_ENV[@]}" apt-get upgrade "${APT_UPGRADE_OPTS[@]}"

  log "Fixing package issues if needed"
  try_run_sudo env "${APT_ENV[@]}" apt-get -f install -y
}

cleanup_system() {
  [ "$DO_CLEANUP" -eq 1 ] || return 0

  log "Cleaning up"
  run_sudo env "${APT_ENV[@]}" apt-get autoremove -y
  run_sudo env "${APT_ENV[@]}" apt-get autoclean -y
}

#######################################
# Install sections
#######################################

install_microcode() {
  [ "$DO_MICROCODE" -eq 1 ] || return 0

  case "$(detect_cpu_vendor)" in
    amd)
      log "AMD CPU detected"
      install_if_available amd64-microcode
      ;;
    intel)
      log "Intel CPU detected"
      install_if_available intel-microcode
      ;;
    *)
      warn "Unknown CPU vendor, skipping microcode"
      ;;
  esac
}

install_nvidia_if_needed() {
  [ "$DO_NVIDIA" -eq 1 ] || return 0

  if has_nvidia_gpu; then
    log "NVIDIA GPU detected"
    if command -v ubuntu-drivers >/dev/null 2>&1; then
      try_run_sudo ubuntu-drivers autoinstall
    else
      warn "ubuntu-drivers not found, skipping NVIDIA auto install"
    fi
  else
    log "No NVIDIA GPU detected, skipping NVIDIA driver auto-install"
  fi
}

print_gpu_summary() {
  log "Detected GPU(s)"
  has_nvidia_gpu && printf '  - NVIDIA\n'
  has_amd_gpu && printf '  - AMD/ATI\n'
  has_intel_gpu && printf '  - Intel\n'
  if ! has_nvidia_gpu && ! has_amd_gpu && ! has_intel_gpu; then
    printf '  - Unknown\n'
  fi
}

install_core_graphics() {
  [ "$DO_GRAPHICS" -eq 1 ] || return 0
  log "Installing graphics and Vulkan support"
  install_if_available "${GRAPHICS_PACKAGES[@]}"
}

install_steam() {
  log "Installing Steam"
  if ! install_first_available steam-installer steam; then
    warn "No Steam package available in current repositories"
    warn "You may need multiverse enabled or manual Steam installation"
  fi
}

install_wine_stack() {
  log "Installing Wine stack"
  install_if_available "${WINE_PACKAGES[@]}"
}

install_gaming_stack() {
  [ "$DO_GAMING" -eq 1 ] || return 0

  log "Installing gaming stack"
  install_steam
  install_if_available "${GAMING_PACKAGES[@]}"
  install_wine_stack
}

install_dev_basics() {
  [ "$DO_DEVTOOLS" -eq 1 ] || return 0

  log "Installing dev basics"
  install_if_available "${DEV_PACKAGES[@]}"
}

install_useful_bits() {
  [ "$DO_EXTRAS" -eq 1 ] || return 0

  log "Installing useful extras"
  install_if_available "${EXTRA_PACKAGES[@]}"
}

install_power_profile_tools() {
  [ "$DO_POWER" -eq 1 ] || return 0

  log "Installing laptop power profile tools"
  install_if_available "${POWER_PACKAGES[@]}"
}

setup_flathub() {
  [ "$DO_FLATHUB" -eq 1 ] || return 0

  if command -v flatpak >/dev/null 2>&1; then
    log "Adding Flathub"
    if [ "$DRY_RUN" -eq 1 ]; then
      printf '[DRY-RUN] flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo\n'
    else
      flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo \
        || warn "Failed to add Flathub"
    fi
  else
    warn "flatpak not installed, skipping Flathub setup"
  fi
}

enable_trim_if_ssd() {
  [ "$DO_TRIM" -eq 1 ] || return 0

  if lsblk -d -o rota | tail -n +2 | grep -q '^0$'; then
    log "SSD detected, enabling fstrim.timer"
    try_run_sudo systemctl enable fstrim.timer
    try_run_sudo systemctl start fstrim.timer
  else
    warn "No SSD detected, skipping fstrim.timer"
  fi
}

set_light_tunables() {
  [ "$DO_TUNING" -eq 1 ] || return 0

  log "Applying lightweight system tuning"

  local tmp
  tmp="$(mktemp)"

  cat > "$tmp" <<'EOF'
# Ubuntu gaming/dev tuneables
# Safe, lightweight VM adjustments
vm.swappiness=10
vm.vfs_cache_pressure=50
EOF

  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[DRY-RUN] compare and possibly install %s -> %s\n' "$tmp" "$SYSCTL_FILE"
    rm -f "$tmp"
    return 0
  fi

  if ! sudo cmp -s "$tmp" "$SYSCTL_FILE" 2>/dev/null; then
    log "Installing sysctl profile: $SYSCTL_FILE"
    sudo install -m 0644 "$tmp" "$SYSCTL_FILE"
    sudo sysctl --system >/dev/null || warn "Failed to reload sysctl settings"
  else
    log "Sysctl tuning already up to date"
  fi

  rm -f "$tmp"
}

set_default_power_mode() {
  [ "$DO_POWER" -eq 1 ] || return 0

  if command -v powerprofilesctl >/dev/null 2>&1; then
    log "Enabling power-profiles-daemon"
    try_run_sudo systemctl enable --now power-profiles-daemon

    log "Setting default power mode to balanced"
    if [ "$DRY_RUN" -eq 1 ]; then
      printf '[DRY-RUN] powerprofilesctl set balanced\n'
    else
      powerprofilesctl set balanced || warn "Failed to set balanced power mode"
    fi
  else
    warn "powerprofilesctl not found, skipping default power mode"
  fi
}

create_power_toggle_scripts() {
  [ "$DO_POWER" -eq 1 ] || return 0

  log "Creating power mode helper scripts"
  mkdir -p "$LOCAL_BIN_DIR"

  write_file_with_mode 0755 "$LOCAL_BIN_DIR/power-battery" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if command -v powerprofilesctl >/dev/null 2>&1; then
  powerprofilesctl set power-saver
  echo "Switched to: power-saver"
else
  echo "powerprofilesctl not found" >&2
  exit 1
fi
EOF

  write_file_with_mode 0755 "$LOCAL_BIN_DIR/power-balanced" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if command -v powerprofilesctl >/dev/null 2>&1; then
  powerprofilesctl set balanced
  echo "Switched to: balanced"
else
  echo "powerprofilesctl not found" >&2
  exit 1
fi
EOF

  write_file_with_mode 0755 "$LOCAL_BIN_DIR/power-performance" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if command -v powerprofilesctl >/dev/null 2>&1; then
  powerprofilesctl set performance
  echo "Switched to: performance"
else
  echo "powerprofilesctl not found" >&2
  exit 1
fi
EOF

  if ! printf '%s\n' "$PATH" | tr ':' '\n' | grep -qx "$LOCAL_BIN_DIR"; then
    warn "~/.local/bin is not in PATH for this shell"
    warn "Add this to ~/.bashrc or ~/.zshrc:"
    warn 'export PATH="$HOME/.local/bin:$PATH"'
  fi
}

#######################################
# Reporting
#######################################

print_plan() {
  cat <<EOF

========================================
Planned sections
========================================
Update system:          $DO_UPDATE
Install microcode:      $DO_MICROCODE
Install NVIDIA driver:  $DO_NVIDIA
Install graphics stack: $DO_GRAPHICS
Install gaming stack:   $DO_GAMING
Install dev tools:      $DO_DEVTOOLS
Install extras:         $DO_EXTRAS
Install power tools:    $DO_POWER
Setup Flathub:          $DO_FLATHUB
Enable TRIM:            $DO_TRIM
Apply sysctl tuning:    $DO_TUNING
Cleanup apt cache:      $DO_CLEANUP
Dry-run mode:           $DRY_RUN
Minimal mode:           $MINIMAL_MODE

EOF
}

show_notes() {
  cat <<'EOF'

========================================
Done.

Installed or attempted:
- graphics + Vulkan userspace
- Steam
- Lutris
- Wine + Winetricks
- GameMode + MangoHud
- firmware updater
- optional dev tools
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
- Use power-saver when on battery
- On some laptops, "performance" may not be available
- Some packages may be skipped if unavailable in your enabled repositories

Useful examples:
  ./ubuntu-gaming-setup.sh --dry-run
  ./ubuntu-gaming-setup.sh --minimal
  ./ubuntu-gaming-setup.sh --skip-devtools --skip-flathub

EOF
}

#######################################
# Main
#######################################

main() {
  parse_args "$@"
  preflight
  init_sudo

  log "Starting Ubuntu gaming setup"
  print_plan

  system_update
  install_useful_bits
  ensure_pciutils_if_possible
  print_gpu_summary
  enable_i386_arch
  install_microcode
  install_nvidia_if_needed
  install_core_graphics
  install_gaming_stack
  install_dev_basics
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
