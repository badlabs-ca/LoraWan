#!/bin/bash

# RAK WisGate Developer Base - Unified Cross-Platform Manager
# Auto-detects environment and handles everything intelligently
# Works on: Windows (PowerShell/Git Bash), Linux (Ubuntu/WSL), macOS

# set -e  # Exit on any error - DISABLED for better error handling
# Instead, we'll handle errors manually where needed

# Global configuration
SCRIPT_VERSION="1.0.0"
WORK_DIR="$HOME/rak_gateway_unified"
CONFIG_FILE="$WORK_DIR/rak_unified_config.conf"
LOG_FILE="$WORK_DIR/rak_unified.log"
DEBUG_MODE="${DEBUG_RAK:-false}"  # Set DEBUG_RAK=true to enable debug mode

# Colors for cross-platform output
if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]] || [[ -n "$WINDIR" ]]; then
    # Windows - basic colors
    RED='[91m'
    GREEN='[92m'
    YELLOW='[93m'
    BLUE='[94m'
    NC='[0m'
else
    # Unix-like - full ANSI colors
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
fi

# Global variables
DETECTED_OS=""
DETECTED_ENV=""
INSTALLATION_STATUS=""
DEVICE_STATUS=""
USB_METHOD=""

# ============================================================================
# CORE FUNCTIONS
# ============================================================================

print_status() {
    local message="$1"
    if [[ "$DEBUG_MODE" == "true" ]]; then
        echo -e "${BLUE}[INFO]${NC} $message (Line: ${BASH_LINENO[1]})" | tee -a "$LOG_FILE" 2>/dev/null || echo -e "${BLUE}[INFO]${NC} $message"
    else
        echo -e "${BLUE}[INFO]${NC} $message" | tee -a "$LOG_FILE" 2>/dev/null || echo -e "${BLUE}[INFO]${NC} $message"
    fi
}

print_debug() {
    if [[ "$DEBUG_MODE" == "true" ]]; then
        echo -e "${YELLOW}[DEBUG]${NC} $1" | tee -a "$LOG_FILE" 2>/dev/null || echo -e "${YELLOW}[DEBUG]${NC} $1"
    fi
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE" 2>/dev/null || echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE" 2>/dev/null || echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE" 2>/dev/null || echo -e "${RED}[ERROR]${NC} $1"
}

init_logging() {
    # Create work directory with better error handling
    if ! mkdir -p "$WORK_DIR" 2>/dev/null; then
        print_warning "Could not create work directory $WORK_DIR"
        WORK_DIR="/tmp/rak_gateway_unified"
        mkdir -p "$WORK_DIR" || WORK_DIR="."
    fi
    
    # Try to write to log file, fallback if it fails
    if ! echo "=== RAK Unified Manager Log - $(date) ===" >> "$LOG_FILE" 2>/dev/null; then
        LOG_FILE="/tmp/rak_unified.log"
        echo "=== RAK Unified Manager Log - $(date) ===" >> "$LOG_FILE" 2>/dev/null || LOG_FILE=""
    fi
}

save_config() {
    mkdir -p "$WORK_DIR" 2>/dev/null || true
    cat > "$CONFIG_FILE" 2>/dev/null << EOF || true
DETECTED_OS=$DETECTED_OS
DETECTED_ENV=$DETECTED_ENV
INSTALLATION_STATUS=$INSTALLATION_STATUS
DEVICE_MODEL=${DEVICE_MODEL:-""}
CONCENTRATOR=${CONCENTRATOR:-""}
REGION=${REGION:-""}
INSTALL_PATH=${INSTALL_PATH:-""}
DEVICE_PATH=${DEVICE_PATH:-""}
USB_BUSID=${USB_BUSID:-""}
LAST_UPDATE=$(date)
SCRIPT_VERSION=$SCRIPT_VERSION
EOF
}

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        if source "$CONFIG_FILE" 2>/dev/null; then
            return 0
        else
            print_warning "Config file exists but could not be loaded"
            return 1
        fi
    else
        return 1
    fi
}

