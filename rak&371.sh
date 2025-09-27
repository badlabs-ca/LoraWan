#!/bin/bash

# RAK7371 Gateway Setup Script for Debian
# This script sets up RAK7371 to work with local ChirpStack

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
GATEWAY_DIR="$HOME/rak7371_gateway"
CHIRPSTACK_IP="127.0.0.1"  # localhost
REGION="EU868"  # Change this to your region: EU868, US915, AS923, etc.

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
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================================${NC}"
}

# Function to check if gateway is connected
check_gateway_connection() {
    print_header "Checking RAK7371 Connection"
    
    print_status "Looking for connected RAK7371 gateway..."
    if lsusb | grep -q "STMicroelectronics Virtual COM Port"; then
        print_status "✓ RAK7371 gateway detected!"
        lsusb | grep "STMicroelectronics"
        return 0
    else
        print_error "✗ RAK7371 gateway not detected"
        print_warning "Make sure:"
        echo "  1. RAK7371 is connected via USB cable"
        echo "  2. Gateway power LED is green"
        echo "  3. USB cable is working properly"
        return 1
    fi
}

# Function to install required tools
install_tools() {
    print_header "Installing Required Tools"
    
    print_status "Updating package list..."
    sudo apt update
    
    print_status "Installing development tools..."
    sudo apt install -y make gcc git wget
    
    print_status "Tools installed successfully!"
}

# Function to download and compile gateway software
install_gateway_software() {
    print_header "Installing RAK7371 Gateway Software"
    
    # Create directory
    mkdir -p "$GATEWAY_DIR"
    cd "$GATEWAY_DIR"
    
    print_status "Downloading SX1302 HAL software..."
    if [ ! -d "sx1302_hal" ]; then
        git clone https://github.com/Lora-net/sx1302_hal.git
    fi
    
    cd sx1302_hal
    
    print_status "Compiling gateway software..."
    make clean
    make
    
    if [ $? -eq 0 ]; then
        print_status "✓ Gateway software compiled successfully!"
    else
        print_error "✗ Compilation failed!"
        return 1
    fi
}

# Function to configure packet forwarder
configure_packet_forwarder() {
    print_header "Configuring Packet Forwarder"
    
    cd "$GATEWAY_DIR/sx1302_hal/packet_forwarder"
    
    print_status "Setting up configuration for $REGION region..."
    
    # Copy the correct configuration file based on region
    case $REGION in
        "EU868")
            cp global_conf.json.sx1250.EU868.USB global_conf.json
            ;;
        "US915")
            cp global_conf.json.sx1250.US915.USB global_conf.json
            ;;
        "AS923")
            cp global_conf.json.sx1250.AS923.USB global_conf.json
            ;;
        *)
            print_warning "Unknown region $REGION, using EU868"
            cp global_conf.json.sx1250.EU868.USB global_conf.json
            ;;
    esac
    
    # Modify configuration to point to local ChirpStack
    print_status "Configuring for local ChirpStack server..."
    
    # Create a temporary file with updated configuration
    cat global_conf.json | \
    sed 's/"server_address": ".*"/"server_address": "'$CHIRPSTACK_IP'"/' | \
    sed 's/"serv_port_up": [0-9]*/"serv_port_up": 1700/' | \
    sed 's/"serv_port_down": [0-9]*/"serv_port_down": 1700/' > global_conf_temp.json
    
    mv global_conf_temp.json global_conf.json
    
    print_status "✓ Configuration updated for local ChirpStack"
}

# Function to get gateway EUI
get_gateway_eui() {
    print_header "Getting Gateway EUI"
    
    cd "$GATEWAY_DIR/sx1302_hal/util_chip_id"
    
    print_status "Reading gateway EUI..."
    EUI=$(sudo ./chip_id -u -d /dev/ttyACM0 2>/dev/null | grep "Gateway EUI" | cut -d':' -f2 | tr -d ' ')
    
    if [ -n "$EUI" ]; then
        print_status "✓ Gateway EUI: $EUI"
        echo "$EUI" > "$GATEWAY_DIR/gateway_eui.txt"
        echo
        print_warning "IMPORTANT: Save this EUI - you'll need it to register in ChirpStack!"
        echo "EUI saved to: $GATEWAY_DIR/gateway_eui.txt"
    else
        print_error "Could not read gateway EUI. Make sure gateway is connected."
        return 1
    fi
}

