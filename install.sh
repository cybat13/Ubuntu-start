#!/usr/bin/env bash
set -Eeuo pipefail

trap 'rc=$?; printf "[ERROR] Line %s: %s (exit %s)\n" "$LINENO" "$BASH_COMMAND" "$rc" >&2; exit "$rc"' ERR

#######################################
# Constants / defaults
#######################################

readonly SCRIPT_NAME="$(basename "$0")"
readonly SYSCTL_FILE="/etc/sysctl.d/99-ubuntu-gaming.conf"
readonly LOCAL_BIN_DIR="${HOME}/.local/bin"
readonly LOCAL_CONFIG_DIR="${HOME}/.config"
readonly MANGOHUD_CONFIG_DIR="${LOCAL_CONFIG_DIR}/MangoHud"
readonly MANGOHUD_CONFIG_FILE="${MANGOHUD_CONFIG_DIR}/MangoHud.conf"

APT_ENV=(DEBIAN_FRONTEND=noninteractive)
APT_INSTALL_OPTS=(-y --no-install-recommends)
APT_UPGRADE_OPTS=(-y)
APT_FIX_OPTS=(-y)
APT_RETRY_OPTS=(-o Acquire::Retries=3)

DO_UPDATE=1
DO_MICROCODE=1
DO_NVIDIA=1
DO_GRAPHICS=1
DO_GAMING=1
DO_GAMING_TOOLS=1
DO_DEVTOOLS=1
DO_EXTRAS=1
DO_POWER=1
DO_FLATHUB=1
DO_TRIM=1
DO_TUNING=1
DO_CLEANUP=1
DO_I386=1
DO_CONFIRM=1

MINIMAL_MODE=0
DRY_RUN=0
ASSUME_YES=0

CPU_VENDOR="unknown"
GPU_INFO=""
GPU_HAS_NVIDIA=0
GPU_HAS_AMD=0
GPU_HAS_INTEL=0

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

GAMING_TOOLS_PACKAGES=(
  gamescope
  goverlay
  vkbasalt
  protontricks
  steam-devices
  obs-studio
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
info() { printf "[INFO] %s\n" "$1"; }
warn() { printf "[WARN] %s\n" "$1" >&2; }
die()  { printf "[ERROR] %s\n" "$1" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"
}

is_tty() {
  [ -t 0 ]
}

confirm() {
  local prompt="$1"

  if [ "$DRY_RUN" -eq 1 ] || [ "$ASSUME_YES" -eq 1 ] || [ "$DO_CONFIRM" -eq 0 ]; then
    return 0
  fi

  if ! is_tty; then
    warn "No interactive TTY; auto-accepting: ${prompt}"
    return 0
  fi

  local answer
  while true; do
    read -r -p "${prompt} [y/N]: " answer
    case "$answer" in
      y|Y|yes|YES) return 0 ;;
      n|N|no|NO|"") return 1 ;;
      *) printf 'Please answer y or n.\n' ;;
    esac
  done
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

path_contains_dir() {
  printf '%s\n' "$PATH" | tr ':' '\n' | grep -Fxq "$1"
}

ensure_user_dir() {
  mkdir -p "$1"
}

service_exists() {
  systemctl list-unit-files "$1" >/dev/null 2>&1
}

has_multiverse_enabled() {
  grep -RhsE '^[[:space:]]*deb .* multiverse([[:space:]]|$)' \
    /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null
}

apt_cmd() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[DRY-RUN] sudo env DEBIAN_FRONTEND=noninteractive apt-get '
    printf '%q ' "$@"
    printf '\n'
    return 0
  fi

  sudo env "${APT_ENV[@]}" apt-get "${APT_RETRY_OPTS[@]}" "$@"
}