# ============================================================================
# ENVIRONMENT DETECTION
# ============================================================================

detect_operating_system() {
    print_status "Detecting operating system and environment..."
    print_debug "OSTYPE: $OSTYPE"
    
    # Detect OS with better error handling
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        DETECTED_OS="LINUX"
        print_debug "Linux detected, checking environment..."
        
        # Check if it's WSL
        if grep -qi microsoft /proc/version 2>/dev/null; then
            DETECTED_ENV="WSL"
        elif command -v systemd-detect-virt >/dev/null 2>&1; then
            if systemd-detect-virt -q 2>/dev/null; then
                DETECTED_ENV="VM"
            else
                DETECTED_ENV="NATIVE"
            fi
        else
            DETECTED_ENV="NATIVE"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        DETECTED_OS="MACOS"
        DETECTED_ENV="NATIVE"
    elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]] || [[ -n "$WINDIR" ]]; then
        DETECTED_OS="WINDOWS"
        # Check if we can access WSL
        if command -v wsl >/dev/null 2>&1; then
            if wsl --status >/dev/null 2>&1; then
                DETECTED_ENV="WINDOWS_WITH_WSL"
            else
                DETECTED_ENV="WINDOWS_ONLY"
            fi
        else
            DETECTED_ENV="WINDOWS_ONLY"
        fi
    else
        DETECTED_OS="UNKNOWN"
        DETECTED_ENV="UNKNOWN"
        print_warning "Unknown operating system detected: $OSTYPE"
    fi
    
    print_success "Detected: $DETECTED_OS ($DETECTED_ENV)"
}

# ============================================================================
# INSTALLATION STATUS CHECK
# ============================================================================

check_installation_status() {
    print_status "Checking RAK software installation status..."
    
    INSTALLATION_STATUS="NOT_INSTALLED"
    
    # Check for existing installation based on OS
    case $DETECTED_OS in
        "LINUX")
            # Look for sx1302_hal installation
            local search_paths=(
                "$HOME/rak_gateway_setup"
                "$HOME/sx1302_hal"
                "$HOME/sx1302_hal-2.0.1"
                "/opt/rak_gateway"
            )
            
            for path in "${search_paths[@]}"; do
                if [ -d "$path" ] && [ -f "$path/packet_forwarder/lora_pkt_fwd" ]; then
                    INSTALLATION_STATUS="INSTALLED"
                    INSTALL_PATH="$path"
                    break
                fi
            done
            ;;
            
        "WINDOWS")
            # Check if WSL has installation
            if [[ "$DETECTED_ENV" == "WINDOWS_WITH_WSL" ]]; then
                if wsl test -f ~/sx1302_hal-2.0.1/packet_forwarder/lora_pkt_fwd 2>/dev/null; then
                    INSTALLATION_STATUS="INSTALLED"
                    INSTALL_PATH="~/sx1302_hal-2.0.1"  # WSL path
                fi
            fi
            ;;
            
        "MACOS")
            # Check for Docker or VM installations
            if docker ps >/dev/null 2>&1 && docker ps -a --format '{{.Names}}' | grep -q rak_gateway; then
                INSTALLATION_STATUS="INSTALLED_DOCKER"
            fi
            ;;
    esac
    
    if [[ "$INSTALLATION_STATUS" == "NOT_INSTALLED" ]]; then
        print_warning "RAK software not found - installation needed"
    else
        print_success "RAK software installation detected: $INSTALLATION_STATUS"
    fi
}

# ============================================================================
# USB DEVICE DETECTION
# ============================================================================

