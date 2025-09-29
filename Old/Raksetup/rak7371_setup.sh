#!/bin/bash

# RAK7371 WisGate Developer Base Setup Script
# For RAK7371 with RAK5146 concentrator
# Author: Auto-generated setup script
# Version: 1.0

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables
SX1302_DIR="sx1302_hal"
GITHUB_REPO="https://github.com/Lora-net/sx1302_hal.git"
DEFAULT_BAND="EU868"
TTN_SERVER="eu1.cloud.thethings.network"

# Exit handling variables
LAST_EXIT_TIME=0
EXIT_REQUESTED=false

# Function to handle exit requests
handle_exit_request() {
    local current_time=$(date +%s)
    local time_diff=$((current_time - LAST_EXIT_TIME))

    if [ "$EXIT_REQUESTED" = true ] && [ $time_diff -lt 2 ]; then
        print_status "Double 'x' detected. Exiting program..."
        exit 0
    else
        EXIT_REQUESTED=true
        LAST_EXIT_TIME=$current_time
        print_warning "Press 'x' again within 2 seconds to exit program, or any other key to return to main menu"
        return 1  # Signal to return to main menu
    fi
}

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================${NC}"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        print_error "This script should not be run as root. Please run as a regular user with sudo privileges."
        exit 1
    fi
}

# Function to check if device is connected
check_device_connection() {
    print_status "Checking device connection..."
    if lsusb | grep -q "STMicroelectronics Virtual COM Port"; then
        print_status "✓ RAK7371 WisGate Developer Base detected"
        return 0
    else
        print_error "RAK7371 WisGate Developer Base not detected. Please check USB connection."
        return 1
    fi
}

# Function to install dependencies
install_dependencies() {
    print_status "Installing build dependencies..."
    sudo apt update
    sudo apt install -y make gcc git
    print_status "✓ Dependencies installed successfully"
}

# Function to check if software is already installed
check_installation() {
    if [ -d "$SX1302_DIR" ]; then
        return 0  # Already installed
    else
        return 1  # Not installed
    fi
}

# Function to install software
install_software() {
    print_status "Installing RAK7371 software..."

    # Remove existing directory if it exists
    if [ -d "$SX1302_DIR" ]; then
        print_warning "Removing existing installation..."
        rm -rf "$SX1302_DIR"
    fi

    # Clone repository
    print_status "Downloading software from GitHub..."
    sudo git clone "$GITHUB_REPO"

    # Navigate to directory
    cd "$SX1302_DIR"

    # Compile software
    print_status "Compiling software (this may take a few minutes)..."
    sudo make

    print_status "✓ Software compiled successfully"
    cd ..
}

# Function to configure band plan
configure_band() {
    local band=$1
    print_status "Configuring for $band band..."

    cd "$SX1302_DIR/packet_forwarder"

    # List available configuration files
    print_status "Available configuration files:"
    ls -1 global_conf.json.*.USB 2>/dev/null || {
        print_error "No USB configuration files found!"
        return 1
    }

    # Copy appropriate configuration
    local config_file="global_conf.json.sx1250.${band}.USB"
    if [ -f "$config_file" ]; then
        sudo cp "$config_file" global_conf.json
        sudo chown $(whoami):$(whoami) global_conf.json 2>/dev/null || true
        print_status "✓ Configuration set for $band band"
    else
        print_error "Configuration file for $band not found!"
        print_status "Available configurations:"
        ls -1 global_conf.json.*.USB
        return 1
    fi

    cd ../..
}

# Function to configure TTN server
configure_ttn_server() {
    local server_address=$1
    print_status "Configuring TTN server: $server_address"

    local config_file="$SX1302_DIR/packet_forwarder/global_conf.json"

    if [ -f "$config_file" ]; then
        # Create backup
        sudo cp "$config_file" "${config_file}.backup"

        # Update server address
        sudo sed -i "s/\"server_address\": \".*\"/\"server_address\": \"$server_address\"/" "$config_file"
        # Fix port numbers to TTN standard
        sudo sed -i "s/\"serv_port_up\": [0-9]*/\"serv_port_up\": 1700/" "$config_file"
        sudo sed -i "s/\"serv_port_down\": [0-9]*/\"serv_port_down\": 1700/" "$config_file"
        print_status "✓ TTN server configured"
    else
        print_error "Configuration file not found!"
        return 1
    fi
}

