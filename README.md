# Ubuntu Start: Lightweight Gaming & Dev Setup
[![Ask DeepWiki](https://devin.ai/assets/askdeepwiki.png)](https://deepwiki.com/cybat13/Ubuntu-start.git)

This repository contains a setup script to configure a fresh Ubuntu installation for gaming and development. It installs essential drivers, gaming clients, performance tools, and a lightweight set of development utilities.

## Features

-   **Gaming Essentials:** Steam, Lutris, Wine, Winetricks, GameMode, and MangoHud.
-   **Graphics Drivers:** Installs Vulkan and Mesa userspace drivers. Automatically detects and installs the latest proprietary NVIDIA drivers if an NVIDIA GPU is present.
-   **Hardware Support:** Installs the latest CPU microcode for AMD or Intel processors.
-   **System Utilities:** Sets up Flatpak with the Flathub repository, enables TRIM for SSDs, and installs firmware update tools.
-   **Developer Tools:** A curated selection of lightweight tools including Git, build-essential, Neovim, tmux, Python, Node.js, and more.
-   **Laptop Power Management:** Installs `power-profiles-daemon` and creates simple command-line scripts (`power-performance`, `power-balanced`, `power-battery`) to easily switch between power modes.
-   **Lightweight Tuning:** Applies minor system tunables for improved desktop responsiveness (`vm.swappiness`, `vm.vfs_cache_pressure`).

## Usage

To run the setup script, clone this repository and execute `install.sh`.

```bash
git clone https://github.com/cybat13/Ubuntu-start.git
cd Ubuntu-start
chmod +x install.sh
./install.sh
```

The script will ask for your password to install packages and configure the system using `sudo`.

## What This Script Does

The script automates the following setup steps:

1.  **System Update:** Updates package lists and upgrades all installed packages to their latest versions.
2.  **Enable 32-bit Architecture:** Adds `i386` architecture support, which is required by Steam and many games.
3.  **Install Hardware Drivers:**
    -   Detects your CPU (AMD/Intel) and installs the relevant microcode package.
    -   Detects your GPU vendor and automatically installs the recommended proprietary NVIDIA driver if applicable.
    -   Installs core Mesa and Vulkan libraries for graphics rendering.
4.  **Install Gaming Software:** Installs Steam, Lutris, GameMode, and MangoHud from the standard Ubuntu repositories.
5.  **Install Development & System Tools:** Installs a base set of tools for software development and system administration.
6.  **Configure System Services & Settings:**
    -   Adds the Flathub remote for Flatpak.
    -   Enables and starts `fstrim.timer` if an SSD is detected to maintain drive performance.
    -   Applies lightweight system settings via `sysctl`.
    -   Enables `power-profiles-daemon` and creates helper scripts in `~/.local/bin` for easy power management.
7.  **System Cleanup:** Removes unnecessary packages and cleans the package cache.

## Post-Installation

After the script completes, a system reboot is highly recommended to ensure all changes take effect.

### Power Mode Helpers

For laptops, you can easily switch power profiles from the terminal:

-   `power-performance` - For maximum performance while gaming (best when plugged in).
-   `power-balanced` - For normal daily use.
-   `power-battery` - To save energy when on battery power.

To check the current active profile, run:
```bash
powerprofilesctl get
```
**Note:** `~/.local/bin` must be in your shell's `PATH`. If the commands don't work, add the following line to your `~/.bashrc` or `~/.zshrc`:
```bash
export PATH="$HOME/.local/bin:$PATH"
```

### Recommended Steam Launch Options

For the best experience, use the following launch options for your games in Steam to enable MangoHud and GameMode:
```
mangohud gamemoderun %command%
```

### Testing the Setup

You can verify that the key components are working with these commands:

-   **Test GameMode:** `gamemoded -t`
-   **Test Vulkan:** `vulkaninfo | less`
