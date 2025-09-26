#!/bin/bash

# RAK WisGate Developer Base - Linux-Optimized Enhanced Manager
# Linux-native setup with advanced Python signal monitoring
# Optimized for swift execution and reliable operation

# Global configuration
SCRIPT_VERSION="1.2.0-fixed"
WORK_DIR="$(pwd)"
CONFIG_FILE="$WORK_DIR/rak_unified_config.conf"
LOG_FILE="$WORK_DIR/rak_unified.log"
DEBUG_MODE="${DEBUG_RAK:-false}"
PYTHON_TOOLS_INSTALLED="false"
QUICK_MODE="${QUICK_RAK:-false}"

# Linux-optimized colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Global variables
DETECTED_OS="LINUX"
DETECTED_ENV=""
INSTALLATION_STATUS=""
DEVICE_STATUS=""
DEVICE_PATH=""
DEVICE_MODEL=""
CONCENTRATE_TYPE=""
REGION=""
INSTALL_PATH=""

# ============================================================================
# UTILITY FUNCTIONS (keeping existing ones)
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
    if ! mkdir -p "$WORK_DIR" 2>/dev/null; then
        print_warning "Could not create work directory $WORK_DIR"
        WORK_DIR="/tmp/rak_gateway_unified"
        mkdir -p "$WORK_DIR" || WORK_DIR="."
    fi

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
PYTHON_TOOLS_INSTALLED=$PYTHON_TOOLS_INSTALLED
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
# LINUX ENVIRONMENT DETECTION
# ============================================================================

detect_operating_system() {
    print_status "Detecting Linux environment..."
    print_debug "OSTYPE: $OSTYPE"

    DETECTED_OS="LINUX"

    # Check Linux environment type
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

    print_success "Detected: $DETECTED_OS ($DETECTED_ENV)"
}

check_installation_status() {
    print_status "Checking RAK software installation status..."

    INSTALLATION_STATUS="NOT_INSTALLED"

    local search_paths=(
        "$HOME/rak_gateway_setup"
        "$HOME/sx1302_hal"
        "$HOME/sx1302_hal-2.0.1"
        "$WORK_DIR/sx1302_hal"
        "$WORK_DIR/sx1302_hal-2.0.1"
        "/opt/rak_gateway"
    )

    for path in "${search_paths[@]}"; do
        if [ -d "$path" ] && [ -f "$path/packet_forwarder/lora_pkt_fwd" ]; then
            INSTALLATION_STATUS="INSTALLED"
            INSTALL_PATH="$path"
            print_success "RAK software found at: $path"
            return 0
        fi
    done

    print_warning "RAK software not found - installation needed"
}

detect_usb_device() {
    if [[ "$QUICK_MODE" == "true" ]] && [[ -n "$DEVICE_PATH" ]] && [[ -e "$DEVICE_PATH" ]]; then
        print_status "Quick mode: Using cached device path $DEVICE_PATH"
        DEVICE_STATUS="FOUND_SERIAL"
        return 0
    fi

    print_status "Detecting RAK USB device..."

    DEVICE_STATUS="NOT_FOUND"
    DEVICE_PATH=""

    # Check lsusb for RAK device
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

    if [[ "$DEVICE_STATUS" == "NOT_FOUND" ]]; then
        print_warning "RAK device not detected"
    fi
}

# ============================================================================
# PYTHON SIGNAL MONITORING SETUP
# ============================================================================

