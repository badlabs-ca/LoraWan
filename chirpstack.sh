#!/bin/bash

# ChirpStack Manager Script for Debian (Enhanced Version)
# This script handles Docker issues automatically and installs Firefox if needed

CHIRPSTACK_DIR="$HOME/chirpstack"
DOCKER_COMPOSE_FILE="$CHIRPSTACK_DIR/docker-compose.yml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

# Enhanced Docker management function
manage_docker() {
    print_header "Docker System Check"
    
    # Check if Docker is installed
    if ! check_docker_installed; then
        print_warning "Docker is not installed. Installing now..."
        install_docker
        return $?
    else
        print_status "✓ Docker is installed ($(docker --version))"
    fi
    
    # Check if Docker service is running
    if ! check_docker_running; then
        print_warning "Docker service is not running. Starting now..."
        sudo systemctl start docker
        if check_docker_running; then
            print_status "✓ Docker service started successfully"
        else
            print_error "✗ Failed to start Docker service"
            print_error "Try running: sudo systemctl status docker"
            return 1
        fi
    else
        print_status "✓ Docker service is running"
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
        print_warning "Group added. You may need to log out and back in for changes to take effect."
        print_status "Applying group changes for current session..."
        newgrp docker <<EOF
        echo "Docker group applied!"
EOF
    else
        print_status "✓ User has Docker permissions"
    fi
    
    # Test Docker daemon connection
    sleep 2  # Give Docker a moment to fully start
    if ! test_docker_daemon; then
        print_warning "Testing Docker daemon connection..."
        # Try with newgrp docker
        if ! docker ps &> /dev/null; then
            print_error "✗ Cannot connect to Docker daemon"
            print_error "You may need to log out and back in, or run: newgrp docker"
            return 1
        fi
    fi
    
    print_status "✓ Docker is fully operational"
    return 0
}

# Function to check and install Firefox
check_and_install_firefox() {
    print_header "Browser Check"
    
    # Check if any browser is available
    local browsers=("firefox" "firefox-esr" "chromium" "google-chrome" "xdg-open")
    local browser_found=false
    
    for browser in "${browsers[@]}"; do
        if command -v "$browser" &> /dev/null; then
            print_status "✓ Browser found: $browser"
            browser_found=true
            break
        fi
    done
    
    if ! $browser_found; then
        print_warning "No suitable browser found. Installing Firefox..."
        
        # Check if we should install from Mozilla repository for newer version
        read -p "Install Firefox from Mozilla (newer) or Debian repository (stable)? (m/d): " choice
        
        if [[ $choice == "m" || $choice == "M" ]]; then
            install_firefox_mozilla
        else
            install_firefox_debian
        fi
    fi
}

# Function to install Firefox from Debian repository
install_firefox_debian() {
    print_status "Installing Firefox from Debian repository..."
    sudo apt update
    sudo apt install -y firefox-esr
    
    if command -v firefox-esr &> /dev/null; then
        print_status "✓ Firefox ESR installed successfully"
    else
        print_error "✗ Firefox installation failed"
        return 1
    fi
}

# Function to install Firefox from Mozilla repository
install_firefox_mozilla() {
    print_status "Installing Firefox from Mozilla repository..."
    
    # Install prerequisites
    sudo apt update
    sudo apt install -y apt-transport-https ca-certificates curl gnupg lsb-release
    
    # Add Mozilla's GPG key
    wget -q https://packages.mozilla.org/apt/repo-signing-key.gpg -O- | sudo apt-key add -
    
    # Add Mozilla repository
    echo "deb https://packages.mozilla.org/apt mozilla main" | sudo tee /etc/apt/sources.list.d/mozilla.list > /dev/null
    
    # Set package priority
    echo 'Package: * Pin: origin packages.mozilla.org Pin-Priority: 1000' | sudo tee /etc/apt/preferences.d/mozilla > /dev/null
    
    # Install Firefox
    sudo apt update
    sudo apt install -y firefox
    
    if command -v firefox &> /dev/null; then
        print_status "✓ Firefox installed successfully from Mozilla"
    else
        print_error "✗ Firefox installation failed, trying Debian version..."
        install_firefox_debian
    fi
}

