#!/bin/bash
# Start Sensorite V4 LoRaWAN capture

echo "🎯 Starting Sensorite V4 LoRaWAN Capture"
echo "========================================="

# Find script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Find packet forwarder
PF_PATH=""
for path in ~/sx1302_hal*/packet_forwarder ~/rak_gateway_setup/sx1302_hal*/packet_forwarder ~/sensorite/LoraWan/sx1302_hal/packet_forwarder /opt/*/packet_forwarder; do
    if [[ -f "$path/lora_pkt_fwd" ]]; then
        PF_PATH="$path"
        break
    fi
done

if [[ -z "$PF_PATH" ]]; then
    echo "❌ Packet forwarder not found!"
    exit 1
fi

echo "📡 Using packet forwarder: $PF_PATH"
echo "🎯 Monitoring for Sensorite V4 LoRaWAN packets..."
echo "📱 Make sure your V4 device is powered on and moving"
echo ""

cd "$PF_PATH"
sudo ./lora_pkt_fwd | python3 "$SCRIPT_DIR/v4_lorawan_monitor.py"