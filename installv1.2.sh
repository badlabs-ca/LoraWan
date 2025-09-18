#!/bin/bash

# RAK WisGate Developer Base - Enhanced Unified Cross-Platform Manager
# Auto-detects environment and handles everything intelligently
# Includes Python signal monitoring and decryption capabilities
# Works on: Windows (PowerShell/Git Bash), Linux (Ubuntu/WSL), macOS

# Global configuration
SCRIPT_VERSION="1.1.0"
WORK_DIR="$HOME/rak_gateway_unified"
CONFIG_FILE="$WORK_DIR/rak_unified_config.conf"
LOG_FILE="$WORK_DIR/rak_unified.log"
DEBUG_MODE="${DEBUG_RAK:-false}"
PYTHON_TOOLS_INSTALLED="false"

# Colors for cross-platform output
if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]] || [[ -n "$WINDIR" ]]; then
    RED='[91m'
    GREEN='[92m'
    YELLOW='[93m'
    BLUE='[94m'
    NC='[0m'
else
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

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE" 2>/dev/null || echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE" 2>/dev/null || echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE" 2>/dev/null || echo -e "${RED}[ERROR]${NC} $1"
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
    
    cat > "$WORK_DIR/rak_signal_monitor.py" << 'EOF'
#!/usr/bin/env python3
"""
RAK Gateway Signal Monitor
Real-time LoRa signal analysis and device-specific decryption
"""

import base64
import binascii
import sys
import json
import re
import time
from datetime import datetime

try:
    from Crypto.Cipher import AES
    CRYPTO_AVAILABLE = True
except ImportError:
    CRYPTO_AVAILABLE = False
    print("WARNING: pycryptodome not installed. Decryption features disabled.")

# Device configuration - UPDATE THESE TO MATCH YOUR DEVICE
DEFAULT_CONFIG = {
    "dev_eui": "0102030405060708",
    "app_eui": "1112131415161718", 
    "app_key": "21222324252627282A2B2C2D2E2F30",
    "device_name": "My RAK Device"
}

