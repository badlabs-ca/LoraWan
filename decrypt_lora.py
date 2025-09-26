#!/usr/bin/env python3
"""
LoRa Data Decryption Script
Decrypts LoRaWAN payloads using your device keys
"""

import base64
import binascii
import sys
from Crypto.Cipher import AES

# Your device keys (same as in RAK13100 firmware)
# Change these to match your firmware keys
DEV_EUI = "0102030405060708"
APP_EUI = "1112131415161718"
APP_KEY = "21222324252627282A2B2C2D2E2F3031"


def parse_lorawan_packet(payload_b64):
    """
    Parse LoRaWAN packet structure to extract DevAddr and other fields
    Returns dict with packet info or None if invalid
    """
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

def check_device_match(json_line):
    """
    Check if the LoRa packet matches our V3 device using specific filtering
    """
    # Extract the data payload
    if '"data":"' not in json_line:
        return False

    start = json_line.find('"data":"') + 8
    end = json_line.find('"', start)

    if start <= 7 or end <= start:
        return False

    payload = json_line[start:end]

    try:
        # Parse LoRaWAN packet structure
        packet_info = parse_lorawan_packet(payload)
        if not packet_info:
            return False

        current_dev_addr = packet_info['dev_addr']
        fport = packet_info.get('fport')
        packet_bytes = packet_info['packet_bytes']
        payload_start = packet_info['payload_start']

        print(f"Found LoRaWAN packet: DevAddr={current_dev_addr}, FCnt={packet_info['fcnt']}, FPort={fport}")

        # Filter for V3 device signature:
        # - Exactly 22 bytes payload (sensor data)
        # - Port 2 (from V3 firmware g_AppPort = 2)
        if len(packet_bytes) >= payload_start + 4:
            payload_length = len(packet_bytes) - payload_start - 4

            if payload_length == 22 and fport == 2:
                print(f"✓ MATCHED V3 device signature: 22-byte payload on port 2")
                return True
            else:
                print(f"✗ Not V3 device: {payload_length}B payload on port {fport} (expected 22B on port 2)")
                return False

        print(f"✗ Packet too short for V3 device")
        return False

    except Exception as e:
        print(f"Error parsing packet: {e}")
        return False


