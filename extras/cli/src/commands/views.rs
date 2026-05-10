//! `pito views list` — saved views listing.
//!
//! Per the Phase 18 CLI parity spec (Pre-existing Phase 4 surfaces),
//! `pito views list` wraps `GET /saved_views.json`. The endpoint is already
//! shipping (see `app/controllers/saved_views_controller.rb`) and returns
//! the locked Rust shape `[{id, kind, name, url}]` consumed by the
//! `SavedView` struct in `api::models`.
//!
//! `views open` (per the matrix) is intentionally NOT implemented — the
//! row reads `(web-only / TUI-only)` since saved views resolve to web URLs
//! that don't make sense to print as a CLI side-effect.

use anyhow::Result;

use crate::api::client::PitoClient;
use crate::api::http_client::HttpClient;
use crate::api::models::SavedView;
use crate::auth;
use crate::cli::{ViewsArgs, ViewsCommand, ViewsListArgs};
use crate::output::{ExitCode, OutputMode, render_table};

pub fn run(args: ViewsArgs) -> Result<()> {
    match args.command {
        ViewsCommand::List(list) => run_list(list),
    }
}

fn run_list(args: ViewsListArgs) -> Result<()> {
    let _ = dotenvy::dotenv();
    let resolved = auth::resolve(
        auth::load_file(&auth::auth_file_path()?)?.as_ref(),
        &auth::Env::system(),
    );
    let client = HttpClient::with_base_url(resolved.base_url.clone());
    let mode = OutputMode::from_json_flag(args.json);

    let views = match client.get_saved_views() {
        Ok(v) => v,
        Err(e) => {
            eprintln!("network error: {}", e);
            std::process::exit(ExitCode::NetworkError.as_i32());
        }
    };

    let limited: Vec<SavedView> = views.into_iter().take(args.limit as usize).collect();

    match mode {
        OutputMode::Json => {
            println!("{}", serde_json::to_string(&limited)?);
        }
        OutputMode::Plaintext => {
            print!("{}", render_views_table(&limited));
        }
    }
    Ok(())
}

/// Pure helper: render a saved-views table as plaintext. Unit-testable
/// without spinning up a wiremock server.
pub fn render_views_table(views: &[SavedView]) -> String {
    let rows: Vec<Vec<String>> = views
        .iter()
        .map(|v| {
            vec![
                v.id.to_string(),
                v.kind.clone(),
                v.name.clone(),
                v.url.clone(),
            ]
        })
        .collect();
    render_table(&["id", "kind", "name", "url"], &rows)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_views() -> Vec<SavedView> {
        vec![
            SavedView {
                id: 1,
                kind: "dashboard".to_string(),
                name: "Weekly".to_string(),
                url: "/dashboard?range=7d".to_string(),
            },
            SavedView {
                id: 2,
                kind: "channel".to_string(),
                name: "Rust".to_string(),
                url: "/channels/1".to_string(),
            },
        ]
    }

    #[test]
    fn render_views_table_emits_header_and_rows() {
        let out = render_views_table(&sample_views());
        let lines: Vec<&str> = out.lines().collect();
        assert_eq!(lines.len(), 4); // header + sep + 2 rows
        assert!(lines[0].starts_with("id"));
        assert!(lines[0].contains("kind"));
        assert!(lines[0].contains("name"));
        assert!(lines[0].contains("url"));
        assert!(lines[2].contains("dashboard"));
        assert!(lines[3].contains("channel"));
    }

    #[test]
    fn render_views_table_with_no_rows_emits_no_records() {
        let out = render_views_table(&[]);
        assert_eq!(out, "no records.\n");
    }
}
