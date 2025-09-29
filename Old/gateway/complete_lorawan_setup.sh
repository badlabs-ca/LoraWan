#!/bin/bash

################################################################################
# Complete LoRaWAN Setup Script for RAK7371 Gateway with ChirpStack
# For Debian VM on Apple Silicon
# This script sets up a complete LoRaWAN network server and gateway integration
################################################################################

# Script Configuration
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$HOME/lorawan-network"
CHIRPSTACK_DIR="$WORK_DIR/chirpstack"
GATEWAY_DIR="$WORK_DIR/rak7371"
DATA_DIR="$WORK_DIR/data"
LOGS_DIR="$WORK_DIR/logs"

# Network Configuration
CHIRPSTACK_HOST="localhost"
CHIRPSTACK_PORT="8080"
MQTT_HOST="localhost"
MQTT_PORT="1883"
GATEWAY_UDP_PORT="1700"

# Gateway Configuration (defaults - will be overridden by region selection)
GATEWAY_REGION="US915"  # Can be changed: EU868, US915, AS923, AU915, CN470, etc.
CHIRPSTACK_REGION="us915_1"  # ChirpStack region identifier
GATEWAY_CONFIG_FILE="global_conf.json.sx1250.US915.USB"  # Gateway config file
GATEWAY_EUI=""          # Will be auto-detected

# ChirpStack Default Credentials
CS_ADMIN_USER="admin"
CS_ADMIN_PASS="admin"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Logging Configuration
LOG_FILE="$LOGS_DIR/setup-$(date +%Y%m%d-%H%M%S).log"

################################################################################
# UTILITY FUNCTIONS
################################################################################

# Initialize logging
init_logging() {
    mkdir -p "$LOGS_DIR"
    exec 1> >(tee -a "$LOG_FILE")
    exec 2>&1
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting LoRaWAN Setup v$SCRIPT_VERSION" >> "$LOG_FILE"
}

# Print functions with logging
print_header() {
    echo -e "\n${BLUE}${BOLD}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}${BOLD}  $1${NC}"
    echo -e "${BLUE}${BOLD}════════════════════════════════════════════════════════════${NC}\n"
}

print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_info() {
    echo -e "${CYAN}[i]${NC} $1"
}

print_progress() {
    echo -e "${MAGENTA}[⏳]${NC} $1"
}

print_success() {
    echo -e "\n${GREEN}${BOLD}✓ $1${NC}\n"
}

# Check if running on Debian
check_debian() {
    if ! grep -q "debian" /etc/os-release 2>/dev/null; then
        print_warning "This script is optimized for Debian. Detected: $(lsb_release -d 2>/dev/null || echo 'Unknown')"
        read -p "Continue anyway? (y/n): " -r
        [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
    fi
}

# Check system requirements
check_system_requirements() {
    print_header "System Requirements Check"

    local errors=0

    # Check memory (minimum 2GB recommended)
    local total_mem=$(free -m | awk 'NR==2{printf "%.0f", $2}')
    if [ "$total_mem" -lt 2048 ]; then
        print_warning "Low memory: ${total_mem}MB (Recommended: 2048MB+)"
        ((errors++))
    else
        print_status "Memory: ${total_mem}MB ✓"
    fi

    # Check disk space (minimum 5GB recommended)
    local available_space=$(df / | awk 'NR==2 {printf "%.0f", $4/1024}')
    if [ "$available_space" -lt 5120 ]; then
        print_warning "Low disk space: ${available_space}MB (Recommended: 5GB+)"
        ((errors++))
    else
        print_status "Disk space: ${available_space}MB ✓"
    fi

    # Check network connectivity
    if ping -c 1 google.com &> /dev/null; then
        print_status "Internet connectivity ✓"
    else
        print_error "No internet connection"
        ((errors++))
    fi

    # Check if running in VM (Apple Silicon detection)
    if [ -f /sys/devices/virtual/dmi/id/product_name ]; then
        local product=$(cat /sys/devices/virtual/dmi/id/product_name)
        print_info "Running in: $product"
    fi

    if [ "$errors" -gt 0 ]; then
        print_warning "System check completed with $errors warning(s)"
        read -p "Continue despite warnings? (y/n): " -r
        [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
    else
        print_success "All system requirements met!"
    fi
}

# Interactive region selection
select_region() {
    print_header "LoRaWAN Region Selection"

    echo "Please select your LoRaWAN frequency region:"
    echo ""
    echo "1) 🇺🇸 US915     - United States, Canada, South America"
    echo "2) 🇪🇺 EU868     - Europe, Africa, Middle East"
    echo "3) 🇯🇵 AS923     - Asia Pacific (Japan, Singapore, etc.)"
    echo "4) 🇦🇺 AU915     - Australia, New Zealand"
    echo "5) 🇨🇳 CN470     - China"
    echo "6) 🇰🇷 KR920     - South Korea"
    echo "7) 🇮🇳 IN865     - India"
    echo "8) 🇷🇺 RU864     - Russia"
    echo ""
    echo "Choose the region that matches your location for legal compliance"
    echo "and optimal performance."
    echo ""

    while true; do
        read -p "Enter your choice (1-8): " choice

        case $choice in
            1)
                GATEWAY_REGION="US915"
                CHIRPSTACK_REGION="us915_1"
                GATEWAY_CONFIG_FILE="global_conf.json.sx1250.US915.USB"
                print_success "Selected: US915 (United States)"
                break
                ;;
            2)
                GATEWAY_REGION="EU868"
                CHIRPSTACK_REGION="eu868"
                GATEWAY_CONFIG_FILE="global_conf.json.sx1250.EU868.USB"
                print_success "Selected: EU868 (Europe)"
                break
                ;;
            3)
                GATEWAY_REGION="AS923"
                CHIRPSTACK_REGION="as923_1"
                GATEWAY_CONFIG_FILE="global_conf.json.sx1250.AS923.USB"
                print_success "Selected: AS923 (Asia Pacific)"
                break
                ;;
            4)
                GATEWAY_REGION="AU915"
                CHIRPSTACK_REGION="au915_1"
                GATEWAY_CONFIG_FILE="global_conf.json.sx1250.AU915.USB"
                print_success "Selected: AU915 (Australia)"
                break
                ;;
            5)
                GATEWAY_REGION="CN470"
                CHIRPSTACK_REGION="cn470_1"
                GATEWAY_CONFIG_FILE="global_conf.json.sx1250.CN470.USB"
                print_success "Selected: CN470 (China)"
                break
                ;;
            6)
                GATEWAY_REGION="KR920"
                CHIRPSTACK_REGION="kr920_1"
                GATEWAY_CONFIG_FILE="global_conf.json.sx1250.KR920.USB"
                print_success "Selected: KR920 (South Korea)"
                break
                ;;
            7)
                GATEWAY_REGION="IN865"
                CHIRPSTACK_REGION="in865_1"
                GATEWAY_CONFIG_FILE="global_conf.json.sx1250.IN865.USB"
                print_success "Selected: IN865 (India)"
                break
                ;;
            8)
                GATEWAY_REGION="RU864"
                CHIRPSTACK_REGION="ru864_1"
                GATEWAY_CONFIG_FILE="global_conf.json.sx1250.RU864.USB"
                print_success "Selected: RU864 (Russia)"
                break
                ;;
            *)
                print_error "Invalid choice. Please enter 1-8."
                ;;
        esac
    done

    print_info "Region Configuration:"
    echo "  Gateway Region: $GATEWAY_REGION"
    echo "  ChirpStack Region: $CHIRPSTACK_REGION"
    echo "  Config File: $GATEWAY_CONFIG_FILE"
    echo ""
}

