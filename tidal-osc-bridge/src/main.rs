// High-performance OSC bridge for tidal-highlights.nvim
// Based on comprehensive architectural research

use clap::Parser;
use log::{debug, error, info, warn};
use rosc::{OscMessage, OscPacket, OscType};
use std::io::ErrorKind;
use std::net::UdpSocket;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

#[derive(Parser, Debug)]
#[command(author, version, about, long_about = None)]
struct Args {
    /// Port to listen for OSC messages
    #[arg(short, long, default_value_t = 6013)]
    port: u16,
    
    /// Enable debug logging
    #[arg(short, long)]
    debug: bool,
    
    /// OSC address to listen for
    #[arg(long, default_value = "/editor/highlights")]
    address: String,
    
    /// Forward highlights to Neovim OSC port
    #[arg(long, default_value_t = 6011)]
    neovim_port: u16,
}

#[derive(Debug, serde::Serialize)]
struct HighlightEvent {
    stream_id: i32,
    start_row: i32,
    start_col: i32,
    end_row: i32,
    end_col: i32,
    duration: f32,
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args = Args::parse();
    
    // Initialize logging
    if args.debug {
        env_logger::Builder::from_default_env()
            .filter_level(log::LevelFilter::Debug)
            .init();
    } else {
        env_logger::Builder::from_default_env()
            .filter_level(log::LevelFilter::Info)
            .init();
    }
    
    info!("TidalOSC Bridge v{}", env!("CARGO_PKG_VERSION"));
    info!("Listening for OSC messages on port {}", args.port);
    info!("Monitoring address: {}", args.address);
    info!("Forwarding to Neovim on port {}", args.neovim_port);
    
    // Bind UDP socket for receiving
    let socket = UdpSocket::bind(format!("127.0.0.1:{}", args.port))?;
    info!("Successfully bound to 127.0.0.1:{}", args.port);
    
    // Create UDP socket for sending to Neovim
    let neovim_socket = UdpSocket::bind("127.0.0.1:0")?; // Bind to any available port
    let neovim_addr = format!("127.0.0.1:{}", args.neovim_port);
    
    // Setup signal handling for graceful shutdown
    let running = Arc::new(AtomicBool::new(true));
    let r = running.clone();
    
    ctrlc::set_handler(move || {
        info!("Received interrupt signal, shutting down...");
        r.store(false, Ordering::SeqCst);
    })?;
    
    // Main OSC processing loop
    let mut buf = [0u8; rosc::decoder::MTU];
    
    while running.load(Ordering::SeqCst) {
        // Set a timeout to check for shutdown signal
        socket.set_read_timeout(Some(std::time::Duration::from_millis(100)))?;
        
        match socket.recv_from(&mut buf) {
            Ok((size, _addr)) => {
                debug!("Received {} bytes", size);
                
                if let Err(e) = process_osc_data(&buf[..size], &args.address, &neovim_socket, &neovim_addr) {
                    warn!("Failed to process OSC data: {}", e);
                }
            }
            Err(ref e) if e.kind() == ErrorKind::WouldBlock => {
                // Timeout reached, continue loop to check shutdown signal
                continue;
            }
            Err(e) => {
                error!("Socket receive error: {}", e);
                break;
            }
        }
    }
    
    info!("TidalOSC Bridge shutting down");
    Ok(())
}

fn process_osc_data(data: &[u8], target_address: &str, neovim_socket: &UdpSocket, neovim_addr: &str) -> Result<(), Box<dyn std::error::Error>> {
    let packet = rosc::decoder::decode_udp(data)?.1;
    
    match packet {
        OscPacket::Message(msg) => {
            process_osc_message(msg, target_address, neovim_socket, neovim_addr)?;
        }
        OscPacket::Bundle(bundle) => {
            debug!("Processing OSC bundle with {} messages", bundle.content.len());
            for packet in bundle.content {
                match packet {
                    OscPacket::Message(msg) => {
                        process_osc_message(msg, target_address, neovim_socket, neovim_addr)?;
                    }
                    OscPacket::Bundle(_) => {
                        warn!("Nested bundles not supported");
                    }
                }
            }
        }
    }
    
    Ok(())
}