# Function to install Docker on Debian
install_docker() {
    print_header "Installing Docker on Debian"
    
    print_status "Updating package list..."
    sudo apt update
    
    print_status "Installing Docker and Docker Compose..."
    sudo apt install -y docker.io docker-compose
    
    if check_docker_installed; then
        print_status "✓ Docker installed successfully"
        
        print_status "Starting Docker service..."
        sudo systemctl start docker
        sudo systemctl enable docker
        
        print_status "Adding user to docker group..."
        sudo usermod -aG docker $USER
        
        print_warning "Group changes applied. You may need to log out and back in."
        return 0
    else
        print_error "✗ Docker installation failed"
        print_status "Trying alternative installation method..."
        install_docker_official
    fi
}

# Function to install Docker from official repository
install_docker_official() {
    print_status "Installing Docker from official repository..."
    
    # Remove any existing Docker
    sudo apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Install prerequisites
    sudo apt install -y apt-transport-https ca-certificates curl gnupg lsb-release
    
    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # Add Docker repository
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    
    # Install docker-compose separately if needed
    if ! command -v docker-compose &> /dev/null; then
        sudo apt install -y docker-compose
    fi
    
    if check_docker_installed; then
        print_status "✓ Docker installed successfully from official repository"
        sudo systemctl start docker
        sudo systemctl enable docker
        sudo usermod -aG docker $USER
    else
        print_error "✗ Docker installation failed"
        return 1
    fi
}

# Function to create ChirpStack directory and docker-compose.yml
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
    
    print_status "Creating docker-compose.yml file..."
    
    cat > "$DOCKER_COMPOSE_FILE" << 'EOF'
version: "3"

services:
  chirpstack-network-server:
    image: chirpstack/chirpstack-network-server:3
    restart: unless-stopped
    depends_on:
      - postgresql
      - redis
    environment:
      - NET_ID=000000
      - BAND=EU868

  chirpstack-application-server:
    image: chirpstack/chirpstack-application-server:3
    restart: unless-stopped
    ports:
      - 8080:8080
    depends_on:
      - chirpstack-network-server
    environment:
      - POSTGRESQL_DSN=postgres://chirpstack_as:chirpstack_as@postgresql/chirpstack_as?sslmode=disable

  chirpstack-gateway-bridge:
    image: chirpstack/chirpstack-gateway-bridge:3
    restart: unless-stopped
    ports:
      - 1700:1700/udp
    depends_on:
      - redis

  postgresql:
    image: postgres:12-alpine
    restart: unless-stopped
    environment:
      - POSTGRES_PASSWORD=root
      - POSTGRES_USER=root
      - POSTGRES_DB=chirpstack_as
    volumes:
      - postgresqldata:/var/lib/postgresql/data

  redis:
    image: redis:6-alpine
    restart: unless-stopped
    volumes:
      - redisdata:/data

volumes:
  postgresqldata:
  redisdata:
EOF

    print_status "✓ ChirpStack configuration created in $CHIRPSTACK_DIR"
    print_status "All services will auto-restart unless manually stopped"
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
    
    # Test Docker daemon before proceeding
    if ! test_docker_daemon; then
        print_error "Cannot connect to Docker daemon"
        print_error "Try running: newgrp docker"
        return 1
    fi
    
    docker-compose up -d
    
    if [ $? -eq 0 ]; then
        print_status "Waiting for services to start..."
        sleep 15
        
        print_status "✓ ChirpStack started successfully!"
        print_status "Web interface: http://localhost:8080"
        print_status "Default login: admin / admin"
        print_status "Services will auto-restart on system reboot"
    else
        print_error "✗ Failed to start ChirpStack"
        print_status "Checking logs..."
        docker-compose logs --tail=10
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
        print_status "✓ ChirpStack stopped successfully!"
    else
        print_error "✗ Error stopping ChirpStack"
        return 1
    fi
}