# Function to configure gateway EUI
configure_gateway_eui() {
    local eui=$1
    print_status "Configuring Gateway EUI: $eui"

    local config_file="$SX1302_DIR/packet_forwarder/global_conf.json"

    if [ -f "$config_file" ]; then
        # Update gateway ID with the EUI
        sudo sed -i "s/\"gateway_ID\": \".*\"/\"gateway_ID\": \"$eui\"/" "$config_file"
        print_status "✓ Gateway EUI configured"
    else
        print_error "Configuration file not found!"
        return 1
    fi
}

# Function to get gateway EUI
get_gateway_eui() {
    print_status "Retrieving gateway EUI..."

    if [ -f "$SX1302_DIR/util_chip_id/chip_id" ]; then
        cd "$SX1302_DIR/util_chip_id"

        # First try to reset the concentrator
        if [ -f "$SX1302_DIR/tools/reset_lgw.sh" ]; then
            print_status "Resetting concentrator..."
            sudo "$SX1302_DIR/tools/reset_lgw.sh" start 2>/dev/null || true
            sleep 1
        fi

        # Run chip_id and capture output
        local output=$(sudo ./chip_id -u -d /dev/ttyACM0 2>&1)

        # Extract EUI from output (format: "INFO: concentrator EUI: 0x0016c001ffxxxxxx")
        local eui=$(echo "$output" | grep -i "concentrator EUI" | sed 's/.*EUI: 0x//' | tr -d '[:space:]')

        if [ -n "$eui" ] && [ "$eui" != "0" ]; then
            print_status "Gateway EUI: $eui"
            echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
            echo -e "${GREEN}Gateway EUI: ${YELLOW}$eui${NC}"
            echo -e "${GREEN}Please save this EUI for TTN registration${NC}"
            echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
            echo "$eui"  # Return the EUI
        else
            print_warning "Could not retrieve EUI. Trying alternate method..."
            # Try without reset
            output=$(sudo ./chip_id -u -d /dev/ttyACM0 2>&1)
            eui=$(echo "$output" | grep -i "concentrator EUI" | sed 's/.*EUI: 0x//' | tr -d '[:space:]')

            if [ -n "$eui" ] && [ "$eui" != "0" ]; then
                print_status "Gateway EUI: $eui"
                echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
                echo -e "${GREEN}Gateway EUI: ${YELLOW}$eui${NC}"
                echo -e "${GREEN}Please save this EUI for TTN registration${NC}"
                echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
                echo "$eui"  # Return the EUI
            else
                print_error "Failed to retrieve EUI. Error output:"
                echo "$output" | grep -i "error" | head -3
                print_warning "You will need to enter the EUI manually."
                echo ""  # Return empty string
            fi
        fi
        cd ../..
    else
        print_warning "chip_id utility not found. You will need to enter the EUI manually."
        echo ""  # Return empty string
    fi
}