fn process_osc_message(msg: OscMessage, target_address: &str, neovim_socket: &UdpSocket, neovim_addr: &str) -> Result<(), Box<dyn std::error::Error>> {
    if msg.addr != target_address {
        debug!("Ignoring message for address: {}", msg.addr);
        return Ok(());
    }
    
    debug!("Processing message: {} with {} args", msg.addr, msg.args.len());
    
    // Parse arguments according to Tidal highlight format
    // Expected: [stream_id, start_row, start_col, end_row, end_col, duration]
    if msg.args.len() < 6 {
        warn!("Insufficient arguments: expected 6, got {}", msg.args.len());
        return Ok(());
    }
    
    let highlight_event = HighlightEvent {
        stream_id: extract_int(&msg.args[0])?,
        start_row: extract_int(&msg.args[1])?,
        start_col: extract_int(&msg.args[2])?,
        end_row: extract_int(&msg.args[3])?,
        end_col: extract_int(&msg.args[4])?,
        duration: extract_float(&msg.args[5])?,
    };
    
    debug!("Parsed highlight event: {:?}", highlight_event);
    
    // Forward to Neovim via OSC
    forward_to_neovim(highlight_event, neovim_socket, neovim_addr)?;
    
    Ok(())
}

fn extract_int(arg: &OscType) -> Result<i32, Box<dyn std::error::Error>> {
    match arg {
        OscType::Int(i) => Ok(*i),
        OscType::Long(l) => Ok(*l as i32),
        OscType::Float(f) => Ok(*f as i32),
        OscType::Double(d) => Ok(*d as i32),
        _ => Err(format!("Cannot convert {:?} to int", arg).into()),
    }
}

fn extract_float(arg: &OscType) -> Result<f32, Box<dyn std::error::Error>> {
    match arg {
        OscType::Float(f) => Ok(*f),
        OscType::Double(d) => Ok(*d as f32),
        OscType::Int(i) => Ok(*i as f32),
        OscType::Long(l) => Ok(*l as f32),
        _ => Err(format!("Cannot convert {:?} to float", arg).into()),
    }
}

fn forward_to_neovim(event: HighlightEvent, neovim_socket: &UdpSocket, neovim_addr: &str) -> Result<(), Box<dyn std::error::Error>> {
    // Convert to OSC message format that the existing Lua OSC handler expects
    // Format: [stream_id, duration, cycle, start_col, event_id, end_col]
    // We'll generate a unique event_id based on timestamp and position
    let event_id = (event.start_row * 1000 + event.start_col) as i32;
    let cycle = 1.0; // Default cycle value
    
    let osc_msg = OscMessage {
        addr: "/editor/highlight".to_string(),
        args: vec![
            OscType::Int(event.stream_id),
            OscType::Float(event.duration),
            OscType::Float(cycle),
            OscType::Int(event.start_col),
            OscType::Int(event_id),
            OscType::Int(event.end_col),
        ],
    };
    
    // Encode and send
    let packet = OscPacket::Message(osc_msg);
    let encoded = rosc::encoder::encode(&packet)?;
    
    neovim_socket.send_to(&encoded, neovim_addr)?;
    
    debug!("Forwarded to Neovim: stream={}, row={}, cols={}..{}, duration={}", 
           event.stream_id, event.start_row, event.start_col, event.end_col, event.duration);
    
    Ok(())
}

// Error handling for ctrlc dependency
#[cfg(not(target_family = "unix"))]
mod ctrlc {
    use std::sync::Arc;
    use std::sync::atomic::AtomicBool;
    
    pub fn set_handler<F>(_handler: F) -> Result<(), Box<dyn std::error::Error>>
    where
        F: Fn() + 'static + Send,
    {
        // Stub implementation for non-Unix platforms
        Ok(())
    }
}

#[cfg(target_family = "unix")]
use ctrlc;