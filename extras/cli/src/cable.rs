use std::sync::mpsc;
use std::thread;
use std::time::Duration;

use crate::api::models::StatusData;

/// Spawn a background thread that connects to the Action Cable WebSocket
/// endpoint and subscribes to StatusBarChannel for live status updates.
/// Uses tungstenite with rustls-tls (matching the reqwest TLS setup).
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
    let (mut ws, _) = tungstenite::connect(url)?;

    let subscribe = r#"{"command":"subscribe","identifier":"{\"channel\":\"StatusBarChannel\"}"}"#;
    ws.send(tungstenite::Message::Text(subscribe.into()))?;

    loop {
        let msg = ws.read()?;
        if let tungstenite::Message::Text(text) = msg {
            if text.contains("ping") { continue; }
            if let Ok(v) = serde_json::from_str::<serde_json::Value>(&text) {
                if v.get("message").and_then(|m| m.get("kind")).and_then(|k| k.as_str()) == Some("status_bar") {
                    if let Some(payload) = v.get("message").and_then(|m| m.get("payload")) {
                        let connected = payload.get("connected").and_then(|c| c.as_bool()).unwrap_or(false);
                        let sidekiq = payload.get("sidekiq").and_then(|s| s.as_object());
                        let busy = sidekiq.and_then(|s| s.get("busy")).and_then(|v| v.as_u64()).unwrap_or(0);
                        let enqueued = sidekiq.and_then(|s| s.get("enqueued")).and_then(|v| v.as_u64()).unwrap_or(0);
                        let retry = sidekiq.and_then(|s| s.get("retry")).and_then(|v| v.as_u64()).unwrap_or(0);
                        let dead = sidekiq.and_then(|s| s.get("dead")).and_then(|v| v.as_u64()).unwrap_or(0);
                        let sd = StatusData { connected, sidekiq_busy: busy, sidekiq_enqueued: enqueued, sidekiq_retry: retry, sidekiq_dead: dead };
                        let _ = tx.send(sd);
                    }
                }
            }
        }
    }
}
