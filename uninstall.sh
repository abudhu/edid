#!/bin/bash
#
# Uninstall script for custom EDID configuration
#

echo "Removing custom EDID configuration..."

# Remove EDID file
sudo rm -f /usr/lib/firmware/edid/ultrawide_5120x1440.bin

# Remove modprobe configuration
sudo rm -f /etc/modprobe.d/drm_kms_helper.conf

# Remove dracut configuration
sudo rm -f /etc/dracut.conf.d/edid.conf

echo "Custom EDID configuration removed. Reboot to apply changes."
