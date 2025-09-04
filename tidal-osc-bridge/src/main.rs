// Efficient OSC bridge for TidalCycles highlighting
// Implements async batching for high-performance event handling

use clap::Parser;
use log::{debug, error, info, warn};
use rosc::{OscMessage, OscPacket, OscType};
use std::collections::VecDeque;
use std::sync::Arc;
use std::time::Duration;
use tokio::net::UdpSocket;
use tokio::sync::Mutex;
use tokio::time::interval;

#[derive(Parser, Debug)]
#[command(author, version, about, long_about = None)]
struct Args {
    /// Port to listen for OSC messages from TidalCycles
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

    /// Batch interval in milliseconds (default 10ms for high performance)
    #[arg(long, default_value_t = 10)]
    batch_interval_ms: u64,
}

#[derive(Debug, Clone)]
struct HighlightEvent {
    stream_id: i32,
    start_row: i32,
    start_col: i32,
    end_row: i32,
    end_col: i32,
    duration: f32,
    sound_name: String,  // Store the sound name for future use
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
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
    
    info!("TidalCycles OSC Bridge v{}", env!("CARGO_PKG_VERSION"));
    info!("Listening for OSC messages on port {}", args.port);
    info!("Monitoring address: {}", args.address);
    info!("Forwarding to Neovim on port {}", args.neovim_port);
    info!("Batch interval: {}ms", args.batch_interval_ms);
    
    // Create sockets
    let receive_socket = UdpSocket::bind(format!("127.0.0.1:{}", args.port)).await?;
    let send_socket = Arc::new(UdpSocket::bind("127.0.0.1:0").await?);
    let neovim_addr = format!("127.0.0.1:{}", args.neovim_port);
    
    info!("Successfully bound to 127.0.0.1:{}", args.port);
    
    // Event buffer for batching (the "shock absorber" from the senior engineer's design)
    let event_buffer = Arc::new(Mutex::new(VecDeque::<HighlightEvent>::new()));
    
    // Spawn the batching task
    let buffer_clone = event_buffer.clone();
    let send_socket_clone = send_socket.clone();
    let neovim_addr_clone = neovim_addr.clone();
    let debug_mode = args.debug;
    
    let batch_task = tokio::spawn(async move {
        let mut batch_interval = interval(Duration::from_millis(args.batch_interval_ms));
        
        loop {
            batch_interval.tick().await;
            
            let mut buffer = buffer_clone.lock().await;
            if buffer.is_empty() {
                continue;
            }
            
            // Collect all pending events into a batch
            let events: Vec<HighlightEvent> = buffer.drain(..).collect();
            drop(buffer); // Release lock quickly
            
            if debug_mode {
                debug!("Processing batch of {} events", events.len());
            }
            
            // Send batch to Neovim
            for event in events {
                if let Err(e) = forward_to_neovim(&event, &send_socket_clone, &neovim_addr_clone).await {
                    warn!("Failed to forward event: {}", e);
                }
            }
        }
    });
    
    // Main OSC processing loop
    let mut buf = [0u8; rosc::decoder::MTU];
    
    info!("Bridge running - listening for TidalCycles OSC messages...");
    
    loop {
        tokio::select! {
            // Handle incoming OSC messages
            result = receive_socket.recv_from(&mut buf) => {
                match result {
                    Ok((size, _addr)) => {
                        if let Err(e) = process_osc_data(
                            &buf[..size], 
                            &args.address, 
                            event_buffer.clone()
                        ).await {
                            warn!("Failed to process OSC data: {}", e);
                        }
                    }
                    Err(e) => {
                        error!("Socket receive error: {}", e);
                        break;
                    }
                }
            }
            
            // Handle Ctrl+C gracefully
            _ = tokio::signal::ctrl_c() => {
                info!("Received interrupt signal, shutting down...");
                break;
            }
        }
    }
    
    // Clean shutdown
    batch_task.abort();
    info!("TidalCycles OSC Bridge shut down");
    Ok(())
}