# Complete cleanup and reset
complete_cleanup() {
    print_header "Complete System Cleanup"

    echo -e "${RED}${BOLD}⚠️  WARNING: This will completely remove ALL LoRaWAN components!${NC}"
    echo ""
    echo "This will remove:"
    echo "  • All ChirpStack containers and data"
    echo "  • All Docker volumes and images"
    echo "  • Gateway software and configurations"
    echo "  • Data dashboard and logs"
    echo "  • System services"
    echo "  • All work directories"
    echo ""
    echo -e "${YELLOW}This action cannot be undone!${NC}"
    echo ""

    read -p "Are you absolutely sure? Type 'CLEANUP' to confirm: " -r

    if [[ $REPLY != "CLEANUP" ]]; then
        print_warning "Cleanup cancelled"
        return 0
    fi

    print_status "Starting complete cleanup..."

    # 1. Stop all services
    print_progress "Stopping all services..."

    # Stop ChirpStack services
    if [ -d "$CHIRPSTACK_DIR" ]; then
        cd "$CHIRPSTACK_DIR" && docker-compose down -v --remove-orphans 2>/dev/null || true
    fi

    # Stop gateway processes
    sudo pkill -f lora_pkt_fwd 2>/dev/null || true
    screen -S rak7371_gateway -X quit 2>/dev/null || true

    # Stop data listener
    sudo pkill -f mqtt_listener.py 2>/dev/null || true

    # Stop systemd services if they exist
    sudo systemctl stop rak7371-gateway 2>/dev/null || true
    sudo systemctl stop lorawan-listener 2>/dev/null || true
    sudo systemctl disable rak7371-gateway 2>/dev/null || true
    sudo systemctl disable lorawan-listener 2>/dev/null || true

    # 2. Remove Docker containers, volumes, and images
    print_progress "Cleaning Docker resources..."

    # Remove ChirpStack-related containers
    docker ps -a --format "table {{.Names}}" | grep -E "(chirpstack|postgres|redis|mosquitto)" | xargs -r docker rm -f 2>/dev/null || true

    # Remove all ChirpStack images
    docker images --format "table {{.Repository}}:{{.Tag}} {{.ID}}" | grep -E "(chirpstack|postgres|redis|mosquitto)" | awk '{print $2}' | xargs -r docker rmi -f 2>/dev/null || true

    # Remove volumes
    docker volume ls -q | grep -E "(chirpstack|postgres|redis|mosquitto)" | xargs -r docker volume rm -f 2>/dev/null || true

    # Clean up unused Docker resources
    docker system prune -f 2>/dev/null || true
    docker volume prune -f 2>/dev/null || true

    # 3. Remove systemd service files
    print_progress "Removing system services..."

    sudo rm -f /etc/systemd/system/rak7371-gateway.service 2>/dev/null || true
    sudo rm -f /etc/systemd/system/lorawan-listener.service 2>/dev/null || true
    sudo systemctl daemon-reload 2>/dev/null || true

    # 4. Remove all work directories
    print_progress "Removing directories..."

    rm -rf "$WORK_DIR" 2>/dev/null || true
    rm -rf ~/rak7371_gateway 2>/dev/null || true
    rm -rf ~/chirpstack 2>/dev/null || true

    # Remove any legacy directories
    rm -rf ~/lorawan-network 2>/dev/null || true
    rm -rf ~/rak7371 2>/dev/null || true

    # 5. Clean up any remaining processes
    print_progress "Cleaning remaining processes..."

    # Kill any remaining LoRa-related processes
    sudo pkill -f "lora_pkt_fwd\|mqtt_listener\|chirpstack" 2>/dev/null || true

    # Remove any screen sessions
    screen -wipe 2>/dev/null || true

    # 6. Clean up logs and temporary files
    print_progress "Cleaning logs and temporary files..."

    # Remove any logs in common locations
    sudo rm -rf /var/log/chirpstack* 2>/dev/null || true
    sudo rm -rf /tmp/chirpstack* 2>/dev/null || true
    sudo rm -rf /tmp/lorawan* 2>/dev/null || true

    # 7. Clean up network interfaces and iptables (if any were created)
    print_progress "Cleaning network configuration..."

    # Remove any Docker networks created by ChirpStack
    docker network ls --format "{{.Name}}" | grep -E "(chirpstack|lorawan)" | xargs -r docker network rm 2>/dev/null || true

    # 8. Reset any system configuration changes
    print_progress "Resetting system configuration..."

    # Remove any sysctl changes (if they were permanent)
    sudo sed -i '/vm.max_map_count=262144/d' /etc/sysctl.conf 2>/dev/null || true

    # Remove Docker daemon configuration we might have added
    if [ -f "/etc/docker/daemon.json" ]; then
        # Only remove if it looks like our configuration
        if grep -q "chirpstack\|lorawan" /etc/docker/daemon.json 2>/dev/null; then
            sudo rm -f /etc/docker/daemon.json
            sudo systemctl restart docker 2>/dev/null || true
        fi
    fi

    # 9. Final verification
    print_progress "Verifying cleanup..."

    local cleanup_issues=0

    # Check for remaining processes
    if pgrep -f "lora_pkt_fwd\|mqtt_listener\|chirpstack" >/dev/null 2>&1; then
        print_warning "Some processes are still running"
        ((cleanup_issues++))
    fi

    # Check for remaining Docker containers
    if docker ps -a --format "{{.Names}}" | grep -E "(chirpstack|postgres|redis|mosquitto)" >/dev/null 2>&1; then
        print_warning "Some Docker containers still exist"
        ((cleanup_issues++))
    fi

    # Check for remaining directories
    if [ -d "$WORK_DIR" ] || [ -d ~/lorawan-network ] || [ -d ~/rak7371_gateway ]; then
        print_warning "Some directories still exist"
        ((cleanup_issues++))
    fi

    echo ""
    if [ $cleanup_issues -eq 0 ]; then
        print_success "✅ Complete cleanup successful!"
        echo ""
        print_info "System has been reset to clean state. You can now:"
        echo "  • Run a fresh installation with: $0 install"
        echo "  • Or use the interactive menu: $0"
    else
        print_warning "⚠️  Cleanup completed with $cleanup_issues minor issues"
        echo ""
        print_info "Most components removed. You may need to:"
        echo "  • Restart your system to clear remaining processes"
        echo "  • Manually remove any stubborn files"
        echo "  • Check 'docker ps -a' and 'docker images' for leftovers"
    fi

    echo ""
    print_info "Cleanup log saved to: $LOG_FILE"
}