# Function to input gateway EUI
input_gateway_eui() {
    echo "" >&2
    echo "Gateway EUI Configuration" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "Enter 'x' to exit to main menu (press twice to exit program)" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "" >&2

    # Try to get EUI automatically first
    print_status "Attempting to retrieve Gateway EUI automatically..." >&2
    local auto_eui=$(get_gateway_eui 2>&1 | tail -n 1)

    if [ -n "$auto_eui" ] && [ "$auto_eui" != "" ]; then
        echo "" >&2
        echo "Detected Gateway EUI: ${YELLOW}$auto_eui${NC}" >&2
        read -p "Use this EUI? (Y/n/x): " use_auto

        if [[ "$use_auto" =~ ^[Xx]$ ]]; then
            if handle_exit_request; then
                echo "MENU_EXIT" >&2
                echo "MENU_EXIT"
            else
                echo "MENU_EXIT" >&2
                echo "MENU_EXIT"
            fi
            return 0
        elif [[ "$use_auto" =~ ^[Nn]$ ]]; then
            echo "" >&2
            echo "Enter your Gateway EUI manually" >&2
            echo "Format: 16 hex characters (e.g., 0016C001F12A89DD)" >&2
            read -p "Gateway EUI (or 'x' to exit): " manual_eui

            # Check for exit request
            if [[ "$manual_eui" =~ ^[Xx]$ ]]; then
                if handle_exit_request; then
                    echo "MENU_EXIT" >&2
                    echo "MENU_EXIT"
                else
                    echo "MENU_EXIT" >&2
                    echo "MENU_EXIT"
                fi
                return 0
            fi

            # Clean up the input (remove 0x, spaces, commas)
            manual_eui=$(echo "$manual_eui" | sed 's/0x//g' | sed 's/,//g' | sed 's/ //g' | tr '[:lower:]' '[:upper:]')

            # Validate format (16 hex characters)
            if [[ ! "$manual_eui" =~ ^[0-9A-F]{16}$ ]]; then
                print_error "Invalid EUI format. Using detected EUI instead." >&2
                echo "$auto_eui"
            else
                print_status "Using manual EUI: $manual_eui" >&2
                echo "$manual_eui"
            fi
        else
            print_status "Using detected EUI: $auto_eui" >&2
            echo "$auto_eui"
        fi
    else
        echo "" >&2
        echo "Could not detect Gateway EUI automatically." >&2
        echo "Enter your Gateway EUI manually" >&2
        echo "Format: 16 hex characters (e.g., 0016C001F12A89DD)" >&2
        echo "You can find it on the device label or using 'chip_id' utility" >&2
        read -p "Gateway EUI (or 'x' to exit): " manual_eui

        # Check for exit request
        if [[ "$manual_eui" =~ ^[Xx]$ ]]; then
            if handle_exit_request; then
                echo "MENU_EXIT" >&2
                echo "MENU_EXIT"
            else
                echo "MENU_EXIT" >&2
                echo "MENU_EXIT"
            fi
            return 0
        fi

        # Clean up the input (remove 0x, spaces, commas)
        manual_eui=$(echo "$manual_eui" | sed 's/0x//g' | sed 's/,//g' | sed 's/ //g' | tr '[:lower:]' '[:upper:]')

        # Validate format (16 hex characters)
        while [[ ! "$manual_eui" =~ ^[0-9A-F]{16}$ ]]; do
            print_error "Invalid EUI format. Must be 16 hex characters." >&2
            echo "Example: 0016C001F12A89DD" >&2
            read -p "Gateway EUI (or 'x' to exit): " manual_eui

            # Check for exit request in the loop
            if [[ "$manual_eui" =~ ^[Xx]$ ]]; then
                if handle_exit_request; then
                    echo "MENU_EXIT" >&2
                    echo "MENU_EXIT"
                else
                    echo "MENU_EXIT" >&2
                    echo "MENU_EXIT"
                fi
                return 0
            fi

            manual_eui=$(echo "$manual_eui" | sed 's/0x//g' | sed 's/,//g' | sed 's/ //g' | tr '[:lower:]' '[:upper:]')
        done

        print_status "Using manual EUI: $manual_eui" >&2
        echo "$manual_eui"
    fi
}

# Function to start packet forwarder
start_packet_forwarder() {
    print_status "Starting packet forwarder..."
    print_warning "Press Ctrl+C to stop the packet forwarder"

    cd "$SX1302_DIR/packet_forwarder"
    sudo ./lora_pkt_fwd
    cd ../..
}

# Function to stop packet forwarder
stop_packet_forwarder() {
    print_status "Stopping packet forwarder..."
    sudo pkill -f lora_pkt_fwd 2>/dev/null || true
    print_status "✓ Packet forwarder stopped"
}