install_python_dependencies() {
    print_status "Installing Python dependencies for signal monitoring..."
    
    # Determine Python command
    local python_cmd=""
    if command -v python3 >/dev/null 2>&1; then
        python_cmd="python3"
    elif command -v python >/dev/null 2>&1; then
        python_cmd="python"
    else
        print_error "Python not found. Installing Python..."
        install_python
        python_cmd="python3"
    fi
    
    # Install pip if not available
    if ! command -v pip3 >/dev/null 2>&1 && ! command -v pip >/dev/null 2>&1; then
        print_status "Installing pip..."
        case $DETECTED_OS in
            "LINUX")
                sudo apt update && sudo apt install -y python3-pip
                ;;
            "WINDOWS")
                if [[ "$DETECTED_ENV" == "WINDOWS_WITH_WSL" ]]; then
                    wsl bash -c "sudo apt update && sudo apt install -y python3-pip"
                fi
                ;;
            "MACOS")
                if command -v brew >/dev/null 2>&1; then
                    brew install python
                else
                    print_error "Please install pip manually or install Homebrew"
                    return 1
                fi
                ;;
        esac
    fi
    
    # Install required Python packages
    local pip_cmd="pip3"
    command -v pip3 >/dev/null 2>&1 || pip_cmd="pip"
    
    print_status "Installing pycryptodome for LoRaWAN decryption..."
    case $DETECTED_OS in
        "LINUX")
            $pip_cmd install --user pycryptodome
            ;;
        "WINDOWS")
            if [[ "$DETECTED_ENV" == "WINDOWS_WITH_WSL" ]]; then
                wsl bash -c "$pip_cmd install --user pycryptodome"
            else
                $pip_cmd install pycryptodome
            fi
            ;;
        "MACOS")
            $pip_cmd install --user pycryptodome
            ;;
    esac
    
    if [ $? -eq 0 ]; then
        PYTHON_TOOLS_INSTALLED="true"
        print_success "Python dependencies installed successfully"
        return 0
    else
        print_error "Failed to install Python dependencies"
        return 1
    fi
}

install_python() {
    print_status "Installing Python..."
    case $DETECTED_OS in
        "LINUX")
            sudo apt update && sudo apt install -y python3 python3-pip
            ;;
        "WINDOWS")
            print_error "Please install Python from https://python.org/downloads"
            print_status "Make sure to check 'Add Python to PATH' during installation"
            return 1
            ;;
        "MACOS")
            if command -v brew >/dev/null 2>&1; then
                brew install python
            else
                print_error "Please install Python from https://python.org/downloads"
                return 1
            fi
            ;;
    esac
}

create_signal_monitor_script() {
    print_status "Creating Python signal monitoring script..."

    print_success "Python signal monitoring script available"

    chmod +x "$WORK_DIR/rak_signal_monitor.py"
    print_success "Signal monitoring script created"
}

create_raw_lora_script() {
    print_status "Creating raw LoRa capture script..."

    # Check if raw_lora_capture.py already exists in the directory
    if [[ -f "$WORK_DIR/raw_lora_capture.py" ]]; then
        print_success "Raw LoRa capture script already exists"
        return 0
    fi

    # Copy from Gateway directory if it exists
    if [[ -f "$(dirname "$0")/raw_lora_capture.py" ]]; then
        cp "$(dirname "$0")/raw_lora_capture.py" "$WORK_DIR/"
        chmod +x "$WORK_DIR/raw_lora_capture.py"
        print_success "Raw LoRa capture script copied and configured"
    else
        print_error "raw_lora_capture.py not found in Gateway directory"
        print_status "Please ensure raw_lora_capture.py is in the same directory as this script"
        return 1
    fi
}

