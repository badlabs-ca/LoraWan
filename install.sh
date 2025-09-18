#!/bin/bash

# RAK Gateway Quick Installer
# One-liner to clone and run RAK Unified Manager
# Repository: https://github.com/badlabs-ca/LoraWan.git

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
REPO_URL="https://github.com/badlabs-ca/LoraWan.git"
INSTALL_DIR="$HOME/rak_gateway"
# Set your password here (or leave empty to prompt)
REQUIRED_PASSWORD="badlabs2024"  # Change this to your desired password

echo -e "${BLUE}🚀 RAK Gateway Quick Installer${NC}"
echo "Downloading from: $REPO_URL"
echo ""

# Password authentication
if [ -n "$REQUIRED_PASSWORD" ]; then
    echo -e "${YELLOW}🔐 Authentication required${NC}"
    read -s -p "Enter access password: " user_password
    echo ""
    
    if [ "$user_password" != "$REQUIRED_PASSWORD" ]; then
        echo -e "${RED}❌ Invalid password! Access denied.${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Authentication successful!${NC}"
    echo ""
fi

# Check if git is available
if ! command -v git >/dev/null 2>&1; then
    echo -e "${RED}❌ Git not found!${NC}"
    echo "Please install git first:"
    echo "  Ubuntu: sudo apt install git"
    echo "  macOS:  brew install git"
    echo "  Windows: Download from https://git-scm.com/"
    exit 1
fi

# Clone or update repository
if [ -d "$INSTALL_DIR" ]; then
    echo -e "${YELLOW}📂 Updating existing installation...${NC}"
    cd "$INSTALL_DIR"
    git pull
else
    echo -e "${BLUE}📥 Cloning repository...${NC}"
    git clone "$REPO_URL" "$INSTALL_DIR"
    cd "$INSTALL_DIR"
fi

# Make script executable and run
if [ -f "rak_unified.sh" ]; then
    echo -e "${GREEN}✅ Starting RAK Unified Manager...${NC}"
    echo ""
    chmod +x rak_unified.sh
    ./rak_unified.sh
else
    echo -e "${RED}❌ rak_unified.sh not found in repository!${NC}"
    echo "Available files:"
    ls -la
    exit 1
fi