# Function to start packet forwarder
start_gateway() {
    print_header "Starting RAK7371 Gateway"
    
    # Check if gateway is connected
    if ! check_gateway_connection; then
        return 1
    fi
    
    cd "$GATEWAY_DIR/sx1302_hal/packet_forwarder"
    
    print_status "Starting packet forwarder..."
    print_warning "Press Ctrl+C to stop the gateway"
    print_status "Gateway will send data to: $CHIRPSTACK_IP:1700"
    echo
    
    sudo ./lora_pkt_fwd
}

# Function to stop gateway (cleanup)
stop_gateway() {
    print_header "Stopping Gateway"
    print_status "Stopping packet forwarder..."
    pkill -f lora_pkt_fwd
    print_status "Gateway stopped."
}

# Function to show gateway status
gateway_status() {
    print_header "Gateway Status"
    
    # Check connection
    check_gateway_connection
    
    # Check if packet forwarder is running
    if pgrep -f lora_pkt_fwd > /dev/null; then
        print_status "✓ Packet forwarder is running"
    else
        print_warning "✗ Packet forwarder is not running"
    fi
    
    # Show EUI if available
    if [ -f "$GATEWAY_DIR/gateway_eui.txt" ]; then
        EUI=$(cat "$GATEWAY_DIR/gateway_eui.txt")
        print_status "Gateway EUI: $EUI"
    fi
    
    echo
    print_status "Configuration:"
    echo "  Server: $CHIRPSTACK_IP:1700"
    echo "  Region: $REGION"
    echo "  Gateway directory: $GATEWAY_DIR"
}

# Function to change region
change_region() {
    print_header "Change Region Configuration"
    
    echo "Available regions:"
    echo "  1) EU868 (Europe)"
    echo "  2) US915 (United States)"
    echo "  3) AS923 (Asia)"
    echo
    read -p "Select region (1-3): " choice
    
    case $choice in
        1) REGION="EU868" ;;
        2) REGION="US915" ;;
        3) REGION="AS923" ;;
        *) print_error "Invalid choice"; return 1 ;;
    esac
    
    print_status "Region changed to: $REGION"
    configure_packet_forwarder
}

# Function to show ChirpStack registration help
show_registration_help() {
    print_header "Register Gateway in ChirpStack"
    
    if [ -f "$GATEWAY_DIR/gateway_eui.txt" ]; then
        EUI=$(cat "$GATEWAY_DIR/gateway_eui.txt")
    else
        EUI="<GET_EUI_FIRST>"
    fi
    
    echo "To register your gateway in ChirpStack:"
    echo
    echo "1. Open ChirpStack web interface:"
    echo "   http://localhost:8080"
    echo
    echo "2. Login with: admin / admin"
    echo
    echo "3. Go to: Gateways → Add Gateway"
    echo
    echo "4. Fill in:"
    echo "   Gateway ID: $EUI"
    echo "   Gateway name: RAK7371-Gateway"
    echo "   Description: My RAK7371 Gateway"
    echo
    echo "5. Save and your gateway should appear as connected!"
}

# Function to show help
show_help() {
    print_header "RAK7371 Gateway Manager Help"
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  check        - Check if RAK7371 is connected"
    echo "  install      - Install required tools and gateway software"
    echo "  configure    - Configure packet forwarder"
    echo "  eui          - Get gateway EUI"
    echo "  start        - Start the gateway"
    echo "  stop         - Stop the gateway"
    echo "  status       - Show gateway status"
    echo "  region       - Change frequency region"
    echo "  register     - Show how to register in ChirpStack"
    echo "  help         - Show this help"
    echo ""
    echo "Quick setup (first time):"
    echo "  1. Connect RAK7371 via USB"
    echo "  2. $0 check"
    echo "  3. $0 install"
    echo "  4. $0 configure"
    echo "  5. $0 eui"
    echo "  6. $0 start"
    echo ""
    echo "Current configuration:"
    echo "  Server: $CHIRPSTACK_IP:1700"
    echo "  Region: $REGION"
}

# Main script logic
case "$1" in
    check)
        check_gateway_connection
        ;;
    install)
        install_tools
        install_gateway_software
        ;;
    configure)
        configure_packet_forwarder
        ;;
    eui)
        get_gateway_eui
        ;;
    start)
        start_gateway
        ;;
    stop)
        stop_gateway
        ;;
    status)
        gateway_status
        ;;
    region)
        change_region
        ;;
    register)
        show_registration_help
        ;;
    help|--help|-h)
        show_help
        ;;
    "")
        show_help
        ;;
    *)
        print_error "Unknown command: $1"
        show_help
        exit 1
        ;;
esac