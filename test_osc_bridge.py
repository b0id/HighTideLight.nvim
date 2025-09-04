#!/usr/bin/env python3
"""
Test script for TidalCycles OSC Bridge
Simulates TidalCycles sending highlight events to test the system
"""

import socket
import struct
import time
import random

def osc_string(s):
    """Convert string to OSC format with null padding"""
    s = s.encode('utf-8')
    length = len(s) + 1
    padded_length = (length + 3) // 4 * 4
    return s + b'\0' * (padded_length - length + 1)

def osc_int(i):
    """Convert integer to OSC format"""
    return struct.pack('>i', i)

def osc_float(f):
    """Convert float to OSC format"""
    return struct.pack('>f', f)

def create_osc_message(address, args):
    """Create OSC message"""
    message = osc_string(address)
    
    # Type tag string
    type_tags = ','
    arg_data = b''
    
    for arg in args:
        if isinstance(arg, int):
            type_tags += 'i'
            arg_data += osc_int(arg)
        elif isinstance(arg, float):
            type_tags += 'f'
            arg_data += osc_float(arg)
        elif isinstance(arg, str):
            type_tags += 's'
            arg_data += osc_string(arg)
    
    message += osc_string(type_tags)
    message += arg_data
    
    return message

def test_bridge():
    """Test the Rust OSC bridge with simulated TidalCycles messages"""
    
    # Connect to bridge
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    bridge_addr = ('127.0.0.1', 6013)  # Bridge listening port
    
    print("Testing TidalCycles OSC Bridge...")
    print("Make sure the bridge is running: ./target/release/tidal-osc-bridge --debug")
    print("And Neovim is open with the HighTideLight plugin loaded")
    print()
    
    # Test different highlight scenarios using TidalCycles format
    # Format: [sound_name, cps, cycle, orbit, delta, start_pos, end_pos]
    test_cases = [
        {
            'name': 'Stream d1 (orbit 0) - bd sound',
            'sound_name': 'bd',
            'cps': 0.5625,
            'cycle': 1.0,
            'orbit': 0,  # d1
            'delta': 0.5,
            'start_pos': 5,
            'end_pos': 15
        },
        {
            'name': 'Stream d2 (orbit 1) - sn sound',
            'sound_name': 'sn',
            'cps': 0.5625,
            'cycle': 2.0,
            'orbit': 1,  # d2
            'delta': 0.8,
            'start_pos': 10,
            'end_pos': 20
        },
        {
            'name': 'Stream d3 (orbit 2) - hh sound',
            'sound_name': 'hh',
            'cps': 0.5625,
            'cycle': 3.0,
            'orbit': 2,  # d3
            'delta': 1.0,
            'start_pos': 0,
            'end_pos': 30
        }
    ]
    
    for i, test in enumerate(test_cases, 1):
        print(f"Test {i}: {test['name']}")
        
        # Create OSC message in TidalCycles format:
        # [sound_name, cps, cycle, orbit, delta, start_pos, end_pos]
        args = [
            str(test['sound_name']),
            float(test['cps']),
            float(test['cycle']),
            int(test['orbit']),
            float(test['delta']),
            int(test['start_pos']),
            int(test['end_pos'])
        ]
        
        message = create_osc_message('/editor/highlights', args)
        
        try:
            sock.sendto(message, bridge_addr)
            print(f"  ✓ Sent: sound={test['sound_name']}, orbit={test['orbit']}, pos={test['start_pos']}..{test['end_pos']}, delta={test['delta']}")
        except Exception as e:
            print(f"  ✗ Error: {e}")
        
        time.sleep(1.5)  # Pause between tests
    
    print()
    print("High-frequency test (simulating dense patterns)...")
    
    # Test high-frequency events to verify batching (TidalCycles format)
    sounds = ['bd', 'sn', 'hh', 'cp']
    for i in range(10):
        args = [
            str(random.choice(sounds)),         # Random sound name
            float(0.5625),                      # CPS
            float(i + 1),                       # Cycle position
            int(random.randint(0, 3)),          # Random orbit (d1-d4)
            float(0.2),                         # Delta (short duration)
            int(i * 5),                         # Start position
            int(i * 5 + 4)                      # End position
        ]
        
        message = create_osc_message('/editor/highlights', args)
        sock.sendto(message, bridge_addr)
        
        if i % 3 == 0:
            print(f"  ✓ Batch {i//3 + 1}: Sent 3 rapid events")
    
    print()
    print("Test complete! Check Neovim for highlights.")
    print("If you see highlights, the system is working correctly.")
    
    sock.close()

if __name__ == '__main__':
    test_bridge()