#!/bin/bash

# ChirpStack Manager Script for Debian
# This script helps you install, manage, and use ChirpStack locally

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
check_docker() {
    if ! command -v docker &> /dev/null; then
        return 1
    fi
    if ! command -v docker-compose &> /dev/null; then
        return 1
    fi
    return 0
}

# Function to install Docker on Debian
install_docker() {
    print_header "Installing Docker on Debian"
    
    print_status "Updating package list..."
    sudo apt update
    
    print_status "Installing Docker and Docker Compose..."
    sudo apt install -y docker.io docker-compose
    
    print_status "Adding user to docker group..."
    sudo usermod -aG docker $USER
    
    print_warning "You may need to log out and back in for docker group changes to take effect"
    print_status "Applying group changes for current session..."
    newgrp docker <<EOF
    echo "Docker group applied!"
EOF
    
    print_status "Docker installation completed!"
}

# Function to create ChirpStack directory and docker-compose.yml
create_chirpstack() {
    print_header "Creating ChirpStack Configuration"
    
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

    print_status "ChirpStack configuration created in $CHIRPSTACK_DIR"
}

# Function to start ChirpStack
start_chirpstack() {
    print_header "Starting ChirpStack"
    
    if [ ! -f "$DOCKER_COMPOSE_FILE" ]; then
        print_error "ChirpStack not created yet. Please run 'create' first."
        return 1
    fi
    
    cd "$CHIRPSTACK_DIR"
    print_status "Starting ChirpStack services..."
    docker-compose up -d
    
    print_status "Waiting for services to start..."
    sleep 10
    
    print_status "ChirpStack started successfully!"
    print_status "Web interface: http://localhost:8080"
    print_status "Default login: admin / admin"
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
    
    print_status "ChirpStack stopped successfully!"
}

# Function to check ChirpStack status
status_chirpstack() {
    print_header "ChirpStack Status"
    
    if [ ! -f "$DOCKER_COMPOSE_FILE" ]; then
        print_error "ChirpStack not created yet."
        return 1
    fi
    
    cd "$CHIRPSTACK_DIR"
    docker-compose ps
    
    echo
    print_status "Service URLs:"
    echo "  Web Interface: http://localhost:8080"
    echo "  Gateway Bridge: UDP port 1700"
}

# Function to view logs
view_logs() {
    print_header "ChirpStack Logs"
    
    if [ ! -f "$DOCKER_COMPOSE_FILE" ]; then
        print_error "ChirpStack not created yet."
        return 1
    fi
    
    cd "$CHIRPSTACK_DIR"
    print_status "Showing recent logs (Press Ctrl+C to exit)..."
    docker-compose logs -f
}

# Function to open web interface
open_web() {
    print_header "Opening ChirpStack Web Interface"
    
    # Check if ChirpStack is running
    cd "$CHIRPSTACK_DIR" 2>/dev/null
    if ! docker-compose ps | grep -q "Up"; then
        print_warning "ChirpStack doesn't appear to be running. Starting it now..."
        start_chirpstack
    fi
    
    print_status "Opening http://localhost:8080 in your default browser..."
    
    # Try different browser commands
    if command -v xdg-open &> /dev/null; then
        xdg-open http://localhost:8080
    elif command -v firefox &> /dev/null; then
        firefox http://localhost:8080 &
    elif command -v chromium &> /dev/null; then
        chromium http://localhost:8080 &
    elif command -v google-chrome &> /dev/null; then
        google-chrome http://localhost:8080 &
    else
        print_warning "Could not detect browser. Please open http://localhost:8080 manually"
    fi
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
            docker-compose down -v
            cd ..
            print_status "Removing ChirpStack directory..."
            rm -rf "$CHIRPSTACK_DIR"
        fi
        print_status "ChirpStack uninstalled successfully!"
    else
        print_status "Uninstall cancelled."
    fi
}

# Function to show help
show_help() {
    print_header "ChirpStack Manager Help"
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  install     - Install Docker (if not installed)"
    echo "  create      - Create ChirpStack configuration"
    echo "  start       - Start ChirpStack services"
    echo "  stop        - Stop ChirpStack services"
    echo "  restart     - Restart ChirpStack services"
    echo "  status      - Show ChirpStack status"
    echo "  logs        - View ChirpStack logs"
    echo "  web         - Open web interface in browser"
    echo "  ip          - Show system IP addresses"
    echo "  uninstall   - Remove ChirpStack completely"
    echo "  help        - Show this help message"
    echo ""
    echo "Quick start:"
    echo "  1. $0 install    (if Docker not installed)"
    echo "  2. $0 create"
    echo "  3. $0 start"
    echo "  4. $0 web"
}

# Main script logic
case "$1" in
    install)
        if check_docker; then
            print_status "Docker is already installed!"
        else
            install_docker
        fi
        ;;
    create)
        if ! check_docker; then
            print_error "Docker not installed. Please run '$0 install' first."
            exit 1
        fi
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