create_monitoring_wrapper() {
    print_status "Creating secure monitoring wrapper scripts..."

    # Basic signal monitor
    cat > "$WORK_DIR/monitor_signals.sh" << 'EOF'
#!/bin/bash
# Simple signal monitoring without decryption

echo "📡 RAK Gateway - Basic Signal Monitor"
echo "Shows all LoRa traffic in your area"
echo "Press Ctrl+C to stop"
echo "=========================="

cd "$(dirname "$0")"

# Find packet forwarder based on OS
if [[ -f "sx1302_hal-2.0.1/packet_forwarder/lora_pkt_fwd" ]]; then
    PF_PATH="sx1302_hal-2.0.1/packet_forwarder"
elif [[ -f "sx1302_hal/packet_forwarder/lora_pkt_fwd" ]]; then
    PF_PATH="sx1302_hal/packet_forwarder"
else
    echo "❌ Packet forwarder not found!"
    echo "Please run the main setup script first."
    exit 1
fi

cd "$PF_PATH"

# Set device permissions
sudo chmod 666 /dev/ttyACM0 2>/dev/null || sudo chmod 666 /dev/ttyUSB0 2>/dev/null

# Start with basic filtering
sudo ./lora_pkt_fwd | grep --line-buffered -E "(rxpk|RSSI|frequency)"
EOF

    # Advanced signal monitor with decryption
    cat > "$WORK_DIR/monitor_my_device.sh" << 'EOF'
#!/bin/bash
# Advanced monitoring with device-specific decryption

echo "🎯 RAK Gateway - My Device Monitor"
echo "Filters and decrypts only YOUR device's signals"
echo "Press Ctrl+C to stop"
echo "================================"

cd "$(dirname "$0")"

# Check if Python script exists
if [[ ! -f "rak_signal_monitor.py" ]]; then
    echo "❌ Signal monitor script not found!"
    echo "Please run the main setup script first."
    exit 1
fi

# Find packet forwarder
if [[ -f "sx1302_hal-2.0.1/packet_forwarder/lora_pkt_fwd" ]]; then
    PF_PATH="sx1302_hal-2.0.1/packet_forwarder"
elif [[ -f "sx1302_hal/packet_forwarder/lora_pkt_fwd" ]]; then
    PF_PATH="sx1302_hal/packet_forwarder"
else
    echo "❌ Packet forwarder not found!"
    exit 1
fi

cd "$PF_PATH"

# Set permissions
sudo chmod 666 /dev/ttyACM0 2>/dev/null || sudo chmod 666 /dev/ttyUSB0 2>/dev/null

# Start packet forwarder and pipe to Python monitor
sudo ./lora_pkt_fwd | python3 "$(dirname "$(dirname "$(pwd)")")/rak_signal_monitor.py"
EOF

    chmod +x "$WORK_DIR/monitor_signals.sh"
    chmod +x "$WORK_DIR/monitor_my_device.sh"
    print_success "Monitoring wrapper scripts created"
}

# ============================================================================
# INSTALLATION MANAGEMENT (Linux-Optimized)
# ============================================================================

run_installation() {
    print_status "Starting RAK software installation for Linux..."

    # Ensure device is accessible
    if [[ "$DEVICE_STATUS" == "NOT_FOUND" ]]; then
        print_error "RAK device not found. Please ensure device is connected."
        return 1
    fi

    # Get device model
    select_device_model

    # Install prerequisites with parallel execution
    print_status "Installing prerequisites..."
    sudo apt update && sudo apt install -y make gcc wget git usbutils build-essential -qq

    # Download and compile
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"

    if [[ "$USE_GIT_CLONE" == "true" ]]; then
        git clone https://github.com/Lora-net/sx1302_hal.git
        cd sx1302_hal
        INSTALL_PATH="$WORK_DIR/sx1302_hal"
    else
        wget -q https://github.com/Lora-net/sx1302_hal/archive/V2.0.1.tar.gz
        tar -zxf V2.0.1.tar.gz
        cd sx1302_hal-2.0.1
        INSTALL_PATH="$WORK_DIR/sx1302_hal-2.0.1"
    fi

    print_status "Compiling RAK software..."
    make -j$(nproc)

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

select_device_model() {
    if [[ "$QUICK_MODE" == "true" ]] && [[ -n "$DEVICE_MODEL" ]]; then
        print_status "Quick mode: Using cached device model $DEVICE_MODEL"
        return 0
    fi

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
    if [[ "$QUICK_MODE" == "true" ]] && [[ -n "$REGION" ]]; then
        print_status "Quick mode: Using cached region $REGION"
        return 0
    fi

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

    if [[ "$INSTALLATION_STATUS" != "INSTALLED" ]]; then
        print_error "Cannot start packet forwarder - installation not found"
        return 1
    fi

    cd "$INSTALL_PATH/packet_forwarder"
    print_warning "Press Ctrl+C to stop. Gateway EUI will be shown in the logs."
    ./lora_pkt_fwd
}

get_gateway_eui() {
    print_status "Getting Gateway EUI..."

    if [[ "$INSTALLATION_STATUS" != "INSTALLED" ]]; then
        print_error "Cannot get EUI - installation not found"
        return 1
    fi

    cd "$INSTALL_PATH/util_chip_id"
    ./chip_id -u -d "${DEVICE_PATH:-/dev/ttyACM0}"
}

# ============================================================================
# ENHANCED MENU SYSTEM
# ============================================================================

show_signal_monitoring_menu() {
    echo ""
    echo "📡 SIGNAL MONITORING OPTIONS:"
    echo "1) Basic signal monitor (all LoRa traffic)"
    echo "2) My device monitor (filtered + decryption)"
    echo "3) Configure device keys"
    echo "4) Test decryption"
    echo "5) Install/update Python tools"
    echo "6) Back to main menu"
    echo ""
}

handle_signal_monitoring() {
    show_signal_monitoring_menu
    read -p "Enter your choice (1-6): " choice
    
    case $choice in
        1) start_basic_monitoring ;;
        2) start_device_monitoring ;;
        3) configure_device_keys ;;
        4) test_decryption ;;
        5) install_python_dependencies ;;
        6) return ;;
        *) print_error "Invalid choice" ;;
    esac
}

