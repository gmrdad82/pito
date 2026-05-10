//! `pito notifications {...}` — Phase 21 surfaces.
//!
//! Reads: `list`, `show`, `badge`. Writes: `read`, `unread`,
//! `mark-read`, `mark-all-read`. Per locked decision #2 the single-record
//! read/unread PATCH endpoints return a JSON body with the new unread
//! count; we surface it on the same line as the success message.

use anyhow::Result;

use crate::api::endpoints::EndpointsClient;
use crate::api::endpoints::notifications::{
    NotificationSummary, NotificationsIndexQuery, NotificationsIndexResponse,
};
use crate::auth;
use crate::cli::{
    NotificationsArgs, NotificationsBadgeArgs, NotificationsCommand, NotificationsListArgs,
    NotificationsMarkAllReadArgs, NotificationsMarkReadArgs, NotificationsReadArgs,
    NotificationsShowArgs, NotificationsUnreadArgs,
};
use crate::commands::calendar::parse_ids_csv;
use crate::confirm;
use crate::output::{ExitCode, OutputMode, render_kv, render_table};

pub fn run(args: NotificationsArgs) -> Result<()> {
    match args.command {
        NotificationsCommand::List(a) => run_list(a),
        NotificationsCommand::Show(a) => run_show(a),
        NotificationsCommand::Badge(a) => run_badge(a),
        NotificationsCommand::Read(a) => run_read(a),
        NotificationsCommand::Unread(a) => run_unread(a),
        NotificationsCommand::MarkRead(a) => run_mark_read(a),
        NotificationsCommand::MarkAllRead(a) => run_mark_all_read(a),
    }
}

fn build_client() -> Result<EndpointsClient> {
    let _ = dotenvy::dotenv();
    let resolved = auth::resolve(
        auth::load_file(&auth::auth_file_path()?)?.as_ref(),
        &auth::Env::system(),
    );
    Ok(EndpointsClient::new(
        resolved.base_url.clone(),
        resolved.token.clone(),
    ))
}

// --- list -------------------------------------------------------------------

fn run_list(args: NotificationsListArgs) -> Result<()> {
    let client = build_client()?;
    let q = NotificationsIndexQuery {
        filter: args.filter,
        kind: args.kind,
        severity: args.severity,
        page: args.page,
    };
    let mode = OutputMode::from_json_flag(args.json);
    let resp = match client.notifications_list(&q) {
        Ok(r) => r,
        Err(e) => {
            eprintln!("network error: {}", e);
            std::process::exit(ExitCode::NetworkError.as_i32());
        }
    };
    let limited: Vec<NotificationSummary> = resp
        .notifications
        .iter()
        .take(args.limit as usize)
        .cloned()
        .collect();
    match mode {
        OutputMode::Json => {
            let mut value = serde_json::to_value(&resp)?;
            if let serde_json::Value::Object(ref mut map) = value {
                map.insert("notifications".to_string(), serde_json::to_value(&limited)?);
            }
            println!("{}", serde_json::to_string(&value)?);
        }
        OutputMode::Plaintext => {
            print!("{}", render_list(&resp, &limited));
        }
    }
    Ok(())
}

pub fn render_list(
    resp: &NotificationsIndexResponse,
    notifications: &[NotificationSummary],
) -> String {
    let mut out = String::new();
    out.push_str(&format!(
        "page {}/{} (total {}, per_page {}) | unread_count {} has_failures {}\n",
        resp.page,
        resp.total_pages,
        resp.total,
        resp.per_page,
        resp.unread_count,
        if resp.has_failures { "yes" } else { "no" },
    ));
    out.push_str(&render_notifications_table(notifications));
    out
}

pub fn render_notifications_table(notifications: &[NotificationSummary]) -> String {
    let rows: Vec<Vec<String>> = notifications
        .iter()
        .map(|n| {
            vec![
                n.id.to_string(),
                n.kind.clone(),
                n.severity.clone(),
                if n.read { "yes" } else { "no" }.to_string(),
                n.title.clone().unwrap_or_default(),
                n.created_at.clone().unwrap_or_default(),
            ]
        })
        .collect();
    render_table(
        &["id", "kind", "severity", "read", "title", "created_at"],
        &rows,
    )
}