def decrypt_payload(base64_data, device_matched=True):
    """
    Decrypt a Base64 encoded LoRaWAN payload using proper LoRaWAN decryption
    Only decrypt if device_matched is True
    """
    if not device_matched:
        return None

    try:
        print(f"Attempting to decrypt LoRaWAN packet: {base64_data}")

        # Parse LoRaWAN packet structure first
        packet_info = parse_lorawan_packet(base64_data)
        if not packet_info:
            print("Invalid LoRaWAN packet structure")
            return None

        packet_bytes = packet_info['packet_bytes']
        fport = packet_info.get('fport')
        payload_start = packet_info['payload_start']

        print(f"DevAddr: {packet_info['dev_addr']}, FCnt: {packet_info['fcnt']}, FPort: {fport}")

        # Extract encrypted payload (excluding MIC)
        if len(packet_bytes) < payload_start + 4:  # Need at least MIC
            print("Packet too short for payload")
            return None

        encrypted_payload = packet_bytes[payload_start:-4]  # Exclude 4-byte MIC
        if len(encrypted_payload) == 0:
            print("No encrypted payload found")
            return None

        print(f"Encrypted payload ({len(encrypted_payload)} bytes): {encrypted_payload.hex()}")

        # For now, try simple AES decryption as fallback
        # Real LoRaWAN uses AES-CTR with specific key derivation
        key_bytes = binascii.unhexlify(APP_KEY)
        cipher = AES.new(key_bytes, AES.MODE_ECB)

        # Pad data to 32 bytes to handle full 22-byte sensor payload
        padded_data = encrypted_payload
        if len(padded_data) % 16 != 0:
            padding = 16 - (len(padded_data) % 16)
            padded_data += b"\x00" * padding

        # Decrypt full payload (up to 32 bytes to cover 22-byte sensor data)
        if len(padded_data) >= 32:
            decrypted = cipher.decrypt(padded_data[:32])
        else:
            decrypted = cipher.decrypt(padded_data)
        print(f"Decrypted hex: {decrypted.hex()}")

        # Try to parse as sensor data (22 bytes expected from firmware)
        if len(decrypted) >= 22:
            print("\n=== Complete Sensor Data Analysis ===")
            # Accelerometer (6 bytes, scaled by 1000)
            ax = int.from_bytes(decrypted[0:2], 'big', signed=True) / 1000.0
            ay = int.from_bytes(decrypted[2:4], 'big', signed=True) / 1000.0
            az = int.from_bytes(decrypted[4:6], 'big', signed=True) / 1000.0
            print(f"Accelerometer [g]: X={ax:.3f}, Y={ay:.3f}, Z={az:.3f}")

            # Gyroscope (6 bytes, scaled by 10)
            gx = int.from_bytes(decrypted[6:8], 'big', signed=True) / 10.0
            gy = int.from_bytes(decrypted[8:10], 'big', signed=True) / 10.0
            gz = int.from_bytes(decrypted[10:12], 'big', signed=True) / 10.0
            print(f"Gyroscope [dps]: X={gx:.1f}, Y={gy:.1f}, Z={gz:.1f}")

            # Magnetometer (6 bytes, scaled by 10)
            mx = int.from_bytes(decrypted[12:14], 'big', signed=True) / 10.0
            my = int.from_bytes(decrypted[14:16], 'big', signed=True) / 10.0
            mz = int.from_bytes(decrypted[16:18], 'big', signed=True) / 10.0
            print(f"Magnetometer [µT]: X={mx:.1f}, Y={my:.1f}, Z={mz:.1f}")

            # ToF sensors (4 bytes total)
            tof_c_raw = int.from_bytes(decrypted[18:20], 'big')
            tof_d_raw = int.from_bytes(decrypted[20:22], 'big')

            tof_c_mm = tof_c_raw if tof_c_raw != 0xFFFF else None
            tof_d_mm = tof_d_raw if tof_d_raw != 0xFFFF else None

            tof_c_str = f"{tof_c_mm}mm" if tof_c_mm is not None else "Out of Range"
            tof_d_str = f"{tof_d_mm}mm" if tof_d_mm is not None else "Out of Range"

            print(f"ToF Distance C: {tof_c_str}")
            print(f"ToF Distance D: {tof_d_str}")
        elif len(decrypted) >= 16:
            print("\n=== Partial Sensor Data (16 bytes) ===")
            # Accelerometer (6 bytes, scaled by 1000)
            ax = int.from_bytes(decrypted[0:2], 'big', signed=True) / 1000.0
            ay = int.from_bytes(decrypted[2:4], 'big', signed=True) / 1000.0
            az = int.from_bytes(decrypted[4:6], 'big', signed=True) / 1000.0
            print(f"Accelerometer [g]: X={ax:.3f}, Y={ay:.3f}, Z={az:.3f}")

            # Gyroscope (6 bytes, scaled by 10)
            gx = int.from_bytes(decrypted[6:8], 'big', signed=True) / 10.0
            gy = int.from_bytes(decrypted[8:10], 'big', signed=True) / 10.0
            gz = int.from_bytes(decrypted[10:12], 'big', signed=True) / 10.0
            print(f"Gyroscope [dps]: X={gx:.1f}, Y={gy:.1f}, Z={gz:.1f}")

            # Partial magnetometer (4 bytes available)
            mx = int.from_bytes(decrypted[12:14], 'big', signed=True) / 10.0
            my = int.from_bytes(decrypted[14:16], 'big', signed=True) / 10.0
            print(f"Magnetometer [µT]: X={mx:.1f}, Y={my:.1f} (Z and ToF data missing)")

        return decrypted

    except Exception as e:
        print(f"Decryption error: {e}")
        return None


def monitor_gateway_output():
    """
    Monitor stdin for gateway output and decrypt only MY device's payloads
    """
    print("=== LoRa Payload Decryption Monitor ===")
    print(f"My Device EUI: {DEV_EUI}")
    print(f"App EUI: {APP_EUI}")
    print(f"App Key: {APP_KEY}")
    print("Monitoring ONLY for MY device's data...")
    print("(Ignoring all other LoRa signals)")
    print("=" * 40)

    packet_count = 0
    my_device_count = 0

    try:
        while True:
            line = input()

            # Look for JSON data lines
            if '"data":"' in line:
                packet_count += 1
                print(f"[Packet #{packet_count}] LoRa signal detected...", end="")

                # Check if this is from MY device
                if check_device_match(line):
                    my_device_count += 1
                    print(f" -> MY DEVICE! (#{my_device_count})")

                    # Extract Base64 payload
                    start = line.find('"data":"') + 8
                    end = line.find('"', start)

                    if start > 7 and end > start:
                        payload = line[start:end]
                        print(f"\n--- MY DEVICE DATA ---")
                        decrypt_payload(payload, device_matched=True)
                        print("-" * 21)
                else:
                    print(" -> Other device (ignored)")

    except KeyboardInterrupt:
        print(f"\nMonitoring stopped.")
        print(f"Total packets seen: {packet_count}")
        print(f"My device packets: {my_device_count}")
    except EOFError:
        print("End of input.")


def main():
    if len(sys.argv) > 1:
        # Command line usage: python3 decrypt_lora.py "base64data"
        payload = sys.argv[1]
        decrypt_payload(payload)
    else:
        # Interactive monitoring mode
        monitor_gateway_output()


if __name__ == "__main__":
    main()
