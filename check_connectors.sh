#!/bin/bash
#
# Script to help identify display connectors on your system
#

echo "=== GPU Cards and Vendors ==="
for card_path in /sys/class/drm/card[0-9]*; do
    if [[ -d "$card_path/device" ]]; then
        card=$(basename "$card_path")
        # Only show card[0-9], not card[0-9]-*
        if [[ $card =~ ^card[0-9]+$ ]]; then
            vendor_id=$(cat "$card_path/device/vendor" 2>/dev/null || echo "unknown")
            device_id=$(cat "$card_path/device/device" 2>/dev/null || echo "unknown")
            
            vendor_name="Unknown"
            case "$vendor_id" in
                "0x10de") vendor_name="NVIDIA (Discrete GPU)" ;;
                "0x1002") vendor_name="AMD (Discrete GPU)" ;;
                "0x8086") vendor_name="Intel (Integrated GPU/iGPU)" ;;
            esac
            
            echo "$card: $vendor_name"
            echo "  Vendor: $vendor_id, Device: $device_id"
        fi
    fi
done

echo -e "\n=== Display Connectors by Card ==="
for card_path in /sys/class/drm/card[0-9]*; do
    if [[ -d "$card_path" ]]; then
        card=$(basename "$card_path")
        if [[ $card =~ ^card[0-9]+$ ]]; then
            echo -e "\n$card:"
            for connector in "$card_path"/$card-*/status; do
                if [[ -f "$connector" ]]; then
                    connector_name=$(echo "$connector" | sed "s/.*\/$card-\(.*\)\/status/\1/")
                    status=$(cat "$connector")
                    echo "  $card-$connector_name: $status"
                fi
            done
        fi
    fi
done

echo -e "\n=== Current Kernel Module Parameters ==="
if [[ -f /sys/module/drm_kms_helper/parameters/edid_firmware ]]; then
    echo "edid_firmware: $(cat /sys/module/drm_kms_helper/parameters/edid_firmware)"
else
    echo "No EDID firmware parameter set"
fi

echo -e "\n=== Instructions ==="
echo "1. Identify your DISCRETE GPU card (NVIDIA/AMD, NOT Intel iGPU)"
echo "2. Look for DISCONNECTED connectors on that card"
echo "3. Edit /etc/modprobe.d/drm_kms_helper.conf"
echo "4. Use the full connector name including card prefix (e.g., card1-HDMI-A-1)"
echo "5. Example: options drm_kms_helper edid_firmware=card1-HDMI-A-1:edid/msi_mpg491cqpx_144hz.bin"
echo "6. Reboot to apply changes"
echo ""
echo "IMPORTANT: Use a connector from your discrete GPU, not the iGPU!"
