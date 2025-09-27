#!/bin/bash

# ChirpStack Manager Script for Debian (Complete Fixed Version)
# This script handles all Docker issues, creates proper configurations, and manages ChirpStack

CHIRPSTACK_DIR="$HOME/chirpstack"
DOCKER_COMPOSE_FILE="$CHIRPSTACK_DIR/docker-compose.yml"
CONFIG_DIR="$CHIRPSTACK_DIR/configuration"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

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

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_fail() {
    echo -e "${RED}✗${NC} $1"
}

# Function to check if Docker is installed
check_docker_installed() {
    if command -v docker &> /dev/null && command -v docker-compose &> /dev/null; then
        return 0
    fi
    return 1
}

# Function to check if Docker service is running
check_docker_running() {
    if sudo systemctl is-active --quiet docker; then
        return 0
    fi
    return 1
}

# Function to check if user is in docker group
check_docker_permissions() {
    if groups $USER | grep -q docker; then
        return 0
    fi
    return 1
}

# Function to test Docker daemon connection
test_docker_daemon() {
    if docker ps &> /dev/null; then
        return 0
    fi
    return 1
}

# Function to wait for service to be ready
wait_for_service() {
    local service_name="$1"
    local port="$2"
    local max_attempts=30
    local attempt=1
    
    print_status "Waiting for $service_name to be ready on port $port..."
    
    while [ $attempt -le $max_attempts ]; do
        if nc -z localhost $port 2>/dev/null; then
            print_success "$service_name is ready!"
            return 0
        fi
        
        echo -n "."
        sleep 2
        attempt=$((attempt + 1))
    done
    
    echo ""
    print_error "$service_name failed to start within expected time"
    return 1
}

# Enhanced Docker management function
manage_docker() {
    print_header "Docker System Management"
    
    # Check if Docker is installed
    if ! check_docker_installed; then
        print_warning "Docker is not installed. Installing now..."
        install_docker
        if [ $? -ne 0 ]; then
            return 1
        fi
    else
        print_success "Docker is installed ($(docker --version | cut -d' ' -f3 | cut -d',' -f1))"
    fi
    
    # Check if Docker service is running
    if ! check_docker_running; then
        print_warning "Docker service is not running. Starting now..."
        sudo systemctl start docker
        sleep 3
        if check_docker_running; then
            print_success "Docker service started"
        else
            print_fail "Failed to start Docker service"
            print_error "Try running: sudo systemctl status docker"
            return 1
        fi
    else
        print_success "Docker service is running"
    fi
    
    # Enable Docker to start on boot
    if ! sudo systemctl is-enabled --quiet docker; then
        print_status "Enabling Docker to start on boot..."
        sudo systemctl enable docker
    fi
    
    # Check Docker permissions
    if ! check_docker_permissions; then
        print_warning "User $USER is not in docker group. Adding now..."
        sudo usermod -aG docker $USER
        print_warning "You may need to log out and back in, or run: newgrp docker"
        
        # Try to apply group in current session
        if ! test_docker_daemon; then
            print_status "Attempting to apply docker group for current session..."
            exec sg docker "$0 $*"
        fi
    else
        print_success "User has Docker permissions"
    fi
    
    # Test Docker daemon connection
    sleep 2
    if ! test_docker_daemon; then
        print_fail "Cannot connect to Docker daemon"
        print_error "You may need to:"
        print_error "1. Log out and back in"
        print_error "2. Run: newgrp docker"
        print_error "3. Reboot your system"
        return 1
    fi
    
    print_success "Docker is fully operational"
    return 0
}

# Function to install Docker on Debian
install_docker() {
    print_header "Installing Docker on Debian"
    
    print_status "Updating package list..."
    sudo apt update
    
    print_status "Installing prerequisites..."
    sudo apt install -y apt-transport-https ca-certificates curl gnupg lsb-release software-properties-common
    
    print_status "Installing Docker and Docker Compose..."
    sudo apt install -y docker.io docker-compose
    
    if check_docker_installed; then
        print_success "Docker installed successfully"
        
        print_status "Configuring Docker service..."
        sudo systemctl start docker
        sudo systemctl enable docker
        
        print_status "Adding user to docker group..."
        sudo usermod -aG docker $USER
        
        print_warning "Group changes applied. You may need to log out and back in."
        return 0
    else
        print_error "Docker installation failed, trying official repository..."
        install_docker_official
    fi
}

