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
APP_KEY = "21222324252627282A2B2C2D2E2F30"


def check_device_match(json_line):
    """
    Check if the LoRa packet matches our device
    This looks for device address or other identifying info
    """
    # In LoRaWAN, we can check the DevAddr field or other identifiers
    # For now, we'll use a simple signature approach

    # Extract the data payload
    if '"data":"' not in json_line:
        return False

    start = json_line.find('"data":"') + 8
    end = json_line.find('"', start)

    if start <= 7 or end <= start:
        return False

    payload = json_line[start:end]

    try:
        # Decode and check for our device signature
        encrypted_bytes = base64.b64decode(payload)

        # Look for our device EUI in the packet (first 8 bytes often contain device info)
        dev_eui_bytes = binascii.unhexlify(DEV_EUI)

        # Check if our device EUI appears in the packet
        if dev_eui_bytes in encrypted_bytes:
            return True

        # Alternative: Check for specific packet characteristics from our device
        # You could also check frequency, data rate, or other identifying features

        return False

    except:
        return False


def decrypt_payload(base64_data, device_matched=True):
    """
    Decrypt a Base64 encoded LoRaWAN payload
    Only decrypt if device_matched is True
    """
    if not device_matched:
        return None

    try:
        print(f"Attempting to decrypt MY DEVICE: {base64_data}")

        # Decode from Base64 to bytes
        encrypted_bytes = base64.b64decode(base64_data)
        print(f"Encrypted bytes: {encrypted_bytes.hex()}")

        # Convert APP_KEY to bytes
        key_bytes = binascii.unhexlify(APP_KEY)

        # Simple AES decryption (ECB mode for testing)
        # Note: Real LoRaWAN uses more complex encryption with frame counters
        cipher = AES.new(key_bytes, AES.MODE_ECB)

        # Pad data to 16 bytes if needed
        padded_data = encrypted_bytes
        if len(padded_data) % 16 != 0:
            padding = 16 - (len(padded_data) % 16)
            padded_data += b"\x00" * padding

        # Decrypt
        decrypted = cipher.decrypt(padded_data[:16])

        print(f"Decrypted hex: {decrypted.hex()}")

        # Try to extract readable text
        try:
            text = decrypted.decode("utf-8").rstrip("\x00")
            print(f"Decrypted text: '{text}'")
        except:
            print("Not readable as text")

        # Show as individual bytes
        byte_values = [f"0x{b:02x}" for b in decrypted[:8]]
        print(f"Byte values: {' '.join(byte_values)}")

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
