#!/bin/bash
#
# Setup script for custom EDID on Bazzite Linux
# This script configures the system to use a custom EDID file for virtual display output
#

set -e

# Cleanup function
cleanup() {
    if [[ $? -ne 0 ]]; then
        echo -e "\033[0;31m[ERROR]\033[0m Setup failed. Please check the error messages above."
    fi
}

trap cleanup EXIT

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    print_error "This script should not be run as root. Please run as a regular user."
    print_status "The script will use sudo when needed."
    exit 1
fi

# Check if we're on Bazzite/Fedora
if ! command -v rpm-ostree >/dev/null 2>&1; then
    print_warning "This script is designed for Bazzite/Fedora Atomic. Your mileage may vary on other distributions."
fi

# Check for required dependencies
if ! command -v python3 >/dev/null 2>&1; then
    print_error "Python 3 is not installed. Please install it first."
    exit 1
fi

# Check system requirements
print_status "Checking system requirements..."

# Check kernel version
KERNEL_VERSION=$(uname -r | cut -d. -f1,2)
KERNEL_MAJOR=$(echo "$KERNEL_VERSION" | cut -d. -f1)
KERNEL_MINOR=$(echo "$KERNEL_VERSION" | cut -d. -f2)
if [[ $KERNEL_MAJOR -lt 5 ]] || [[ $KERNEL_MAJOR -eq 5 && $KERNEL_MINOR -lt 10 ]]; then
    print_warning "Kernel version $KERNEL_VERSION may not fully support custom EDID. Recommended: 5.10+"
fi

# Check if we're on an immutable system (Bazzite/Fedora Atomic)
if command -v rpm-ostree >/dev/null 2>&1; then
    FIRMWARE_BASE="/etc/firmware"
    print_status "Detected immutable system, using $FIRMWARE_BASE"
else
    FIRMWARE_BASE="/usr/lib/firmware"
    if [[ ! -d "$FIRMWARE_BASE" ]]; then
        print_error "Firmware directory $FIRMWARE_BASE not found. Your system may not support custom EDID."
        exit 1
    fi
fi

print_status "Setting up custom EDID for 5120x1440 ultrawide resolution..."

# Create EDID files if they don't exist
if [[ ! -f "ultrawide_5120x1440.bin" ]] || [[ ! -f "msi_mpg491cqpx_60hz.bin" ]]; then
    print_status "EDID files not found. Generating them now..."
    if [[ -f "create_edid.py" ]]; then
        python3 create_edid.py
    else
        print_error "create_edid.py not found. Please run this script from the correct directory."
        exit 1
    fi
fi

# Ask user which refresh rate they prefer
echo ""
print_status "Available EDID files with different refresh rates:"
echo "  1) 60Hz  - Standard refresh rate, best compatibility"
echo "  2) 120Hz - High refresh rate"
echo "  3) 144Hz - Gaming optimized"
echo "  4) 240Hz - Maximum refresh rate (requires powerful GPU)"
echo ""
read -p "Select default refresh rate (1-4) [1]: " refresh_choice
refresh_choice=${refresh_choice:-1}

case $refresh_choice in
    1) selected_hz="60" ;;
    2) selected_hz="120" ;;
    3) selected_hz="144" ;;
    4) selected_hz="240" ;;
    *)
        print_warning "Invalid choice, defaulting to 60Hz"
        selected_hz="60"
        ;;
esac

selected_file="msi_mpg491cqpx_${selected_hz}hz.bin"
print_success "Selected ${selected_hz}Hz refresh rate"
echo ""

# Create firmware directory for EDID files
EDID_DIR="$FIRMWARE_BASE/edid"
print_status "Creating EDID firmware directory at $EDID_DIR..."
sudo mkdir -p "$EDID_DIR"

