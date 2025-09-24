#!/usr/bin/env python3
"""
RAK Gateway Advanced Signal Monitor
Real-time LoRa signal analysis with device-specific decryption
Enhanced version based on proven decrypt_lora.py
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

# Default device configuration - UPDATE THESE TO MATCH YOUR DEVICE
DEFAULT_CONFIG = {
    "dev_eui": "0102030405060708",
    "app_eui": "1112131415161718",
    "app_key": "21222324252627282A2B2C2D2E2F30",
    "device_name": "RAK Device"
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
        """Check if packet is from configured device (enhanced from decrypt_lora.py)"""
        if not packet_info or not packet_info['data']:
            return False

        try:
            # Decode and check for our device signature
            encrypted_bytes = base64.b64decode(packet_info['data'])
            dev_eui_bytes = binascii.unhexlify(self.config['dev_eui'])

            # Check if our device EUI appears in the packet
            if dev_eui_bytes in encrypted_bytes:
                return True

            # Check if any part of our device EUI is in the packet
            return dev_eui_bytes[:4] in encrypted_bytes or dev_eui_bytes[4:] in encrypted_bytes
        except:
            return False

    def decrypt_payload(self, data_b64):
        """Decrypt LoRaWAN payload using device keys (enhanced from decrypt_lora.py)"""
        if not CRYPTO_AVAILABLE:
            return {"error": "Crypto library not available", "success": False}

        try:
            encrypted_bytes = base64.b64decode(data_b64)
            key_bytes = binascii.unhexlify(self.config['app_key'])

            # Simple AES decryption (ECB mode for testing)
            cipher = AES.new(key_bytes, AES.MODE_ECB)

            # Pad data to 16 bytes if needed
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

    def monitor(self, show_all=False):
        """Main monitoring loop"""
        print("🎯 RAK Gateway Advanced Signal Monitor")
        print(f"📱 Device: {self.config['device_name']}")
        print(f"🆔 EUI: {self.config['dev_eui']}")
        if show_all:
            print("📡 Monitoring ALL LoRa signals...")
        else:
            print("📡 Monitoring for MY device only...")
        print("📡 Press Ctrl+C to stop")
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
                            self.print_packet_summary(packet_info, True)
                        elif show_all:
                            self.print_packet_summary(packet_info, False)

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
        elif sys.argv[1] == "all":
            # Monitor all devices
            config = load_config()
            monitor = LoRaSignalMonitor(config)
            monitor.monitor(show_all=True)
            return

    # Default: Monitor only my device
    config = load_config()
    monitor = LoRaSignalMonitor(config)
    monitor.monitor()

if __name__ == "__main__":
    main()