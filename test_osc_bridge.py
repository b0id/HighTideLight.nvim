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
    
    # Test different highlight scenarios
    test_cases = [
        {
            'name': 'Stream d1 highlight',
            'stream_id': 1,
            'start_row': 1,
            'start_col': 5,
            'end_row': 1,
            'end_col': 15,
            'duration': 0.5
        },
        {
            'name': 'Stream d2 highlight',
            'stream_id': 2,
            'start_row': 2,
            'start_col': 10,
            'end_row': 2,
            'end_col': 20,
            'duration': 0.8
        },
        {
            'name': 'Stream d3 multi-highlight',
            'stream_id': 3,
            'start_row': 3,
            'start_col': 0,
            'end_row': 3,
            'end_col': 30,
            'duration': 1.0
        }
    ]
    
    for i, test in enumerate(test_cases, 1):
        print(f"Test {i}: {test['name']}")
        
        # Create OSC message in expected format:
        # [stream_id, start_row, start_col, end_row, end_col, duration]
        args = [
            test['stream_id'],
            test['start_row'],
            test['start_col'], 
            test['end_row'],
            test['end_col'],
            test['duration']
        ]
        
        message = create_osc_message('/editor/highlights', args)
        
        try:
            sock.sendto(message, bridge_addr)
            print(f"  ✓ Sent: stream={test['stream_id']}, pos=({test['start_row']},{test['start_col']})-({test['end_row']},{test['end_col']}), duration={test['duration']}")
        except Exception as e:
            print(f"  ✗ Error: {e}")
        
        time.sleep(1.5)  # Pause between tests
    
    print()
    print("High-frequency test (simulating dense patterns)...")
    
    # Test high-frequency events to verify batching
    for i in range(10):
        args = [
            random.randint(1, 4),  # Random stream
            1,  # Same row
            i * 5,  # Different columns
            1,
            i * 5 + 4,
            0.2  # Short duration
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