# Function to install Docker from official repository
install_docker_official() {
    print_status "Installing Docker from official Docker repository..."
    
    # Remove existing Docker packages
    sudo apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # Add Docker repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    
    # Install docker-compose separately if needed
    if ! command -v docker-compose &> /dev/null; then
        sudo apt install -y docker-compose
    fi
    
    if check_docker_installed; then
        print_success "Docker installed from official repository"
        sudo systemctl start docker
        sudo systemctl enable docker
        sudo usermod -aG docker $USER
        return 0
    else
        print_fail "Docker installation failed"
        return 1
    fi
}

# Function to create ChirpStack configuration files
create_config_files() {
    print_status "Creating ChirpStack configuration files..."
    
    # Create configuration directories
    mkdir -p "$CONFIG_DIR/chirpstack-application-server"
    mkdir -p "$CONFIG_DIR/chirpstack-network-server"
    mkdir -p "$CONFIG_DIR/chirpstack-gateway-bridge"
    mkdir -p "$CONFIG_DIR/postgresql/initdb"
    
    # Create application server configuration
    cat > "$CONFIG_DIR/chirpstack-application-server/chirpstack-application-server.toml" << 'EOF'
[postgresql]
dsn="postgres://chirpstack_as:chirpstack_as@postgresql/chirpstack_as?sslmode=disable"

[redis]
url="redis://redis:6379"

[application_server]
  [application_server.external_api]
  bind="0.0.0.0:8080"
  tls_cert=""
  tls_key=""

  [application_server.api]
  bind="0.0.0.0:8001"

[join_server]
default="http://chirpstack-application-server:8003"
EOF

    # Create network server configuration
    cat > "$CONFIG_DIR/chirpstack-network-server/chirpstack-network-server.toml" << 'EOF'
[postgresql]
dsn="postgres://chirpstack_ns:chirpstack_ns@postgresql/chirpstack_ns?sslmode=disable"

[redis]
url="redis://redis:6379"

[network_server]
net_id="000000"

  [network_server.band]
  name="EU868"

  [network_server.api]
  bind="0.0.0.0:8000"

  [network_server.gateway]
    [network_server.gateway.backend]
      [network_server.gateway.backend.mqtt]
      server="tcp://mosquitto:1883"
EOF

    # Create gateway bridge configuration
    cat > "$CONFIG_DIR/chirpstack-gateway-bridge/chirpstack-gateway-bridge.toml" << 'EOF'
[backend]
type="semtech_udp"

  [backend.semtech_udp]
  udp_bind="0.0.0.0:1700"

[integration]
marshaler="protobuf"

  [integration.mqtt]
  auth_type="generic"
  server="tcp://mosquitto:1883"
  username=""
  password=""
EOF

    # Create PostgreSQL initialization script
    cat > "$CONFIG_DIR/postgresql/initdb/001-init-chirpstack_ns.sh" << 'EOF'
#!/bin/bash
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    create role chirpstack_ns with login password 'chirpstack_ns';
    create database chirpstack_ns with owner chirpstack_ns;
EOSQL
EOF

    cat > "$CONFIG_DIR/postgresql/initdb/002-init-chirpstack_as.sh" << 'EOF'
#!/bin/bash
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    create role chirpstack_as with login password 'chirpstack_as';
    create database chirpstack_as with owner chirpstack_as;
EOSQL
EOF

    # Make init scripts executable
    chmod +x "$CONFIG_DIR/postgresql/initdb/"*.sh
    
    print_success "Configuration files created"
}