# Create directory structure
create_directories() {
    print_progress "Creating directory structure..."
    mkdir -p "$WORK_DIR"
    mkdir -p "$CHIRPSTACK_DIR"
    mkdir -p "$GATEWAY_DIR"
    mkdir -p "$DATA_DIR"
    mkdir -p "$LOGS_DIR"
    mkdir -p "$CHIRPSTACK_DIR/configuration"
    mkdir -p "$CHIRPSTACK_DIR/configuration/chirpstack"
    mkdir -p "$CHIRPSTACK_DIR/configuration/chirpstack-gateway-bridge"
    mkdir -p "$CHIRPSTACK_DIR/configuration/postgresql/initdb"
    print_status "Directory structure created"
}

################################################################################
# DOCKER INSTALLATION AND MANAGEMENT
################################################################################

install_docker() {
    print_header "Docker Installation"

    # Check if Docker is already installed
    if command -v docker &> /dev/null; then
        print_status "Docker is already installed: $(docker --version)"

        # Check if Docker service is running
        if ! systemctl is-active --quiet docker; then
            print_progress "Starting Docker service..."
            sudo systemctl start docker
            sudo systemctl enable docker
        fi

        # Add user to docker group if needed
        if ! groups $USER | grep -q docker; then
            print_progress "Adding user to docker group..."
            sudo usermod -aG docker $USER
            print_warning "You may need to log out and back in for group changes to take effect"
        fi

        return 0
    fi

    print_progress "Installing Docker and Docker Compose..."

    # Update package list
    sudo apt update -qq

    # Install prerequisites
    sudo apt install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        software-properties-common

    # Try installing from Debian repos first
    sudo apt install -y docker.io docker-compose

    if ! command -v docker &> /dev/null; then
        print_warning "Installing from Docker official repository..."

        # Add Docker's official GPG key
        curl -fsSL https://download.docker.com/linux/debian/gpg | \
            sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

        # Add Docker repository
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
            https://download.docker.com/linux/debian $(lsb_release -cs) stable" | \
            sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

        # Install Docker
        sudo apt update
        sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    fi

    # Start and enable Docker
    sudo systemctl start docker
    sudo systemctl enable docker

    # Add user to docker group
    sudo usermod -aG docker $USER

    print_success "Docker installed successfully!"
    print_warning "You may need to log out and back in to use Docker without sudo"
}

################################################################################
# CHIRPSTACK CONFIGURATION
################################################################################