# Function to view current configuration
view_configuration() {
    print_header "Current Gateway Configuration"

    local config_file="$SX1302_DIR/packet_forwarder/global_conf.json"

    if [ ! -f "$config_file" ]; then
        print_error "Configuration file not found!"
        print_status "Please run installation first."
        return 1
    fi

    # Extract key configuration values
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}KEY CONFIGURATION SETTINGS:${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # Get Gateway ID
    local gateway_id=$(grep '"gateway_ID"' "$config_file" | cut -d'"' -f4)
    echo -e "${GREEN}Gateway EUI/ID:${NC} ${YELLOW}$gateway_id${NC}"

    # Get server configuration
    local server=$(grep '"server_address"' "$config_file" | cut -d'"' -f4)
    local port_up=$(grep '"serv_port_up"' "$config_file" | sed 's/.*: \([0-9]*\).*/\1/')
    local port_down=$(grep '"serv_port_down"' "$config_file" | sed 's/.*: \([0-9]*\).*/\1/')

    echo -e "${GREEN}TTN Server:${NC} $server"
    echo -e "${GREEN}Port (up/down):${NC} $port_up / $port_down"

    # Check if ports are correct
    if [ "$port_up" != "1700" ] || [ "$port_down" != "1700" ]; then
        print_warning "⚠ Ports should be 1700 for TTN!"
    fi

    # Get radio frequencies
    echo ""
    echo -e "${GREEN}Radio Configuration:${NC}"
    local radio_0_freq=$(grep '"radio_0"' "$config_file" -A2 | grep '"freq"' | sed 's/.*: \([0-9]*\).*/\1/')
    local radio_1_freq=$(grep '"radio_1"' "$config_file" -A2 | grep '"freq"' | sed 's/.*: \([0-9]*\).*/\1/')
    echo "  Radio 0 frequency: $radio_0_freq Hz"
    echo "  Radio 1 frequency: $radio_1_freq Hz"

    # Detect band based on frequency
    if [ "$radio_0_freq" = "868500000" ]; then
        echo -e "  ${GREEN}Detected Band: EU868${NC}"
    elif [ "$radio_0_freq" = "904300000" ]; then
        echo -e "  ${GREEN}Detected Band: US915${NC}"
    elif [ "$radio_0_freq" = "923000000" ]; then
        echo -e "  ${GREEN}Detected Band: AS923${NC}"
    elif [ "$radio_0_freq" = "486600000" ]; then
        echo -e "  ${GREEN}Detected Band: CN490${NC}"
    fi

    # Show other important settings
    echo ""
    echo -e "${GREEN}Other Settings:${NC}"
    local keepalive=$(grep '"keepalive_interval"' "$config_file" | sed 's/.*: \([0-9]*\).*/\1/')
    local stat_interval=$(grep '"stat_interval"' "$config_file" | sed 's/.*: \([0-9]*\).*/\1/')
    echo "  Keepalive interval: $keepalive seconds"
    echo "  Status interval: $stat_interval seconds"

    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # Ask if user wants to see full config
    read -p "Do you want to view the full configuration file? (y/N): " view_full

    if [[ "$view_full" =~ ^[Yy]$ ]]; then
        echo ""
        echo -e "${YELLOW}FULL CONFIGURATION FILE:${NC}"
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        # Show only the gateway_conf section for clarity
        sed -n '/"gateway_conf"/,/^    }/p' "$config_file" | head -20
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo "Config file location: $config_file"
    fi
}

# Function to uninstall software
uninstall_software() {
    print_header "RAK7371 Software Uninstallation"

    print_warning "This will remove the RAK7371 software and all configurations."
    read -p "Are you sure you want to uninstall? (y/N): " confirm

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_status "Uninstallation cancelled."
        return 0
    fi

    # Stop packet forwarder if running
    stop_packet_forwarder

    # Remove software directory
    if [ -d "$SX1302_DIR" ]; then
        print_status "Removing software directory..."
        sudo rm -rf "$SX1302_DIR"
        print_status "✓ Software directory removed"
    else
        print_warning "Software directory not found."
    fi

    print_status "✓ RAK7371 software uninstalled successfully"
}

# Function to show status
show_status() {
    print_header "RAK7371 Status"

    # Check device connection
    if check_device_connection; then
        echo -e "${GREEN}Device Connection: ✓ Connected${NC}"
    else
        echo -e "${RED}Device Connection: ✗ Not detected${NC}"
    fi

    # Check software installation
    if check_installation; then
        echo -e "${GREEN}Software Installation: ✓ Installed${NC}"

        # Check if packet forwarder is running
        if pgrep -f lora_pkt_fwd > /dev/null; then
            echo -e "${GREEN}Packet Forwarder: ✓ Running${NC}"
        else
            echo -e "${YELLOW}Packet Forwarder: ⚠ Stopped${NC}"
        fi

        # Show current configuration
        local config_file="$SX1302_DIR/packet_forwarder/global_conf.json"
        if [ -f "$config_file" ]; then
            local server=$(grep "server_address" "$config_file" | cut -d'"' -f4)
            echo -e "${BLUE}TTN Server: $server${NC}"
        fi
    else
        echo -e "${RED}Software Installation: ✗ Not installed${NC}"
    fi
}

