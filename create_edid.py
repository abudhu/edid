#!/usr/bin/env python3
"""
Custom EDID Generator for 5120x1440 Ultrawide Resolution
Creates an EDID binary file that can be loaded by the Linux kernel
to enable custom display resolutions for streaming applications like Moonlight.
"""

import struct
import binascii

def calculate_checksum(data):
    """Calculate EDID checksum (sum of all bytes should equal 0 mod 256)"""
    checksum = (256 - (sum(data) % 256)) % 256
    return checksum

def create_ultrawide_edid(refresh_rate=60):
    """Create EDID for 5120x1440 ultrawide monitor at specified refresh rate"""
    
    # Validate refresh rate
    if refresh_rate not in [60, 120, 144, 240]:
        raise ValueError(f"Unsupported refresh rate: {refresh_rate}Hz. Supported: 60, 120, 144, 240")
    
    # EDID Header (8 bytes)
    header = [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00]
    
    # Manufacturer ID (2 bytes) - "MSI" for Micro-Star International
    # Encoded as: ((('M'-'A'+1) & 0x1F) << 10) | ((('S'-'A'+1) & 0x1F) << 5) | (('I'-'A'+1) & 0x1F)
    manufacturer_id = [0x36, 0xC9]  # "MSI"
    
    # Product ID (2 bytes) - MPG 491CQPX
    product_id = [0x91, 0x04]  # 0x0491 for MPG 491
    
    # Serial number (4 bytes)
    serial_number = [0x01, 0x00, 0x00, 0x00]
    
    # Week of manufacture, Year of manufacture (2 bytes)
    week_year = [0x01, 0x20]  # Week 1, Year 2022
    
    # EDID version (2 bytes)
    edid_version = [0x01, 0x04]  # EDID 1.4
    
    # Basic display parameters (5 bytes)
    display_params = [
        0x80,  # Digital input, no VSYNC serration
        0x73,  # Horizontal screen size (115 cm)
        0x2E,  # Vertical screen size (46 cm) 
        0x78,  # Display gamma (2.2)
        0x2A   # Feature support
    ]
    
    # Color characteristics (10 bytes) - sRGB-like
    color_chars = [
        0xEE, 0x91, 0xA3, 0x54, 0x4C, 0x99, 0x26, 0x0F, 0x50, 0x54
    ]
    
    # Established timings (3 bytes)
    established_timings = [0x00, 0x00, 0x00]
    
    # Standard timings (16 bytes) - 8 entries of 2 bytes each
    standard_timings = [0x01, 0x01] * 8  # Unused entries
    
    # Detailed timing descriptor 1: 5120x1440 at specified refresh rate
    # Calculate pixel clock based on refresh rate
    # Base calculation: (5120 + blanking) * (1440 + blanking) * refresh_rate
    total_horizontal = 5120 + 160  # Active + blanking
    total_vertical = 1440 + 45     # Active + blanking
    pixel_clock_mhz = (total_horizontal * total_vertical * refresh_rate) / 1000000
    pixel_clock_10khz = int(pixel_clock_mhz * 100)  # Convert to 10kHz units
    
    pixel_clock = [pixel_clock_10khz & 0xFF, (pixel_clock_10khz >> 8) & 0xFF]
    
    horizontal_active = 5120
    horizontal_blanking = 160  # Front porch + sync + back porch
    horizontal_active_low = horizontal_active & 0xFF
    horizontal_blanking_low = horizontal_blanking & 0xFF
    horizontal_high = ((horizontal_active >> 8) & 0x0F) | ((horizontal_blanking >> 4) & 0xF0)
    
    vertical_active = 1440
    vertical_blanking = 45  # Front porch + sync + back porch  
    vertical_active_low = vertical_active & 0xFF
    vertical_blanking_low = vertical_blanking & 0xFF
    vertical_high = ((vertical_active >> 8) & 0x0F) | ((vertical_blanking >> 4) & 0xF0)
    
    horizontal_sync_offset = 48
    horizontal_sync_pulse = 32
    vertical_sync_offset = 3
    vertical_sync_pulse = 5
    
    h_sync_offset_low = horizontal_sync_offset & 0xFF
    h_sync_pulse_low = horizontal_sync_pulse & 0xFF
    v_sync_combined = ((vertical_sync_offset & 0x0F) << 4) | (vertical_sync_pulse & 0x0F)
    sync_high = ((horizontal_sync_offset >> 8) & 0xC0) | ((horizontal_sync_pulse >> 8) & 0x30) | ((vertical_sync_offset >> 4) & 0x0C) | ((vertical_sync_pulse >> 4) & 0x03)
    
    # Display size in mm (MSI MPG 491CQPX actual dimensions)
    horizontal_size_low = 0x97  # 1196.7mm / 10 = 119.67 -> 0x77 low byte
    vertical_size_low = 0x21   # 339.2mm / 10 = 33.92 -> 0x21 low byte
    size_high = 0x00  # Upper bits of sizes
    
    detailed_timing_1 = [
        pixel_clock[0], pixel_clock[1],  # Bytes 0-1: Pixel clock
        horizontal_active_low,           # Byte 2: Horizontal active low
        horizontal_blanking_low,         # Byte 3: Horizontal blanking low
        horizontal_high,                 # Byte 4: Horizontal active/blanking high
        vertical_active_low,             # Byte 5: Vertical active low
        vertical_blanking_low,           # Byte 6: Vertical blanking low
        vertical_high,                   # Byte 7: Vertical active/blanking high
        h_sync_offset_low,               # Byte 8: Horizontal sync offset low
        h_sync_pulse_low,                # Byte 9: Horizontal sync pulse width low
        v_sync_combined,                 # Byte 10: Vertical sync offset/pulse low
        sync_high,                       # Byte 11: Horizontal/vertical sync high
        horizontal_size_low,             # Byte 12: Horizontal image size low
        vertical_size_low,               # Byte 13: Vertical image size low
        size_high,                       # Byte 14: Horizontal/vertical image size high
        0x00,                           # Byte 15: Horizontal border
        0x00,                           # Byte 16: Vertical border
        0x1E                            # Byte 17: Flags (digital separate sync)
    ]
    
    # Detailed timing descriptor 2: Display name
    display_name = [
        0x00, 0x00, 0x00, 0xFC, 0x00,  # Display name tag
        0x4D, 0x50, 0x47, 0x34, 0x39,  # "MPG49"
        0x31, 0x43, 0x51, 0x50, 0x58,  # "1CQPX"
        0x0A, 0x20, 0x20              # "\n  "
    ]
    
    # Detailed timing descriptor 3: Range limits
    range_limits = [
        0x00, 0x00, 0x00, 0xFD, 0x00,  # Range limits tag
        0x30, 0xF0, 0x1E, 0x87, 0x3C,  # V freq 48-240Hz, H freq 30-135kHz
        0x00, 0x0A, 0x20, 0x20, 0x20,  # Max pixel clock 600MHz
        0x20, 0x20, 0x20              # Padding
    ]
    
    # Detailed timing descriptor 4: Dummy/Unused
    dummy_descriptor = [0x00] * 18
    
    # Extension flag (1 byte)
    extension_flag = [0x00]
    
    # Assemble the complete EDID (without checksum)
    edid_data = (header + manufacturer_id + product_id + serial_number + 
                week_year + edid_version + display_params + color_chars +
                established_timings + standard_timings + detailed_timing_1 +
                display_name + range_limits + dummy_descriptor + extension_flag)
    
    # Calculate and append checksum
    checksum = calculate_checksum(edid_data)
    edid_data.append(checksum)
    
    return bytes(edid_data)