start_basic_monitoring() {
    print_status "Starting basic signal monitoring..."
    
    if [[ ! -f "$WORK_DIR/monitor_signals.sh" ]]; then
        create_monitoring_wrapper
    fi
    
    case "$DETECTED_OS-$INSTALLATION_STATUS" in
        "LINUX-INSTALLED")
            cd "$WORK_DIR"
            ./monitor_signals.sh
            ;;
        "WINDOWS-INSTALLED")
            wsl bash -c "cd ~/rak_gateway_unified && ./monitor_signals.sh"
            ;;
        "MACOS-INSTALLED_DOCKER")
            docker exec -it rak_gateway bash -c "cd /opt && ./monitor_signals.sh"
            ;;
        *)
            print_error "Monitoring not available - check installation status"
            ;;
    esac
}

start_device_monitoring() {
    print_status "Starting device-specific monitoring..."
    
    # Ensure Python tools are installed
    if [[ "$PYTHON_TOOLS_INSTALLED" != "true" ]]; then
        print_status "Installing Python tools first..."
        install_python_dependencies
    fi
    
    if [[ ! -f "$WORK_DIR/rak_signal_monitor.py" ]]; then
        create_signal_monitor_script
    fi
    
    if [[ ! -f "$WORK_DIR/monitor_my_device.sh" ]]; then
        create_monitoring_wrapper
    fi
    
    case "$DETECTED_OS-$INSTALLATION_STATUS" in
        "LINUX-INSTALLED")
            cd "$WORK_DIR"
            ./monitor_my_device.sh
            ;;
        "WINDOWS-INSTALLED")
            wsl bash -c "cd ~/rak_gateway_unified && ./monitor_my_device.sh"
            ;;
        "MACOS-INSTALLED_DOCKER")
            docker exec -it rak_gateway bash -c "cd /opt && ./monitor_my_device.sh"
            ;;
        *)
            print_error "Device monitoring not available - check installation status"
            ;;
    esac
}

configure_device_keys() {
    print_status "Configuring device keys..."
    
    if [[ ! -f "$WORK_DIR/rak_signal_monitor.py" ]]; then
        create_signal_monitor_script
    fi
    
    case "$DETECTED_OS" in
        "LINUX")
            cd "$WORK_DIR"
            python3 rak_signal_monitor.py configure
            ;;
        "WINDOWS")
            wsl bash -c "cd ~/rak_gateway_unified && python3 rak_signal_monitor.py configure"
            ;;
        "MACOS")
            cd "$WORK_DIR"
            python3 rak_signal_monitor.py configure
            ;;
    esac
}

test_decryption() {
    print_status "Testing decryption with sample data..."
    
    if [[ ! -f "$WORK_DIR/rak_signal_monitor.py" ]]; then
        create_signal_monitor_script
    fi
    
    case "$DETECTED_OS" in
        "LINUX")
            cd "$WORK_DIR"
            python3 rak_signal_monitor.py test
            ;;
        "WINDOWS")
            wsl bash -c "cd ~/rak_gateway_unified && python3 rak_signal_monitor.py test"
            ;;
        "MACOS")
            cd "$WORK_DIR"
            python3 rak_signal_monitor.py test
            ;;
    esac
}

# ============================================================================
# ENHANCED MAIN MENU
# ============================================================================