detect_usb_device() {
    print_status "Detecting RAK USB device..."
    
    DEVICE_STATUS="NOT_FOUND"
    DEVICE_PATH=""
    
    case $DETECTED_OS in
        "LINUX")
            # Check lsusb
            if command -v lsusb >/dev/null 2>&1; then
                if lsusb | grep -qi "0483:5740\|stmicroelectronics"; then
                    DEVICE_STATUS="FOUND_USB"
                    print_success "RAK device detected via lsusb"
                fi
            fi
            
            # Check serial devices
            for path in /dev/ttyACM* /dev/ttyUSB*; do
                if [[ -e $path ]]; then
                    DEVICE_STATUS="FOUND_SERIAL"
                    DEVICE_PATH=$path
                    print_success "RAK device found at: $path"
                    break
                fi
            done
            ;;
            
        "WINDOWS")
            # Check Windows Device Manager
            if command -v powershell >/dev/null 2>&1; then
                local device_check
                device_check=$(powershell -command "Get-WmiObject -Class Win32_SerialPort | Where-Object {\$_.Description -like '*STMicroelectronics*'} | Select-Object -First 1 DeviceID" 2>/dev/null)
                if [[ -n "$device_check" ]]; then
                    DEVICE_STATUS="FOUND_WINDOWS"
                    print_success "RAK device detected in Windows"
                fi
            fi
            
            # Check usbipd
            if command -v usbipd >/dev/null 2>&1; then
                if usbipd list 2>/dev/null | grep -qi "0483:5740"; then
                    USB_BUSID=$(usbipd list 2>/dev/null | grep "0483:5740" | awk '{print $1}')
                    DEVICE_STATUS="FOUND_USBIPD"
                    print_success "RAK device found via usbipd: $USB_BUSID"
                fi
            fi
            ;;
            
        "MACOS")
            # Check macOS USB devices
            if system_profiler SPUSBDataType 2>/dev/null | grep -qi "stmicroelectronics"; then
                DEVICE_STATUS="FOUND_MACOS"
                local device_path
                device_path=$(ls /dev/cu.usbmodem* 2>/dev/null | head -1)
                if [[ -n "$device_path" ]]; then
                    DEVICE_PATH=$device_path
                    print_success "RAK device found at: $device_path"
                fi
            fi
            ;;
    esac
    
    if [[ "$DEVICE_STATUS" == "NOT_FOUND" ]]; then
        print_warning "RAK device not detected"
    fi
}

# ============================================================================
# USB MANAGEMENT
# ============================================================================

setup_usb_passthrough() {
    print_status "Setting up USB passthrough for $DETECTED_OS ($DETECTED_ENV)..."
    
    case "$DETECTED_OS-$DETECTED_ENV" in
        "WINDOWS-WINDOWS_WITH_WSL")
            setup_windows_wsl_usb
            ;;
        "MACOS-NATIVE")
            setup_macos_usb
            ;;
        "LINUX-VM")
            print_warning "VM USB passthrough needs to be configured in your VM software"
            show_vm_usb_instructions
            ;;
        "LINUX-WSL")
            print_status "USB should already be passed through from Windows"
            ;;
        "LINUX-NATIVE")
            print_status "Native Linux - direct USB access available"
            ;;
        *)
            print_warning "USB passthrough not implemented for this environment"
            ;;
    esac
}

setup_windows_wsl_usb() {
    print_status "Setting up Windows → WSL USB passthrough..."
    
    # Check if usbipd is installed
    if ! command -v usbipd >/dev/null 2>&1; then
        print_status "Installing usbipd-win..."
        if command -v winget >/dev/null 2>&1; then
            winget install --interactive --exact dorssel.usbipd-win
        else
            print_error "Please install usbipd-win manually from: https://github.com/dorssel/usbipd-win/releases"
            return 1
        fi
    fi
    
    # List devices and find RAK device
    print_status "Scanning for RAK device..."
    usbipd list
    
    if [[ -n "$USB_BUSID" ]]; then
        print_status "Binding and attaching device $USB_BUSID..."
        usbipd bind --busid "$USB_BUSID" 2>/dev/null || print_warning "Device might already be bound"
        usbipd attach --wsl --busid "$USB_BUSID"
        
        if [ $? -eq 0 ]; then
            print_success "USB device attached to WSL successfully!"
            return 0
        else
            print_error "Failed to attach USB device to WSL"
            return 1
        fi
    else
        print_error "RAK device not found. Please ensure it's connected and try again."
        return 1
    fi
}