# Enhanced status function
status_chirpstack() {
    print_header "ChirpStack System Status"
    
    # Check Docker first
    echo -e "${BLUE}Docker Status:${NC}"
    if check_docker_installed; then
        echo -e "  ✓ Docker installed: $(docker --version)"
    else
        echo -e "  ✗ Docker not installed"
        return 1
    fi
    
    if check_docker_running; then
        echo -e "  ✓ Docker service: Running"
    else
        echo -e "  ✗ Docker service: Stopped"
        print_warning "Run './chirpstack.sh start' to fix Docker issues"
        return 1
    fi
    
    if test_docker_daemon; then
        echo -e "  ✓ Docker daemon: Accessible"
    else
        echo -e "  ✗ Docker daemon: Cannot connect"
        print_warning "You may need to run: newgrp docker"
        return 1
    fi
    
    echo ""
    echo -e "${BLUE}ChirpStack Status:${NC}"
    
    if [ ! -f "$DOCKER_COMPOSE_FILE" ]; then
        echo -e "  ✗ ChirpStack not created yet"
        print_warning "Run './chirpstack.sh create' first"
        return 1
    fi
    
    cd "$CHIRPSTACK_DIR" 2>/dev/null || return 1
    docker-compose ps
    
    echo ""
    print_status "Service URLs:"
    echo "  Web Interface: http://localhost:8080"
    echo "  Gateway Bridge: UDP port 1700"
    echo "  Default Login: admin / admin"
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
    print_status "Showing recent logs (Press Ctrl+C to exit)..."
    docker-compose logs -f
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
    
    # Wait a moment for web server to be ready
    print_status "Waiting for web server to be ready..."
    sleep 5
    
    # Test if web server is responding
    if curl -s http://localhost:8080 > /dev/null; then
        print_status "✓ Web server is responding"
    else
        print_warning "Web server may still be starting up..."
    fi
    
    print_status "Opening http://localhost:8080 in your browser..."
    
    # Try different browser commands
    if command -v firefox &> /dev/null; then
        firefox http://localhost:8080 &
        print_status "✓ Opened in Firefox"
    elif command -v firefox-esr &> /dev/null; then
        firefox-esr http://localhost:8080 &
        print_status "✓ Opened in Firefox ESR"
    elif command -v xdg-open &> /dev/null; then
        xdg-open http://localhost:8080
        print_status "✓ Opened with default browser"
    elif command -v chromium &> /dev/null; then
        chromium http://localhost:8080 &
        print_status "✓ Opened in Chromium"
    elif command -v google-chrome &> /dev/null; then
        google-chrome http://localhost:8080 &
        print_status "✓ Opened in Google Chrome"
    else
        print_warning "No browser found. Please install Firefox:"
        print_status "Run: ./chirpstack.sh install-browser"
        print_warning "Or manually open: http://localhost:8080"
    fi
    
    echo ""
    print_status "ChirpStack Login Credentials:"
    echo "  Username: admin"
    echo "  Password: admin"
}

# Function to get system IP
get_ip() {
    print_header "System IP Address"
    
    echo "Local IP addresses for RAK gateway configuration:"
    ip addr show | grep 'inet ' | grep -v '127.0.0.1' | awk '{print "  " $2}' | cut -d'/' -f1
    
    echo
    print_status "Use one of these IP addresses in your RAK gateway configuration"
    print_status "Set server_address to one of the above IPs in your gateway config"
}

# Function to restart ChirpStack
restart_chirpstack() {
    print_header "Restarting ChirpStack"
    stop_chirpstack
    sleep 5
    start_chirpstack
}