# Function to create ChirpStack docker-compose.yml
create_chirpstack() {
    print_header "Creating ChirpStack Configuration"
    
    # Ensure Docker is working first
    if ! manage_docker; then
        print_error "Docker issues must be resolved before creating ChirpStack"
        return 1
    fi
    
    # Create directory
    mkdir -p "$CHIRPSTACK_DIR"
    cd "$CHIRPSTACK_DIR"
    
    # Create configuration files
    create_config_files
    
    print_status "Creating docker-compose.yml file..."
    
    cat > "$DOCKER_COMPOSE_FILE" << 'EOF'
version: "3.8"

services:
  mosquitto:
    image: eclipse-mosquitto:2
    restart: unless-stopped
    ports:
      - "1883:1883"
    volumes:
      - mosquittodata:/mosquitto/data
      - mosquittologs:/mosquitto/log

  postgresql:
    image: postgres:14-alpine
    restart: unless-stopped
    environment:
      - POSTGRES_PASSWORD=root
      - POSTGRES_USER=root
      - POSTGRES_DB=chirpstack
    volumes:
      - postgresqldata:/var/lib/postgresql/data
      - ./configuration/postgresql/initdb:/docker-entrypoint-initdb.d
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U root -d chirpstack"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    restart: unless-stopped
    volumes:
      - redisdata:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 3s
      retries: 5

  chirpstack-network-server:
    image: chirpstack/chirpstack-network-server:3
    restart: unless-stopped
    depends_on:
      postgresql:
        condition: service_healthy
      redis:
        condition: service_healthy
      mosquitto:
        condition: service_started
    volumes:
      - ./configuration/chirpstack-network-server:/etc/chirpstack-network-server
    environment:
      - NET_ID=000000
      - BAND=EU868

  chirpstack-application-server:
    image: chirpstack/chirpstack-application-server:3
    restart: unless-stopped
    ports:
      - "8080:8080"
    depends_on:
      postgresql:
        condition: service_healthy
      redis:
        condition: service_healthy
      chirpstack-network-server:
        condition: service_started
    volumes:
      - ./configuration/chirpstack-application-server:/etc/chirpstack-application-server
    environment:
      - POSTGRESQL_DSN=postgres://chirpstack_as:chirpstack_as@postgresql/chirpstack_as?sslmode=disable
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080"]
      interval: 30s
      timeout: 10s
      retries: 3

  chirpstack-gateway-bridge:
    image: chirpstack/chirpstack-gateway-bridge:3
    restart: unless-stopped
    ports:
      - "1700:1700/udp"
    depends_on:
      - mosquitto
      - redis
    volumes:
      - ./configuration/chirpstack-gateway-bridge:/etc/chirpstack-gateway-bridge

volumes:
  postgresqldata:
  redisdata:
  mosquittodata:
  mosquittologs:

networks:
  default:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16
EOF

    print_success "ChirpStack configuration created in $CHIRPSTACK_DIR"
    print_status "Services configured with health checks and proper networking"
}

# Function to start ChirpStack
start_chirpstack() {
    print_header "Starting ChirpStack"
    
    # Ensure Docker is working
    if ! manage_docker; then
        print_error "Cannot start ChirpStack - Docker issues detected"
        return 1
    fi
    
    if [ ! -f "$DOCKER_COMPOSE_FILE" ]; then
        print_error "ChirpStack not created yet. Please run 'create' first."
        return 1
    fi
    
    cd "$CHIRPSTACK_DIR"
    print_status "Starting ChirpStack services..."
    
    # Pull latest images
    print_status "Pulling Docker images..."
    docker-compose pull
    
    # Start services
    docker-compose up -d
    
    if [ $? -eq 0 ]; then
        print_status "Services starting up..."
        
        # Wait for PostgreSQL
        wait_for_service "PostgreSQL" 5432
        
        # Wait for Redis
        wait_for_service "Redis" 6379
        
        # Wait for web interface
        wait_for_service "ChirpStack Web Interface" 8080
        
        print_success "ChirpStack started successfully!"
        echo ""
        print_status "Access Information:"
        echo "  📱 Web Interface: http://localhost:8080"
        echo "  👤 Default Login: admin / admin"
        echo "  🌐 Gateway UDP Port: 1700"
        echo "  📊 MQTT Broker: localhost:1883"
        echo ""
        print_status "Services will auto-restart on system reboot"
    else
        print_fail "Failed to start ChirpStack"
        print_status "Checking logs for errors..."
        docker-compose logs --tail=20
        return 1
    fi
}

# Function to stop ChirpStack
stop_chirpstack() {
    print_header "Stopping ChirpStack"
    
    if [ ! -f "$DOCKER_COMPOSE_FILE" ]; then
        print_error "ChirpStack not found."
        return 1
    fi
    
    cd "$CHIRPSTACK_DIR"
    print_status "Stopping ChirpStack services..."
    docker-compose down
    
    if [ $? -eq 0 ]; then
        print_success "ChirpStack stopped successfully!"
    else
        print_fail "Error stopping ChirpStack"
        return 1
    fi
}

