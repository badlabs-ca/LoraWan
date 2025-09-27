#!/bin/bash
# Script to copy updated files to gateway

echo "Copying updated setup script to gateway..."

# Replace with your gateway IP
GATEWAY_IP="your_gateway_ip"

scp setup_raw_lora.sh debian@$GATEWAY_IP:/home/debian/sensorite/LoraWan/
echo "Updated setup script copied to gateway"