async fn process_osc_data(
    data: &[u8], 
    target_address: &str, 
    event_buffer: Arc<Mutex<VecDeque<HighlightEvent>>>
) -> Result<(), Box<dyn std::error::Error>> {
    let packet = rosc::decoder::decode_udp(data)?.1;
    
    match packet {
        OscPacket::Message(msg) => {
            process_osc_message(msg, target_address, event_buffer).await?;
        }
        OscPacket::Bundle(bundle) => {
            debug!("Processing OSC bundle with {} messages", bundle.content.len());
            for packet in bundle.content {
                match packet {
                    OscPacket::Message(msg) => {
                        process_osc_message(msg, target_address, event_buffer.clone()).await?;
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

async fn process_osc_message(
    msg: OscMessage, 
    target_address: &str, 
    event_buffer: Arc<Mutex<VecDeque<HighlightEvent>>>
) -> Result<(), Box<dyn std::error::Error>> {
    if msg.addr != target_address {
        debug!("Ignoring message for address: {}", msg.addr);
        return Ok(());
    }
    
    debug!("Processing message: {} with {} args", msg.addr, msg.args.len());
    
    // Parse arguments from TidalCycles: [sound_name, cps, cycle, orbit, delta, start_pos, end_pos]
    if msg.args.len() < 7 {
        warn!("Insufficient arguments: expected 7, got {}", msg.args.len());
        return Ok(());
    }
    
    // Extract TidalCycles format
    let sound_name = extract_string(&msg.args[0])?;
    let _cps = extract_float(&msg.args[1])?;        // Cycles per second (tempo)
    let _cycle = extract_float(&msg.args[2])?;      // Pattern position
    let orbit = extract_int(&msg.args[3])?;         // Stream (d1=0, d2=1, etc.)
    let delta = extract_float(&msg.args[4])?;       // Duration
    let start_pos = extract_int(&msg.args[5])?;     // Start position
    let end_pos = extract_int(&msg.args[6])?;       // End position
    
    let highlight_event = HighlightEvent {
        stream_id: orbit + 1,  // Convert orbit 0->d1, orbit 1->d2, etc.
        start_row: 0,          // Default to row 0 for now
        start_col: start_pos,
        end_row: 0,            // Default to same row
        end_col: end_pos,
        duration: delta,
        sound_name,
    };
    
    debug!("Parsed highlight event: {:?}", highlight_event);
    
    // Add to buffer for batched processing (non-blocking)
    let mut buffer = event_buffer.lock().await;
    buffer.push_back(highlight_event);
    
    Ok(())
}

async fn forward_to_neovim(
    event: &HighlightEvent, 
    socket: &UdpSocket, 
    neovim_addr: &str
) -> Result<(), Box<dyn std::error::Error>> {
    // Format expected by lua/tidal-highlight/init.lua handle_osc_highlight()
    // 6-argument format: [stream_id, duration, cycle, start_col, event_id, end_col]
    let event_id = (event.start_row * 1000 + event.start_col) as i32;
    let cycle = 1.0; // Default cycle value
    
    let osc_msg = OscMessage {
        addr: "/editor/highlights".to_string(),
        args: vec![
            OscType::Int(event.stream_id),
            OscType::Float(event.duration),
            OscType::Float(cycle),
            OscType::Int(event.start_col), // Keep 0-indexed, Lua will convert
            OscType::Int(event_id),
            OscType::Int(event.end_col),   // Keep 0-indexed, Lua will convert
        ],
    };
    
    // Encode and send
    let packet = OscPacket::Message(osc_msg);
    let encoded = rosc::encoder::encode(&packet)?;
    
    socket.send_to(&encoded, neovim_addr).await?;
    
    debug!("Forwarded to Neovim: stream={}, row={}, cols={}..{}, duration={}", 
           event.stream_id, event.start_row, event.start_col, event.end_col, event.duration);
    
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

fn extract_string(arg: &OscType) -> Result<String, Box<dyn std::error::Error>> {
    match arg {
        OscType::String(s) => Ok(s.clone()),
        _ => Err(format!("Cannot convert {:?} to string", arg).into()),
    }
}