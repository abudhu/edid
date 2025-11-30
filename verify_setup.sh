#!/bin/bash
#
# Verification script to check if EDID configuration is working
#

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }

echo "=== EDID Configuration Verification ==="
echo ""

# Detect firmware directory
if command -v rpm-ostree >/dev/null 2>&1; then
    EDID_DIR="/etc/firmware/edid"
else
    EDID_DIR="/usr/lib/firmware/edid"
fi

# 1. Check if EDID files are installed
print_status "Checking EDID files in $EDID_DIR..."
if [[ -d "$EDID_DIR" ]]; then
    print_success "EDID directory exists"
    
    edid_count=$(ls -1 "$EDID_DIR"/*.bin 2>/dev/null | wc -l)
    if [[ $edid_count -gt 0 ]]; then
        print_success "Found $edid_count EDID file(s)"
        ls -lh "$EDID_DIR"/*.bin
    else
        print_error "No EDID files found in $EDID_DIR"
    fi
else
    print_error "EDID directory does not exist: $EDID_DIR"
fi
echo ""

# 2. Check kernel module configuration
print_status "Checking kernel module configuration..."
MODPROBE_CONF="/etc/modprobe.d/drm_kms_helper.conf"
if [[ -f "$MODPROBE_CONF" ]]; then
    print_success "Modprobe configuration exists"
    echo "Configuration:"
    cat "$MODPROBE_CONF" | grep -v "^#" | grep -v "^$"
else
    print_error "Modprobe configuration not found: $MODPROBE_CONF"
fi
echo ""

# 3. Check if kernel module has loaded the EDID parameter
print_status "Checking loaded kernel parameters..."
if [[ -f /sys/module/drm_kms_helper/parameters/edid_firmware ]]; then
    edid_param=$(cat /sys/module/drm_kms_helper/parameters/edid_firmware)
    if [[ -n "$edid_param" && "$edid_param" != "(null)" ]]; then
        print_success "EDID firmware parameter is loaded: $edid_param"
    else
        print_warning "EDID firmware parameter exists but is empty"
        print_warning "This means the kernel module config was not applied"
        echo ""
        print_status "Troubleshooting steps:"
        echo "  1. Check if modprobe.d config is correct:"
        echo "     cat /etc/modprobe.d/drm_kms_helper.conf"
        echo "  2. For Bazzite/immutable systems, rebuild initramfs:"
        echo "     sudo rpm-ostree initramfs --enable"
        echo "  3. Then reboot again"
    fi
else
    print_warning "drm_kms_helper parameter file not found"
    print_warning "This means drm_kms_helper is built into the kernel"
    echo ""
    print_status "For built-in drm_kms_helper, check kernel command line:"
    if grep -q "drm.edid_firmware" /proc/cmdline 2>/dev/null; then
        karg=$(grep -o "drm.edid_firmware=[^ ]*" /proc/cmdline)
        print_success "Kernel parameter is set: $karg"
    else
        print_error "Kernel parameter drm.edid_firmware is NOT set"
        echo ""
        print_status "To fix this on rpm-ostree systems:"
        echo "  1. Get your connector from the display connectors section below"
        echo "  2. Run: sudo rpm-ostree kargs --append=\"drm.edid_firmware=CONNECTOR:edid/EDID_FILE\""
        echo "  3. Example: sudo rpm-ostree kargs --append=\"drm.edid_firmware=card0-DP-2:edid/msi_mpg491cqpx_144hz.bin\""
        echo "  4. Reboot to apply"
        echo ""
        print_warning "Or use ./configure_msi.sh which will handle this automatically"
    fi
fi
echo ""

# 3a. Check kernel module load status
print_status "Checking kernel module load status..."
if lsmod | grep -q drm_kms_helper; then
    print_success "drm_kms_helper module is loaded"
elif lsmod | grep -q drm; then
    print_warning "DRM is loaded but drm_kms_helper may be built-in"
    print_status "Checking if drm_kms_helper is built into kernel..."
    if [[ -d /sys/module/drm_kms_helper ]]; then
        print_success "drm_kms_helper is available (built-in to kernel)"
    else
        print_error "drm_kms_helper not found"
    fi
else
    print_warning "DRM subsystem not detected - are you in a graphical session?"
fi

# Check dmesg for EDID loading messages
if command -v dmesg >/dev/null 2>&1; then
    print_status "Checking kernel messages for EDID..."
    echo "Recent EDID-related messages:"
    sudo dmesg | grep -i "edid\|firmware" | grep -i "drm\|card\|HDMI\|DP" | tail -10 || print_warning "No EDID messages in kernel log"
fi
echo ""

# 4. Check dracut configuration (for immutable systems)
if command -v rpm-ostree >/dev/null 2>&1; then
    print_status "Checking dracut configuration..."
    DRACUT_CONF="/etc/dracut.conf.d/edid.conf"
    if [[ -f "$DRACUT_CONF" ]]; then
        print_success "Dracut configuration exists"
        cat "$DRACUT_CONF"
    else
        print_warning "Dracut configuration not found: $DRACUT_CONF"
    fi
    echo ""
fi

# 5. Check available display connectors
print_status "Checking display connectors..."
connector_found=false
for card_path in /sys/class/drm/card[0-9]*; do
    if [[ -d "$card_path" ]]; then
        card=$(basename "$card_path")
        if [[ $card =~ ^card[0-9]+$ ]]; then
            vendor_id=$(cat "$card_path/device/vendor" 2>/dev/null || echo "unknown")
            vendor_name="Unknown"
            case "$vendor_id" in
                "0x10de") vendor_name="NVIDIA" ;;
                "0x1002") vendor_name="AMD" ;;
                "0x8086") vendor_name="Intel" ;;
            esac
            
            echo "  $card [$vendor_name]:"
            
            for connector in "$card_path"/$card-*/status; do
                if [[ -f "$connector" ]]; then
                    conn_name=$(echo "$connector" | sed "s/.*\/$card-\(.*\)\/status/\1/")
                    status=$(cat "$connector" 2>/dev/null)
                    
                    if [[ "$status" == "connected" ]]; then
                        echo "    $card-$conn_name: $status ✓"
                        connector_found=true
                        
                        # Check if EDID override is active on this connector
                        edid_override="$card_path/$card-$conn_name/edid"
                        if [[ -f "$edid_override" ]]; then
                            edid_size=$(stat -f%z "$edid_override" 2>/dev/null || stat -c%s "$edid_override" 2>/dev/null)
                            if [[ $edid_size -eq 128 ]]; then
                                print_success "    Custom EDID active on $card-$conn_name (128 bytes)"
                            fi
                        fi
                    else
                        echo "    $card-$conn_name: $status"
                    fi
                fi
            done
        fi
    fi
done
echo ""

# 6. Check display outputs
print_status "Checking active displays..."
if command -v xrandr >/dev/null 2>&1 && [[ -n "$DISPLAY" ]]; then
    xrandr --query | grep -E "connected|Screen" | head -10
elif command -v wlr-randr >/dev/null 2>&1; then
    wlr-randr | grep -E "Enabled|Mode"
else
    print_warning "Neither xrandr nor wlr-randr available"
    print_status "Use GNOME Settings or KDE Display Settings to check displays"
fi
echo ""

# 7. Summary and next steps
echo "=== Summary ==="
if [[ -f "$MODPROBE_CONF" ]] && [[ -d "$EDID_DIR" ]]; then
    # Check if parameter is loaded via sysfs or kernel cmdline
    param_loaded=false
    if [[ -f /sys/module/drm_kms_helper/parameters/edid_firmware ]]; then
        edid_param=$(cat /sys/module/drm_kms_helper/parameters/edid_firmware)
        if [[ -n "$edid_param" && "$edid_param" != "(null)" ]]; then
            param_loaded=true
        fi
    elif grep -q "drm.edid_firmware" /proc/cmdline 2>/dev/null; then
        param_loaded=true
    fi
    
    if $param_loaded; then
        print_success "Configuration is active and loaded!"
        echo ""
        echo "Next steps:"
        echo "1. Check your display settings (GNOME Settings → Displays)"
        echo "2. Enable the virtual display if it appears as disabled"
        echo "3. Configure Moonlight to use 5120x1440 resolution"
    else
        print_warning "Configuration installed but not yet active"
        echo ""
        echo "Next steps:"
        echo "1. If drm_kms_helper is built into kernel, you need to add kernel parameter:"
        echo "   sudo rpm-ostree kargs --append=\"drm.edid_firmware=CONNECTOR:edid/EDID_FILE\""
        echo "   (Or use ./configure_msi.sh which handles this automatically)"
        echo "2. Reboot your system to activate the configuration"
        echo "3. After reboot, run this script again to verify"
        echo "4. Enable the virtual display in display settings"
    fi
else
    print_error "Configuration incomplete"
    echo ""
    echo "Please run ./setup.sh to complete the installation"
fi
