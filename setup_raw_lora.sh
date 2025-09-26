#!/bin/bash
# Setup script to configure RAK7371 for raw LoRa packet capture

echo "🎯 Setting up RAK7371 for Sensorite V4 Raw LoRa Capture"
echo "=================================================="

# Step 1: Check if packet forwarder is installed
echo "[1/5] Checking packet forwarder installation..."
PF_PATH=""

# Find packet forwarder installation
for path in ~/sx1302_hal*/packet_forwarder ~/rak_gateway_setup/sx1302_hal*/packet_forwarder ~/sensorite/LoraWan/sx1302_hal/packet_forwarder /opt/*/packet_forwarder; do
    if [[ -f "$path/lora_pkt_fwd" ]]; then
        PF_PATH="$path"
        echo "✅ Found packet forwarder at: $path"
        break
    fi
done

if [[ -z "$PF_PATH" ]]; then
    echo "❌ Packet forwarder not found!"
    echo "Please install RAK gateway software first using installv1.2.sh"
    exit 1
fi

# Step 2: Backup original configuration
echo "[2/5] Backing up original configuration..."
cd "$PF_PATH"
if [[ -f "global_conf.json" ]]; then
    cp global_conf.json global_conf.json.backup
    echo "✅ Original configuration backed up"
else
    echo "⚠️  No existing configuration found"
fi

# Step 3: Install raw LoRa configuration
echo "[3/5] Installing raw LoRa configuration..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/global_conf_raw_lora.json" ]]; then
    cp "$SCRIPT_DIR/global_conf_raw_lora.json" global_conf.json
    echo "✅ Raw LoRa configuration installed"
else
    echo "❌ Raw LoRa configuration file not found!"
    exit 1
fi

# Step 4: Set device permissions
echo "[4/5] Setting up device permissions..."
for device in /dev/ttyACM* /dev/ttyUSB*; do
    if [[ -e "$device" ]]; then
        sudo chmod 666 "$device" 2>/dev/null
        echo "✅ Set permissions for $device"

        # Update config file with correct device path
        sed -i "s|/dev/ttyACM0|$device|g" global_conf.json
        echo "✅ Updated device path in configuration"
        break
    fi
done

# Step 5: Create monitoring script
echo "[5/5] Creating monitoring wrapper..."
cat > "$SCRIPT_DIR/start_v4_capture.sh" << 'EOF'
#!/bin/bash
# Start Sensorite V4 raw LoRa capture

echo "🎯 Starting Sensorite V4 Raw LoRa Capture"
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
echo "🎯 Monitoring for Sensorite V4 packets..."
echo "📱 Make sure your V4 device is powered on and moving"
echo ""

cd "$PF_PATH"
sudo ./lora_pkt_fwd | python3 "$SCRIPT_DIR/raw_lora_capture.py"
EOF

chmod +x "$SCRIPT_DIR/start_v4_capture.sh"

echo ""
echo "🎉 Setup Complete!"
echo "==================="
echo ""
echo "To start capturing Sensorite V4 data:"
echo "1. Make sure your V4 device is powered on"
echo "2. Run: ./start_v4_capture.sh"
echo "3. Move/shake your V4 device to trigger transmission"
echo ""
echo "You should see beautiful sensor data output like:"
echo "🎯 SENSORITE V4 PACKET #1"
echo "🏃 Accel [g]: X=0.051, Y=-0.116, Z=1.020"
echo "📏 ToF C: 39mm, ToF D: 62mm"
echo ""
echo "To restore original configuration:"
echo "cd '$PF_PATH' && cp global_conf.json.backup global_conf.json"