# Enhanced status function
status_chirpstack() {
    print_header "ChirpStack System Status"
    
    # Check Docker first
    echo -e "${BLUE}Docker Status:${NC}"
    if check_docker_installed; then
        echo -e "  ✓ Docker: $(docker --version | cut -d' ' -f3 | cut -d',' -f1)"
        echo -e "  ✓ Docker Compose: $(docker-compose --version | cut -d' ' -f4 | cut -d',' -f1)"
    else
        echo -e "  ✗ Docker: Not installed"
        return 1
    fi
    
    if check_docker_running; then
        echo -e "  ✓ Docker Service: Running"
    else
        echo -e "  ✗ Docker Service: Stopped"
        print_warning "Run '$0 start' to fix Docker issues"
        return 1
    fi
    
    if test_docker_daemon; then
        echo -e "  ✓ Docker Daemon: Accessible"
    else
        echo -e "  ✗ Docker Daemon: Cannot connect"
        print_warning "You may need to run: newgrp docker"
        return 1
    fi
    
    echo ""
    echo -e "${BLUE}ChirpStack Status:${NC}"
    
    if [ ! -f "$DOCKER_COMPOSE_FILE" ]; then
        echo -e "  ✗ ChirpStack: Not created"
        print_warning "Run '$0 create' first"
        return 1
    fi
    
    cd "$CHIRPSTACK_DIR" 2>/dev/null || return 1
    
    # Show container status
    echo ""
    docker-compose ps
    
    echo ""
    echo -e "${BLUE}Service Health:${NC}"
    
    # Check each service
    if curl -s http://localhost:8080 > /dev/null 2>&1; then
        echo -e "  ✓ Web Interface: http://localhost:8080 - ${GREEN}Healthy${NC}"
    else
        echo -e "  ✗ Web Interface: http://localhost:8080 - ${RED}Not responding${NC}"
    fi
    
    if nc -z localhost 1700 2>/dev/null; then
        echo -e "  ✓ Gateway Bridge: UDP 1700 - ${GREEN}Listening${NC}"
    else
        echo -e "  ✗ Gateway Bridge: UDP 1700 - ${RED}Not listening${NC}"
    fi
    
    if nc -z localhost 1883 2>/dev/null; then
        echo -e "  ✓ MQTT Broker: TCP 1883 - ${GREEN}Listening${NC}"
    else
        echo -e "  ✗ MQTT Broker: TCP 1883 - ${RED}Not listening${NC}"
    fi
    
    echo ""
    print_status "Quick Access:"
    echo "  🌐 Web Interface: http://localhost:8080"
    echo "  👤 Login: admin / admin"
}

# Function to view logs
view_logs() {
    print_header "ChirpStack Logs"
    
    if ! manage_docker; then
        return 1
    fi
    
    if [ ! -f "$DOCKER_COMPOSE_FILE" ]; then
        print_error "ChirpStack not created yet."
        return 1
    fi
    
    cd "$CHIRPSTACK_DIR"
    
    # Show recent logs for all services
    if [ "$2" = "follow" ] || [ "$2" = "-f" ]; then
        print_status "Following logs (Press Ctrl+C to exit)..."
        docker-compose logs -f
    else
        print_status "Recent logs (last 50 lines per service):"
        docker-compose logs --tail=50
    fi
}