apt_install() {
  [ $# -gt 0 ] || return 0
  apt_cmd install "${APT_INSTALL_OPTS[@]}" "$@"
}

install_if_available() {
  local to_install=()
  local pkg

  for pkg in "$@"; do
    if ! have_pkg "$pkg"; then
      warn "Package unavailable: $pkg"
    elif is_installed "$pkg"; then
      info "Already installed: $pkg"
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

write_if_changed() {
  local mode="$1"
  local target="$2"
  local tmp
  tmp="$(mktemp)"

  cat > "$tmp"

  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[DRY-RUN] compare and maybe install -m %s %s %s\n' "$mode" "$tmp" "$target"
    rm -f "$tmp"
    return 0
  fi

  if [ -f "$target" ] && cmp -s "$tmp" "$target"; then
    info "Already up to date: $target"
    rm -f "$tmp"
    return 0
  fi

  install -D -m "$mode" "$tmp" "$target"
  rm -f "$tmp"
}

warn_if_local_bin_missing_from_path() {
  if ! path_contains_dir "$LOCAL_BIN_DIR"; then
    warn "~/.local/bin is not in PATH for this shell"
    warn "Add this to ~/.bashrc or ~/.zshrc:"
    warn 'export PATH="$HOME/.local/bin:$PATH"'
  fi
}

#######################################
# Usage / args
#######################################

print_usage() {
  cat <<EOF
Usage:
  $SCRIPT_NAME [options]

Options:
  --dry-run              Show what would run, but do not make changes
  --yes                  Auto-confirm all prompts
  --no-confirm           Disable confirmations
  --minimal              Install a smaller core set only
  --full                 Enable all default sections
  --no-update            Skip apt update/upgrade
  --skip-microcode       Skip CPU microcode installation
  --skip-nvidia          Skip NVIDIA driver auto-install
  --skip-i386            Skip enabling i386 architecture
  --skip-graphics        Skip Mesa/Vulkan userspace packages
  --skip-gaming          Skip Steam/Lutris/Wine/GameMode/MangoHud
  --skip-gaming-tools    Skip extra gaming tools
  --skip-devtools        Skip developer tools
  --skip-extras          Skip useful extras
  --skip-power           Skip power-profiles-daemon and helper scripts
  --skip-flathub         Skip Flathub setup
  --skip-trim            Skip fstrim.timer enablement
  --skip-tuning          Skip sysctl tuning
  --skip-cleanup         Skip apt autoremove/autoclean
  --help, -h             Show this help

Examples:
  ./$SCRIPT_NAME
  ./$SCRIPT_NAME --dry-run
  ./$SCRIPT_NAME --yes --skip-nvidia
  ./$SCRIPT_NAME --minimal --skip-gaming-tools
EOF
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run)            DRY_RUN=1 ;;
      --yes|--no-confirm)   ASSUME_YES=1; DO_CONFIRM=0 ;;
      --minimal)            MINIMAL_MODE=1 ;;
      --full)               MINIMAL_MODE=0 ;;
      --no-update)          DO_UPDATE=0 ;;
      --skip-microcode)     DO_MICROCODE=0 ;;
      --skip-nvidia)        DO_NVIDIA=0 ;;
      --skip-i386)          DO_I386=0 ;;
      --skip-graphics)      DO_GRAPHICS=0 ;;
      --skip-gaming)        DO_GAMING=0 ;;
      --skip-gaming-tools)  DO_GAMING_TOOLS=0 ;;
      --skip-devtools)      DO_DEVTOOLS=0 ;;
      --skip-extras)        DO_EXTRAS=0 ;;
      --skip-power)         DO_POWER=0 ;;
      --skip-flathub)       DO_FLATHUB=0 ;;
      --skip-trim)          DO_TRIM=0 ;;
      --skip-tuning)        DO_TUNING=0 ;;
      --skip-cleanup)       DO_CLEANUP=0 ;;
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
    DO_GAMING_TOOLS=0
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

warn_if_non_lts() {
  local version_id=""
  version_id="$(. /etc/os-release && printf '%s' "${VERSION_ID:-}")"
  case "$version_id" in
    20.04|22.04|24.04) ;;
    *) warn "Ubuntu ${version_id:-unknown} detected. Best tested on LTS versions: 20.04 / 22.04 / 24.04." ;;
  esac
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
  warn_if_non_lts
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
    CPU_VENDOR="amd"
  elif grep -qi 'GenuineIntel\|intel' /proc/cpuinfo; then
    CPU_VENDOR="intel"
  else
    CPU_VENDOR="unknown"
  fi
}