def validate_edid(edid_data):
    """Validate EDID data structure and checksum"""
    if len(edid_data) != 128:
        raise ValueError(f"Invalid EDID length: {len(edid_data)} (expected 128)")
    
    # Verify header
    expected_header = bytes([0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00])
    if edid_data[:8] != expected_header:
        raise ValueError("Invalid EDID header")
    
    # Verify checksum
    checksum = sum(edid_data) % 256
    if checksum != 0:
        raise ValueError(f"Invalid EDID checksum: {checksum}")
    
    return True

def main():
    """Generate and save the custom EDID files"""
    print("Creating custom EDID for MSI MPG 491CQPX QD-OLED (5120x1440)...")
    
    # Create EDID files for different refresh rates
    refresh_rates = [60, 120, 144, 240]
    
    for refresh_rate in refresh_rates:
        print(f"\nGenerating EDID for {refresh_rate}Hz...")
        
        try:
            edid_data = create_ultrawide_edid(refresh_rate)
            
            # Validate before saving
            validate_edid(edid_data)
            print(f"✓ EDID validation passed")
            
            # Save as binary file
            filename = f'msi_mpg491cqpx_{refresh_rate}hz.bin'
            with open(filename, 'wb') as f:
                f.write(edid_data)
            
            print(f"✓ Created {filename} ({len(edid_data)} bytes)")
        except (ValueError, IOError) as e:
            print(f"✗ Failed to create EDID for {refresh_rate}Hz: {e}")
            continue
        
        # Also save as hex dump for reference
        hex_filename = f'msi_mpg491cqpx_{refresh_rate}hz.hex'
        with open(hex_filename, 'w') as f:
            hex_dump = binascii.hexlify(edid_data).decode('ascii')
            # Format as groups of 32 characters (16 bytes) per line
            for i in range(0, len(hex_dump), 32):
                f.write(hex_dump[i:i+32] + '\n')
        
        print(f"✓ Created {hex_filename} (human-readable format)")
    
    # Create a default symlink for backwards compatibility
    import os
    try:
        if os.path.exists('ultrawide_5120x1440.bin'):
            os.remove('ultrawide_5120x1440.bin')
        os.symlink('msi_mpg491cqpx_60hz.bin', 'ultrawide_5120x1440.bin')
        print("✓ Created ultrawide_5120x1440.bin symlink (60Hz default)")
    except OSError:
        # Fallback: copy file if symlinks not supported
        import shutil
        shutil.copy2('msi_mpg491cqpx_60hz.bin', 'ultrawide_5120x1440.bin')
        print("✓ Created ultrawide_5120x1440.bin copy (60Hz default)")
    
    # Display info about the generated EDIDs
    print(f"\nEDID Information:")
    print(f"- Resolution: 5120x1440")
    print(f"- Manufacturer: MSI (Micro-Star International)")
    print(f"- Product: MPG 491CQPX QD-OLED")
    print(f"- Refresh Rates: {', '.join(map(str, refresh_rates))}Hz")
    print(f"- File size: {len(edid_data)} bytes each")
    print(f"- Default file: ultrawide_5120x1440.bin (60Hz)")

if __name__ == "__main__":
    main()