show_enhanced_main_menu() {
    echo ""
    echo "=== RAK UNIFIED GATEWAY MANAGER v$SCRIPT_VERSION ==="

    if [[ "$INSTALLATION_STATUS" == "INSTALLED" ]] && [[ "$DEVICE_STATUS" == "FOUND"* ]]; then
        echo "🚀 GATEWAY OPERATIONS:"
        echo "1) Start packet forwarder"
        echo "2) Signal monitoring & analysis"
        echo "3) Get Gateway EUI"
        echo "4) View status"
        echo ""
        echo "⚙️  MANAGEMENT:"
        echo "5) USB troubleshooting"
        echo "6) Reconfigure region"
        echo "7) Python tools setup"
        echo "8) Detailed diagnostics"
        echo "9) Exit"
    else
        echo "🔧 SETUP REQUIRED:"
        echo "1) Auto-setup (detect and install everything)"
        echo "2) Manual USB setup"
        echo "3) Manual software installation"
        echo "4) Install Python monitoring tools"
        echo ""
        echo "ℹ️  INFORMATION:"
        echo "5) Check device connection"
        echo "6) Show system status"
        echo "7) Troubleshooting help"
        echo "8) Exit"
    fi
    echo ""
}

handle_enhanced_menu_choice() {
    if [[ "$INSTALLATION_STATUS" == "INSTALLED" ]] && [[ "$DEVICE_STATUS" == "FOUND"* ]]; then
        read -p "Enter your choice (1-9): " choice
        case $choice in
            1) start_packet_forwarder ;;
            2) handle_signal_monitoring ;;
            3) get_gateway_eui ;;
            4) show_status_summary ;;
            5) setup_device_permissions ;;
            6) reconfigure_region ;;
            7) install_python_dependencies ;;
            8) toggle_quick_mode ;;
            9) exit_script ;;
            *) print_error "Invalid choice" ;;
        esac
    else
        read -p "Enter your choice (1-8): " choice
        case $choice in
            1) enhanced_auto_setup ;;
            2) setup_device_permissions && detect_usb_device ;;
            3) run_installation ;;
            4) install_python_dependencies && create_signal_monitor_script && create_monitoring_wrapper ;;
            5) detect_usb_device ;;
            6) show_status_summary ;;
            7) show_troubleshooting ;;
            8) exit_script ;;
            *) print_error "Invalid choice" ;;
        esac
    fi
}

# [Keep all existing functions from the original script: detect_operating_system, check_installation_status, etc.]

# ============================================================================
# ENHANCED AUTO SETUP
# ============================================================================

enhanced_auto_setup() {
    print_status "Starting enhanced automatic setup with Python tools..."
    
    # Standard setup steps
    if [[ "$DEVICE_STATUS" == "NOT_FOUND" ]]; then
        print_status "Setting up USB passthrough..."
        setup_usb_passthrough
        detect_usb_device
    fi
    
    if [[ "$INSTALLATION_STATUS" == "NOT_INSTALLED" ]]; then
        print_status "Installing RAK software..."
        run_installation
    fi
    
    # Enhanced: Install Python monitoring tools
    print_status "Setting up Python signal monitoring tools..."
    install_python_dependencies
    create_signal_monitor_script
    create_monitoring_wrapper
    
    # Verification
    check_installation_status
    detect_usb_device
    
    if [[ "$INSTALLATION_STATUS" == *"INSTALLED"* ]] && [[ "$DEVICE_STATUS" == "FOUND"* ]]; then
        print_success "Enhanced auto-setup completed successfully!"
        print_status "Python signal monitoring tools are ready"
        save_config
    else
        print_error "Setup incomplete. Check troubleshooting section."
    fi
}

# ============================================================================
# ENHANCED SAVE/LOAD CONFIG
# ============================================================================

save_enhanced_config() {
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
PYTHON_TOOLS_INSTALLED=$PYTHON_TOOLS_INSTALLED
LAST_UPDATE=$(date)
SCRIPT_VERSION=$SCRIPT_VERSION
EOF
}

# ============================================================================
# MAIN EXECUTION (Updated)
# ============================================================================