create_chirpstack_config() {
    print_header "Creating ChirpStack Configuration"

    # Create docker-compose.yml
    cat > "$CHIRPSTACK_DIR/docker-compose.yml" << 'EOF'
version: "3.8"

services:
  # PostgreSQL Database
  postgres:
    image: postgres:14-alpine
    container_name: chirpstack-postgres
    restart: unless-stopped
    environment:
      - POSTGRES_PASSWORD=chirpstack
      - POSTGRES_USER=chirpstack
      - POSTGRES_DB=chirpstack
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./configuration/postgresql/initdb:/docker-entrypoint-initdb.d
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U chirpstack"]
      interval: 10s
      timeout: 5s
      retries: 5

  # Redis Cache
  redis:
    image: redis:7-alpine
    container_name: chirpstack-redis
    restart: unless-stopped
    command: redis-server --save 300 1 --appendonly yes
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  # Mosquitto MQTT Broker
  mosquitto:
    image: eclipse-mosquitto:2
    container_name: chirpstack-mosquitto
    restart: unless-stopped
    ports:
      - "1883:1883"
      - "9001:9001"
    volumes:
      - mosquitto_data:/mosquitto/data
      - mosquitto_log:/mosquitto/log
      - ./configuration/mosquitto/mosquitto.conf:/mosquitto/config/mosquitto.conf

  # ChirpStack Application Server
  chirpstack:
    image: chirpstack/chirpstack:4
    container_name: chirpstack-application-server
    restart: unless-stopped
    command: -c /etc/chirpstack
    ports:
      - "8080:8080"
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
      mosquitto:
        condition: service_started
    volumes:
      - ./configuration/chirpstack:/etc/chirpstack
    environment:
      - MQTT_BROKER_HOST=mosquitto
      - REDIS_HOST=redis
      - POSTGRESQL_HOST=postgres

  # ChirpStack Gateway Bridge
  chirpstack-gateway-bridge:
    image: chirpstack/chirpstack-gateway-bridge:4
    container_name: chirpstack-gateway-bridge
    restart: unless-stopped
    ports:
      - "1700:1700/udp"
    depends_on:
      - mosquitto
    volumes:
      - ./configuration/chirpstack-gateway-bridge:/etc/chirpstack-gateway-bridge
    environment:
      - INTEGRATION__MQTT__EVENT_TOPIC_TEMPLATE=${CHIRPSTACK_REGION}/gateway/{{ .GatewayID }}/event/{{ .EventType }}
      - INTEGRATION__MQTT__STATE_TOPIC_TEMPLATE=${CHIRPSTACK_REGION}/gateway/{{ .GatewayID }}/state/{{ .StateType }}
      - INTEGRATION__MQTT__COMMAND_TOPIC_TEMPLATE=${CHIRPSTACK_REGION}/gateway/{{ .GatewayID }}/command/{{ .CommandType }}

volumes:
  postgres_data:
  redis_data:
  mosquitto_data:
  mosquitto_log:

networks:
  default:
    name: chirpstack-network
EOF

    # Create ChirpStack configuration
    mkdir -p "$CHIRPSTACK_DIR/configuration/chirpstack"
    cat > "$CHIRPSTACK_DIR/configuration/chirpstack/chirpstack.toml" << EOF
[logging]
level = "info"

[postgresql]
dsn = "postgresql://chirpstack:chirpstack@postgres/chirpstack?sslmode=disable"
max_open_connections = 10
min_idle_connections = 0

[redis]
servers = ["redis://redis:6379"]
cluster = false

[network]
enabled_regions = ["$CHIRPSTACK_REGION"]

[api]
bind = "0.0.0.0:8080"
secret = "chirpstack-secret-key"

[integration]
enabled = ["mqtt"]

  [integration.mqtt]
  server = "tcp://mosquitto:1883"
  json = true
EOF

    # Create Gateway Bridge configuration
    mkdir -p "$CHIRPSTACK_DIR/configuration/chirpstack-gateway-bridge"
    cat > "$CHIRPSTACK_DIR/configuration/chirpstack-gateway-bridge/chirpstack-gateway-bridge.toml" << 'EOF'
[general]
log_level = 4

[backend]
type = "semtech_udp"

  [backend.semtech_udp]
  udp_bind = "0.0.0.0:1700"

[integration]
marshaler = "protobuf"

  [integration.mqtt]
  auth_type = "generic"
  server = "tcp://mosquitto:1883"
  username = ""
  password = ""
  qos = 0
  clean_session = true
  client_id = ""
EOF

    # Create Mosquitto configuration
    mkdir -p "$CHIRPSTACK_DIR/configuration/mosquitto"
    cat > "$CHIRPSTACK_DIR/configuration/mosquitto/mosquitto.conf" << 'EOF'
persistence true
persistence_location /mosquitto/data/
log_dest file /mosquitto/log/mosquitto.log
listener 1883
allow_anonymous true
listener 9001
protocol websockets
EOF

    # Create PostgreSQL initialization script
    cat > "$CHIRPSTACK_DIR/configuration/postgresql/initdb/001-init-chirpstack.sh" << 'EOF'
#!/bin/bash
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE EXTENSION IF NOT EXISTS pg_trgm;
    CREATE EXTENSION IF NOT EXISTS hstore;
EOSQL
EOF
    chmod +x "$CHIRPSTACK_DIR/configuration/postgresql/initdb/001-init-chirpstack.sh"

    print_success "ChirpStack configuration created!"
}

start_chirpstack() {
    print_header "Starting ChirpStack Services"

    # Check if region is set, if not, prompt for it
    if [ -z "$CHIRPSTACK_REGION" ] || [ "$CHIRPSTACK_REGION" = "" ]; then
        print_warning "LoRaWAN region not configured!"
        select_region
        # Recreate config with the selected region
        create_chirpstack_config
    fi

    cd "$CHIRPSTACK_DIR"

    print_progress "Pulling Docker images..."
    docker-compose pull

    print_progress "Starting services with region: $CHIRPSTACK_REGION..."
    # Set environment variable and start
    CHIRPSTACK_REGION="$CHIRPSTACK_REGION" docker-compose up -d

    # Wait for services to be ready
    print_progress "Waiting for services to initialize..."
    local max_attempts=30
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if curl -s "http://localhost:8080/api" &>/dev/null; then
            print_success "ChirpStack is ready!"
            break
        fi
        echo -n "."
        sleep 2
        ((attempt++))
    done

    if [ $attempt -gt $max_attempts ]; then
        print_error "ChirpStack failed to start. Check logs with: docker-compose logs"
        return 1
    fi

    # Show service status
    docker-compose ps

    print_info "ChirpStack Web UI: http://localhost:8080"
    print_info "Default credentials: admin / admin"
    print_info "MQTT Broker: localhost:1883"
    print_info "Gateway UDP Port: 1700"
}

################################################################################
# GATEWAY SETUP
################################################################################

install_gateway_tools() {
    print_header "Installing RAK7371 Gateway Tools"

    print_progress "Installing required packages..."
    sudo apt update
    sudo apt install -y \
        git \
        make \
        gcc \
        g++ \
        libusb-1.0-0-dev \
        pkg-config \
        jq \
        netcat-openbsd \
        screen

    print_success "Gateway tools installed!"
}

