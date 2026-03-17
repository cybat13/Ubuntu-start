# Ubuntu Start: Lightweight Gaming & Development Setup

[![Ask DeepWiki](https://devin.ai/assets/askdeepwiki.png)](https://deepwiki.com/cybat13/Ubuntu-start.git)
![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04%2B-orange.svg)

A comprehensive, automated setup script for configuring a fresh Ubuntu installation optimized for gaming and development. This script intelligently detects your hardware and installs essential drivers, gaming platforms, development tools, and system optimizations with minimal user intervention.

> **⚡ Quick Start:** Clone, run, and enjoy a fully configured gaming & dev environment in minutes.

## 📋 Table of Contents

- [Features](#-features)
- [System Requirements](#-system-requirements)
- [Installation](#-installation)
- [What Gets Installed](#-what-gets-installed)
- [Post-Installation](#-post-installation)
- [Troubleshooting](#-troubleshooting)
- [Uninstalling](#-uninstalling)
- [Contributing](#-contributing)
- [License](#-license)

## ⚙️ Features

### Gaming & Performance
- **Gaming Platforms:** Steam, Lutris, Wine, Winetricks for running Windows games on Linux
- **Performance Tools:** GameMode (automatic CPU/GPU optimization) and MangoHud (in-game performance monitoring)
- **Graphics Stack:** Vulkan and Mesa drivers for optimal gaming performance

### Hardware Support
- **GPU Detection:** Automatically detects and installs the latest proprietary NVIDIA drivers
- **CPU Optimization:** Installs the latest microcode updates for both AMD and Intel processors
- **Storage Optimization:** Enables TRIM for SSDs to maintain drive performance over time
- **Firmware Updates:** Installs tools for keeping system firmware up-to-date

### Development Environment
- **Version Control:** Git with common configurations
- **Build Tools:** build-essential, compiler chains, and development headers
- **Editors & Tools:** Neovim, tmux, and other developer essentials
- **Languages:** Python, Node.js, and npm pre-installed and ready
- **Package Management:** Flatpak integration with Flathub for easy app installation

### Power Management (Laptop-Friendly)
- **Power Profiles Daemon:** Intelligent power management with easy-to-use CLI commands
- **Quick Power Switching:** Commands to instantly switch between performance, balanced, and battery-saving modes
- **Smart Defaults:** Optimized system tunables for desktop responsiveness

## 📦 System Requirements

- **OS:** Ubuntu 22.04 LTS or later (including Ubuntu 24.04)
- **RAM:** Minimum 4GB (8GB+ recommended for gaming)
- **Disk Space:** ~10GB free space
- **Internet Connection:** Required for package downloads
- **Sudo Access:** Script requires administrator privileges

## 🚀 Installation

### Method 1: Recommended (Direct Clone & Execute)

```bash
git clone https://github.com/cybat13/Ubuntu-start.git
cd Ubuntu-start
chmod +x install.sh
./install.sh
```

### Method 2: One-Liner (Use with Caution)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/cybat13/Ubuntu-start/main/install.sh)
```

**What Happens Next:**
1. The script will display what it intends to install
2. You'll be prompted for your sudo password
3. Installation proceeds automatically (takes 10-20 minutes depending on internet speed)
4. After completion, a system reboot is **highly recommended**

## 📥 What Gets Installed

### 1. System Foundation
- Updates all existing packages to latest versions
- Enables 32-bit architecture support (required by Steam and many games)
- Configures system repositories and package sources

### 2. Hardware Drivers
- **CPU:** AMD microcode or Intel microcode (auto-detected)
- **GPU:** 
  - Mesa libraries (universal graphics support)
  - Vulkan drivers (modern graphics API)
  - Proprietary NVIDIA drivers (if NVIDIA GPU detected)
- **Firmware:** LVFS integration for hardware firmware updates

### 3. Gaming Suite
| Component | Purpose |
|-----------|---------|
| **Steam** | Official Linux gaming platform |
| **Lutris** | Game management and compatibility layer |
| **Wine** | Windows application compatibility |
| **Winetricks** | Dependency installer for Wine |
| **GameMode** | Automatic CPU/GPU optimization during gaming |
| **MangoHud** | In-game performance overlay (FPS, temps, CPU/GPU usage) |

### 4. Development Tools
```
Git • build-essential • Python 3 • Node.js & npm • Neovim
tmux • curl • wget • htop • nano • vim • gcc • g++ • make
```

### 5. System Utilities
- **Flatpak:** Container-based app distribution (Flathub repository)
- **Firmware Tools:** fwupd for BIOS/firmware updates
- **SSD Management:** fstrim for TRIM support
- **System Monitor:** Tools for performance analysis

### 6. System Optimizations
- SSD TRIM enabled via `fstrim.timer`
- Swappiness reduced for better responsiveness
- VFS cache pressure tuned for desktop workloads
- Unnecessary packages cleaned up

## 🔧 Post-Installation

### ⚡ Power Management (Laptops)

After installation, use these commands to manage power profiles:

```bash
# Switch to maximum performance (best for gaming, needs AC power)
power-performance

# Balanced mode (normal daily use)
power-balanced

# Battery saver mode (extends battery life)
power-battery

# Check current active profile
powerprofilesctl get
```

**If commands don't work:**
Ensure `~/.local/bin` is in your PATH by adding this to `~/.bashrc` or `~/.zshrc`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Then restart your terminal.

### 🎮 Gaming Optimization

#### Steam Launch Options
For the best gaming experience with performance monitoring and auto-optimization, set these launch options in Steam:

1. Right-click game → Properties → Launch Options
2. Add: `mangohud gamemoderun %command%`

This enables:
- **GameMode:** Automatic CPU/GPU prioritization
- **MangoHud:** Real-time performance metrics overlay

#### Recommended Graphics Settings
- **Resolution:** Match your monitor's native resolution
- **GPU Driver:** Use "Vulkan" when available in game settings
- **VRAM:** Set to match your GPU's VRAM (check with `glxinfo | grep "VRAM"`)

### ✅ Verify Installation

Test that key components are working correctly:

```bash
# Test GameMode is active
gamemoded -t

# Check Vulkan support
vulkaninfo | head -20

# Verify Steam installation
steam --version

# Check GPU drivers
glxinfo | grep "OpenGL version"

# Test power profiles
powerprofilesctl profiles

# Monitor system resources
htop
```

## 🐛 Troubleshooting

### Script Won't Run
**Error:** `Permission denied` when running `./install.sh`

**Solution:**
```bash
chmod +x install.sh
./install.sh
```

### Steam Won't Start
**Error:** Steam crashes or won't launch

**Solution:**
1. Clear Steam cache: `rm -rf ~/.steam/ubuntu12_32`
2. Reinstall Steam runtime: `steam --help` (will trigger automatic fix)
3. Enable 32-bit support: `sudo dpkg --add-architecture i386 && sudo apt update`

### Games Won't Run / Poor Performance
**Issue:** Games crash or run slowly

**Troubleshooting Steps:**
1. Verify Vulkan is working: `vulkaninfo | grep "apiVersion"`
2. Check GPU drivers: `glxinfo | grep "Device"`
3. Monitor temps: `watch -n 1 "gpustat"` (requires `gpustat` package)
4. Test with a simple game first (e.g., Portal 2)
5. Check game compatibility at [ProtonDB](https://protondb.com)

### Vulkan Not Working
**Solution:**
```bash
sudo apt reinstall libvulkan1 vulkan-tools vulkan-icd-loader
```

### Power Commands Not Found
**Issue:** `power-performance`, `power-balanced`, `power-battery` commands don't exist

**Solution:**
```bash
# Check if scripts were created
ls -la ~/.local/bin/power-*

# If missing, add PATH and run:
mkdir -p ~/.local/bin
export PATH="$HOME/.local/bin:$PATH"

# Manually create the scripts:
echo 'powerprofilesctl set performance' > ~/.local/bin/power-performance
echo 'powerprofilesctl set balanced' > ~/.local/bin/power-balanced
echo 'powerprofilesctl set power-saver' > ~/.local/bin/power-battery
chmod +x ~/.local/bin/power-*
```

### NVIDIA Drivers Issues
**Issue:** NVIDIA drivers didn't install or aren't working

**Solution:**
```bash
# Remove broken drivers
sudo apt remove nvidia-* 

# Reinstall latest drivers
sudo apt install nvidia-driver-latest-dkms

# Verify installation
nvidia-smi
```

## 🗑️ Uninstalling / Reverting Changes

If you need to revert to a clean Ubuntu installation:

```bash
# Remove all installed packages (this is extensive)
sudo apt autoremove --purge steam lutris wine winetricks gamemode mangohud

# Disable Flatpak
sudo systemctl disable flatpak
sudo apt remove flatpak

# Remove power management scripts
rm -rf ~/.local/bin/power-*

# Optional: Revert sysctl changes
sudo sysctl -w vm.swappiness=60
sudo sysctl -w vm.vfs_cache_pressure=100
```

## 🤝 Contributing

Contributions are welcome! Please feel free to:

- Report bugs or issues
- Suggest new features or tools
- Improve documentation
- Submit pull requests

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 💡 Tips & Tricks

### Getting the Best Gaming Performance
1. **Use performance power profile** when gaming: `power-performance`
2. **Enable MangoHud** to monitor performance: `mangohud gamemoderun %command%`
3. **Close background apps** to free up system resources
4. **Use Vulkan** renderer in games when available
5. **Monitor temperatures** with: `watch -n 1 "nvidia-smi"`

### For Development
- Use Neovim with plugins for a lightweight editor: `nvim ~/.bashrc`
- Create tmux sessions for organized workflows: `tmux new-session -s work`
- Install additional tools via Flatpak: `flatpak install flathub [APP_ID]`

### SSD Health
```bash
# Check SSD TRIM status
sudo fstrim -v /

# Monitor SSD health
sudo apt install nvme-cli
sudo nvme smart-log /dev/nvme0n1
```

---

**Last Updated:** 2026-03-17

For issues, questions, or feature requests, please open an [issue on GitHub](https://github.com/cybat13/Ubuntu-start/issues).