collect_gpu_info() {
  if command -v lspci >/dev/null 2>&1; then
    GPU_INFO="$(lspci | grep -Ei 'vga|3d|display' || true)"
  else
    GPU_INFO=""
  fi

  if printf '%s\n' "$GPU_INFO" | grep -qi nvidia; then
    GPU_HAS_NVIDIA=1
  fi
  if printf '%s\n' "$GPU_INFO" | grep -Eqi 'amd|advanced micro devices|ati'; then
    GPU_HAS_AMD=1
  fi
  if printf '%s\n' "$GPU_INFO" | grep -qi intel; then
    GPU_HAS_INTEL=1
  fi
}

has_nvidia_gpu() { [ "$GPU_HAS_NVIDIA" -eq 1 ]; }
has_amd_gpu()    { [ "$GPU_HAS_AMD" -eq 1 ]; }
has_intel_gpu()  { [ "$GPU_HAS_INTEL" -eq 1 ]; }

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
  [ "$DO_I386" -eq 1 ] || return 0

  if ! confirm "Enable i386 architecture (needed for many Wine/Proton titles)?"; then
    warn "Skipped i386 architecture"
    return 0
  fi

  if ! dpkg --print-foreign-architectures | grep -qx i386; then
    log "Enabling i386 architecture"
    run_sudo dpkg --add-architecture i386
    apt_cmd update
  else
    log "i386 architecture already enabled"
  fi
}

system_update() {
  [ "$DO_UPDATE" -eq 1 ] || return 0

  if ! confirm "Run apt update/upgrade now?"; then
    warn "Skipping package update/upgrade"
    return 0
  fi

  log "Updating package lists"
  apt_cmd update

  log "Upgrading installed packages"
  apt_cmd upgrade "${APT_UPGRADE_OPTS[@]}"

  log "Fixing package issues if needed"
  try_run_sudo env "${APT_ENV[@]}" apt-get "${APT_RETRY_OPTS[@]}" -f install "${APT_FIX_OPTS[@]}"
}

cleanup_system() {
  [ "$DO_CLEANUP" -eq 1 ] || return 0

  log "Cleaning up"
  apt_cmd autoremove -y
  apt_cmd autoclean -y
}

#######################################
# Install sections
#######################################

install_microcode() {
  [ "$DO_MICROCODE" -eq 1 ] || return 0

  case "$CPU_VENDOR" in
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

  if ! has_nvidia_gpu; then
    log "No NVIDIA GPU detected, skipping NVIDIA driver auto-install"
    return 0
  fi

  log "NVIDIA GPU detected"

  if ! confirm "Run ubuntu-drivers autoinstall for NVIDIA?"; then
    warn "Skipping NVIDIA auto-install"
    return 0
  fi

  if command -v ubuntu-drivers >/dev/null 2>&1; then
    try_run_sudo ubuntu-drivers autoinstall
  else
    warn "ubuntu-drivers not found, skipping NVIDIA auto-install"
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

  if ! has_multiverse_enabled; then
    warn "Multiverse does not appear enabled. Steam may be unavailable."
    warn "Enable it with:"
    warn "  sudo add-apt-repository multiverse && sudo apt update"
  fi

  if ! install_first_available steam-installer steam; then
    warn "No Steam package available in current repositories"
  fi
}

install_wine_stack() {
  log "Installing Wine stack"
  install_if_available "${WINE_PACKAGES[@]}"
}

install_gaming_tools() {
  [ "$DO_GAMING_TOOLS" -eq 1 ] || return 0

  log "Installing additional gaming tools"
  install_if_available "${GAMING_TOOLS_PACKAGES[@]}"
}

install_gaming_stack() {
  [ "$DO_GAMING" -eq 1 ] || return 0

  log "Installing gaming stack"
  install_steam
  install_if_available "${GAMING_PACKAGES[@]}"
  install_wine_stack
  install_gaming_tools
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

  if lsblk -dno ROTA | grep -qx '0'; then
    log "SSD detected, enabling fstrim.timer"
    if service_exists fstrim.timer; then
      try_run_sudo systemctl enable fstrim.timer
      try_run_sudo systemctl start fstrim.timer
    else
      warn "fstrim.timer service not found"
    fi
  else
    warn "No SSD detected, skipping fstrim.timer"
  fi
}

