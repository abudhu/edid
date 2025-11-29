# Installation Guide for Custom EDID on Bazzite Linux

## Prerequisites

- Bazzite Linux system (Fedora Atomic-based)
- Administrative (sudo) access
- Basic knowledge of terminal commands

## Step-by-Step Installation

### 1. Generate the Custom EDID

First, create the EDID binary file for your 5120x1440 ultrawide resolution:

```bash
python3 create_edid.py
```

This will create:
- `ultrawide_5120x1440.bin` - The binary EDID file
- `ultrawide_5120x1440.hex` - Human-readable hex dump

### 2. Run the Setup Script

Execute the setup script to configure your system:

```bash
chmod +x setup.sh
./setup.sh
```

This script will:
- Install the EDID file to `/usr/lib/firmware/edid/`
- Create kernel module configuration
- Set up dracut configuration for rpm-ostree systems
- Create helper scripts

### 3. Identify Your Display Connector

Run the connector identification script:

```bash
./check_connectors.sh
```

Look for disconnected connectors and note their names (e.g., `HDMI-A-1`, `DP-1`, etc.).

### 4. Configure the Correct Connector

Edit the kernel module configuration:

```bash
sudo nano /etc/modprobe.d/drm_kms_helper.conf
```

Replace `HDMI-A-1` with your target connector name from step 3.

### 5. Reboot

Restart your system to load the new configuration:

```bash
sudo reboot
```

### 6. Verify the Custom Resolution

After reboot, check if the custom resolution is available:

For Wayland (default on Bazzite):
```bash
# Install wlr-randr if not available
flatpak install org.freedesktop.Sdk.Extension.wlroots

# Check available outputs and resolutions
wlr-randr
```

For X11 (if using X session):
```bash
xrandr
```

### 7. Enable the Virtual Display

You may need to manually enable the virtual display:

**Using GNOME Settings:**
1. Open Settings → Displays
2. Look for the new ultrawide display
3. Enable it and set resolution to 5120x1440

**Using wlr-randr (Wayland):**
```bash
# Enable the virtual output
wlr-randr --output HDMI-A-1 --mode 5120x1440 --pos 1920,0
```

**Using xrandr (X11):**
```bash
# Enable the virtual output
xrandr --output HDMI-1 --mode 5120x1440 --right-of eDP-1
```

### 8. Configure Moonlight

1. Open Moonlight
2. Go to Settings → Streaming
3. Set resolution to 5120x1440
4. Set the display to your virtual ultrawide display

## Troubleshooting

### Custom Resolution Not Available

1. Check kernel logs:
   ```bash
   dmesg | grep -i edid
   dmesg | grep -i drm
   ```

2. Verify EDID file is loaded:
   ```bash
   cat /sys/module/drm_kms_helper/parameters/edid_firmware
   ```

3. Check if connector exists:
   ```bash
   ls /sys/class/drm/card*/card*/status
   ```

### Wrong Connector Name

1. Run `./check_connectors.sh` again
2. Try different connector names in the configuration
3. Common names: `HDMI-A-1`, `HDMI-A-2`, `DP-1`, `DP-2`, `VIRTUAL1`

### Moonlight Not Detecting Resolution

1. Ensure the virtual display is enabled and active
2. Try setting the virtual display as primary
3. Restart Moonlight after enabling the display
4. Check Moonlight logs for resolution detection issues

### Performance Issues

1. Ensure your GPU can handle 5120x1440 encoding
2. Adjust Moonlight bitrate settings
3. Use hardware encoding if available
4. Consider using a lower refresh rate (30Hz) for better stability

## Advanced Configuration

### Custom Refresh Rates

Edit `create_edid.py` to modify the refresh rate in the `detailed_timing_1` calculation.

### Multiple Virtual Displays

Create additional EDID files with different names and add multiple entries to the kernel module configuration.

### Persistent Configuration on rpm-ostree

For persistent configuration across system updates, consider creating a custom overlay or using systemd services.

## Uninstallation

To remove the custom EDID configuration:

```bash
./uninstall.sh
sudo reboot
```

## Support

If you encounter issues:

1. Check Bazzite community forums
2. Review kernel and system logs
3. Verify hardware compatibility
4. Test with simpler resolutions first

## References

- [Linux DRM/KMS EDID Documentation](https://www.kernel.org/doc/html/latest/gpu/drm-kms.html)
- [Bazzite Documentation](https://bazzite.gg/)
- [Moonlight Documentation](https://moonlight-stream.org/)