# Function to show help
show_help() {
    cat << EOF
RAK7371 WisGate Developer Base Setup Script

Usage: $0 [OPTION]

Options:
    install     Install and configure the RAK7371 software
    uninstall   Uninstall the RAK7371 software
    start       Start the packet forwarder
    stop        Stop the packet forwarder
    restart     Restart the packet forwarder
    status      Show current status
    eui         Get gateway EUI
    config      Reconfigure band plan and TTN server
    view        View current configuration
    help        Show this help message

Examples:
    $0 install          # Install software and configure
    $0 uninstall        # Remove software and configurations
    $0 start            # Start packet forwarder
    $0 view             # View current configuration
    $0 status           # Check status
    $0 restart          # Restart packet forwarder

EOF
}

# Function to select band plan
select_band_plan() {
    echo "" >&2
    echo "Available band plans:" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "1) EU868 - Europe (863-870 MHz)" >&2
    echo "2) US915 - North America (902-928 MHz)" >&2
    echo "3) AS923 - Asia-Pacific (923 MHz)" >&2
    echo "4) CN490 - China (470-510 MHz)" >&2
    echo "x) Exit to main menu (press twice to exit program)" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "" >&2
    read -p "Select band plan (1-4, x to exit) [default: 1 for EU868]: " choice

    case $choice in
        1|"")
            print_status "Selected: EU868 (Europe)" >&2
            echo "EU868"
            ;;
        2)
            print_status "Selected: US915 (North America)" >&2
            echo "US915"
            ;;
        3)
            print_status "Selected: AS923 (Asia-Pacific)" >&2
            echo "AS923"
            ;;
        4)
            print_status "Selected: CN490 (China)" >&2
            echo "CN490"
            ;;
        x|X)
            if handle_exit_request; then
                echo "MENU_EXIT"
            else
                echo "MENU_EXIT"
            fi
            ;;
        *)
            print_error "Invalid choice '$choice'. Available options are:" >&2
            echo "  1 - EU868 (Europe)" >&2
            echo "  2 - US915 (North America)" >&2
            echo "  3 - AS923 (Asia-Pacific)" >&2
            echo "  4 - CN490 (China)" >&2
            echo "  x - Exit to main menu" >&2
            print_warning "Using EU868 (Europe) as default." >&2
            echo "EU868"
            ;;
    esac
}

# Function to select TTN server
select_ttn_server() {
    echo "" >&2
    echo "Available TTN servers:" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "1) eu1.cloud.thethings.network  - Europe" >&2
    echo "2) nam1.cloud.thethings.network - North America" >&2
    echo "3) au1.cloud.thethings.network  - Australia" >&2
    echo "4) as1.cloud.thethings.network  - Asia" >&2
    echo "5) Custom server address" >&2
    echo "x) Exit to main menu (press twice to exit program)" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "" >&2
    read -p "Select TTN server (1-5, x to exit) [default: 1 for Europe]: " choice

    case $choice in
        1|"")
            print_status "Selected: Europe TTN server" >&2
            echo "eu1.cloud.thethings.network"
            ;;
        2)
            print_status "Selected: North America TTN server" >&2
            echo "nam1.cloud.thethings.network"
            ;;
        3)
            print_status "Selected: Australia TTN server" >&2
            echo "au1.cloud.thethings.network"
            ;;
        4)
            print_status "Selected: Asia TTN server" >&2
            echo "as1.cloud.thethings.network"
            ;;
        5)
            echo "" >&2
            echo "Enter custom server address" >&2
            echo "Example: my-server.example.com or 192.168.1.100" >&2
            read -p "Server address: " custom_server

            # Remove any leading/trailing whitespace
            custom_server=$(echo "$custom_server" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

            # Basic validation - check if not empty
            if [ -z "$custom_server" ]; then
                print_error "Server address cannot be empty" >&2
                print_warning "Using Europe server as default." >&2
                echo "eu1.cloud.thethings.network"
            else
                # Optional: Basic format validation (contains at least one dot for domain or IP)
                if [[ "$custom_server" == *"."* ]]; then
                    print_status "Using custom server: $custom_server" >&2
                    echo "$custom_server"
                else
                    print_warning "Server address should be a domain or IP (e.g., server.example.com)" >&2
                    print_warning "Using provided address anyway: $custom_server" >&2
                    echo "$custom_server"
                fi
            fi
            ;;
        x|X)
            if handle_exit_request; then
                echo "MENU_EXIT"
            else
                echo "MENU_EXIT"
            fi
            ;;
        *)
            print_error "Invalid choice '$choice'. Available options are:" >&2
            echo "  1 - Europe (eu1.cloud.thethings.network)" >&2
            echo "  2 - North America (nam1.cloud.thethings.network)" >&2
            echo "  3 - Australia (au1.cloud.thethings.network)" >&2
            echo "  4 - Asia (as1.cloud.thethings.network)" >&2
            echo "  5 - Custom server address" >&2
            echo "  x - Exit to main menu" >&2
            print_warning "Using Europe server as default." >&2
            echo "eu1.cloud.thethings.network"
            ;;
    esac
}