setup_gateway_software() {
    print_header "Setting up RAK7371 Gateway Software"

    cd "$GATEWAY_DIR"

    # Clone sx1302_hal repository if not exists
    if [ ! -d "sx1302_hal" ]; then
        print_progress "Cloning Semtech SX1302 HAL..."
        git clone https://github.com/Lora-net/sx1302_hal.git
    fi

    cd sx1302_hal

    print_progress "Compiling gateway software..."
    make clean
    make

    if [ $? -eq 0 ]; then
        print_success "Gateway software compiled successfully!"
    else
        print_error "Compilation failed!"
        return 1
    fi
}

configure_packet_forwarder() {
    print_header "Configuring Packet Forwarder"

    cd "$GATEWAY_DIR/sx1302_hal/packet_forwarder"

    # Use the config file selected during region selection
    local config_file="$GATEWAY_CONFIG_FILE"

    print_status "Using configuration file: $config_file for $GATEWAY_REGION region"

    # Copy configuration file
    if [ -f "$config_file" ]; then
        cp "$config_file" global_conf.json
    else
        print_warning "Config file $config_file not found, trying default EU868"
        cp "global_conf.json.sx1250.EU868.USB" global_conf.json
    fi

    # Update server address to point to local ChirpStack
    jq '.gateway_conf.server_address = "localhost" |
        .gateway_conf.serv_port_up = 1700 |
        .gateway_conf.serv_port_down = 1700' \
        global_conf.json > global_conf.json.tmp && \
        mv global_conf.json.tmp global_conf.json

    print_success "Packet forwarder configured for $GATEWAY_REGION region!"
}

detect_gateway_eui() {
    print_header "Detecting Gateway EUI"

    # Check if gateway is connected
    if ! lsusb | grep -q "STMicroelectronics\|RAK"; then
        print_warning "RAK7371 gateway not detected via USB"
        print_info "Please ensure the gateway is connected and powered on"
        return 1
    fi

    cd "$GATEWAY_DIR/sx1302_hal/util_chip_id"

    # Try to get EUI
    local eui=$(sudo ./chip_id -u -d /dev/ttyACM0 2>/dev/null | grep "EUI" | awk '{print $NF}')

    if [ -z "$eui" ]; then
        # Try alternative device paths
        for device in /dev/ttyUSB0 /dev/ttyUSB1 /dev/ttyACM1; do
            if [ -e "$device" ]; then
                eui=$(sudo ./chip_id -u -d "$device" 2>/dev/null | grep "EUI" | awk '{print $NF}')
                [ -n "$eui" ] && break
            fi
        done
    fi

    if [ -n "$eui" ]; then
        GATEWAY_EUI="$eui"
        echo "$GATEWAY_EUI" > "$GATEWAY_DIR/gateway_eui.txt"
        print_success "Gateway EUI detected: $GATEWAY_EUI"
    else
        print_warning "Could not auto-detect Gateway EUI"
        print_info "You may need to get it manually from the gateway"
        return 1
    fi
}

register_gateway_chirpstack() {
    print_header "Registering Gateway in ChirpStack"

    if [ -z "$GATEWAY_EUI" ]; then
        if [ -f "$GATEWAY_DIR/gateway_eui.txt" ]; then
            GATEWAY_EUI=$(cat "$GATEWAY_DIR/gateway_eui.txt")
        else
            print_error "Gateway EUI not available. Please detect it first."
            return 1
        fi
    fi

    print_progress "Attempting to register gateway with EUI: $GATEWAY_EUI"

    # Get auth token
    local auth_response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "{\"email\":\"$CS_ADMIN_USER\",\"password\":\"$CS_ADMIN_PASS\"}" \
        "http://localhost:8080/api/internal/login")

    local jwt_token=$(echo "$auth_response" | jq -r '.jwt // empty')

    if [ -z "$jwt_token" ]; then
        print_warning "Could not authenticate with ChirpStack API"
        print_info "Please register the gateway manually in the web UI"
        print_info "Gateway EUI: $GATEWAY_EUI"
        return 1
    fi

    # Create gateway
    local gateway_data='{
        "gateway": {
            "id": "'$GATEWAY_EUI'",
            "name": "RAK7371-Gateway",
            "description": "RAK7371 LoRaWAN Gateway",
            "location": {
                "latitude": 0,
                "longitude": 0,
                "altitude": 0
            },
            "gateway_profile_id": null
        }
    }'

    local response=$(curl -s -X POST \
        -H "Authorization: Bearer $jwt_token" \
        -H "Content-Type: application/json" \
        -d "$gateway_data" \
        "http://localhost:8080/api/gateways")

    if echo "$response" | grep -q "error"; then
        print_warning "Gateway registration via API failed"
        print_info "Please register manually in the web UI"
    else
        print_success "Gateway registered successfully!"
    fi
}

start_gateway() {
    print_header "Starting RAK7371 Gateway"

    cd "$GATEWAY_DIR/sx1302_hal/packet_forwarder"

    # Check if already running
    if pgrep -f lora_pkt_fwd > /dev/null; then
        print_warning "Gateway packet forwarder is already running"
        return 0
    fi

    print_progress "Starting packet forwarder..."

    # Start in screen session for background operation
    screen -dmS rak7371_gateway sudo ./lora_pkt_fwd

    sleep 3

    if pgrep -f lora_pkt_fwd > /dev/null; then
        print_success "Gateway started successfully!"
        print_info "View gateway logs: screen -r rak7371_gateway"
    else
        print_error "Failed to start gateway"
        return 1
    fi
}

################################################################################
# DATA DISPLAY AND MONITORING
################################################################################

