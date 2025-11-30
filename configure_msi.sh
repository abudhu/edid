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

get_gpu_info() {
    local card=$1
    local vendor="unknown"
    local device_name="unknown"
    
    if [[ -f "/sys/class/drm/$card/device/vendor" ]]; then
        local vendor_id=$(cat "/sys/class/drm/$card/device/vendor" 2>/dev/null)
        case "$vendor_id" in
            "0x10de") vendor="NVIDIA" ;;
            "0x1002") vendor="AMD" ;;
            "0x8086") vendor="Intel (iGPU)" ;;
            *) vendor="$vendor_id" ;;
        esac
    fi
    
    # Try to get device name from uevent or modalias
    if [[ -f "/sys/class/drm/$card/device/uevent" ]]; then
        device_name=$(grep "PCI_SLOT_NAME" "/sys/class/drm/$card/device/uevent" 2>/dev/null | cut -d'=' -f2 || echo "unknown")
    fi
    
    echo "$vendor ($device_name)"
}

list_gpu_cards() {
    print_status "Available GPU cards:"
    echo ""
    
    local cards=()
    for card_path in /sys/class/drm/card[0-9]*; do
        if [[ -d "$card_path/device" ]]; then
            local card=$(basename "$card_path")
            # Skip card[0-9]-* entries, only show card[0-9]
            if [[ $card =~ ^card[0-9]+$ ]]; then
                local gpu_info=$(get_gpu_info "$card")
                echo "  $card: $gpu_info"
                cards+=("$card")
            fi
        fi
    done
    echo ""
    
    # Highlight which is likely discrete vs integrated
    for card in "${cards[@]}"; do
        local vendor_id=$(cat "/sys/class/drm/$card/device/vendor" 2>/dev/null || echo "")
        if [[ "$vendor_id" == "0x8086" ]]; then
            print_warning "$card appears to be integrated GPU (Intel)"
        elif [[ "$vendor_id" == "0x10de" ]] || [[ "$vendor_id" == "0x1002" ]]; then
            print_success "$card appears to be discrete GPU (NVIDIA/AMD)"
        fi
    done
    echo ""
}

detect_connector() {
    print_status "Auto-detecting available connectors..."
    
    local connectors=()
    local discrete_connectors=()
    
    for connector in /sys/class/drm/card*/card*/status; do
        if [[ -f "$connector" ]]; then
            # Extract full connector name including card prefix (e.g., card1-HDMI-A-1)
            connector_name=$(echo "$connector" | sed 's/.*\/card\([0-9]\)-\(.*\)\/status/card\1-\2/')
            status=$(cat "$connector" 2>/dev/null || echo "unknown")
            
            if [[ "$status" == "disconnected" ]]; then
                connectors+=("$connector_name")
                
                # Check if this connector belongs to a discrete GPU (non-Intel)
                local card=$(echo "$connector_name" | grep -o 'card[0-9]\+')
                if [[ -f "/sys/class/drm/$card/device/vendor" ]]; then
                    local vendor_id=$(cat "/sys/class/drm/$card/device/vendor" 2>/dev/null)
                    # Prioritize NVIDIA (0x10de) and AMD (0x1002) over Intel (0x8086)
                    if [[ "$vendor_id" == "0x10de" ]] || [[ "$vendor_id" == "0x1002" ]]; then
                        discrete_connectors+=("$connector_name")
                    fi
                fi
            fi
        fi
    done
    
    # Prefer discrete GPU connectors if available
    if [[ ${#discrete_connectors[@]} -gt 0 ]]; then
        echo "${discrete_connectors[0]}"
    elif [[ ${#connectors[@]} -gt 0 ]]; then
        print_warning "No discrete GPU connectors found, using first available."
        echo "${connectors[0]}"
    else
        print_warning "No disconnected connectors found. Using card0-HDMI-A-1 as default."
        echo "card0-HDMI-A-1"
    fi
}

show_current_config() {
    echo "=== Current Configuration ==="
    echo ""
    
    # Show GPU cards first
    list_gpu_cards
    
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
    list_gpu_cards
    
    print_status "Available display connectors by card:"
    for card_path in /sys/class/drm/card[0-9]*; do
        if [[ -d "$card_path" ]]; then
            local card=$(basename "$card_path")
            if [[ $card =~ ^card[0-9]+$ ]]; then
                local gpu_info=$(get_gpu_info "$card")
                echo "  $card [$gpu_info]:"
                for connector in "$card_path"/$card-*/status; do
                    if [[ -f "$connector" ]]; then
                        local conn_name=$(echo "$connector" | sed "s/.*\/$card-\(.*\)\/status/\1/")
                        local status=$(cat "$connector" 2>/dev/null)
                        echo "    $card-$conn_name: $status"
                    fi
                done
            fi
        fi
    done
    echo ""
    print_warning "Choose a DISCONNECTED connector from your DISCRETE GPU (NVIDIA/AMD)."
    print_warning "Avoid Intel iGPU connectors unless that's your intended target."
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