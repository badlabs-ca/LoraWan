#!/usr/bin/env python3
"""
Sensorite V4 LoRaWAN Monitor
Real-time LoRaWAN signal analysis and sensor data display
Based on proven rak_signal_monitor.py but optimized for V4 22-byte packets
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

# V4 LoRaWAN device configuration (same credentials as V3 for compatibility)
V4_CONFIG = {
    "dev_eui": "0102030405060708",
    "app_eui": "1112131415161718",
    "app_key": "21222324252627282A2B2C2D2E2F3031",
    "device_name": "Sensorite V4 LoRaWAN"
}

class V4LoRaWANMonitor:
    def __init__(self):
        self.packet_count = 0
        self.v4_device_count = 0
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
                'channel': rxpk.get('chan', 0),
                'raw_json': json_match.group()
            }
        except (json.JSONDecodeError, KeyError, IndexError):
            return None

    def parse_lorawan_frame(self, data_b64):
        """Parse LoRaWAN frame structure"""
        try:
            packet_bytes = base64.b64decode(data_b64)
            if len(packet_bytes) < 12:  # Minimum LoRaWAN frame size
                return None

            # LoRaWAN frame structure:
            # MHDR (1) | DevAddr (4) | FCtrl (1) | FCnt (2) | FPort (1) | FRMPayload | MIC (4)
            mhdr = packet_bytes[0]
            dev_addr = packet_bytes[1:5].hex().upper()
            fctrl = packet_bytes[5]
            fcnt = int.from_bytes(packet_bytes[6:8], 'little')

            # Calculate payload start (skip MHDR + DevAddr + FCtrl + FCnt)
            payload_start = 8

            # Check for FPort (optional)
            fport = None
            if len(packet_bytes) > payload_start:
                fport = packet_bytes[payload_start]
                payload_start += 1

            return {
                'mhdr': mhdr,
                'dev_addr': dev_addr,
                'fctrl': fctrl,
                'fcnt': fcnt,
                'fport': fport,
                'payload_start': payload_start,
                'packet_bytes': packet_bytes
            }
        except:
            return None

    def is_v4_device(self, packet_info):
        """Check if packet is from Sensorite V4 device using LoRaWAN signature"""
        if not packet_info or not packet_info['data']:
            return False

        try:
            lorawan_info = self.parse_lorawan_frame(packet_info['data'])
            if not lorawan_info:
                return False

            # V4 device signature (22-byte payload like V3 but different packet counter behavior)
            packet_bytes = lorawan_info['packet_bytes']
            fport = lorawan_info.get('fport')
            payload_start = lorawan_info['payload_start']

            # Extract payload length (excluding MIC)
            if len(packet_bytes) >= payload_start + 4:
                payload_length = len(packet_bytes) - payload_start - 4

                # V4 LoRaWAN signature:
                # - Exactly 22 bytes payload (same as V3)
                # - Port 2 (configured in firmware)
                # - Valid LoRaWAN structure
                if payload_length == 22 and fport == 2:
                    current_dev_addr = lorawan_info['dev_addr']
                    print(f"[FILTER] ✓ MATCHED V4 device: DevAddr={current_dev_addr}, Payload={payload_length}B, Port={fport}")
                    return True
                else:
                    current_dev_addr = lorawan_info['dev_addr']
                    print(f"[FILTER] Rejected: DevAddr={current_dev_addr}, Payload={payload_length}B, Port={fport} (expected 22B on port 2)")
                    return False
            return False
        except Exception as e:
            print(f"[FILTER] Error: {e}")
            return False

    def decrypt_v4_payload(self, packet_info):
        """Decrypt and parse V4 sensor payload"""
        if not CRYPTO_AVAILABLE:
            return {"error": "Crypto library not available", "success": False}

        try:
            lorawan_info = self.parse_lorawan_frame(packet_info['data'])
            if not lorawan_info:
                return {"error": "Invalid LoRaWAN frame", "success": False}

            packet_bytes = lorawan_info['packet_bytes']
            payload_start = lorawan_info['payload_start']

            # Extract encrypted payload (excluding MIC)
            if len(packet_bytes) < payload_start + 4:
                return {"error": "Packet too short", "success": False}

            encrypted_payload = packet_bytes[payload_start:-4]  # Remove MIC

            if len(encrypted_payload) != 22:
                return {"error": f"Invalid payload size: {len(encrypted_payload)} (expected 22)", "success": False}

            # Decrypt payload using AppKey (same as V3)
            app_key_bytes = bytes.fromhex(V4_CONFIG["app_key"])
            cipher = AES.new(app_key_bytes, AES.MODE_ECB)

            # Pad to 32 bytes for AES decryption
            padded_data = encrypted_payload + b'\x00' * (32 - len(encrypted_payload))
            decrypted = cipher.decrypt(padded_data)

            # Parse V4 sensor data (22 bytes) - same format as V3
            sensor_data = {}
            if len(decrypted) >= 22:
                # Accelerometer (6 bytes, scaled by 1000)
                ax = int.from_bytes(decrypted[0:2], 'big', signed=True) / 1000.0
                ay = int.from_bytes(decrypted[2:4], 'big', signed=True) / 1000.0
                az = int.from_bytes(decrypted[4:6], 'big', signed=True) / 1000.0

                # Gyroscope (6 bytes, scaled by 10)
                gx = int.from_bytes(decrypted[6:8], 'big', signed=True) / 10.0
                gy = int.from_bytes(decrypted[8:10], 'big', signed=True) / 10.0
                gz = int.from_bytes(decrypted[10:12], 'big', signed=True) / 10.0

                # Magnetometer (6 bytes, scaled by 10)
                mx = int.from_bytes(decrypted[12:14], 'big', signed=True) / 10.0
                my = int.from_bytes(decrypted[14:16], 'big', signed=True) / 10.0
                mz = int.from_bytes(decrypted[16:18], 'big', signed=True) / 10.0

                # ToF sensors (4 bytes)
                tof_c_raw = int.from_bytes(decrypted[18:20], 'big')
                tof_d_raw = int.from_bytes(decrypted[20:22], 'big')

                tof_c_mm = tof_c_raw if tof_c_raw != 0xFFFF else None
                tof_d_mm = tof_d_raw if tof_d_raw != 0xFFFF else None

                sensor_data = {
                    "accelerometer": {"x": ax, "y": ay, "z": az},
                    "gyroscope": {"x": gx, "y": gy, "z": gz},
                    "magnetometer": {"x": mx, "y": my, "z": mz},
                    "tof": {
                        "distance_c_mm": tof_c_mm,
                        "distance_d_mm": tof_d_mm,
                        "c_valid": tof_c_mm is not None,
                        "d_valid": tof_d_mm is not None
                    }
                }

            return {
                "lorawan_info": lorawan_info,
                "sensor_data": sensor_data,
                "encrypted_hex": encrypted_payload.hex(),
                "decrypted_hex": decrypted[:22].hex(),
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

    def print_packet_summary(self, packet_info, decrypt_result):
        """Print formatted packet information and sensor data"""
        timestamp = datetime.now().strftime("%H:%M:%S")

        print(f"\n🎯 SENSORITE V4 LoRaWAN PACKET #{self.v4_device_count}")
        print(f"⏰ Time: {timestamp}")
        print(f"📶 RSSI: {packet_info['rssi']} dBm")
        print(f"📊 SNR: {packet_info['lsnr']} dB")
        print(f"📻 Freq: {packet_info['frequency']} MHz")
        print(f"📏 Size: {packet_info['size']} bytes")
        print(f"📡 Rate: {packet_info['datarate']}")

        # Signal quality analysis
        quality = self.analyze_signal_quality(packet_info)
        print(f"🔍 Quality: {quality['signal_quality']} ({quality['distance_estimate']})")

        if decrypt_result.get('success'):
            lorawan_info = decrypt_result['lorawan_info']
            print(f"🆔 DevAddr: {lorawan_info['dev_addr']}")
            print(f"📊 FCnt: {lorawan_info['fcnt']}")
            print(f"🚪 Port: {lorawan_info['fport']}")

            sensor_data = decrypt_result.get('sensor_data', {})
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

            print(f"🔒 Encrypted: {decrypt_result['encrypted_hex'][:32]}...")
            print(f"🔓 Decrypted: {decrypt_result['decrypted_hex'][:32]}...")
        else:
            print(f"❌ Decryption failed: {decrypt_result.get('error', 'Unknown')}")

        print("-" * 60)

    def print_statistics(self):
        """Print session statistics"""
        duration = datetime.now() - self.start_time
        print(f"\n📊 SESSION STATISTICS")
        print(f"Duration: {duration}")
        print(f"Total packets: {self.packet_count}")
        print(f"Sensorite V4 packets: {self.v4_device_count}")
        if self.packet_count > 0:
            percentage = (self.v4_device_count / self.packet_count) * 100
            print(f"V4 percentage: {percentage:.1f}%")

    def monitor(self, show_all=False):
        """Main monitoring loop"""
        print("🎯 Sensorite V4 LoRaWAN Monitor")
        print(f"🆔 DevEUI: {V4_CONFIG['dev_eui']}")
        print(f"🔑 AppEUI: {V4_CONFIG['app_eui']}")
        print(f"📦 Expected payload: 22 bytes on port 2")
        if show_all:
            print("📡 Monitoring ALL LoRaWAN signals...")
        else:
            print("📡 Monitoring for Sensorite V4 only...")
        print("📡 Press Ctrl+C to stop")
        print("=" * 60)

        try:
            while True:
                try:
                    line = input()
                    packet_info = self.parse_lora_packet(line)

                    if packet_info:
                        self.packet_count += 1
                        is_v4 = self.is_v4_device(packet_info)

                        if is_v4:
                            self.v4_device_count += 1
                            decrypt_result = self.decrypt_v4_payload(packet_info)
                            self.print_packet_summary(packet_info, decrypt_result)
                        elif show_all:
                            timestamp = datetime.now().strftime("%H:%M:%S")
                            print(f"[{timestamp}] #{self.packet_count} Other device: "
                                  f"RSSI={packet_info['rssi']}dBm, "
                                  f"Size={packet_info['size']}B, "
                                  f"Freq={packet_info['frequency']}MHz")

                except EOFError:
                    break

        except KeyboardInterrupt:
            print("\n🛑 Monitoring stopped by user")
        finally:
            self.print_statistics()

def main():
    if len(sys.argv) > 1:
        if sys.argv[1] == "all":
            # Monitor all devices
            monitor = V4LoRaWANMonitor()
            monitor.monitor(show_all=True)
            return

    # Default: Monitor only Sensorite V4
    monitor = V4LoRaWANMonitor()
    monitor.monitor()

if __name__ == "__main__":
    main()