# Enhanced web interface function
open_web() {
    print_header "Opening ChirpStack Web Interface"
    
    # Ensure Docker is working
    if ! manage_docker; then
        return 1
    fi
    
    # Check if ChirpStack is running
    cd "$CHIRPSTACK_DIR" 2>/dev/null
    if ! docker-compose ps 2>/dev/null | grep -q "Up"; then
        print_warning "ChirpStack doesn't appear to be running. Starting it now..."
        start_chirpstack
        if [ $? -ne 0 ]; then
            print_error "Failed to start ChirpStack"
            return 1
        fi
    fi
    
    # Test if web server is responding
    print_status "Testing web server connectivity..."
    local attempts=0
    local max_attempts=10
    
    while [ $attempts -lt $max_attempts ]; do
        if curl -s http://localhost:8080 > /dev/null 2>&1; then
            print_success "Web server is responding"
            break
        fi
        print_status "Waiting for web server... ($((attempts + 1))/$max_attempts)"
        sleep 3
        attempts=$((attempts + 1))
    done
    
    if [ $attempts -eq $max_attempts ]; then
        print_error "Web server is not responding"
        print_status "Check logs with: $0 logs"
        return 1
    fi
    
    print_status "Opening http://localhost:8080 in browser..."
    
    # Try different browsers
    local browser_opened=false
    
    for browser in firefox firefox-esr chromium google-chrome; do
        if command -v "$browser" &> /dev/null; then
            $browser http://localhost:8080 >/dev/null 2>&1 &
            print_success "Opened in $browser"
            browser_opened=true
            break
        fi
    done
    
    if ! $browser_opened; then
        if command -v xdg-open &> /dev/null; then
            xdg-open http://localhost:8080 >/dev/null 2>&1 &
            print_success "Opened with default browser"
            browser_opened=true
        fi
    fi
    
    if ! $browser_opened; then
        print_warning "No browser found. Install Firefox:"
        print_status "sudo apt install firefox-esr"
        print_warning "Or manually open: http://localhost:8080"
    fi
    
    echo ""
    echo -e "${CYAN}ChirpStack Login Information:${NC}"
    echo "  🌐 URL: http://localhost:8080"
    echo "  👤 Username: admin"
    echo "  🔑 Password: admin"
    echo ""
    echo -e "${CYAN}First-time setup:${NC}"
    echo "  1. Login with admin/admin"
    echo "  2. Go to 'Network Servers' and add: localhost:8000"
    echo "  3. Create an application"
    echo "  4. Add devices to your application"
}

# Function to get system IP
get_ip() {
    print_header "Network Information"
    
    echo -e "${BLUE}Local IP Addresses:${NC}"
    ip addr show | grep 'inet ' | grep -v '127.0.0.1' | awk '{print "  📍 " $2}' | cut -d'/' -f1
    
    echo ""
    echo -e "${BLUE}ChirpStack Service Ports:${NC}"
    echo "  🌐 Web Interface: 8080"
    echo "  📡 LoRaWAN Gateway: 1700 (UDP)"
    echo "  📊 MQTT Broker: 1883"
    echo "  🔗 Network Server API: 8000"
    echo "  📱 Application Server API: 8001"
    
    echo ""
    echo -e "${CYAN}Gateway Configuration:${NC}"
    echo "Use one of the IP addresses above as your gateway's server address"
    echo "Set gateway to forward packets to: <IP>:1700"
}

# Function to restart ChirpStack
restart_chirpstack() {
    print_header "Restarting ChirpStack"
    stop_chirpstack
    sleep 5
    start_chirpstack
}

# Function to clean up and reset
cleanup_chirpstack() {
    print_header "Cleaning Up ChirpStack"
    
    if [ -f "$DOCKER_COMPOSE_FILE" ]; then
        cd "$CHIRPSTACK_DIR"
        print_status "Stopping and removing containers..."
        docker-compose down -v --remove-orphans
        
        print_status "Removing unused Docker images..."
        docker image prune -f
        
        print_status "Removing unused Docker volumes..."
        docker volume prune -f
    fi
    
    print_success "Cleanup completed"
}

# Function to uninstall ChirpStack
uninstall_chirpstack() {
    print_header "Uninstalling ChirpStack"
    
    echo -e "${RED}WARNING: This will remove all ChirpStack data and configurations!${NC}"
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " -r
    
    if [[ $REPLY == "yes" ]]; then
        if [ -d "$CHIRPSTACK_DIR" ]; then
            cd "$CHIRPSTACK_DIR"
            print_status "Stopping and removing all containers and data..."
            docker-compose down -v --remove-orphans
            
            print_status "Removing ChirpStack images..."
            docker rmi $(docker images | grep chirpstack | awk '{print $3}') 2>/dev/null || true
            
            cd "$HOME"
            print_status "Removing ChirpStack directory..."
            rm -rf "$CHIRPSTACK_DIR"
        fi
        
        print_success "ChirpStack uninstalled successfully!"
    else
        print_status "Uninstall cancelled."
    fi
}