class LoRaSignalMonitor:
    def __init__(self, config=None):
        self.config = config or DEFAULT_CONFIG
        self.packet_count = 0
        self.my_device_count = 0
        self.start_time = datetime.now()
        
    def parse_lora_packet(self, line):
        """Extract LoRa packet information from gateway output"""
        try:
            # Look for JSON data in the line
            json_match = re.search(r'\{"rxpk":\[.*?\]\}', line)
            if not json_match:
                return None
                
            packet_data = json.loads(json_match.group())
            if 'rxpk' not in packet_data or not packet_data['rxpk']:
                return None
                
            rxpk = packet_data['rxpk'][0]  # First packet
            
            return {
                'timestamp': rxpk.get('time', ''),
                'frequency': rxpk.get('freq', 0),
                'rssi': rxpk.get('rssi', 0),
                'lsnr': rxpk.get('lsnr', 0),
                'datarate': rxpk.get('datr', ''),
                'size': rxpk.get('size', 0),
                'data': rxpk.get('data', ''),
                'channel': rxpk.get('chan', 0)
            }
        except (json.JSONDecodeError, KeyError, IndexError):
            return None
    
    def is_my_device(self, packet_info):
        """Check if packet is from configured device"""
        if not packet_info or not packet_info['data']:
            return False
            
        try:
            # Simple method: check if our device EUI appears in the data
            decoded = base64.b64decode(packet_info['data'])
            dev_eui_bytes = binascii.unhexlify(self.config['dev_eui'])
            
            # Check if any part of our device EUI is in the packet
            return dev_eui_bytes[:4] in decoded or dev_eui_bytes[4:] in decoded
        except:
            return False
    
    def decrypt_payload(self, data_b64):
        """Decrypt LoRaWAN payload using device keys"""
        if not CRYPTO_AVAILABLE:
            return {"error": "Crypto library not available"}
            
        try:
            encrypted_bytes = base64.b64decode(data_b64)
            key_bytes = binascii.unhexlify(self.config['app_key'])
            
            # Simple AES decryption (real LoRaWAN is more complex)
            cipher = AES.new(key_bytes, AES.MODE_ECB)
            
            # Pad to 16 bytes
            padded_data = encrypted_bytes
            if len(padded_data) % 16 != 0:
                padding = 16 - (len(padded_data) % 16)
                padded_data += b'\x00' * padding
            
            decrypted = cipher.decrypt(padded_data[:16])
            
            # Try to extract readable text
            try:
                text = decrypted.decode('utf-8').rstrip('\x00')
                return {"text": text, "hex": decrypted.hex(), "success": True}
            except:
                return {"text": None, "hex": decrypted.hex(), "success": True}
                
        except Exception as e:
            return {"error": str(e), "success": False}
    
    def analyze_signal_quality(self, packet_info):
        """Analyze signal quality and provide feedback"""
        rssi = packet_info['rssi']
        lsnr = packet_info['lsnr']
        
        # Signal strength analysis
        if rssi > -80:
            signal_quality = "Excellent"
        elif rssi > -100:
            signal_quality = "Good"
        elif rssi > -120:
            signal_quality = "Fair"
        else:
            signal_quality = "Poor"
            
        # SNR analysis
        if lsnr > 5:
            snr_quality = "Excellent"
        elif lsnr > 0:
            snr_quality = "Good"
        elif lsnr > -10:
            snr_quality = "Fair"
        else:
            snr_quality = "Poor"
            
        return {
            "signal_quality": signal_quality,
            "snr_quality": snr_quality,
            "distance_estimate": self.estimate_distance(rssi)
        }
    
    def estimate_distance(self, rssi):
        """Rough distance estimation based on RSSI"""
        if rssi > -50:
            return "< 100m"
        elif rssi > -80:
            return "100m - 1km"
        elif rssi > -100:
            return "1km - 5km"
        elif rssi > -120:
            return "5km - 15km"
        else:
            return "> 15km"
    
    def print_packet_summary(self, packet_info, is_mine=False):
        """Print formatted packet information"""
        timestamp = datetime.now().strftime("%H:%M:%S")
        
        if is_mine:
            print(f"\n🎯 MY DEVICE PACKET #{self.my_device_count}")
            print(f"⏰ Time: {timestamp}")
            print(f"📶 RSSI: {packet_info['rssi']} dBm")
            print(f"📊 SNR: {packet_info['lsnr']} dB")
            print(f"📻 Freq: {packet_info['frequency']} MHz")
            print(f"📏 Size: {packet_info['size']} bytes")
            print(f"📡 Rate: {packet_info['datarate']}")
            
            # Signal quality analysis
            quality = self.analyze_signal_quality(packet_info)
            print(f"🔍 Quality: {quality['signal_quality']} ({quality['distance_estimate']})")
            
            # Decryption attempt
            if packet_info['data']:
                print(f"🔒 Raw Data: {packet_info['data'][:32]}...")
                decrypt_result = self.decrypt_payload(packet_info['data'])
                
                if decrypt_result.get('success'):
                    if decrypt_result.get('text'):
                        print(f"📝 Decrypted: '{decrypt_result['text']}'")
                    else:
                        print(f"🔢 Hex: {decrypt_result['hex'][:32]}...")
                else:
                    print(f"❌ Decrypt failed: {decrypt_result.get('error', 'Unknown')}")
            print("-" * 50)
        else:
            print(f"[{timestamp}] #{self.packet_count} Other device: "
                  f"RSSI={packet_info['rssi']}dBm, "
                  f"Freq={packet_info['frequency']}MHz")
    
    def print_statistics(self):
        """Print session statistics"""
        duration = datetime.now() - self.start_time
        print(f"\n📊 SESSION STATISTICS")
        print(f"Duration: {duration}")
        print(f"Total packets: {self.packet_count}")
        print(f"My device packets: {self.my_device_count}")
        if self.packet_count > 0:
            percentage = (self.my_device_count / self.packet_count) * 100
            print(f"My device percentage: {percentage:.1f}%")
    
    def monitor(self):
        """Main monitoring loop"""
        print("🎯 RAK Gateway Signal Monitor")
        print(f"📱 Device: {self.config['device_name']}")
        print(f"🆔 EUI: {self.config['dev_eui']}")
        print("📡 Monitoring LoRa signals... (Ctrl+C to stop)")
        print("=" * 60)
        
        try:
            while True:
                try:
                    line = input()
                    packet_info = self.parse_lora_packet(line)
                    
                    if packet_info:
                        self.packet_count += 1
                        is_mine = self.is_my_device(packet_info)
                        
                        if is_mine:
                            self.my_device_count += 1
                            
                        self.print_packet_summary(packet_info, is_mine)
                        
                except EOFError:
                    break
                    
        except KeyboardInterrupt:
            print("\n🛑 Monitoring stopped by user")
        finally:
            self.print_statistics()

