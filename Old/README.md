# RAK WisGate Developer Base - Unified Manager

A cross-platform intelligent setup and management tool for RAK LoRaWAN gateways that automatically detects your environment and handles everything intelligently.

## Overview

This unified manager simplifies the process of setting up and managing RAK WisGate devices across different operating systems and environments. It provides automatic environment detection, intelligent USB passthrough setup, and streamlined installation procedures.

## Supported Platforms

- **Linux** (Native, VM, WSL)
- **Windows** (with WSL2 support)
- **macOS** (Docker and VM solutions)

## Supported Devices

- **RAK7271** (with RAK2287 concentrator)
- **RAK7371** (with RAK5146 concentrator)

## Supported Regions

- EU868 (Europe)
- US915 (North America)
- AS923 (Asia-Pacific)
- AU915 (Australia)

## Quick Start

1. **Download and run the installer:**
   ```bash
   curl -O https://raw.githubusercontent.com/your-repo/install.sh
   chmod +x install.sh
   ./install.sh
   ```

2. **Follow the interactive menu** - the script will:
   - Auto-detect your operating system and environment
   - Detect connected RAK devices
   - Set up USB passthrough if needed
   - Install and configure the packet forwarder
   - Guide you through region selection

## Features

### Automatic Detection
- **Environment Detection**: Automatically identifies Linux native, WSL, VM, Windows, or macOS
- **Device Detection**: Scans for connected RAK devices using multiple methods
- **Installation Status**: Checks for existing installations and configurations

### Cross-Platform USB Support
- **Windows + WSL**: Automated usbipd setup for USB passthrough
- **Linux VM**: Guided USB passthrough configuration
- **macOS**: Docker and VM solutions with device mapping

### Intelligent Installation
- **Adaptive Installation**: Chooses the best installation method for your environment
- **Dependency Management**: Automatically installs required packages
- **Configuration Management**: Handles region-specific configurations

### Management Features
- **Quick Operations**: Start packet forwarder, get Gateway EUI
- **Region Reconfiguration**: Easy switching between LoRaWAN regions
- **Status Monitoring**: Comprehensive system and device status
- **Troubleshooting**: Built-in diagnostic and help system

## Installation Methods by Platform

### Linux (Native)
- Direct compilation and installation
- Native USB device access
- Full feature support

### Windows + WSL2
- Automatic usbipd-win installation
- USB device binding and attachment to WSL
- Installation within WSL environment

### macOS
- Docker-based solution (recommended)
- VM support with USB passthrough
- Guided setup for different hypervisors

## Usage

### First Time Setup
Run the script and select "Auto-setup" from the menu:
```bash
./install.sh
# Select option 1: Auto-setup
```

### Operational Commands
Once installed, use the quick operations:
- **Start Packet Forwarder**: Begins LoRaWAN packet forwarding
- **Get Gateway EUI**: Retrieves the unique gateway identifier
- **Reconfigure Region**: Change LoRaWAN frequency plan

### Manual Operations
For advanced users:
- **Manual USB Setup**: Configure USB passthrough manually
- **Manual Installation**: Step-by-step software installation
- **Troubleshooting**: Access diagnostic tools and guides

## Configuration

The script maintains configuration in `~/rak_gateway_unified/rak_unified_config.conf` including:
- Detected environment details
- Device model and concentrator type
- Installation paths and device paths
- Regional configuration
- USB setup parameters

## Troubleshooting

### Common Issues

**Device Not Detected:**
- Check USB cable and device power LED
- Verify USB passthrough configuration
- Run device detection manually

**Permission Denied:**
- Add user to dialout group: `sudo usermod -a -G dialout $USER`
- Log out and back in to apply changes

**Compilation Errors:**
- Install build dependencies: `sudo apt install build-essential`
- Verify device model selection

**WSL USB Issues:**
- Install usbipd-win: `winget install usbipd`
- Run PowerShell as Administrator for binding
- Check device status: `usbipd list`

### Debug Mode
Enable verbose logging:
```bash
DEBUG_RAK=true ./install.sh
```

## File Structure

```
LoraWanSetUp/
├── install.sh          # Main unified manager script
└── README.md           # This documentation
```

## Requirements

### Linux
- Ubuntu 18.04+ or compatible distribution
- sudo access
- USB access permissions

### Windows
- Windows 10/11 with WSL2
- PowerShell with Administrator privileges
- usbipd-win (auto-installed)

### macOS
- macOS 10.15+
- Docker Desktop (for Docker method)
- VM software with USB support (for VM method)

## Version Information

- **Script Version**: 1.0.0
- **Supported sx1302_hal**: V2.0.1
- **Compatible Hardware**: RAK7271, RAK7371

## License

This project is provided as-is for educational and development purposes.

## Support

For issues and troubleshooting:
1. Use the built-in troubleshooting menu
2. Check the log file at `~/rak_gateway_unified/rak_unified.log`
3. Run with debug mode enabled for detailed information
