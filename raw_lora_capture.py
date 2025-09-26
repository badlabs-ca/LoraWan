#!/usr/bin/env python3
"""
Raw LoRa Packet Capture for Sensorite V4
Captures raw LoRa packets directly from RAK7371 gateway
No LoRaWAN network server required
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
    print("WARNING: pycryptodome not installed. Encryption features disabled.")

# Sensorite V4 device configuration
DEVICE_ID = 0x5353  # "SS" for Sensorite
EXPECTED_PACKET_SIZE = 26  # 2 bytes header + 2 bytes counter + 22 bytes sensor data

class RawLoRaCapture:
    def __init__(self):
        self.packet_count = 0
        self.sensorite_count = 0
        self.start_time = datetime.now()

    def parse_raw_lora_packet(self, line):
        """Extract raw LoRa packet information from gateway output"""
        try:
            # Look for JSON data in the line (standard LoRaWAN format)
            json_match = re.search(r'\\{"rxpk":\\[.*?\\]\\}', line)
            if json_match:
                packet_data = json.loads(json_match.group())
                if 'rxpk' in packet_data and packet_data['rxpk']:
                    rxpk = packet_data['rxpk'][0]  # First packet
                    return {
                        'timestamp': rxpk.get('time', ''),
                        'frequency': rxpk.get('freq', 0),
                        'rssi': rxpk.get('rssi', 0),
                        'lsnr': rxpk.get('lsnr', 0),
                        'datarate': rxpk.get('datr', ''),
                        'size': rxpk.get('size', 0),
                        'data': rxpk.get('data', ''),
                        'channel': rxpk.get('chan', 0),
                        'packet_type': 'lorawan'
                    }

            # Look for raw LoRa packet format (modified packet forwarder)
            # Format: RXPK,timestamp,freq,rssi,lsnr,sf,bw,cr,size,data
            if line.startswith('RXPK,'):
                parts = line.strip().split(',')
                if len(parts) >= 10:
                    return {
                        'timestamp': parts[1],
                        'frequency': float(parts[2]),
                        'rssi': int(parts[3]),
                        'lsnr': float(parts[4]),
                        'datarate': f"SF{parts[5]}BW{parts[6]}",
                        'size': int(parts[8]),
                        'data': parts[9],
                        'channel': 0,
                        'packet_type': 'raw_lora'
                    }

            # Alternative: Look for packet forwarder debug output
            # Format: "INFO: [RAW] freq=915.2 rssi=-89 snr=8.5 size=26 data=535300050033..."
            raw_match = re.search(r'INFO: \\[RAW\\] freq=([0-9.]+) rssi=(-?[0-9]+) snr=(-?[0-9.]+) size=([0-9]+) data=([A-Fa-f0-9]+)', line)
            if raw_match:
                return {
                    'timestamp': datetime.now().strftime("%Y-%m-%dT%H:%M:%S.%fZ"),
                    'frequency': float(raw_match.group(1)),
                    'rssi': int(raw_match.group(2)),
                    'lsnr': float(raw_match.group(3)),
                    'datarate': "SF7BW125",  # Default for V4
                    'size': int(raw_match.group(4)),
                    'data': base64.b64encode(bytes.fromhex(raw_match.group(5))).decode(),
                    'channel': 0,
                    'packet_type': 'raw_debug'
                }

            return None
        except (json.JSONDecodeError, KeyError, IndexError, ValueError):
            return None

    def is_sensorite_packet(self, packet_info):
        """Check if packet is from Sensorite V4 device"""
        if not packet_info or not packet_info['data']:
            return False

        try:
            # Decode packet data
            packet_bytes = base64.b64decode(packet_info['data'])

            # Check packet size
            if len(packet_bytes) != EXPECTED_PACKET_SIZE:
                return False

            # Check device ID in header (first 2 bytes)
            if len(packet_bytes) >= 2:
                device_id = (packet_bytes[0] << 8) | packet_bytes[1]
                if device_id == DEVICE_ID:
                    return True

            return False
        except:
            return False

    def parse_sensorite_data(self, data_b64):
        """Parse Sensorite V4 packet format"""
        try:
            packet_bytes = base64.b64decode(data_b64)

            if len(packet_bytes) != EXPECTED_PACKET_SIZE:
                return {"error": f"Invalid packet size: {len(packet_bytes)} (expected {EXPECTED_PACKET_SIZE})", "success": False}

            # Parse header (4 bytes)
            device_id = (packet_bytes[0] << 8) | packet_bytes[1]
            packet_counter = (packet_bytes[2] << 8) | packet_bytes[3]

            # Parse accelerometer (6 bytes, scaled by 1000)
            ax = int.from_bytes(packet_bytes[4:6], 'big', signed=True) / 1000.0
            ay = int.from_bytes(packet_bytes[6:8], 'big', signed=True) / 1000.0
            az = int.from_bytes(packet_bytes[8:10], 'big', signed=True) / 1000.0

            # Parse gyroscope (6 bytes, scaled by 10)
            gx = int.from_bytes(packet_bytes[10:12], 'big', signed=True) / 10.0
            gy = int.from_bytes(packet_bytes[12:14], 'big', signed=True) / 10.0
            gz = int.from_bytes(packet_bytes[14:16], 'big', signed=True) / 10.0

            # Parse magnetometer (6 bytes, scaled by 10)
            mx = int.from_bytes(packet_bytes[16:18], 'big', signed=True) / 10.0
            my = int.from_bytes(packet_bytes[18:20], 'big', signed=True) / 10.0
            mz = int.from_bytes(packet_bytes[20:22], 'big', signed=True) / 10.0

            # Parse ToF sensors (4 bytes)
            tof_c_raw = int.from_bytes(packet_bytes[22:24], 'big')
            tof_d_raw = int.from_bytes(packet_bytes[24:26], 'big')

            tof_c_mm = tof_c_raw if tof_c_raw != 0xFFFF else None
            tof_d_mm = tof_d_raw if tof_d_raw != 0xFFFF else None

            return {
                "device_id": f"0x{device_id:04X}",
                "packet_counter": packet_counter,
                "sensor_data": {
                    "accelerometer": {"x": ax, "y": ay, "z": az},
                    "gyroscope": {"x": gx, "y": gy, "z": gz},
                    "magnetometer": {"x": mx, "y": my, "z": mz},
                    "tof": {
                        "distance_c_mm": tof_c_mm,
                        "distance_d_mm": tof_d_mm,
                        "c_valid": tof_c_mm is not None,
                        "d_valid": tof_d_mm is not None
                    }
                },
                "raw_hex": packet_bytes.hex(),
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

    def print_packet_summary(self, packet_info, parse_result):
        """Print formatted packet information"""
        timestamp = datetime.now().strftime("%H:%M:%S")

        print(f"\\n🎯 SENSORITE V4 PACKET #{self.sensorite_count}")
        print(f"⏰ Time: {timestamp}")
        print(f"📶 RSSI: {packet_info['rssi']} dBm")
        print(f"📊 SNR: {packet_info['lsnr']} dB")
        print(f"📻 Freq: {packet_info['frequency']} MHz")
        print(f"📏 Size: {packet_info['size']} bytes")
        print(f"📡 Rate: {packet_info['datarate']}")

        # Signal quality analysis
        quality = self.analyze_signal_quality(packet_info)
        print(f"🔍 Quality: {quality['signal_quality']} ({quality['distance_estimate']})")

        if parse_result.get('success'):
            print(f"🆔 Device ID: {parse_result['device_id']}")
            print(f"📊 Packet #: {parse_result['packet_counter']}")

            sensor_data = parse_result.get('sensor_data', {})
            if 'accelerometer' in sensor_data:
                acc = sensor_data['accelerometer']
                print(f"🏃 Accel [g]: X={acc['x']:.3f}, Y={acc['y']:.3f}, Z={acc['z']:.3f}")

            if 'gyroscope' in sensor_data:
                gyro = sensor_data['gyroscope']
                print(f"🌀 Gyro [dps]: X={gyro['x']:.1f}, Y={gyro['y']:.1f}, Z={gyro['z']:.1f}")

            if 'magnetometer' in sensor_data:
                mag = sensor_data['magnetometer']
                print(f"🧭 Mag [µT]: X={mag['x']:.1f}, Y={mag['y']:.1f}, Z={mag['z']:.1f}")

            if 'tof' in sensor_data:
                tof = sensor_data['tof']
                c_str = f"{tof['distance_c_mm']}mm" if tof['c_valid'] else "Out of Range"
                d_str = f"{tof['distance_d_mm']}mm" if tof['d_valid'] else "Out of Range"
                print(f"📏 ToF C: {c_str}, ToF D: {d_str}")

            print(f"🔢 Raw: {parse_result['raw_hex'][:32]}...")
        else:
            print(f"❌ Parse failed: {parse_result.get('error', 'Unknown')}")

        print("-" * 50)

    def print_statistics(self):
        """Print session statistics"""
        duration = datetime.now() - self.start_time
        print(f"\\n📊 SESSION STATISTICS")
        print(f"Duration: {duration}")
        print(f"Total packets: {self.packet_count}")
        print(f"Sensorite packets: {self.sensorite_count}")
        if self.packet_count > 0:
            percentage = (self.sensorite_count / self.packet_count) * 100
            print(f"Sensorite percentage: {percentage:.1f}%")

    def monitor(self, show_all=False):
        """Main monitoring loop"""
        print("🎯 Sensorite V4 Raw LoRa Capture")
        print(f"🆔 Device ID: 0x{DEVICE_ID:04X}")
        print(f"📦 Expected packet size: {EXPECTED_PACKET_SIZE} bytes")
        if show_all:
            print("📡 Monitoring ALL raw LoRa signals...")
        else:
            print("📡 Monitoring for Sensorite V4 only...")
        print("📡 Press Ctrl+C to stop")
        print("=" * 60)

        try:
            while True:
                try:
                    line = input()
                    packet_info = self.parse_raw_lora_packet(line)

                    if packet_info:
                        self.packet_count += 1
                        is_sensorite = self.is_sensorite_packet(packet_info)

                        if is_sensorite:
                            self.sensorite_count += 1
                            parse_result = self.parse_sensorite_data(packet_info['data'])
                            self.print_packet_summary(packet_info, parse_result)
                        elif show_all:
                            timestamp = datetime.now().strftime("%H:%M:%S")
                            print(f"[{timestamp}] #{self.packet_count} Other device: "
                                  f"RSSI={packet_info['rssi']}dBm, "
                                  f"Size={packet_info['size']}B, "
                                  f"Freq={packet_info['frequency']}MHz")

                except EOFError:
                    break

        except KeyboardInterrupt:
            print("\\n🛑 Monitoring stopped by user")
        finally:
            self.print_statistics()

def main():
    if len(sys.argv) > 1:
        if sys.argv[1] == "test":
            # Test mode with sample data
            capture = RawLoRaCapture()
            # Create a test packet with Sensorite V4 format
            test_data = bytearray(26)
            test_data[0:2] = DEVICE_ID.to_bytes(2, 'big')  # Device ID
            test_data[2:4] = (42).to_bytes(2, 'big')       # Packet counter
            test_data[4:6] = (1234).to_bytes(2, 'big', signed=True)   # Accel X
            test_data[6:8] = (-567).to_bytes(2, 'big', signed=True)   # Accel Y
            test_data[8:10] = (890).to_bytes(2, 'big', signed=True)   # Accel Z
            # ... fill rest with test data
            test_b64 = base64.b64encode(test_data).decode()

            parse_result = capture.parse_sensorite_data(test_b64)
            print("🧪 Test Mode - Sample Sensorite V4 Packet:")
            print(json.dumps(parse_result, indent=2))
            return
        elif sys.argv[1] == "all":
            # Monitor all devices
            capture = RawLoRaCapture()
            capture.monitor(show_all=True)
            return

    # Default: Monitor only Sensorite V4
    capture = RawLoRaCapture()
    capture.monitor()

if __name__ == "__main__":
    main()