# Copy EDID files to firmware directory
print_status "Installing MSI MPG 491CQPX EDID files..."
for file in msi_mpg491cqpx_*.bin; do
    if [[ -f "$file" ]]; then
        sudo cp "$file" "$EDID_DIR/"
        sudo chmod 644 "$EDID_DIR/$file"
        
        # Verify the copy was successful
        if [[ ! -f "$EDID_DIR/$file" ]] || [[ ! -r "$EDID_DIR/$file" ]]; then
            print_error "Failed to install $file"
            exit 1
        fi
        
        print_success "Installed $file"
    fi
done

# Copy the selected refresh rate as the default
if [[ ! -f "$selected_file" ]]; then
    print_error "Selected EDID file $selected_file not found!"
    exit 1
fi

sudo cp "$selected_file" "$EDID_DIR/ultrawide_5120x1440.bin"
sudo chmod 644 "$EDID_DIR/ultrawide_5120x1440.bin"

# Verify default file
if [[ ! -f "$EDID_DIR/ultrawide_5120x1440.bin" ]] || [[ ! -r "$EDID_DIR/ultrawide_5120x1440.bin" ]]; then
    print_error "Failed to install ultrawide_5120x1440.bin"
    exit 1
fi

print_success "Installed ultrawide_5120x1440.bin (${selected_hz}Hz default)"

# Create kernel module configuration for DRM
print_status "Configuring DRM kernel module..."
MODPROBE_DIR="/etc/modprobe.d"
sudo mkdir -p "$MODPROBE_DIR"

# Create the modprobe configuration
sudo tee "$MODPROBE_DIR/drm_kms_helper.conf" > /dev/null << 'EOF'
# Custom EDID configuration for virtual display
# This loads a custom EDID for connector HDMI-A-1
# Adjust the connector name based on your system
options drm_kms_helper edid_firmware=HDMI-A-1:edid/ultrawide_5120x1440.bin
EOF

print_success "Created DRM kernel module configuration"

# For Bazzite/rpm-ostree systems, we need to rebuild initramfs
if command -v rpm-ostree >/dev/null 2>&1; then
    print_status "Detected rpm-ostree system. Creating initramfs configuration..."
    
    # Create dracut configuration to include the EDID
    DRACUT_CONF_DIR="/etc/dracut.conf.d"
    sudo mkdir -p "$DRACUT_CONF_DIR"
    
    sudo tee "$DRACUT_CONF_DIR/edid.conf" > /dev/null << EOF
# Include custom EDID in initramfs
install_items+=" $EDID_DIR/ultrawide_5120x1440.bin "
EOF

    print_success "Created dracut configuration for EDID"
fi

# Create a script to help identify the correct connector
cat > check_connectors.sh << 'EOF'
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
EOF

chmod +x check_connectors.sh
print_success "Created connector identification script: check_connectors.sh"

chmod +x configure_msi.sh
print_success "Created MSI configuration tool: configure_msi.sh"

# Create uninstall script
cat > uninstall.sh << 'EOF'
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
EOF

chmod +x uninstall.sh
print_success "Created uninstall script: uninstall.sh"

print_status "Setup completed! Next steps:"
echo ""
echo "RECOMMENDED: Use the interactive configuration tool:"
echo "  ./configure_msi.sh"
echo ""
echo "OR manually configure:"
echo "1. Run './check_connectors.sh' to identify your display connectors"
echo "2. Edit /etc/modprobe.d/drm_kms_helper.conf to match your connector and desired refresh rate"
echo "3. Reboot your system"
echo "4. Enable the virtual display using GNOME Settings or wlr-randr"
echo "5. Configure Moonlight to use 5120x1440 resolution"
echo ""
echo "Available refresh rates: 60Hz, 120Hz, 144Hz, 240Hz"
echo "Default configuration: 60Hz on HDMI-A-1"
echo ""
print_warning "After reboot, you may need to manually enable the virtual display"
print_warning "Higher refresh rates (240Hz) may require more GPU power for encoding"