set_light_tunables() {
  [ "$DO_TUNING" -eq 1 ] || return 0

  if ! confirm "Apply lightweight sysctl tuning for gaming responsiveness?"; then
    warn "Skipping sysctl tuning"
    return 0
  fi

  log "Applying lightweight system tuning"

  write_if_changed 0644 "$SYSCTL_FILE" <<'EOF'
# Ubuntu gaming/dev tunables
# Safe, lightweight VM adjustments
vm.swappiness=10
vm.vfs_cache_pressure=50
EOF

  if [ "$DRY_RUN" -ne 1 ]; then
    sudo sysctl --system >/dev/null || warn "Failed to reload sysctl settings"
  fi
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
  ensure_user_dir "$LOCAL_BIN_DIR"

  write_if_changed 0755 "$LOCAL_BIN_DIR/power-battery" <<'EOF'
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

  write_if_changed 0755 "$LOCAL_BIN_DIR/power-balanced" <<'EOF'
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

  write_if_changed 0755 "$LOCAL_BIN_DIR/power-performance" <<'EOF'
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

  warn_if_local_bin_missing_from_path
}

create_gaming_helper_scripts() {
  [ "$DO_GAMING" -eq 1 ] || return 0

  log "Creating gaming helper scripts"
  ensure_user_dir "$LOCAL_BIN_DIR"

  write_if_changed 0755 "$LOCAL_BIN_DIR/game-launch" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [ $# -eq 0 ]; then
  echo "Usage: game-launch <command> [args...]" >&2
  exit 1
fi

runner=()
if command -v mangohud >/dev/null 2>&1; then
  runner+=(mangohud)
fi
if command -v gamemoderun >/dev/null 2>&1; then
  runner+=(gamemoderun)
fi

exec "${runner[@]}" "$@"
EOF

  warn_if_local_bin_missing_from_path
}

configure_mangohud_default() {
  [ "$DO_GAMING" -eq 1 ] || return 0

  log "Configuring default MangoHud profile"
  ensure_user_dir "$MANGOHUD_CONFIG_DIR"

  write_if_changed 0644 "$MANGOHUD_CONFIG_FILE" <<'EOF'
# Minimal readable default MangoHud config
legacy_layout=false
horizontal
fps
frametime
gpu_stats
cpu_stats
temp
ram
vram
EOF
}

#######################################
# Reporting
#######################################

print_plan() {
  cat <<EOF

========================================
Planned sections
========================================
Update system:              $DO_UPDATE
Enable i386 arch:           $DO_I386
Install microcode:          $DO_MICROCODE
Install NVIDIA driver:      $DO_NVIDIA
Install graphics stack:     $DO_GRAPHICS
Install gaming stack:       $DO_GAMING
Install gaming tools:       $DO_GAMING_TOOLS
Install dev tools:          $DO_DEVTOOLS
Install extras:             $DO_EXTRAS
Install power tools:        $DO_POWER
Setup Flathub:              $DO_FLATHUB
Enable TRIM:                $DO_TRIM
Apply sysctl tuning:        $DO_TUNING
Cleanup apt cache:          $DO_CLEANUP
Dry-run mode:               $DRY_RUN
Minimal mode:               $MINIMAL_MODE
Confirmations enabled:      $DO_CONFIRM
Assume yes:                 $ASSUME_YES
CPU vendor:                 $CPU_VENDOR

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
- gaming tools (gamescope/goverlay/vkbasalt/protontricks/obs)
- firmware updater
- optional dev tools
- Flatpak support
- mild system tuning
- power mode + launcher helper scripts

Helper commands:
  power-battery
  power-balanced
  power-performance
  game-launch %command%

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
     game-launch %command%

EOF
}

#######################################
# Main
#######################################

main() {
  parse_args "$@"
  preflight
  detect_cpu_vendor

  log "Starting Ubuntu gaming setup"
  print_plan

  if ! confirm "Proceed with the selected setup plan?"; then
    die "Cancelled by user"
  fi

  init_sudo
  system_update
  install_useful_bits
  ensure_pciutils_if_possible
  collect_gpu_info
  print_gpu_summary
  enable_i386_arch
  install_microcode
  install_nvidia_if_needed
  install_core_graphics
  install_gaming_stack
  configure_mangohud_default
  install_dev_basics
  install_power_profile_tools
  setup_flathub
  enable_trim_if_ssd
  set_light_tunables
  set_default_power_mode
  create_power_toggle_scripts
  create_gaming_helper_scripts
  cleanup_system
  show_notes
}

main "$@"