setup_macos_usb() {
    print_status "macOS USB options..."
    echo ""
    echo "=== macOS USB SETUP OPTIONS ==="
    echo "1) Use Docker (recommended for testing)"
    echo "2) Use Parallels/VMware VM"
    echo "3) Use native macOS compilation (advanced)"
    echo ""
    read -p "Enter your choice (1-3): " macos_choice
    
    case $macos_choice in
        1)
            setup_macos_docker
            ;;
        2)
            show_macos_vm_instructions
            ;;
        3)
            print_warning "Native macOS compilation requires additional setup"
            print_status "Consider using Docker or VM for easier setup"
            ;;
    esac
}

setup_macos_docker() {
    print_status "Setting up Docker solution for macOS..."
    
    if ! command -v docker >/dev/null 2>&1; then
        print_error "Docker not found. Please install Docker Desktop for Mac."
        print_status "Download from: https://www.docker.com/products/docker-desktop"
        return 1
    fi
    
    if [[ -n "$DEVICE_PATH" ]]; then
        print_status "Starting Docker container with device access..."
        docker run -d --name rak_gateway --privileged --device="$DEVICE_PATH:$DEVICE_PATH" ubuntu:20.04 sleep infinity
        print_success "Docker container created with USB access"
    else
        print_error "Device path not found for Docker mapping"
        return 1
    fi
}

show_vm_usb_instructions() {
    echo ""
    echo "=== VM USB PASSTHROUGH INSTRUCTIONS ==="
    echo ""
    case "$DETECTED_ENV" in
        "VM")
            echo "For VMware/VirtualBox/Parallels:"
            echo "1. Power off your Ubuntu VM"
            echo "2. Go to VM settings → USB"
            echo "3. Add USB device filter for RAK device (0483:5740)"
            echo "4. Start VM and run this script again"
            ;;
    esac
    echo ""
    read -p "Press Enter after configuring USB passthrough..."
}

show_macos_vm_instructions() {
    echo ""
    echo "=== macOS VM USB PASSTHROUGH ==="
    echo ""
    echo "For Parallels Desktop:"
    echo "1. Select your VM → Configure (⚙️)"
    echo "2. Hardware → USB & Bluetooth"
    echo "3. Find 'STMicroelectronics Virtual COM Port'"
    echo "4. Set to 'Windows' or 'Linux' (not macOS)"
    echo ""
    echo "For VMware Fusion:"
    echo "1. VM → USB & Bluetooth"
    echo "2. Connect RAK device to VM"
    echo ""
    read -p "Press Enter after configuring..."
}

# ============================================================================
# INSTALLATION MANAGEMENT
# ============================================================================

run_installation() {
    print_status "Starting RAK software installation..."
    
    case $DETECTED_OS in
        "LINUX")
            install_linux_native
            ;;
        "WINDOWS")
            if [[ "$DETECTED_ENV" == "WINDOWS_WITH_WSL" ]]; then
                install_windows_wsl
            else
                print_error "WSL not available. Please install WSL2 first."
                return 1
            fi
            ;;
        "MACOS")
            install_macos_docker
            ;;
        *)
            print_error "Installation not supported for $DETECTED_OS"
            return 1
            ;;
    esac
}