create_data_viewer() {
    print_header "Creating Data Viewer Dashboard"

    # Create simple web dashboard for viewing data
    cat > "$DATA_DIR/index.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>LoRaWAN Data Dashboard</title>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
        }
        .header {
            text-align: center;
            color: white;
            margin-bottom: 30px;
        }
        .header h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
        }
        .card {
            background: white;
            border-radius: 10px;
            padding: 20px;
            margin-bottom: 20px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.1);
        }
        .status-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
            margin-bottom: 20px;
        }
        .status-item {
            padding: 15px;
            background: #f8f9fa;
            border-radius: 8px;
            text-align: center;
        }
        .status-item.online { border-left: 4px solid #28a745; }
        .status-item.offline { border-left: 4px solid #dc3545; }
        .status-label {
            font-size: 0.9em;
            color: #6c757d;
            margin-bottom: 5px;
        }
        .status-value {
            font-size: 1.5em;
            font-weight: bold;
            color: #212529;
        }
        .data-table {
            width: 100%;
            border-collapse: collapse;
        }
        .data-table th {
            background: #f8f9fa;
            padding: 12px;
            text-align: left;
            font-weight: 600;
            color: #495057;
            border-bottom: 2px solid #dee2e6;
        }
        .data-table td {
            padding: 12px;
            border-bottom: 1px solid #dee2e6;
        }
        .data-table tr:hover {
            background: #f8f9fa;
        }
        .timestamp {
            color: #6c757d;
            font-size: 0.9em;
        }
        .device-id {
            font-family: monospace;
            background: #e9ecef;
            padding: 2px 6px;
            border-radius: 4px;
        }
        .data-value {
            font-family: monospace;
            color: #007bff;
        }
        .no-data {
            text-align: center;
            color: #6c757d;
            padding: 40px;
            font-size: 1.1em;
        }
        .refresh-btn {
            background: #007bff;
            color: white;
            border: none;
            padding: 10px 20px;
            border-radius: 5px;
            cursor: pointer;
            font-size: 1em;
        }
        .refresh-btn:hover {
            background: #0056b3;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🌐 LoRaWAN Data Dashboard</h1>
            <p>Real-time monitoring of RAK7371 Gateway and connected devices</p>
        </div>

        <div class="card">
            <h2>System Status</h2>
            <div class="status-grid">
                <div class="status-item online">
                    <div class="status-label">ChirpStack Server</div>
                    <div class="status-value" id="server-status">Online</div>
                </div>
                <div class="status-item" id="gateway-status-card">
                    <div class="status-label">Gateway</div>
                    <div class="status-value" id="gateway-status">Checking...</div>
                </div>
                <div class="status-item">
                    <div class="status-label">Active Devices</div>
                    <div class="status-value" id="device-count">0</div>
                </div>
                <div class="status-item">
                    <div class="status-label">Messages Today</div>
                    <div class="status-value" id="message-count">0</div>
                </div>
            </div>
        </div>

        <div class="card">
            <div style="display: flex; justify-content: between; align-items: center; margin-bottom: 20px;">
                <h2 style="flex: 1;">Recent Data Packets</h2>
                <button class="refresh-btn" onclick="refreshData()">↻ Refresh</button>
            </div>
            <div id="data-container">
                <table class="data-table">
                    <thead>
                        <tr>
                            <th>Timestamp</th>
                            <th>Device ID</th>
                            <th>RSSI</th>
                            <th>SNR</th>
                            <th>Data</th>
                        </tr>
                    </thead>
                    <tbody id="data-tbody">
                        <tr>
                            <td colspan="5" class="no-data">Waiting for data...</td>
                        </tr>
                    </tbody>
                </table>
            </div>
        </div>
    </div>

    <script>
        // WebSocket connection for real-time updates
        let ws = null;
        let reconnectInterval = null;

        function connectWebSocket() {
            ws = new WebSocket('ws://localhost:9001');

            ws.onopen = function() {
                console.log('Connected to MQTT WebSocket');
                document.getElementById('gateway-status').textContent = 'Connected';
                document.getElementById('gateway-status-card').classList.add('online');
                document.getElementById('gateway-status-card').classList.remove('offline');

                // Subscribe to topics
                ws.send(JSON.stringify({
                    type: 'subscribe',
                    topic: 'application/+/device/+/event/up'
                }));
            };

            ws.onmessage = function(event) {
                try {
                    const data = JSON.parse(event.data);
                    updateDataTable(data);
                } catch (e) {
                    console.error('Error parsing message:', e);
                }
            };

            ws.onerror = function(error) {
                console.error('WebSocket error:', error);
            };

            ws.onclose = function() {
                console.log('Disconnected from MQTT WebSocket');
                document.getElementById('gateway-status').textContent = 'Offline';
                document.getElementById('gateway-status-card').classList.add('offline');
                document.getElementById('gateway-status-card').classList.remove('online');

                // Try to reconnect
                if (!reconnectInterval) {
                    reconnectInterval = setInterval(function() {
                        console.log('Attempting to reconnect...');
                        connectWebSocket();
                    }, 5000);
                }
            };
        }

        function updateDataTable(data) {
            const tbody = document.getElementById('data-tbody');

            // Remove "no data" message if present
            if (tbody.querySelector('.no-data')) {
                tbody.innerHTML = '';
            }

            // Create new row
            const row = document.createElement('tr');
            const timestamp = new Date().toLocaleString();

            row.innerHTML = `
                <td class="timestamp">${timestamp}</td>
                <td><span class="device-id">${data.deviceId || 'Unknown'}</span></td>
                <td>${data.rssi || '-'} dBm</td>
                <td>${data.snr || '-'} dB</td>
                <td><span class="data-value">${JSON.stringify(data.data || {})}</span></td>
            `;

            // Add to top of table
            tbody.insertBefore(row, tbody.firstChild);

            // Keep only last 20 entries
            while (tbody.children.length > 20) {
                tbody.removeChild(tbody.lastChild);
            }

            // Update counters
            updateCounters();
        }

        function updateCounters() {
            const deviceCount = document.getElementById('device-count');
            const messageCount = document.getElementById('message-count');
            const tbody = document.getElementById('data-tbody');

            // Update message count
            messageCount.textContent = tbody.children.length;

            // Update unique device count
            const devices = new Set();
            tbody.querySelectorAll('.device-id').forEach(function(elem) {
                devices.add(elem.textContent);
            });
            deviceCount.textContent = devices.size;
        }

        function refreshData() {
            // Fetch latest data from API
            fetch('http://localhost:8080/api/devices')
                .then(response => response.json())
                .then(data => {
                    console.log('Refreshed data:', data);
                })
                .catch(error => {
                    console.error('Error fetching data:', error);
                });
        }

        // Initialize on page load
        document.addEventListener('DOMContentLoaded', function() {
            connectWebSocket();
            setInterval(updateCounters, 5000);
        });
    </script>
</body>
</html>
EOF

    # Create Python script for MQTT data listener
    cat > "$DATA_DIR/mqtt_listener.py" << 'EOF'
#!/usr/bin/env python3

import json
import paho.mqtt.client as mqtt
import sqlite3
from datetime import datetime
import os

# Configuration
MQTT_HOST = "localhost"
MQTT_PORT = 1883
DB_FILE = "/home/lorawan-network/data/lorawan_data.db"

# Initialize database
def init_db():
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS device_data (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
            device_id TEXT,
            gateway_id TEXT,
            rssi REAL,
            snr REAL,
            frequency REAL,
            data TEXT,
            raw_payload TEXT
        )
    ''')
    conn.commit()
    conn.close()

# MQTT callbacks
def on_connect(client, userdata, flags, rc):
    print(f"Connected to MQTT broker with result code {rc}")
    # Subscribe to all application data
    client.subscribe("application/+/device/+/event/up")
    client.subscribe("gateway/+/event/+")
    print("Subscribed to topics")

def on_message(client, userdata, msg):
    try:
        payload = json.loads(msg.payload.decode('utf-8'))
        print(f"Received message on topic: {msg.topic}")

        # Parse and store data
        if "application" in msg.topic:
            store_device_data(payload)
        elif "gateway" in msg.topic:
            print(f"Gateway event: {payload}")

    except Exception as e:
        print(f"Error processing message: {e}")

def store_device_data(payload):
    """Store device data in database"""
    try:
        conn = sqlite3.connect(DB_FILE)
        cursor = conn.cursor()

        device_id = payload.get('deviceName', 'Unknown')
        gateway_id = payload.get('rxInfo', [{}])[0].get('gatewayId', '')
        rssi = payload.get('rxInfo', [{}])[0].get('rssi', 0)
        snr = payload.get('rxInfo', [{}])[0].get('loraSnr', 0)
        frequency = payload.get('txInfo', {}).get('frequency', 0)
        data = json.dumps(payload.get('object', {}))
        raw_payload = json.dumps(payload)

        cursor.execute('''
            INSERT INTO device_data
            (device_id, gateway_id, rssi, snr, frequency, data, raw_payload)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        ''', (device_id, gateway_id, rssi, snr, frequency, data, raw_payload))

        conn.commit()
        conn.close()

        print(f"Stored data from device: {device_id}, RSSI: {rssi}, SNR: {snr}")

    except Exception as e:
        print(f"Error storing data: {e}")

# Main function
def main():
    print("LoRaWAN MQTT Data Listener")
    print(f"Connecting to {MQTT_HOST}:{MQTT_PORT}")

    # Initialize database
    init_db()

    # Create MQTT client
    client = mqtt.Client()
    client.on_connect = on_connect
    client.on_message = on_message

    # Connect to broker
    try:
        client.connect(MQTT_HOST, MQTT_PORT, 60)
        client.loop_forever()
    except KeyboardInterrupt:
        print("\nShutting down...")
        client.disconnect()
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    main()
EOF
    chmod +x "$DATA_DIR/mqtt_listener.py"

    # Install Python MQTT client if needed
    pip3 install paho-mqtt 2>/dev/null || sudo apt install -y python3-paho-mqtt

    print_success "Data viewer dashboard created!"
    print_info "Dashboard available at: file://$DATA_DIR/index.html"
}

start_data_listener() {
    print_header "Starting Data Listener"

    # Check if already running
    if pgrep -f mqtt_listener.py > /dev/null; then
        print_warning "Data listener is already running"
        return 0
    fi

    # Start in background
    cd "$DATA_DIR"
    nohup python3 mqtt_listener.py > "$LOGS_DIR/mqtt_listener.log" 2>&1 &

    print_success "Data listener started!"
    print_info "Logs available at: $LOGS_DIR/mqtt_listener.log"
}

################################################################################
# SERVICE MANAGEMENT
################################################################################

create_systemd_services() {
    print_header "Creating System Services"

    # Create service for gateway
    sudo tee /etc/systemd/system/rak7371-gateway.service > /dev/null << EOF
[Unit]
Description=RAK7371 LoRaWAN Gateway
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=$USER
WorkingDirectory=$GATEWAY_DIR/sx1302_hal/packet_forwarder
ExecStart=/usr/bin/sudo $GATEWAY_DIR/sx1302_hal/packet_forwarder/lora_pkt_fwd
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    # Create service for data listener
    sudo tee /etc/systemd/system/lorawan-listener.service > /dev/null << EOF
[Unit]
Description=LoRaWAN MQTT Data Listener
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=$USER
WorkingDirectory=$DATA_DIR
ExecStart=/usr/bin/python3 $DATA_DIR/mqtt_listener.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd
    sudo systemctl daemon-reload

    print_success "System services created!"
    print_info "Enable auto-start with: sudo systemctl enable rak7371-gateway lorawan-listener"
}

################################################################################
# STATUS AND MONITORING
################################################################################

show_status() {
    print_header "System Status"

    echo -e "${CYAN}═══ ChirpStack Services ═══${NC}"
    cd "$CHIRPSTACK_DIR" 2>/dev/null && docker-compose ps

    echo -e "\n${CYAN}═══ Gateway Status ═══${NC}"
    if pgrep -f lora_pkt_fwd > /dev/null; then
        echo -e "${GREEN}✓${NC} Packet forwarder is running"
    else
        echo -e "${RED}✗${NC} Packet forwarder is not running"
    fi

    if [ -f "$GATEWAY_DIR/gateway_eui.txt" ]; then
        echo "Gateway EUI: $(cat $GATEWAY_DIR/gateway_eui.txt)"
    fi

    echo -e "\n${CYAN}═══ Data Listener ═══${NC}"
    if pgrep -f mqtt_listener.py > /dev/null; then
        echo -e "${GREEN}✓${NC} MQTT listener is running"
    else
        echo -e "${RED}✗${NC} MQTT listener is not running"
    fi

    echo -e "\n${CYAN}═══ Network Ports ═══${NC}"
    echo "ChirpStack Web UI: http://localhost:8080"
    echo "MQTT Broker: localhost:1883"
    echo "Gateway UDP: localhost:1700"
    echo "WebSocket: ws://localhost:9001"

    echo -e "\n${CYAN}═══ Recent Logs ═══${NC}"
    if [ -f "$LOGS_DIR/mqtt_listener.log" ]; then
        tail -5 "$LOGS_DIR/mqtt_listener.log"
    fi
}

view_logs() {
    print_header "System Logs"

    echo "1) ChirpStack logs"
    echo "2) Gateway logs"
    echo "3) Data listener logs"
    echo "4) All logs"

    read -p "Select option (1-4): " choice

    case $choice in
        1)
            cd "$CHIRPSTACK_DIR" && docker-compose logs -f --tail=50
            ;;
        2)
            screen -r rak7371_gateway
            ;;
        3)
            tail -f "$LOGS_DIR/mqtt_listener.log"
            ;;
        4)
            tail -f "$LOGS_DIR"/*.log
            ;;
        *)
            print_error "Invalid choice"
            ;;
    esac
}

################################################################################
# MAIN MENU
################################################################################

show_menu() {
    clear
    print_header "LoRaWAN Network Setup - Main Menu"

    echo "━━━━━━━━━━ Quick Setup ━━━━━━━━━━"
    echo "  1) Complete Installation (First Time Setup)"
    echo "  2) Select LoRaWAN Region"
    echo ""
    echo "━━━━━━━━ ChirpStack Server ━━━━━━━"
    echo "  3) Install Docker"
    echo "  4) Deploy ChirpStack"
    echo "  5) Start ChirpStack"
    echo "  6) Stop ChirpStack"
    echo ""
    echo "━━━━━━━━━ RAK7371 Gateway ━━━━━━━━"
    echo "  7) Install Gateway Tools"
    echo "  8) Setup Gateway Software"
    echo "  9) Configure Packet Forwarder"
    echo " 10) Detect Gateway EUI"
    echo " 11) Register Gateway"
    echo " 12) Start Gateway"
    echo ""
    echo "━━━━━━━━ Data & Monitoring ━━━━━━━━"
    echo " 13) Create Data Dashboard"
    echo " 14) Start Data Listener"
    echo " 15) View Status"
    echo " 16) View Logs"
    echo ""
    echo "━━━━━━━━━━ System ━━━━━━━━━━━━"
    echo " 17) Create System Services"
    echo " 18) Open ChirpStack Web UI"
    echo " 19) Open Data Dashboard"
    echo ""
    echo "━━━━━━━━━━ Cleanup ━━━━━━━━━━━━"
    echo " 20) 🗑️  Complete Cleanup (Remove Everything)"
    echo ""
    echo " 0) Exit"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    read -p "Select option: " choice

    case $choice in
        1)
            # Complete installation
            check_system_requirements
            select_region
            create_directories
            install_docker
            create_chirpstack_config
            start_chirpstack
            install_gateway_tools
            setup_gateway_software
            configure_packet_forwarder
            detect_gateway_eui
            register_gateway_chirpstack
            start_gateway
            create_data_viewer
            start_data_listener
            create_systemd_services
            show_status
            ;;
        2) select_region ;;
        3) install_docker ;;
        4) create_chirpstack_config ;;
        5) start_chirpstack ;;
        6) cd "$CHIRPSTACK_DIR" && docker-compose down ;;
        7) install_gateway_tools ;;
        8) setup_gateway_software ;;
        9) configure_packet_forwarder ;;
        10) detect_gateway_eui ;;
        11) register_gateway_chirpstack ;;
        12) start_gateway ;;
        13) create_data_viewer ;;
        14) start_data_listener ;;
        15) show_status ;;
        16) view_logs ;;
        17) create_systemd_services ;;
        18) xdg-open "http://localhost:8080" 2>/dev/null || echo "Open: http://localhost:8080" ;;
        19) xdg-open "file://$DATA_DIR/index.html" 2>/dev/null || echo "Open: file://$DATA_DIR/index.html" ;;
        20) complete_cleanup ;;
        0) exit 0 ;;
        *) print_error "Invalid option" ;;
    esac

    if [ "$choice" != "0" ]; then
        echo ""
        read -p "Press Enter to continue..."
        show_menu
    fi
}

################################################################################
# SCRIPT ENTRY POINT
################################################################################

main() {
    clear
    print_header "LoRaWAN Network Setup Script v$SCRIPT_VERSION"
    print_info "For RAK7371 Gateway with ChirpStack on Debian VM"

    # Initialize
    init_logging
    check_debian
    create_directories

    # Check for command line arguments
    if [ $# -eq 0 ]; then
        show_menu
    else
        case "$1" in
            install)
                check_system_requirements
                select_region
                create_directories
                install_docker
                create_chirpstack_config
                start_chirpstack
                install_gateway_tools
                setup_gateway_software
                configure_packet_forwarder
                detect_gateway_eui
                register_gateway_chirpstack
                start_gateway
                create_data_viewer
                start_data_listener
                create_systemd_services
                show_status
                ;;
            start)
                start_chirpstack
                start_gateway
                start_data_listener
                ;;
            stop)
                cd "$CHIRPSTACK_DIR" && docker-compose down
                pkill -f lora_pkt_fwd
                pkill -f mqtt_listener.py
                ;;
            status)
                show_status
                ;;
            logs)
                view_logs
                ;;
            cleanup)
                complete_cleanup
                ;;
            --help|-h)
                echo "Usage: $0 [command]"
                echo ""
                echo "Commands:"
                echo "  install    - Complete installation"
                echo "  start      - Start all services"
                echo "  stop       - Stop all services"
                echo "  status     - Show system status"
                echo "  logs       - View logs"
                echo "  cleanup    - Complete cleanup (remove everything)"
                echo "  (no args)  - Show interactive menu"
                ;;
            *)
                print_error "Unknown command: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    fi
}

# Run main function
main "$@"