// --- show -------------------------------------------------------------------

fn run_show(args: NotificationsShowArgs) -> Result<()> {
    let client = build_client()?;
    let mode = OutputMode::from_json_flag(args.json);
    let resp = match client.notifications_show(args.id) {
        Ok(r) => r,
        Err(e) => {
            let msg = format!("{}", e);
            eprintln!("network error: {}", msg);
            if msg.contains("404") {
                std::process::exit(ExitCode::NotFound.as_i32());
            }
            std::process::exit(ExitCode::NetworkError.as_i32());
        }
    };
    match mode {
        OutputMode::Json => {
            println!("{}", serde_json::to_string(&resp)?);
        }
        OutputMode::Plaintext => {
            print!("{}", render_notification_detail(&resp.notification));
        }
    }
    Ok(())
}

pub fn render_notification_detail(n: &NotificationSummary) -> String {
    let mut rows: Vec<(&str, String)> = vec![
        ("id", n.id.to_string()),
        ("kind", n.kind.clone()),
        ("severity", n.severity.clone()),
        ("read", if n.read { "yes" } else { "no" }.to_string()),
    ];
    if let Some(t) = &n.title {
        rows.push(("title", t.clone()));
    }
    if let Some(b) = &n.body {
        rows.push(("body", b.clone()));
    }
    if let Some(u) = &n.url {
        rows.push(("url", u.clone()));
    }
    if let Some(f) = &n.fires_at {
        rows.push(("fires_at", f.clone()));
    }
    if let Some(t) = &n.in_app_read_at {
        rows.push(("in_app_read_at", t.clone()));
    }
    if let Some(t) = &n.discord_delivered_at {
        rows.push(("discord_delivered_at", t.clone()));
    }
    if let Some(t) = &n.slack_delivered_at {
        rows.push(("slack_delivered_at", t.clone()));
    }
    if let Some(r) = n.retry_count {
        rows.push(("retry_count", r.to_string()));
    }
    if let Some(e) = &n.last_error {
        rows.push(("last_error", e.clone()));
    }
    if let Some(c) = &n.created_at {
        rows.push(("created_at", c.clone()));
    }
    render_kv(&rows)
}

// --- badge ------------------------------------------------------------------

fn run_badge(args: NotificationsBadgeArgs) -> Result<()> {
    let client = build_client()?;
    let mode = OutputMode::from_json_flag(args.json);
    let resp = match client.notifications_badge() {
        Ok(r) => r,
        Err(e) => {
            eprintln!("network error: {}", e);
            std::process::exit(ExitCode::NetworkError.as_i32());
        }
    };
    match mode {
        OutputMode::Json => {
            println!("{}", serde_json::to_string(&resp)?);
        }
        OutputMode::Plaintext => {
            println!(
                "unread_count {} | has_failures {}",
                resp.unread_count,
                if resp.has_failures { "yes" } else { "no" }
            );
        }
    }
    Ok(())
}

// --- read / unread ----------------------------------------------------------

fn run_read(args: NotificationsReadArgs) -> Result<()> {
    let client = build_client()?;
    let mode = OutputMode::from_json_flag(args.json);
    let resp = match client.notification_mark_read_single(args.id) {
        Ok(r) => r,
        Err(e) => {
            eprintln!("network error: {}", e);
            std::process::exit(ExitCode::NetworkError.as_i32());
        }
    };
    match mode {
        OutputMode::Json => {
            println!("{}", serde_json::to_string(&resp)?);
        }
        OutputMode::Plaintext => {
            println!(
                "marked {} read. unread_count {}.",
                resp.id, resp.unread_count
            );
        }
    }
    Ok(())
}

fn run_unread(args: NotificationsUnreadArgs) -> Result<()> {
    let client = build_client()?;
    let mode = OutputMode::from_json_flag(args.json);
    let resp = match client.notification_mark_unread_single(args.id) {
        Ok(r) => r,
        Err(e) => {
            eprintln!("network error: {}", e);
            std::process::exit(ExitCode::NetworkError.as_i32());
        }
    };
    match mode {
        OutputMode::Json => {
            println!("{}", serde_json::to_string(&resp)?);
        }
        OutputMode::Plaintext => {
            println!(
                "marked {} unread. unread_count {}.",
                resp.id, resp.unread_count
            );
        }
    }
    Ok(())
}