install_linux_native() {
    print_status "Installing RAK software on Linux..."
    
    # Ensure device is accessible
    if [[ "$DEVICE_STATUS" == "NOT_FOUND" ]]; then
        print_error "RAK device not found. Please ensure USB passthrough is working."
        return 1
    fi
    
    # Get device model
    select_device_model
    
    # Install prerequisites
    sudo apt update
    sudo apt install -y make gcc wget git usbutils
    
    # Download and compile
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"
    
    if [[ "$USE_GIT_CLONE" == "true" ]]; then
        git clone https://github.com/Lora-net/sx1302_hal.git
        cd sx1302_hal
        INSTALL_PATH="$WORK_DIR/sx1302_hal"
    else
        wget https://github.com/Lora-net/sx1302_hal/archive/V2.0.1.tar.gz
        tar -zxvf V2.0.1.tar.gz
        cd sx1302_hal-2.0.1
        INSTALL_PATH="$WORK_DIR/sx1302_hal-2.0.1"
    fi
    
    make
    
    # Configure
    cd packet_forwarder
    select_region
    cp "global_conf.json.sx1250.$REGION.USB" global_conf.json
    
    # Update device path
    if [[ -n "$DEVICE_PATH" ]]; then
        sed -i "s|/dev/ttyACM0|$DEVICE_PATH|g" global_conf.json
    fi
    
    INSTALLATION_STATUS="INSTALLED"
    print_success "Installation completed successfully!"
}

install_windows_wsl() {
    print_status "Installing RAK software in WSL..."
    
    # Ensure USB is passed through
    if [[ "$DEVICE_STATUS" != "FOUND_USBIPD" ]]; then
        print_status "Setting up USB passthrough first..."
        setup_usb_passthrough
    fi
    
    # Run installation in WSL
    print_status "Running installation commands in WSL..."
    wsl bash -c "
        sudo apt update
        sudo apt install -y make gcc wget git
        mkdir -p ~/rak_gateway_setup
        cd ~/rak_gateway_setup
        wget https://github.com/Lora-net/sx1302_hal/archive/V2.0.1.tar.gz
        tar -zxvf V2.0.1.tar.gz
        cd sx1302_hal-2.0.1
        make
        cd packet_forwarder
        cp global_conf.json.sx1250.US915.USB global_conf.json
        echo 'Installation completed in WSL!'
    "
    
    INSTALLATION_STATUS="INSTALLED"
    INSTALL_PATH="~/rak_gateway_setup/sx1302_hal-2.0.1"
    print_success "WSL installation completed!"
}

install_macos_docker() {
    print_status "Installing RAK software in Docker..."
    
    if docker ps --format '{{.Names}}' | grep -q rak_gateway; then
        print_status "Using existing Docker container..."
    else
        setup_macos_docker
    fi
    
    print_status "Running installation in Docker container..."
    docker exec rak_gateway bash -c "
        apt update
        apt install -y make gcc wget git
        cd /opt
        wget https://github.com/Lora-net/sx1302_hal/archive/V2.0.1.tar.gz
        tar -zxvf V2.0.1.tar.gz
        cd sx1302_hal-2.0.1
        make
        cd packet_forwarder
        cp global_conf.json.sx1250.US915.USB global_conf.json
        echo 'Docker installation completed!'
    "
    
    INSTALLATION_STATUS="INSTALLED_DOCKER"
    print_success "Docker installation completed!"
}

select_device_model() {
    echo ""
    echo "Select your RAK device model:"
    echo "1) RAK7271 (with RAK2287 inside)"
    echo "2) RAK7371 (with RAK5146 inside)"
    echo ""
    read -p "Enter your choice (1-2): " model_choice
    
    case $model_choice in
        1)
            DEVICE_MODEL="RAK7271"
            CONCENTRATOR="RAK2287"
            USE_GIT_CLONE="false"
            ;;
        2)
            DEVICE_MODEL="RAK7371"
            CONCENTRATOR="RAK5146"
            USE_GIT_CLONE="true"
            ;;
        *)
            print_warning "Invalid choice, defaulting to RAK7271"
            DEVICE_MODEL="RAK7271"
            CONCENTRATOR="RAK2287"
            USE_GIT_CLONE="false"
            ;;
    esac
}

select_region() {
    echo ""
    echo "Select your LoRaWAN region:"
    echo "1) EU868 (Europe)"
    echo "2) US915 (North America)"
    echo "3) AS923 (Asia-Pacific)"
    echo "4) AU915 (Australia)"
    echo ""
    read -p "Enter your choice (1-4): " region_choice
    
    case $region_choice in
        1) REGION="EU868" ;;
        2) REGION="US915" ;;
        3) REGION="AS923" ;;
        4) REGION="AU915" ;;
        *) REGION="US915"; print_warning "Invalid choice, defaulting to US915" ;;
    esac
}