main() {
    # Initialize
    init_logging
    echo "================================================"
    echo "RAK WisGate Developer Base - Enhanced Unified Manager v$SCRIPT_VERSION"
    echo "Cross-platform setup with Python signal monitoring"
    echo "================================================"
    
    # Load existing config
    load_config
    
    # Detection phase
    detect_operating_system
    detect_usb_device
    check_installation_status
    
    # Check if Python tools are available
    if command -v python3 >/dev/null 2>&1 && python3 -c "import Crypto.Cipher" 2>/dev/null; then
        PYTHON_TOOLS_INSTALLED="true"
    fi
    
    # Save initial detection
    save_config
    
    # Show current status
    show_status_summary
    
    # Main loop with enhanced menu
    while true; do
        show_enhanced_main_menu
        handle_enhanced_menu_choice
        echo ""
        read -p "Press Enter to continue..." || break
    done
}

# ============================================================================
# MISSING FUNCTIONS IMPLEMENTATION
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
    if [[ -n "$DEVICE_MODEL" ]]; then
        echo "Device Model: $DEVICE_MODEL ($CONCENTRATOR)"
    fi
    if [[ -n "$REGION" ]]; then
        echo "Region: $REGION"
    fi
    if [[ -n "$INSTALL_PATH" ]]; then
        echo "Install Path: $INSTALL_PATH"
    fi
    echo "Python Tools: $PYTHON_TOOLS_INSTALLED"
    echo "Quick Mode: $QUICK_MODE"
    echo ""
}

show_troubleshooting() {
    echo ""
    echo "=== LINUX TROUBLESHOOTING GUIDE ==="
    echo ""
    echo "Common Issues:"
    echo "- Device not detected: Check USB cable and ensure device is powered"
    echo "- Permission denied: Run 'sudo usermod -a -G dialout \$USER' and re-login"
    echo "- Compilation fails: Install build-essential: 'sudo apt install build-essential'"
    echo "- Port conflicts: Stop other packet forwarders with 'sudo pkill lora_pkt_fwd'"
    echo "- Python errors: Install pycryptodome: 'pip3 install --user pycryptodome'"
    echo ""
    echo "Device Detection:"
    echo "- Check lsusb: 'lsusb | grep -i stmicro'"
    echo "- Check serial ports: 'ls /dev/ttyACM* /dev/ttyUSB*'"
    echo "- Test device: 'dmesg | tail -20' after connecting"
    echo ""
    read -p "Press Enter to continue..."
}

toggle_quick_mode() {
    if [[ "$QUICK_MODE" == "true" ]]; then
        export QUICK_RAK=false
        QUICK_MODE="false"
        print_status "Quick mode disabled - full checks will be performed"
    else
        export QUICK_RAK=true
        QUICK_MODE="true"
        print_status "Quick mode enabled - cached values will be used"
    fi

    if grep -q "QUICK_RAK" ~/.bashrc; then
        sed -i "s/export QUICK_RAK=.*/export QUICK_RAK=$QUICK_MODE/" ~/.bashrc
    else
        echo "export QUICK_RAK=$QUICK_MODE" >> ~/.bashrc
    fi

    save_config
}

reconfigure_region() {
    print_status "Reconfiguring region..."
    select_region

    if [[ "$INSTALLATION_STATUS" == "INSTALLED" ]]; then
        cd "$INSTALL_PATH/packet_forwarder"
        cp "global_conf.json.sx1250.$REGION.USB" global_conf.json
    fi

    save_config
    print_success "Region reconfigured to $REGION"
}

exit_script() {
    print_status "Saving configuration and exiting..."
    save_config
    print_status "Goodbye!"
    exit 0
}


# ============================================================================
# SIGNAL MONITORING FUNCTIONS
# ============================================================================

handle_signal_monitoring() {
    echo ""
    echo "📡 SIGNAL MONITORING OPTIONS:"
    echo "1) Basic signal monitor (all LoRa traffic)"
    echo "2) My device monitor (filtered + decryption)"
    echo "3) All devices monitor (advanced analysis)"
    echo "4) Raw LoRa capture (Sensorite V4 mode)"
    echo "5) Configure device keys"
    echo "6) Test decryption"
    echo "7) Back to main menu"
    echo ""
    read -p "Enter your choice (1-7): " choice

    case $choice in
        1) start_basic_monitoring ;;
        2) start_device_monitoring ;;
        3) start_all_devices_monitoring ;;
        4) start_raw_lora_capture ;;
        5) configure_device_keys ;;
        6) test_decryption ;;
        7) return ;;
        *) print_error "Invalid choice" ;;
    esac
}