// --- mark-read (bulk) -------------------------------------------------------

fn run_mark_read(args: NotificationsMarkReadArgs) -> Result<()> {
    let ids = match parse_ids_csv(&args.ids) {
        Ok(v) if v.is_empty() => {
            eprintln!("mark-read: at least one id is required");
            std::process::exit(ExitCode::Validation.as_i32());
        }
        Ok(v) => v,
        Err(e) => {
            eprintln!("mark-read: {}", e);
            std::process::exit(ExitCode::Validation.as_i32());
        }
    };
    let mode = OutputMode::from_json_flag(args.json);
    let client = build_client()?;
    let resp = match client.notifications_mark_read_bulk(&ids) {
        Ok(r) => r,
        Err(e) => {
            eprintln!("network error: {}", e);
            std::process::exit(ExitCode::NetworkError.as_i32());
        }
    };
    match mode {
        OutputMode::Json => {
            println!("{}", serde_json::to_string(&resp)?);
        }
        OutputMode::Plaintext => {
            println!(
                "marked {} read. unread_count {} has_failures {}",
                resp.marked,
                resp.unread_count,
                if resp.has_failures { "yes" } else { "no" }
            );
        }
    }
    Ok(())
}

// --- mark-all-read ----------------------------------------------------------

fn run_mark_all_read(args: NotificationsMarkAllReadArgs) -> Result<()> {
    let confirmed = confirm::is_confirmed(args.confirm);
    let mode = OutputMode::from_json_flag(args.json);
    if !confirmed {
        match mode {
            OutputMode::Json => {
                let payload = serde_json::json!({
                    "preview": true,
                    "message": "rerun with --confirm yes to mark every notification read.",
                });
                println!("{}", serde_json::to_string(&payload)?);
            }
            OutputMode::Plaintext => {
                println!("would mark every notification read.");
                println!("rerun with --confirm yes to apply.");
            }
        }
        return Ok(());
    }
    let client = build_client()?;
    let resp = match client.notifications_mark_all_read() {
        Ok(r) => r,
        Err(e) => {
            eprintln!("network error: {}", e);
            std::process::exit(ExitCode::NetworkError.as_i32());
        }
    };
    match mode {
        OutputMode::Json => {
            println!("{}", serde_json::to_string(&resp)?);
        }
        OutputMode::Plaintext => {
            println!(
                "marked {} read. unread_count {} has_failures {}",
                resp.marked,
                resp.unread_count,
                if resp.has_failures { "yes" } else { "no" }
            );
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample() -> NotificationSummary {
        NotificationSummary {
            id: 91,
            kind: "video_published".to_string(),
            severity: "success".to_string(),
            event_type: Some("video.published".to_string()),
            title: Some("video published".to_string()),
            body: Some("...".to_string()),
            url: Some("/videos/abc".to_string()),
            fires_at: Some("2026-05-10T17:00:00Z".to_string()),
            in_app_read_at: None,
            read: false,
            discord_delivered_at: None,
            slack_delivered_at: None,
            retry_count: Some(0),
            last_error: None,
            created_at: Some("2026-05-10T17:00:00Z".to_string()),
        }
    }

    #[test]
    fn render_notifications_table_emits_header_and_rows() {
        let out = render_notifications_table(&[sample()]);
        let lines: Vec<&str> = out.lines().collect();
        assert_eq!(lines.len(), 3);
        assert!(lines[0].contains("id"));
        assert!(lines[0].contains("kind"));
        assert!(lines[0].contains("read"));
        assert!(lines[2].contains("video_published"));
        assert!(lines[2].contains("success"));
        // Boundary rule: read renders as "no".
        assert!(lines[2].contains("no"));
    }

    #[test]
    fn render_notifications_table_empty_emits_no_records() {
        let out = render_notifications_table(&[]);
        assert_eq!(out, "no records.\n");
    }

    #[test]
    fn render_notification_detail_includes_known_keys() {
        let out = render_notification_detail(&sample());
        assert!(out.contains("id"));
        assert!(out.contains("kind"));
        assert!(out.contains("severity"));
        assert!(out.contains("video_published"));
    }
}