# ============================================================================
# OPERATIONAL FUNCTIONS
# ============================================================================

start_packet_forwarder() {
    print_status "Starting packet forwarder..."
    
    case "$DETECTED_OS-$INSTALLATION_STATUS" in
        "LINUX-INSTALLED")
            cd "$INSTALL_PATH/packet_forwarder"
            print_warning "Press Ctrl+C to stop. Gateway EUI will be shown in the logs."
            sudo ./lora_pkt_fwd
            ;;
        "WINDOWS-INSTALLED")
            print_status "Starting packet forwarder in WSL..."
            wsl bash -c "cd ~/rak_gateway_setup/sx1302_hal-2.0.1/packet_forwarder && sudo ./lora_pkt_fwd"
            ;;
        "MACOS-INSTALLED_DOCKER")
            print_status "Starting packet forwarder in Docker..."
            docker exec -it rak_gateway bash -c "cd /opt/sx1302_hal-2.0.1/packet_forwarder && ./lora_pkt_fwd"
            ;;
        *)
            print_error "Cannot start packet forwarder - installation not found or incompatible"
            ;;
    esac
}

get_gateway_eui() {
    print_status "Getting Gateway EUI..."
    
    case "$DETECTED_OS-$INSTALLATION_STATUS" in
        "LINUX-INSTALLED")
            cd "$INSTALL_PATH/util_chip_id"
            sudo ./chip_id -u -d "${DEVICE_PATH:-/dev/ttyACM0}"
            ;;
        "WINDOWS-INSTALLED")
            wsl bash -c "cd ~/rak_gateway_setup/sx1302_hal-2.0.1/util_chip_id && sudo ./chip_id -u -d /dev/ttyACM0"
            ;;
        "MACOS-INSTALLED_DOCKER")
            docker exec rak_gateway bash -c "cd /opt/sx1302_hal-2.0.1/util_chip_id && ./chip_id -u -d $DEVICE_PATH"
            ;;
        *)
            print_error "Cannot get EUI - installation not found"
            ;;
    esac
}

# ============================================================================
# MENU SYSTEM
# ============================================================================

show_status_summary() {
    echo ""
    echo "=== RAK GATEWAY STATUS SUMMARY ==="
    echo "OS/Environment: $DETECTED_OS ($DETECTED_ENV)"
    echo "Installation: $INSTALLATION_STATUS"
    echo "Device Status: $DEVICE_STATUS"
    if [[ -n "$DEVICE_PATH" ]]; then
        echo "Device Path: $DEVICE_PATH"
    fi
    if [[ -n "$USB_BUSID" ]]; then
        echo "USB Bus ID: $USB_BUSID"
    fi
    if [[ -n "$DEVICE_MODEL" ]]; then
        echo "Device Model: $DEVICE_MODEL ($CONCENTRATOR)"
    fi
    if [[ -n "$REGION" ]]; then
        echo "Region: $REGION"
    fi
    echo ""
}

show_main_menu() {
    echo ""
    echo "=== RAK UNIFIED GATEWAY MANAGER ==="
    
    if [[ "$INSTALLATION_STATUS" == *"INSTALLED"* ]] && [[ "$DEVICE_STATUS" == "FOUND"* ]]; then
        # Quick operation menu for installed systems
        echo "🚀 QUICK OPERATIONS:"
        echo "1) Start packet forwarder"
        echo "2) Get Gateway EUI"
        echo "3) View status"
        echo ""
        echo "⚙️  MANAGEMENT:"
        echo "4) USB troubleshooting"
        echo "5) Reconfigure region"
        echo "6) Reinstall software"
        echo "7) Show detailed status"
        echo "8) Exit"
    else
        # Setup menu for new installations
        echo "🔧 SETUP REQUIRED:"
        echo "1) Auto-setup (detect and install everything)"
        echo "2) Manual USB setup"
        echo "3) Manual software installation"
        echo ""
        echo "ℹ️  INFORMATION:"
        echo "4) Check device connection"
        echo "5) Show system status"
        echo "6) Troubleshooting help"
        echo "7) Exit"
    fi
    echo ""
}