# Function to uninstall ChirpStack
uninstall_chirpstack() {
    print_header "Uninstalling ChirpStack"
    
    read -p "Are you sure you want to remove ChirpStack and all data? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if [ -d "$CHIRPSTACK_DIR" ]; then
            cd "$CHIRPSTACK_DIR"
            print_status "Stopping and removing containers..."
            docker-compose down -v 2>/dev/null || true
            cd ..
            print_status "Removing ChirpStack directory..."
            rm -rf "$CHIRPSTACK_DIR"
        fi
        print_status "✓ ChirpStack uninstalled successfully!"
    else
        print_status "Uninstall cancelled."
    fi
}

# Function to install browser only
install_browser() {
    check_and_install_firefox
}

# Function to stop Docker service
stop_docker() {
    print_header "Stopping Docker Service"
    
    # First stop ChirpStack if running
    if [ -f "$DOCKER_COMPOSE_FILE" ]; then
        print_status "Stopping ChirpStack services first..."
        cd "$CHIRPSTACK_DIR"
        docker-compose down 2>/dev/null || true
    fi
    
    # Stop all running containers
    print_status "Stopping all Docker containers..."
    docker stop $(docker ps -q) 2>/dev/null || true
    
    # Stop Docker service
    print_status "Stopping Docker service..."
    sudo systemctl stop docker
    
    if ! check_docker_running; then
        print_status "✓ Docker service stopped successfully"
        print_warning "Note: ChirpStack and all containers are now stopped"
        print_status "To start again: ./chirpstack.sh start"
    else
        print_error "✗ Failed to stop Docker service"
        return 1
    fi
}

# Function to start Docker service only
start_docker() {
    print_header "Starting Docker Service"
    
    if check_docker_running; then
        print_status "✓ Docker service is already running"
        return 0
    fi
    
    print_status "Starting Docker service..."
    sudo systemctl start docker
    
    if check_docker_running; then
        print_status "✓ Docker service started successfully"
        print_status "ChirpStack containers will auto-start if configured"
    else
        print_error "✗ Failed to start Docker service"
        return 1
    fi
}

# Function to show help
show_help() {
    print_header "ChirpStack Manager Help"
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  install         - Install Docker and Firefox (if needed)"
    echo "  create          - Create ChirpStack configuration"
    echo "  start           - Start ChirpStack services"
    echo "  stop            - Stop ChirpStack services"
    echo "  restart         - Restart ChirpStack services"
    echo "  status          - Show detailed system status"
    echo "  logs            - View ChirpStack logs"
    echo "  web             - Open web interface in browser"
    echo "  ip              - Show system IP addresses"
    echo "  install-browser - Install Firefox browser only"
    echo "  start-docker    - Start Docker service only"
    echo "  stop-docker     - Stop Docker service (stops all containers)"
    echo "  uninstall       - Remove ChirpStack completely"
    echo "  help            - Show this help message"
    echo ""
    echo "Quick start (first time):"
    echo "  1. $0 install    (installs Docker and Firefox)"
    echo "  2. $0 create     (creates ChirpStack config)"
    echo "  3. $0 start      (starts all services)"
    echo "  4. $0 web        (opens web interface)"
    echo ""
    echo "Daily use:"
    echo "  $0 web           (services auto-start if needed)"
    echo ""
    echo "Docker management:"
    echo "  $0 start-docker  (start Docker service only)"
    echo "  $0 stop-docker   (stop Docker service and all containers)"
    echo ""
    echo "Features:"
    echo "  • Automatic Docker service management"
    echo "  • Auto-restart services on reboot"
    echo "  • Browser installation if needed"
    echo "  • Comprehensive error handling"
    echo "  • Smart dependency checking"
}

# Main script logic
case "$1" in
    install)
        manage_docker
        check_and_install_firefox
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
        view_logs
        ;;
    web)
        open_web
        ;;
    ip)
        get_ip
        ;;
    install-browser)
        install_browser
        ;;
    start-docker)
        start_docker
        ;;
    stop-docker)
        stop_docker
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