# Main installation function
main_install() {
    print_header "RAK7371 WisGate Developer Base Installation"

    # Check device connection
    if ! check_device_connection; then
        print_error "Please connect your RAK7371 device and try again."
        exit 1
    fi

    # Install dependencies
    install_dependencies

    # Install software
    install_software

    # Configure band plan
    print_status "Configuring band plan..."
    local band=$(select_band_plan)
    if [ "$band" = "MENU_EXIT" ]; then
        print_status "Returning to main menu..."
        return 0
    fi
    configure_band "$band"

    # Configure TTN server
    print_status "Configuring TTN server..."
    local server=$(select_ttn_server)
    if [ "$server" = "MENU_EXIT" ]; then
        print_status "Returning to main menu..."
        return 0
    fi
    configure_ttn_server "$server"

    # Configure Gateway EUI
    print_status "Configuring Gateway EUI..."
    local gateway_eui=$(input_gateway_eui)
    if [ "$gateway_eui" = "MENU_EXIT" ]; then
        print_status "Returning to main menu..."
        return 0
    fi
    configure_gateway_eui "$gateway_eui"

    # Display final EUI
    echo ""
    echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}Gateway configured with EUI: ${YELLOW}$gateway_eui${NC}"
    echo -e "${GREEN}Use this EUI to register on TTN Console${NC}"
    echo -e "${GREEN}══════════════════════════════════════════════════${NC}"

    print_header "Installation Complete!"
    print_status "Your RAK7371 is now configured and ready to use."
    print_status "Use '$0 start' to start the packet forwarder."
    print_status "Use '$0 status' to check the current status."
}

# Main configuration function
main_config() {
    print_header "RAK7371 Configuration"

    if ! check_installation; then
        print_error "Software not installed. Please run '$0 install' first."
        exit 1
    fi

    # Stop packet forwarder if running
    stop_packet_forwarder

    # Reconfigure band plan
    local band=$(select_band_plan)
    if [ "$band" = "MENU_EXIT" ]; then
        print_status "Returning to main menu..."
        return 0
    fi
    configure_band "$band"

    # Reconfigure TTN server
    local server=$(select_ttn_server)
    if [ "$server" = "MENU_EXIT" ]; then
        print_status "Returning to main menu..."
        return 0
    fi
    configure_ttn_server "$server"

    # Reconfigure Gateway EUI
    print_status "Configuring Gateway EUI..."
    local gateway_eui=$(input_gateway_eui)
    if [ "$gateway_eui" = "MENU_EXIT" ]; then
        print_status "Returning to main menu..."
        return 0
    fi
    configure_gateway_eui "$gateway_eui"

    print_status "✓ Configuration updated successfully"
    print_status "Use '$0 start' to start with new configuration."
}

