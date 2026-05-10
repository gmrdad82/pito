//! `pito search <query>` — wraps `GET /search.json`.
//!
//! Already supported in the TUI; this surface exposes the same engine to
//! scripts via plaintext / JSON output.

use anyhow::Result;

use crate::api::client::PitoClient;
use crate::api::http_client::HttpClient;
use crate::api::models::{SearchHit, Video};
use crate::auth;
use crate::cli::SearchArgs;
use crate::output::{ExitCode, OutputMode, render_table};

pub fn run(args: SearchArgs) -> Result<()> {
    let _ = dotenvy::dotenv();
    let resolved = auth::resolve(
        auth::load_file(&auth::auth_file_path()?)?.as_ref(),
        &auth::Env::system(),
    );
    let client = HttpClient::with_base_url(resolved.base_url.clone());
    let mode = OutputMode::from_json_flag(args.json);

    let results = match client.search(&args.query) {
        Ok(r) => r,
        Err(e) => {
            eprintln!("network error: {}", e);
            std::process::exit(ExitCode::NetworkError.as_i32());
        }
    };

    let limited: Vec<SearchHit<Video>> = results
        .videos
        .into_iter()
        .take(args.limit as usize)
        .collect();

    match mode {
        OutputMode::Json => {
            // Mirror the Rails serializer's flat shape rather than wrapping
            // again — the spec locks the JSON output as the on-the-wire
            // shape minus the limit cap.
            let payload = serde_json::json!({
                "query": args.query,
                "videos": limited,
                "video_total": results.video_total,
                "took_ms": results.took_ms,
            });
            println!("{}", serde_json::to_string(&payload)?);
        }
        OutputMode::Plaintext => {
            print!("{}", render_search_table(&limited));
        }
    }
    Ok(())
}

/// Pure helper: render a search-hits table as plaintext.
pub fn render_search_table(hits: &[SearchHit<Video>]) -> String {
    let rows: Vec<Vec<String>> = hits
        .iter()
        .map(|h| {
            vec![
                h.record.id.to_string(),
                h.record.youtube_video_id.clone(),
                h.record.channel_url.clone().unwrap_or_default(),
                h.record.views.to_string(),
            ]
        })
        .collect();
    render_table(&["id", "youtube_id", "channel_url", "views"], &rows)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_hits() -> Vec<SearchHit<Video>> {
        vec![SearchHit {
            record: Video {
                id: 11,
                youtube_video_id: "dQw4w9WgXcQ".to_string(),
                channel_id: 1,
                channel_url: Some("https://youtube.com/@x".to_string()),
                star: false,
                views: 1234,
                likes: 56,
                comments: 7,
                watch_time_minutes: 89.5,
                last_synced_at: None,
                trend: None,
            },
            highlights: None,
        }]
    }

    #[test]
    fn render_search_table_emits_header_and_rows() {
        let out = render_search_table(&sample_hits());
        let lines: Vec<&str> = out.lines().collect();
        assert_eq!(lines.len(), 3); // header + sep + 1 row
        assert!(lines[0].contains("id"));
        assert!(lines[0].contains("youtube_id"));
        assert!(lines[2].contains("dQw4w9WgXcQ"));
    }

    #[test]
    fn render_search_table_with_no_hits_emits_no_records() {
        let out = render_search_table(&[]);
        assert_eq!(out, "no records.\n");
    }
}
