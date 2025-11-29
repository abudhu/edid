#!/bin/bash
#
# MSI MPG 491CQPX EDID Configuration Tool
# Easily switch between different refresh rate configurations
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

EDID_DIR="/usr/lib/firmware/edid"
MODPROBE_CONF="/etc/modprobe.d/drm_kms_helper.conf"
LOG_FILE="/tmp/msi_edid_config.log"

log_action() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

detect_connector() {
    print_status "Auto-detecting available connectors..."
    
    local connectors=()
    for connector in /sys/class/drm/card*/card*/status; do
        if [[ -f "$connector" ]]; then
            connector_name=$(echo "$connector" | sed 's/.*\/\(.*\)\/status/\1/')
            status=$(cat "$connector" 2>/dev/null || echo "unknown")
            if [[ "$status" == "disconnected" ]]; then
                connectors+=("$connector_name")
            fi
        fi
    done
    
    if [[ ${#connectors[@]} -eq 0 ]]; then
        print_warning "No disconnected connectors found. Using HDMI-A-1 as default."
        echo "HDMI-A-1"
    else
        echo "${connectors[0]}"
    fi
}

show_current_config() {
    echo "=== Current Configuration ==="
    
    if [[ -f "$MODPROBE_CONF" ]]; then
        echo "Kernel module configuration:"
        cat "$MODPROBE_CONF"
    else
        echo "No kernel module configuration found."
    fi
    
    echo ""
    echo "Available EDID files:"
    ls -la "$EDID_DIR"/msi_mpg491cqpx_*.bin 2>/dev/null || echo "No MSI EDID files found"
    
    echo ""
    echo "Current kernel parameter:"
    if [[ -f /sys/module/drm_kms_helper/parameters/edid_firmware ]]; then
        echo "edid_firmware: $(cat /sys/module/drm_kms_helper/parameters/edid_firmware)"
    else
        echo "No EDID firmware parameter currently loaded"
    fi
}

list_refresh_rates() {
    echo "=== Available Refresh Rate Configurations ==="
    local count=1
    for file in "$EDID_DIR"/msi_mpg491cqpx_*.bin; do
        if [[ -f "$file" ]]; then
            filename=$(basename "$file")
            refresh_rate=$(echo "$filename" | grep -o '[0-9]\+hz' | grep -o '[0-9]\+')
            echo "$count) ${refresh_rate}Hz ($filename)"
            ((count++))
        fi
    done
    
    if [[ $count -eq 1 ]]; then
        print_error "No MSI EDID files found. Please run setup.sh first."
        return 1
    fi
}

configure_refresh_rate() {
    local refresh_rate=$1
    local connector=${2:-"HDMI-A-1"}
    
    local edid_file="msi_mpg491cqpx_${refresh_rate}hz.bin"
    
    if [[ ! -f "$EDID_DIR/$edid_file" ]]; then
        print_error "EDID file for ${refresh_rate}Hz not found: $edid_file"
        log_action "ERROR: EDID file not found for ${refresh_rate}Hz"
        return 1
    fi
    
    log_action "Configuring ${refresh_rate}Hz on connector $connector"
    print_status "Configuring ${refresh_rate}Hz refresh rate for connector $connector..."
    
    # Backup existing configuration
    if [[ -f "$MODPROBE_CONF" ]]; then
        sudo cp "$MODPROBE_CONF" "$MODPROBE_CONF.backup.$(date +%Y%m%d_%H%M%S)"
        print_status "Backed up existing configuration"
        log_action "Backed up configuration to $MODPROBE_CONF.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    # Update modprobe configuration
    sudo tee "$MODPROBE_CONF" > /dev/null << EOF
# MSI MPG 491CQPX QD-OLED custom EDID configuration
# Connector: $connector, Refresh Rate: ${refresh_rate}Hz
options drm_kms_helper edid_firmware=$connector:edid/$edid_file
EOF
    
    print_success "Updated kernel module configuration for ${refresh_rate}Hz"
    print_warning "Reboot required to apply changes"
}

interactive_setup() {
    echo "=== MSI MPG 491CQPX Interactive Configuration ==="
    echo ""
    
    # Show current configuration
    show_current_config
    echo ""
    
    # List available refresh rates
    if ! list_refresh_rates; then
        return 1
    fi
    echo ""
    
    # Get user choice for refresh rate
    read -p "Select refresh rate (1-4): " choice
    
    case $choice in
        1) refresh_rate="60" ;;
        2) refresh_rate="120" ;;
        3) refresh_rate="144" ;;
        4) refresh_rate="240" ;;
        *) 
            print_error "Invalid choice"
            return 1
            ;;
    esac
    
    echo ""
    print_status "Available display connectors:"
    ./check_connectors.sh 2>/dev/null || {
        echo "HDMI-A-1 (common)"
        echo "HDMI-A-2 (alternate)"
        echo "DP-1 (DisplayPort)"
        echo "DP-2 (alternate DisplayPort)"
    }
    echo ""
    
    # Auto-detect connector
    detected_connector=$(detect_connector)
    print_status "Auto-detected connector: $detected_connector"
    echo ""
    
    # Get connector choice
    read -p "Enter connector name (default: $detected_connector): " connector
    connector=${connector:-"$detected_connector"}
    
    echo ""
    configure_refresh_rate "$refresh_rate" "$connector"
    
    echo ""
    print_status "Configuration complete!"
    print_warning "Please reboot to apply the changes."
    print_status "After reboot, use display settings or wlr-randr to enable the ${refresh_rate}Hz mode."
}

case "${1:-interactive}" in
    "current"|"status")
        show_current_config
        ;;
    "list")
        list_refresh_rates
        ;;
    "60"|"120"|"144"|"240")
        configure_refresh_rate "$1" "${2:-HDMI-A-1}"
        ;;
    "interactive"|"")
        interactive_setup
        ;;
    *)
        echo "MSI MPG 491CQPX EDID Configuration Tool"
        echo ""
        echo "Usage: $0 [command] [connector]"
        echo ""
        echo "Commands:"
        echo "  interactive    Interactive configuration (default)"
        echo "  current        Show current configuration"
        echo "  list           List available refresh rates"
        echo "  60|120|144|240 Configure specific refresh rate"
        echo ""
        echo "Examples:"
        echo "  $0                    # Interactive mode"
        echo "  $0 current           # Show current config"
        echo "  $0 144 HDMI-A-1     # Set 144Hz on HDMI-A-1"
        echo "  $0 240 DP-1         # Set 240Hz on DP-1"
        ;;
esac