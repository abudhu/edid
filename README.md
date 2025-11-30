# MSI MPG 491CQPX QD-OLED Virtual Display for Bazzite/Wayland

This repository contains tools and configuration files to create custom EDID (Extended Display Identification Data) files specifically designed for the MSI MPG 491CQPX QD-OLED ultrawide monitor (5120x1440) on Bazzite Linux with Wayland, optimized for Moonlight game streaming.

## Overview

When streaming games via Moonlight, you may want to use your ultrawide monitor's native resolution even when it's not physically connected to the streaming host. By creating and loading custom EDID files that match your MSI monitor's specifications, you can trick the system into thinking the monitor is connected, enabling optimal streaming quality.

## Files

- `create_edid.py` - Python script to generate MSI MPG 491CQPX EDID files
- `msi_mpg491cqpx_*.bin` - Generated EDID binary files (60Hz, 120Hz, 144Hz, 240Hz)
- `setup.sh` - Automated setup script for Bazzite
- `configure_msi.sh` - Interactive configuration tool for refresh rate selection
- `check_connectors.sh` - Helper script to identify display connectors
- `drm_kms_helper.conf` - Kernel module configuration template
- `install.md` - Detailed installation instructions

## Quick Start

1. Run the EDID generator: `python3 create_edid.py`
2. Execute the setup script: `./setup.sh`
3. Configure your preferred refresh rate: `./configure_msi.sh`
4. Reboot your system
5. Enable the virtual display in GNOME Settings
6. Configure Moonlight to use 5120x1440 resolution

## Features

- **Multiple Refresh Rates**: 60Hz, 120Hz, 144Hz, 240Hz support
- **MSI Monitor Specs**: Matches actual MPG 491CQPX specifications
- **Interactive Setup**: Easy-to-use configuration tool
- **Auto-Detection**: Automatically detects available display connectors
- **Configuration Backup**: Saves backups before making changes
- **Validation**: Verifies EDID integrity before installation
- **Logging**: Tracks configuration changes in `/tmp/msi_edid_config.log`
- **Bazzite Optimized**: Designed for rpm-ostree immutable systems
- **Wayland Compatible**: Works with Bazzite's default Wayland session

## Requirements

- Bazzite Linux (Fedora Atomic-based immutable OS)
- MSI MPG 491CQPX QD-OLED monitor (or similar 5120x1440 ultrawide)
- Python 3
- Administrative (sudo) access
- Linux kernel 5.10 or newer (recommended)

## GPU Compatibility

- **NVIDIA**: Requires proprietary drivers; Wayland support may be limited
- **AMD**: Full support on recent kernels (5.15+), excellent Wayland compatibility
- **Intel**: Full support on recent kernels, excellent Wayland compatibility

### Discrete GPU vs Integrated GPU (iGPU)

**IMPORTANT**: If your system has both a discrete GPU (NVIDIA/AMD) and an integrated GPU (Intel), you need to ensure the EDID is loaded on the correct GPU.

The setup scripts now automatically:
- Detect and display all GPU cards with their vendors
- Identify which cards are discrete GPUs vs iGPUs
- Prioritize discrete GPU connectors during auto-detection
- Show connectors grouped by their GPU card

When configuring, **always choose a connector from your discrete GPU** (NVIDIA/AMD), not the Intel iGPU, unless you specifically intend to use the iGPU for streaming.

Example connector names:
- `card0-HDMI-A-1` - HDMI port on card0
- `card1-DP-1` - DisplayPort on card1

The card number matters - make sure you select a connector from the correct card!

## Wayland Compositor Notes

For **Sway** users, you may need to reload the configuration after enabling the display:
```bash
swaymsg reload
```

For **KDE Plasma** Wayland users, use System Settings → Display Configuration to enable the virtual display.