handle_menu_choice() {
    if [[ "$INSTALLATION_STATUS" == *"INSTALLED"* ]] && [[ "$DEVICE_STATUS" == "FOUND"* ]]; then
        # Operational menu
        read -p "Enter your choice (1-8): " choice
        case $choice in
            1) start_packet_forwarder ;;
            2) get_gateway_eui ;;
            3) show_status_summary ;;
            4) setup_usb_passthrough ;;
            5) reconfigure_region ;;
            6) run_installation ;;
            7) show_detailed_status ;;
            8) exit_script ;;
            *) print_error "Invalid choice" ;;
        esac
    else
        # Setup menu
        read -p "Enter your choice (1-7): " choice
        case $choice in
            1) auto_setup ;;
            2) setup_usb_passthrough ;;
            3) run_installation ;;
            4) detect_usb_device ;;
            5) show_status_summary ;;
            6) show_troubleshooting ;;
            7) exit_script ;;
            *) print_error "Invalid choice" ;;
        esac
    fi
}

auto_setup() {
    print_status "Starting automatic setup..."
    
    # Step 1: Ensure device is detected
    if [[ "$DEVICE_STATUS" == "NOT_FOUND" ]]; then
        print_status "Setting up USB passthrough..."
        setup_usb_passthrough
        # Re-detect after USB setup
        detect_usb_device
    fi
    
    # Step 2: Install software if needed
    if [[ "$INSTALLATION_STATUS" == "NOT_INSTALLED" ]]; then
        print_status "Installing RAK software..."
        run_installation
    fi
    
    # Step 3: Verify everything is working
    print_status "Verifying installation..."
    check_installation_status
    detect_usb_device
    
    if [[ "$INSTALLATION_STATUS" == *"INSTALLED"* ]] && [[ "$DEVICE_STATUS" == "FOUND"* ]]; then
        print_success "Auto-setup completed successfully!"
        save_config
    else
        print_error "Auto-setup incomplete. Please check troubleshooting."
    fi
}

reconfigure_region() {
    print_status "Reconfiguring region..."
    select_region
    
    case "$DETECTED_OS-$INSTALLATION_STATUS" in
        "LINUX-INSTALLED")
            cd "$INSTALL_PATH/packet_forwarder"
            cp "global_conf.json.sx1250.$REGION.USB" global_conf.json
            ;;
        "WINDOWS-INSTALLED")
            wsl bash -c "cd ~/rak_gateway_setup/sx1302_hal-2.0.1/packet_forwarder && cp global_conf.json.sx1250.$REGION.USB global_conf.json"
            ;;
        "MACOS-INSTALLED_DOCKER")
            docker exec rak_gateway bash -c "cd /opt/sx1302_hal-2.0.1/packet_forwarder && cp global_conf.json.sx1250.$REGION.USB global_conf.json"
            ;;
    esac
    
    save_config
    print_success "Region reconfigured to $REGION"
}