# Function to show interactive menu
show_menu() {
    clear
    print_header "RAK7371 WisGate Developer Base Manager"
    echo ""
    echo "Please select an option:"
    echo ""
    echo "  1) Install and configure software"
    echo "  2) Start packet forwarder"
    echo "  3) Stop packet forwarder"
    echo "  4) Restart packet forwarder"
    echo "  5) Show status"
    echo "  6) Get gateway EUI"
    echo "  7) Reconfigure band plan and TTN server"
    echo "  8) View current configuration"
    echo "  9) Uninstall software"
    echo "  10) Help"
    echo "  0) Exit"
    echo "  x) Exit (press twice to exit program)"
    echo ""
    read -p "Enter your choice (0-10, x): " menu_choice
    echo ""
}

# Function to handle menu selection
handle_menu_choice() {
    # Reset exit request when returning to menu
    EXIT_REQUESTED=false

    case $menu_choice in
        1)
            main_install
            ;;
        2)
            if ! check_installation; then
                print_error "Software not installed. Please select option 1 to install first."
                read -p "Press Enter to continue..."
                return
            fi
            if ! check_device_connection; then
                print_error "Device not connected."
                read -p "Press Enter to continue..."
                return
            fi
            start_packet_forwarder
            ;;
        3)
            stop_packet_forwarder
            read -p "Press Enter to continue..."
            ;;
        4)
            stop_packet_forwarder
            sleep 2
            if check_installation && check_device_connection; then
                start_packet_forwarder
            else
                print_error "Cannot restart: software not installed or device not connected."
                read -p "Press Enter to continue..."
            fi
            ;;
        5)
            show_status
            read -p "Press Enter to continue..."
            ;;
        6)
            if check_installation; then
                # Show configured EUI from config file
                local config_file="$SX1302_DIR/packet_forwarder/global_conf.json"
                if [ -f "$config_file" ]; then
                    local configured_eui=$(grep "gateway_ID" "$config_file" | cut -d'"' -f4)
                    echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
                    echo -e "${GREEN}Configured Gateway EUI: ${YELLOW}$configured_eui${NC}"
                    echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
                    echo ""
                    read -p "Do you want to detect the actual hardware EUI? (y/N): " detect
                    if [[ "$detect" =~ ^[Yy]$ ]]; then
                        get_gateway_eui
                    fi
                else
                    print_error "Configuration file not found."
                fi
            else
                print_error "Software not installed. Please select option 1 to install first."
            fi
            read -p "Press Enter to continue..."
            ;;
        7)
            main_config
            read -p "Press Enter to continue..."
            ;;
        8)
            view_configuration
            read -p "Press Enter to continue..."
            ;;
        9)
            uninstall_software
            read -p "Press Enter to continue..."
            ;;
        10)
            show_help
            read -p "Press Enter to continue..."
            ;;
        0)
            print_status "Exiting..."
            exit 0
            ;;
        x|X)
            handle_exit_request
            ;;
        *)
            print_error "Invalid choice. Please select a number from 0-10 or 'x'."
            read -p "Press Enter to continue..."
            ;;
    esac
}

# Main script logic
main() {
    check_root

    # Check if command-line argument is provided for backward compatibility
    if [ $# -gt 0 ]; then
        case "$1" in
            "install")
                main_install
                ;;
            "start")
                if ! check_installation; then
                    print_error "Software not installed. Please run '$0 install' first."
                    exit 1
                fi
                if ! check_device_connection; then
                    print_error "Device not connected."
                    exit 1
                fi
                start_packet_forwarder
                ;;
            "stop")
                stop_packet_forwarder
                ;;
            "restart")
                stop_packet_forwarder
                sleep 2
                if check_installation && check_device_connection; then
                    start_packet_forwarder
                else
                    print_error "Cannot restart: software not installed or device not connected."
                    exit 1
                fi
                ;;
            "status")
                show_status
                ;;
            "eui")
                if check_installation; then
                    get_gateway_eui
                else
                    print_error "Software not installed. Please run '$0 install' first."
                    exit 1
                fi
                ;;
            "config")
                main_config
                ;;
            "view")
                view_configuration
                ;;
            "uninstall")
                uninstall_software
                ;;
            "help")
                show_help
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    else
        # Run interactive menu if no arguments provided
        while true; do
            show_menu
            handle_menu_choice
        done
    fi
}

# Run main function with all arguments
main "$@"