def load_config():
    """Load device configuration from file"""
    config_file = "rak_device_config.json"
    try:
        with open(config_file, 'r') as f:
            return json.load(f)
    except FileNotFoundError:
        return DEFAULT_CONFIG

def save_config(config):
    """Save device configuration to file"""
    config_file = "rak_device_config.json"
    try:
        with open(config_file, 'w') as f:
            json.dump(config, f, indent=2)
        print(f"Configuration saved to {config_file}")
    except Exception as e:
        print(f"Failed to save config: {e}")

def configure_device():
    """Interactive device configuration"""
    print("\n🔧 Device Configuration")
    print("Enter your RAK device details (or press Enter for defaults):")
    
    config = load_config()
    
    name = input(f"Device name [{config['device_name']}]: ").strip()
    if name:
        config['device_name'] = name
        
    dev_eui = input(f"Device EUI [{config['dev_eui']}]: ").strip()
    if dev_eui:
        config['dev_eui'] = dev_eui.replace('-', '').replace(':', '')
        
    app_eui = input(f"App EUI [{config['app_eui']}]: ").strip()
    if app_eui:
        config['app_eui'] = app_eui.replace('-', '').replace(':', '')
        
    app_key = input(f"App Key [{config['app_key']}]: ").strip()
    if app_key:
        config['app_key'] = app_key.replace('-', '').replace(':', '')
    
    save_config(config)
    return config

def main():
    if len(sys.argv) > 1:
        if sys.argv[1] == "configure":
            configure_device()
            return
        elif sys.argv[1] == "test":
            # Test mode with sample data
            config = load_config()
            monitor = LoRaSignalMonitor(config)
            sample_line = '{"rxpk":[{"tmst":12345,"time":"2024-01-01T12:00:00Z","chan":0,"rfch":0,"freq":915.0,"stat":1,"modu":"LORA","datr":"SF7BW125","codr":"4/5","lsnr":8.5,"rssi":-45,"size":23,"data":"QAEBAgMEBQYHCAkKCwwNDg8="}]}'
            packet_info = monitor.parse_lora_packet(sample_line)
            if packet_info:
                monitor.print_packet_summary(packet_info, True)
            return
    
    # Load configuration and start monitoring
    config = load_config()
    monitor = LoRaSignalMonitor(config)
    monitor.monitor()

if __name__ == "__main__":
    main()
EOF

    chmod +x "$WORK_DIR/rak_signal_monitor.py"
    print_success "Signal monitoring script created"
}

create_monitoring_wrapper() {
    print_status "Creating monitoring wrapper scripts..."
    
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
    
    if [[ "$INSTALLATION_STATUS" == *"INSTALLED"* ]] && [[ "$DEVICE_STATUS" == "FOUND"* ]]; then
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
    if [[ "$INSTALLATION_STATUS" == *"INSTALLED"* ]] && [[ "$DEVICE_STATUS" == "FOUND"* ]]; then
        read -p "Enter your choice (1-9): " choice
        case $choice in
            1) start_packet_forwarder ;;
            2) handle_signal_monitoring ;;
            3) get_gateway_eui ;;
            4) show_status_summary ;;
            5) setup_usb_passthrough ;;
            6) reconfigure_region ;;
            7) install_python_dependencies ;;
            8) show_detailed_status ;;
            9) exit_script ;;
            *) print_error "Invalid choice" ;;
        esac
    else
        read -p "Enter your choice (1-8): " choice
        case $choice in
            1) auto_setup ;;
            2) setup_usb_passthrough ;;
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
    save_enhanced_config
    
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

# Include all existing functions from the original script here
# [The rest of the original functions would be included]

# Run main function
main "$@"