# Function to update ChirpStack
update_chirpstack() {
    print_header "Updating ChirpStack"
    
    if [ ! -f "$DOCKER_COMPOSE_FILE" ]; then
        print_error "ChirpStack not found. Please create it first."
        return 1
    fi
    
    cd "$CHIRPSTACK_DIR"
    
    print_status "Pulling latest Docker images..."
    docker-compose pull
    
    print_status "Restarting services with new images..."
    docker-compose up -d
    
    print_success "ChirpStack updated successfully!"
    
    # Check if services are healthy
    sleep 10
    if curl -s http://localhost:8080 > /dev/null 2>&1; then
        print_success "Update completed successfully!"
    else
        print_warning "Services may still be starting up..."
        print_status "Check status with: $0 status"
    fi
}

# Function to backup ChirpStack data
backup_chirpstack() {
    print_header "Backing Up ChirpStack Data"
    
    if [ ! -f "$DOCKER_COMPOSE_FILE" ]; then
        print_error "ChirpStack not found."
        return 1
    fi
    
    local backup_dir="$HOME/chirpstack-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"
    
    cd "$CHIRPSTACK_DIR"
    
    print_status "Creating database backup..."
    docker-compose exec -T postgresql pg_dumpall -U root > "$backup_dir/database.sql"
    
    print_status "Backing up configuration files..."
    cp -r configuration "$backup_dir/"
    cp docker-compose.yml "$backup_dir/"
    
    print_success "Backup created at: $backup_dir"
}

# Function to show help
show_help() {
    print_header "ChirpStack Manager Help"
    echo -e "${CYAN}Usage:${NC} $0 [COMMAND]"
    echo ""
    echo -e "${BLUE}Setup Commands:${NC}"
    echo "  install         Install Docker and dependencies"
    echo "  create          Create ChirpStack configuration"
    echo "  start           Start ChirpStack services"
    echo ""
    echo -e "${BLUE}Management Commands:${NC}"
    echo "  stop            Stop ChirpStack services"
    echo "  restart         Restart ChirpStack services"
    echo "  status          Show detailed system status"
    echo "  logs [follow]   View ChirpStack logs (-f for follow mode)"
    echo "  web             Open web interface in browser"
    echo ""
    echo -e "${BLUE}Maintenance Commands:${NC}"
    echo "  update          Update ChirpStack to latest version"
    echo "  cleanup         Clean up unused Docker resources"
    echo "  backup          Backup ChirpStack data"
    echo "  uninstall       Remove ChirpStack completely"
    echo ""
    echo -e "${BLUE}Information Commands:${NC}"
    echo "  ip              Show network information"
    echo "  help            Show this help message"
    echo ""
    echo -e "${CYAN}Quick Start (first time):${NC}"
    echo "  1. $0 install    # Install Docker"
    echo "  2. $0 create     # Create configuration"
    echo "  3. $0 start      # Start services"
    echo "  4. $0 web        # Open web interface"
    echo ""
    echo -e "${CYAN}Daily Usage:${NC}"
    echo "  $0 web           # Open web interface (auto-starts if needed)"
    echo "  $0 status        # Check system health"
    echo "  $0 logs          # View recent logs"
    echo ""
    echo -e "${BLUE}Features:${NC}"
    echo "  • Automatic Docker installation and configuration"
    echo "  • Health checks and service monitoring" 
    echo "  • Comprehensive error handling"
    echo "  • Complete LoRaWAN stack with MQTT broker"
    echo "  • Auto-restart services on reboot"
    echo "  • Easy backup and update procedures"
}

# Main script logic
case "$1" in
    install)
        manage_docker
        ;;
    create)
        create_chirpstack
        ;;
    start)
        start_chirpstack
        ;;
    stop)
        stop_chirpstack
        ;;
    restart)
        restart_chirpstack
        ;;
    status)
        status_chirpstack
        ;;
    logs)
        view_logs "$@"
        ;;
    web)
        open_web
        ;;
    ip)
        get_ip
        ;;
    update)
        update_chirpstack
        ;;
    cleanup)
        cleanup_chirpstack
        ;;
    backup)
        backup_chirpstack
        ;;
    uninstall)
        uninstall_chirpstack
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