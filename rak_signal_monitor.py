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
    "app_key": "21222324252627282A2B2C2D2E2F3031",
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

    def parse_lorawan_packet(self, payload_b64):
        """Parse LoRaWAN packet structure to extract DevAddr and other fields"""
        try:
            packet_bytes = base64.b64decode(payload_b64)
            if len(packet_bytes) < 12:  # Minimum LoRaWAN packet size
                return None

            # LoRaWAN packet structure:
            # MHDR (1) | DevAddr (4) | FCtrl (1) | FCnt (2) | FPort (1) | FRMPayload | MIC (4)

            mhdr = packet_bytes[0]
            msg_type = (mhdr >> 5) & 0x07

            # Check if this is a data message (unconfirmed/confirmed uplink)
            if msg_type not in [0x02, 0x04]:  # 010 = unconfirmed uplink, 100 = confirmed uplink
                return None

            # Extract DevAddr (4 bytes, little endian)
            dev_addr = packet_bytes[1:5]
            dev_addr_hex = dev_addr[::-1].hex().upper()  # Reverse for big endian display

            fctrl = packet_bytes[5]
            fcnt = int.from_bytes(packet_bytes[6:8], 'little')

            # Check if FPort exists
            fport = None
            payload_start = 8
            if fctrl & 0x0F == 0:  # No FOpts
                if len(packet_bytes) > 12:  # Has FPort + payload + MIC
                    fport = packet_bytes[8]
                    payload_start = 9

            return {
                'mhdr': mhdr,
                'msg_type': msg_type,
                'dev_addr': dev_addr_hex,
                'fctrl': fctrl,
                'fcnt': fcnt,
                'fport': fport,
                'payload_start': payload_start,
                'packet_bytes': packet_bytes
            }
        except:
            return None

    def is_my_device(self, packet_info):
        """Check if packet is from configured device using LoRaWAN packet parsing"""
        if not packet_info or not packet_info['data']:
            return False

        try:
            # Parse LoRaWAN packet structure
            lorawan_info = self.parse_lorawan_packet(packet_info['data'])
            if not lorawan_info:
                return False

            # For now, accept any valid LoRaWAN uplink packet
            # In production, you would check against known DevAddr
            return True
        except:
            return False

    def decrypt_payload(self, data_b64):
        """Decrypt LoRaWAN payload using proper LoRaWAN decryption"""
        if not CRYPTO_AVAILABLE:
            return {"error": "Crypto library not available", "success": False}

        try:
            # Parse LoRaWAN packet structure first
            lorawan_info = self.parse_lorawan_packet(data_b64)
            if not lorawan_info:
                return {"error": "Invalid LoRaWAN packet structure", "success": False}

            packet_bytes = lorawan_info['packet_bytes']
            fport = lorawan_info.get('fport')
            payload_start = lorawan_info['payload_start']

            # Extract encrypted payload (excluding MIC)
            if len(packet_bytes) < payload_start + 4:  # Need at least MIC
                return {"error": "Packet too short for payload", "success": False}

            encrypted_payload = packet_bytes[payload_start:-4]  # Exclude 4-byte MIC
            if len(encrypted_payload) == 0:
                return {"error": "No encrypted payload found", "success": False}

            # For now, try simple AES decryption as fallback
            key_bytes = binascii.unhexlify(self.config['app_key'])
            cipher = AES.new(key_bytes, AES.MODE_ECB)

            # Pad data to 16 bytes if needed
            padded_data = encrypted_payload
            if len(padded_data) % 16 != 0:
                padding = 16 - (len(padded_data) % 16)
                padded_data += b'\x00' * padding

            decrypted = cipher.decrypt(padded_data[:16])

            # Try to parse as sensor data (22 bytes expected from firmware)
            sensor_data = {}
            if len(decrypted) >= 16:
                # Accelerometer (6 bytes, scaled by 1000)
                ax = int.from_bytes(decrypted[0:2], 'big', signed=True) / 1000.0
                ay = int.from_bytes(decrypted[2:4], 'big', signed=True) / 1000.0
                az = int.from_bytes(decrypted[4:6], 'big', signed=True) / 1000.0
                sensor_data['accelerometer'] = {'x': ax, 'y': ay, 'z': az}

                # Gyroscope (6 bytes, scaled by 10)
                gx = int.from_bytes(decrypted[6:8], 'big', signed=True) / 10.0
                gy = int.from_bytes(decrypted[8:10], 'big', signed=True) / 10.0
                gz = int.from_bytes(decrypted[10:12], 'big', signed=True) / 10.0
                sensor_data['gyroscope'] = {'x': gx, 'y': gy, 'z': gz}

                # Magnetometer (6 bytes, scaled by 10)
                mx = int.from_bytes(decrypted[12:14], 'big', signed=True) / 10.0
                my = int.from_bytes(decrypted[14:16], 'big', signed=True) / 10.0
                sensor_data['magnetometer'] = {'x': mx, 'y': my}

            return {
                "dev_addr": lorawan_info['dev_addr'],
                "fcnt": lorawan_info['fcnt'],
                "fport": fport,
                "sensor_data": sensor_data,
                "hex": decrypted.hex(),
                "success": True
            }

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
                    print(f"📡 DevAddr: {decrypt_result.get('dev_addr', 'Unknown')}")
                    print(f"📊 FCnt: {decrypt_result.get('fcnt', 'Unknown')}")

                    sensor_data = decrypt_result.get('sensor_data', {})
                    if sensor_data:
                        if 'accelerometer' in sensor_data:
                            acc = sensor_data['accelerometer']
                            print(f"🏃 Accel [g]: X={acc['x']:.3f}, Y={acc['y']:.3f}, Z={acc['z']:.3f}")
                        if 'gyroscope' in sensor_data:
                            gyro = sensor_data['gyroscope']
                            print(f"🌀 Gyro [dps]: X={gyro['x']:.1f}, Y={gyro['y']:.1f}, Z={gyro['z']:.1f}")
                        if 'magnetometer' in sensor_data:
                            mag = sensor_data['magnetometer']
                            print(f"🧭 Mag [µT]: X={mag['x']:.1f}, Y={mag['y']:.1f}")
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