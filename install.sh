#!/usr/bin/env bash
set -Eeuo pipefail

#######################################
# Configuration
#######################################

readonly SCRIPT_VERSION="2.0"
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd ""){(dirname "${BASH_SOURCE[0]}")}"," && pwd)"
readonly LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/ubuntu-start"
readonly LOG_FILE="$LOG_DIR/install-$(date +%Y%m%d_%H%M%S).log"
readonly CONFIG_BACKUP_DIR="$LOG_DIR/backups"

# Ensure log directory exists
mkdir -p "$LOG_DIR" "$CONFIG_BACKUP_DIR"

trap 'echo "[ERROR] Line $LINENO: $BASH_COMMAND" >&2' ERR

#######################################
# Logging / helpers
#######################################

log()  {
  local msg="$1"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  printf "\n[%s] ==> %s\n" "$timestamp" "$msg" | tee -a "$LOG_FILE"
}

warn() {
  local msg="$1"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  printf "[%s] [WARN] %s\n" "$timestamp" "$msg" | tee -a "$LOG_FILE" >&2
}

die() {
  local msg="$1"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  printf "[%s] [ERROR] %s\n" "$timestamp" "$msg" | tee -a "$LOG_FILE" >&2
  exit 1
}

debug() {
  if [ "
${DEBUG:-0}" -eq 1 ]; then
    local msg="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    printf "[%s] [DEBUG] %s\n" "$timestamp" "$msg" | tee -a "$LOG_FILE" >&2
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"
}

check_version() {
  local cmd="$1"
  local min_version="$2"
  
  if ! command -v "$cmd" >/dev/null 2>&1; then
    return 1
  fi
  
  local version
  version="$cmd" --version 2>/dev/null | head -n1 | grep -oP '\d+\.\d+' | head -n1)
  
  if [ -z "$version" ]; then
    debug "Could not determine version of $cmd"
    return 0
  fi
  
  if [ "$(printf '%s\n' "$min_version" "$version" | sort -V | head -n1)" = "$min_version" ]; then
    return 0
  fi
  
  return 1
}

backup_config() {
  local file="$1"
  if [ -f "$file" ]; then
    local backup_name="
"(basename "$file")-$(date +%s).bak"
    cp -v "$file" "$CONFIG_BACKUP_DIR/$backup_name" >> "$LOG_FILE"
    log "Backed up $file to $CONFIG_BACKUP_DIR/$backup_name"
  fi
}

prompt_continue() {
  local msg="${1:-Continue?}"
  if [ "$ASSUME_YES" -eq 0 ]; then
    local response
    read -rp "$msg (y/n): " response
    [ "$response" = "y" ] || return 1
  fi
  return 0
}

#######################################
# Defaults / flags
#######################################

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
ASSUME_YES=1
DEBUG=0
INTERACTIVE=0

print_usage() {
  cat <<'EOF'
Usage:
  ubuntu-gaming-setup.sh [options]

Options:
  --dry-run              Show what would run, but do not make changes
  --minimal              Install a smaller core set only
  --full                 Enable all default sections
  --interactive          Ask before each major step
  --no-assume-yes        Prompt for confirmation
  --debug                Enable debug output
  --no-update            Skip apt update/upgrade
  --skip-microcode       Skip CPU microcode installation
  --skip-nvidia          Skip NVIDIA driver auto-install
  --skip-graphics        Skip Mesa/Vulkan userspace packages
  --skip-gaming          Skip Steam/Lutris/Wine/GameMode/MangoHud
  --skip-devtools        Skip developer tools
  --skip-extras          Skip useful extras
  --skip-power           Skip power-profiles-daemon and helper scripts
  --skip-flathub         Skip Flathub setup
  --skip-trim            Skip fstrim.timer enablement
  --skip-tuning          Skip sysctl tuning
  --skip-cleanup         Skip apt autoremove/autoclean
  --version              Show version
  --help                 Show this help

Examples:
  ./ubuntu-gaming-setup.sh
  ./ubuntu-gaming-setup.sh --minimal
  ./ubuntu-gaming-setup.sh --dry-run --skip-devtools
  ./ubuntu-gaming-setup.sh --interactive --skip-nvidia
  DEBUG=1 ./ubuntu-gaming-setup.sh --debug
EOF
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run)        DRY_RUN=1 ;; ...



