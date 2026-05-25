use std::io::Read;
use std::io::Write;
use std::net::TcpStream;
use std::sync::mpsc;
use std::thread;
use std::time::Duration;

use crate::api::models::StatusData;

/// Spawn a background thread that connects to Action Cable via WebSocket,
/// subscribes to StatusBarChannel, and forwards status updates.
pub fn spawn(base_url: &str, tx: mpsc::Sender<StatusData>) {
    let ws_url = base_url
        .replace("https://", "wss://")
        .replace("http://", "ws://")
        + "/cable";

    thread::spawn(move || {
        loop {
            let result = try_connect(&ws_url, &tx);
            eprintln!("[cable] disconnected: {:?}", result.err());
            thread::sleep(Duration::from_secs(3));
        }
    });
}

fn try_connect(url: &str, tx: &mpsc::Sender<StatusData>) -> Result<(), Box<dyn std::error::Error>> {
    use openssl::ssl::{SslConnector, SslMethod};

    let host_str = if url.starts_with("wss://") {
        url[6..].split('/').next().unwrap_or("app.pitomd.com").to_string()
    } else {
        url[5..].split('/').next().unwrap_or("localhost").to_string()
    };

    let tcp = TcpStream::connect((host_str.as_str(), 443))?;
    let connector = SslConnector::builder(SslMethod::tls())?.build();
    let mut tls = connector.connect(&host_str, tcp)?;

    let key = generate_ws_key();
    let request = format!(
        "GET /cable HTTP/1.1\r\nHost: {}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: {}\r\nUser-Agent: pito-tui/0.1\r\nOrigin: https://app.pitomd.com\r\n\r\n",
        host_str, key
    );
    tls.write_all(request.as_bytes())?;

    let mut buf = [0u8; 4096];
    let mut response = Vec::new();
    loop {
        let n = tls.read(&mut buf)?;
        if n == 0 { return Err("connection closed".into()); }
        response.extend_from_slice(&buf[..n]);
        if response.windows(4).any(|w| w == b"\r\n\r\n") { break; }
    }

    let resp_str = String::from_utf8_lossy(&response);
    if !resp_str.starts_with("HTTP/1.1 101") {
        return Err(format!("WS handshake failed: {}", resp_str.lines().next().unwrap_or("?")).into());
    }

    // Subscribe to StatusBarChannel
    let subscribe = r#"{"command":"subscribe","identifier":"{\"channel\":\"StatusBarChannel\"}"}"#;
    let frame = build_text_frame(subscribe);
    tls.write_all(&frame)?;

    loop {
        let msg = read_text_frame(&mut tls)?;
        if msg.contains("ping") { continue; }
        if let Ok(v) = serde_json::from_str::<serde_json::Value>(&msg) {
            if v.get("message").and_then(|m| m.get("kind")).and_then(|k| k.as_str()) == Some("status_bar") {
                if let Some(payload) = v.get("message").and_then(|m| m.get("payload")) {
                    let connected = payload.get("connected").and_then(|c| c.as_bool()).unwrap_or(false);
                    let sk = payload.get("sidekiq").and_then(|s| s.as_object());
                    let sd = StatusData {
                        connected,
                        sidekiq_busy: sk.and_then(|s| s.get("busy")).and_then(|v| v.as_u64()).unwrap_or(0),
                        sidekiq_enqueued: sk.and_then(|s| s.get("enqueued")).and_then(|v| v.as_u64()).unwrap_or(0),
                        sidekiq_retry: sk.and_then(|s| s.get("retry")).and_then(|v| v.as_u64()).unwrap_or(0),
                        sidekiq_dead: sk.and_then(|s| s.get("dead")).and_then(|v| v.as_u64()).unwrap_or(0),
                    };
                    let _ = tx.send(sd);
                }
            }
        }
    }
}

fn generate_ws_key() -> String {
    use rand::Rng;
    let mut rng = rand::thread_rng();
    let bytes: [u8; 16] = rng.r#gen();
    base64::Engine::encode(&base64::engine::general_purpose::STANDARD, &bytes)
}

fn build_text_frame(payload: &str) -> Vec<u8> {
    use rand::Rng;
    let mut rng = rand::thread_rng();
    let bytes = payload.as_bytes();
    let len = bytes.len();
    let mut frame = Vec::new();

    frame.push(0x81); // FIN + text
    if len < 126 {
        frame.push(0x80 | len as u8);
    } else if len < 65536 {
        frame.push(0x80 | 126);
        frame.extend_from_slice(&(len as u16).to_be_bytes());
    } else {
        frame.push(0x80 | 127);
        frame.extend_from_slice(&(len as u64).to_be_bytes());
    }

    let mask: [u8; 4] = rng.r#gen();
    frame.extend_from_slice(&mask);
    for (i, b) in bytes.iter().enumerate() { frame.push(b ^ mask[i % 4]); }
    frame
}

fn read_text_frame(stream: &mut dyn Read) -> Result<String, Box<dyn std::error::Error>> {
    let mut hdr = [0u8; 2];
    stream.read_exact(&mut hdr)?;

    let opcode = hdr[0] & 0x0f;
    match opcode {
        0x08 => return Err("close".into()),
        0x09 => { // ping — discard rest, return next frame
            let _ = read_frame_payload(stream, hdr[1])?;
            return read_text_frame(stream);
        }
        0x0a => { // pong — discard
            let _ = read_frame_payload(stream, hdr[1])?;
            return read_text_frame(stream);
        }
        0x01 => {} // text — proceed
        _ => return Err(format!("opcode 0x{:x}", opcode).into()),
    }

    let payload = read_frame_payload(stream, hdr[1])?;
    Ok(String::from_utf8(payload)?)
}

fn read_frame_payload(stream: &mut dyn Read, second: u8) -> Result<Vec<u8>, Box<dyn std::error::Error>> {
    let _masked = (second & 0x80) != 0;
    let mut len = (second & 0x7f) as u64;

    if len == 126 {
        let mut b = [0u8; 2];
        stream.read_exact(&mut b)?;
        len = u16::from_be_bytes(b) as u64;
    } else if len == 127 {
        let mut b = [0u8; 8];
        stream.read_exact(&mut b)?;
        len = u64::from_be_bytes(b);
    }

    // Server-to-client frames are NOT masked
    let mut payload = vec![0u8; len as usize];
    stream.read_exact(&mut payload)?;
    Ok(payload)
}