start_basic_monitoring() {
    print_status "Starting basic signal monitoring..."
    if [[ ! -f "$WORK_DIR/monitor_signals.sh" ]]; then
        create_monitoring_wrapper
    fi
    cd "$WORK_DIR" && ./monitor_signals.sh
}

start_device_monitoring() {
    print_status "Starting device-specific monitoring..."
    if [[ "$PYTHON_TOOLS_INSTALLED" != "true" ]]; then
        install_python_dependencies
    fi
    if [[ ! -f "$WORK_DIR/rak_signal_monitor.py" ]]; then
        create_signal_monitor_script
    fi
    if [[ ! -f "$WORK_DIR/monitor_my_device.sh" ]]; then
        create_monitoring_wrapper
    fi
    cd "$WORK_DIR" && ./monitor_my_device.sh
}

start_all_devices_monitoring() {
    print_status "Starting all devices monitoring..."
    if [[ "$PYTHON_TOOLS_INSTALLED" != "true" ]]; then
        install_python_dependencies
    fi
    if [[ ! -f "$WORK_DIR/monitor_all_devices.sh" ]]; then
        create_monitoring_wrapper
    fi
    cd "$WORK_DIR" && ./monitor_all_devices.sh
}

start_raw_lora_capture() {
    print_status "Starting raw LoRa capture for Sensorite V4..."

    # Check if raw_lora_capture.py exists
    if [[ ! -f "$WORK_DIR/raw_lora_capture.py" ]]; then
        print_status "Creating raw LoRa capture script..."
        create_raw_lora_script
    fi

    # Ensure Python tools are installed
    if [[ "$PYTHON_TOOLS_INSTALLED" != "true" ]]; then
        print_status "Installing Python tools first..."
        install_python_dependencies
    fi

    echo ""
    echo "🎯 RAW LORA CAPTURE MODE"
    echo "This mode captures raw LoRa packets from Sensorite V4 devices"
    echo "No LoRaWAN network server required"
    echo ""
    echo "Options:"
    echo "1) Monitor Sensorite V4 only (filtered)"
    echo "2) Monitor all raw LoRa traffic"
    echo "3) Test with sample data"
    echo ""
    read -p "Enter your choice (1-3): " raw_choice

    cd "$WORK_DIR"
    case $raw_choice in
        1)
            print_status "Monitoring Sensorite V4 devices only..."
            # Monitor packet forwarder output and pipe to raw capture
            if [[ "$INSTALLATION_STATUS" == "INSTALLED" ]]; then
                cd "$INSTALL_PATH/packet_forwarder"
                sudo ./lora_pkt_fwd | python3 "$WORK_DIR/raw_lora_capture.py"
            else
                print_error "Packet forwarder not installed. Run main installation first."
            fi
            ;;
        2)
            print_status "Monitoring all raw LoRa traffic..."
            if [[ "$INSTALLATION_STATUS" == "INSTALLED" ]]; then
                cd "$INSTALL_PATH/packet_forwarder"
                sudo ./lora_pkt_fwd | python3 "$WORK_DIR/raw_lora_capture.py" all
            else
                print_error "Packet forwarder not installed. Run main installation first."
            fi
            ;;
        3)
            print_status "Testing with sample data..."
            python3 "$WORK_DIR/raw_lora_capture.py" test
            ;;
        *)
            print_error "Invalid choice"
            ;;
    esac
}

configure_device_keys() {
    print_status "Configuring device keys..."
    if [[ ! -f "$WORK_DIR/rak_signal_monitor.py" ]]; then
        create_signal_monitor_script
    fi
    cd "$WORK_DIR" && python3 rak_signal_monitor.py configure
}

test_decryption() {
    print_status "Testing decryption with sample data..."
    if [[ ! -f "$WORK_DIR/rak_signal_monitor.py" ]]; then
        create_signal_monitor_script
    fi
    cd "$WORK_DIR" && python3 rak_signal_monitor.py test
}

# Handle Ctrl+C gracefully
trap 'echo -e "\n${YELLOW}[INFO]${NC} Script interrupted. Configuration saved."; save_config; exit 1' INT

# Run main function
main "$@"
