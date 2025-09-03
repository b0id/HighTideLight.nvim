#!/usr/bin/env python3
"""
Simple OSC test script for HighTideLight.nvim
Sends test messages to verify the bridge is working
"""

import socket
import struct
import time

def create_osc_message(address, *args):
    """Create an OSC message with given address and arguments"""
    # Address (null-terminated, padded to 4-byte boundary)
    addr = address.encode() + b'\x00'
    while len(addr) % 4 != 0:
        addr += b'\x00'
    
    # Type tags (comma-separated, null-terminated, padded)
    types = ','
    arg_data = b''
    
    for arg in args:
        if isinstance(arg, int):
            types += 'i'
            arg_data += struct.pack('>i', arg)
        elif isinstance(arg, float):
            types += 'f' 
            arg_data += struct.pack('>f', arg)
        elif isinstance(arg, str):
            types += 's'
            s = arg.encode() + b'\x00'
            while len(s) % 4 != 0:
                s += b'\x00'
            arg_data += s
    
    types = types.encode() + b'\x00'
    while len(types) % 4 != 0:
        types += b'\x00'
    
    return addr + types + arg_data

def test_bridge():
    """Test the OSC bridge with sample highlight messages"""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    
    # Test messages based on 6-argument format from research
    test_cases = [
        # [stream_id, start_row, start_col, end_row, end_col, duration]
        (1, 1, 5, 1, 10, 500),    # Simple highlight on row 1, cols 5-10
        (2, 2, 0, 2, 15, 750),    # Stream 2 highlight on row 2, cols 0-15
        (1, 3, 8, 3, 12, 400),    # Back to stream 1, different position
        (3, 4, 3, 4, 20, 600),    # Stream 3 highlight
    ]
    
    print("Sending test OSC messages to localhost:6013...")
    
    for i, args in enumerate(test_cases):
        msg = create_osc_message('/editor/highlights', *args)
        sock.sendto(msg, ('localhost', 6013))
        print(f"Sent test {i+1}: stream={args[0]}, pos=({args[1]},{args[2]})-({args[3]},{args[4]}), dur={args[5]}ms")
        time.sleep(1)  # Wait between messages
    
    sock.close()
    print("Test complete. Check Neovim for highlights if plugin is loaded.")

if __name__ == '__main__':
    try:
        test_bridge()
    except Exception as e:
        print(f"Error: {e}")
        print("Make sure the OSC bridge is running on port 6013")