show_detailed_status() {
    echo ""
    echo "=== DETAILED SYSTEM STATUS ==="
    echo "Script Version: $SCRIPT_VERSION"
    echo "Detected OS: $DETECTED_OS"
    echo "Environment: $DETECTED_ENV"
    echo "Installation: $INSTALLATION_STATUS"
    echo "Device Status: $DEVICE_STATUS"
    echo "Install Path: ${INSTALL_PATH:-'Not set'}"
    echo "Device Path: ${DEVICE_PATH:-'Not set'}"
    echo "USB Bus ID: ${USB_BUSID:-'Not set'}"
    echo "Device Model: ${DEVICE_MODEL:-'Not set'}"
    echo "Region: ${REGION:-'Not set'}"
    echo "Config File: $CONFIG_FILE"
    echo "Log File: $LOG_FILE"
    echo ""
    
    # Show environment-specific details
    case $DETECTED_OS in
        "LINUX")
            echo "=== LINUX DETAILS ==="
            echo "Kernel: $(uname -r)"
            echo "Distribution: $(lsb_release -d 2>/dev/null | cut -f2 || echo 'Unknown')"
            if command -v lsusb >/dev/null 2>&1; then
                echo "USB devices: $(lsusb | wc -l) found"
            fi
            ;;
        "WINDOWS")
            echo "=== WINDOWS DETAILS ==="
            if command -v wsl >/dev/null 2>&1; then
                echo "WSL Status: Available"
                wsl --status 2>/dev/null || echo "WSL status unknown"
            fi
            if command -v usbipd >/dev/null 2>&1; then
                echo "usbipd: Installed"
            else
                echo "usbipd: Not installed"
            fi
            ;;
        "MACOS")
            echo "=== MACOS DETAILS ==="
            echo "macOS Version: $(sw_vers -productVersion 2>/dev/null || echo 'Unknown')"
            if command -v docker >/dev/null 2>&1; then
                echo "Docker: Available"
            else
                echo "Docker: Not available"
            fi
            ;;
    esac
    echo ""
}

show_troubleshooting() {
    echo ""
    echo "=== TROUBLESHOOTING GUIDE ==="
    echo ""
    
    case "$DETECTED_OS-$DETECTED_ENV" in
        "WINDOWS-WINDOWS_WITH_WSL")
            echo "Windows + WSL Troubleshooting:"
            echo "1. Ensure RAK device shows in Windows Device Manager"
            echo "2. Install usbipd-win: winget install usbipd"
            echo "3. Run as Administrator: usbipd bind --busid X-X"
            echo "4. Attach to WSL: usbipd attach --wsl --busid X-X"
            echo "5. Check in WSL: lsusb | grep STMicroelectronics"
            ;;
        "LINUX-VM")
            echo "Linux VM Troubleshooting:"
            echo "1. Enable USB passthrough in VM settings"
            echo "2. Add USB device filter for 0483:5740"
            echo "3. Restart VM after changes"
            echo "4. Check: lsusb and ls /dev/tty*"
            ;;
        "MACOS-NATIVE")
            echo "macOS Troubleshooting:"
            echo "1. Use Docker for easiest setup"
            echo "2. Or use VM with USB passthrough"
            echo "3. Check: system_profiler SPUSBDataType | grep STMicroelectronics"
            echo "4. Device path: ls /dev/cu.usbmodem*"
            ;;
    esac
    
    echo ""
    echo "General Issues:"
    echo "- Device not detected: Check USB cable and power LED"
    echo "- Permission denied: Add user to dialout group"
    echo "- Compilation fails: Install build-essential package"
    echo "- Port conflicts: Stop other packet forwarders"
    echo ""
    read -p "Press Enter to continue..."
}

exit_script() {
    print_status "Saving configuration and exiting..."
    save_config
    print_status "Goodbye!"
    exit 0
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    # Initialize
    init_logging
    echo "================================================"
    echo "RAK WisGate Developer Base - Unified Manager v$SCRIPT_VERSION"
    echo "Cross-platform intelligent setup and management"
    echo "================================================"
    
    # Load existing config
    load_config
    
    # Detection phase
    detect_operating_system
    detect_usb_device
    check_installation_status
    
    # Save initial detection
    save_config
    
    # Show current status
    show_status_summary
    
    # Main loop
    while true; do
        show_main_menu
        handle_menu_choice
        echo ""
        read -p "Press Enter to continue..." || break
    done
}

# Handle Ctrl+C gracefully
trap 'echo -e "\n${YELLOW}[INFO]${NC} Script interrupted. Configuration saved."; save_config; exit 1' INT

# Run main function
main "$@"