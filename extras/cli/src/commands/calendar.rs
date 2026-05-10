//! `pito calendar {...}` — Phase 21 surfaces.
//!
//! Reads: `schedule`, `month`, `show`. Writes: `create`, `update`, `note`,
//! `cancel`. Write paths follow the project's bulk-as-foundation +
//! `--confirm yes` discipline; `cancel` is a soft-cancel against the
//! `DELETE /deletions/calendar_entry/:ids.json` endpoint.

use anyhow::Result;
use serde_json::{Map, Value};

use crate::api::endpoints::EndpointsClient;
use crate::api::endpoints::calendar::{
    CalendarEntryDetail, CalendarEntrySoftCancelResponse, CalendarEntrySummary, CalendarMonthQuery,
    CalendarMonthResponse, CalendarScheduleQuery, CalendarScheduleResponse,
};
use crate::auth;
use crate::cli::{
    CalendarArgs, CalendarCancelArgs, CalendarCommand, CalendarCreateArgs, CalendarMonthArgs,
    CalendarNoteArgs, CalendarScheduleArgs, CalendarShowArgs, CalendarUpdateArgs,
};
use crate::confirm::{self, YesNo};
use crate::output::{ExitCode, OutputMode, render_kv, render_table};

pub fn run(args: CalendarArgs) -> Result<()> {
    match args.command {
        CalendarCommand::Schedule(a) => run_schedule(a),
        CalendarCommand::Month(a) => run_month(a),
        CalendarCommand::Show(a) => run_show(a),
        CalendarCommand::Create(a) => run_create(a),
        CalendarCommand::Update(a) => run_update(a),
        CalendarCommand::Note(a) => run_note(a),
        CalendarCommand::Cancel(a) => run_cancel(a),
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

// --- schedule ---------------------------------------------------------------

fn run_schedule(args: CalendarScheduleArgs) -> Result<()> {
    let client = build_client()?;
    let q = CalendarScheduleQuery {
        types: args.types,
        source: args.source,
        state: args.state,
        page: args.page,
    };
    let mode = OutputMode::from_json_flag(args.json);
    let resp = match client.calendar_schedule(&q) {
        Ok(r) => r,
        Err(e) => {
            eprintln!("network error: {}", e);
            std::process::exit(ExitCode::NetworkError.as_i32());
        }
    };
    let entries: Vec<CalendarEntrySummary> = resp
        .entries
        .iter()
        .take(args.limit as usize)
        .cloned()
        .collect();
    match mode {
        OutputMode::Json => {
            // Echo the locked wire shape, but with the rendered limit applied.
            let mut value = serde_json::to_value(&resp)?;
            if let Value::Object(ref mut map) = value {
                map.insert("entries".to_string(), serde_json::to_value(&entries)?);
            }
            println!("{}", serde_json::to_string(&value)?);
        }
        OutputMode::Plaintext => {
            print!("{}", render_schedule(&resp, &entries));
        }
    }
    Ok(())
}

pub fn render_schedule(
    resp: &CalendarScheduleResponse,
    entries: &[CalendarEntrySummary],
) -> String {
    let mut out = String::new();
    out.push_str(&format!(
        "page {}/{} (total {}, per_page {})\n",
        resp.page, resp.total_pages, resp.total, resp.per_page
    ));
    out.push_str(&render_entries_table(entries));
    out
}

pub fn render_entries_table(entries: &[CalendarEntrySummary]) -> String {
    let rows: Vec<Vec<String>> = entries
        .iter()
        .map(|e| {
            vec![
                e.id.to_string(),
                e.entry_type.clone(),
                e.title.clone(),
                e.starts_at.clone().unwrap_or_default(),
                e.state.clone(),
                if e.read_only { "yes" } else { "no" }.to_string(),
            ]
        })
        .collect();
    render_table(
        &[
            "id",
            "entry_type",
            "title",
            "starts_at",
            "state",
            "read_only",
        ],
        &rows,
    )
}

// --- month ------------------------------------------------------------------

fn run_month(args: CalendarMonthArgs) -> Result<()> {
    let client = build_client()?;
    let q = CalendarMonthQuery {
        types: args.types,
        state: args.state,
    };
    let mode = OutputMode::from_json_flag(args.json);
    let resp = match client.calendar_month(args.year, args.month, &q) {
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
            print!("{}", render_month(&resp));
        }
    }
    Ok(())
}

pub fn render_month(resp: &CalendarMonthResponse) -> String {
    let mut out = String::new();
    out.push_str(&format!("{}-{:02}\n", resp.year, resp.month));
    if let Some(tz) = &resp.install_tz {
        out.push_str(&format!("install_tz: {}\n", tz));
    }
    if resp.buckets.is_empty() {
        out.push_str("no entries this month.\n");
        return out;
    }
    for (date, entries) in &resp.buckets {
        out.push_str(&format!("\n{} ({} entries)\n", date, entries.len()));
        out.push_str(&render_entries_table(entries));
    }
    out
}

// --- show -------------------------------------------------------------------

fn run_show(args: CalendarShowArgs) -> Result<()> {
    let client = build_client()?;
    let mode = OutputMode::from_json_flag(args.json);
    let resp = match client.calendar_entry_show(args.id) {
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
            print!("{}", render_entry_detail(&resp.entry));
            if !resp.dispatch_declarations.is_empty() {
                println!();
                println!(
                    "dispatch declarations: {}",
                    resp.dispatch_declarations.len()
                );
            }
        }
    }
    Ok(())
}

pub fn render_entry_detail(e: &CalendarEntryDetail) -> String {
    let mut rows: Vec<(&str, String)> = vec![
        ("id", e.id.to_string()),
        ("entry_type", e.entry_type.clone()),
        ("title", e.title.clone()),
        ("state", e.state.clone()),
    ];
    if let Some(s) = &e.starts_at {
        rows.push(("starts_at", s.clone()));
    }
    if let Some(s) = &e.ends_at {
        rows.push(("ends_at", s.clone()));
    }
    rows.push(("all_day", if e.all_day { "yes" } else { "no" }.to_string()));
    rows.push((
        "read_only",
        if e.read_only { "yes" } else { "no" }.to_string(),
    ));
    if let Some(tz) = &e.timezone {
        rows.push(("timezone", tz.clone()));
    }
    if let Some(src) = &e.source {
        rows.push(("source", src.clone()));
    }
    if let Some(p) = e.parent_entry_id {
        rows.push(("parent_entry_id", p.to_string()));
    }
    if !e.child_entry_ids.is_empty() {
        let ids: Vec<String> = e.child_entry_ids.iter().map(|i| i.to_string()).collect();
        rows.push(("child_entry_ids", ids.join(",")));
    }
    if let Some(g) = e.game_id {
        rows.push(("game_id", g.to_string()));
    }
    if let Some(v) = e.video_id {
        rows.push(("video_id", v.to_string()));
    }
    if let Some(c) = e.channel_id {
        rows.push(("channel_id", c.to_string()));
    }
    if let Some(p) = e.project_id {
        rows.push(("project_id", p.to_string()));
    }
    render_kv(&rows)
}

// --- create -----------------------------------------------------------------

/// Pure helper: build the inner `calendar_entry` body from a
/// `CalendarCreateArgs`. The serializer keeps yes/no strings (the wire
/// boundary requires them) and skips fields the caller did not provide.
pub fn build_create_inner(args: &CalendarCreateArgs) -> Value {
    let mut inner: Map<String, Value> = Map::new();
    inner.insert(
        "entry_type".to_string(),
        Value::String(args.entry_type.clone()),
    );
    inner.insert("title".to_string(), Value::String(args.title.clone()));
    inner.insert(
        "starts_at".to_string(),
        Value::String(args.starts_at.clone()),
    );
    if let Some(e) = &args.ends_at {
        inner.insert("ends_at".to_string(), Value::String(e.clone()));
    }
    if let Some(tz) = &args.timezone {
        inner.insert("timezone".to_string(), Value::String(tz.clone()));
    }
    if let Some(all_day) = args.all_day {
        inner.insert(
            "all_day".to_string(),
            Value::String(yes_no_string(all_day).to_string()),
        );
    }
    if let Some(d) = &args.description {
        inner.insert("description".to_string(), Value::String(d.clone()));
    }
    if let Some(pid) = args.parent_entry_id {
        inner.insert("parent_entry_id".to_string(), Value::Number(pid.into()));
    }
    Value::Object(inner)
}

fn yes_no_string(value: YesNo) -> &'static str {
    value.as_wire()
}

fn run_create(args: CalendarCreateArgs) -> Result<()> {
    let inner = build_create_inner(&args);
    let mode = OutputMode::from_json_flag(args.json);
    let client = build_client()?;
    let resp = match client.calendar_entry_create(inner) {
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
            println!("created entry {}.", resp.entry.id);
            print!("{}", render_entry_detail(&resp.entry));
        }
    }
    Ok(())
}

// --- update -----------------------------------------------------------------

pub fn build_update_inner(args: &CalendarUpdateArgs) -> Value {
    let mut inner: Map<String, Value> = Map::new();
    if let Some(t) = &args.title {
        inner.insert("title".to_string(), Value::String(t.clone()));
    }
    if let Some(s) = &args.starts_at {
        inner.insert("starts_at".to_string(), Value::String(s.clone()));
    }
    if let Some(e) = &args.ends_at {
        inner.insert("ends_at".to_string(), Value::String(e.clone()));
    }
    if let Some(tz) = &args.timezone {
        inner.insert("timezone".to_string(), Value::String(tz.clone()));
    }
    if let Some(all_day) = args.all_day {
        inner.insert(
            "all_day".to_string(),
            Value::String(yes_no_string(all_day).to_string()),
        );
    }
    if let Some(d) = &args.description {
        inner.insert("description".to_string(), Value::String(d.clone()));
    }
    Value::Object(inner)
}

fn run_update(args: CalendarUpdateArgs) -> Result<()> {
    let inner = build_update_inner(&args);
    let mode = OutputMode::from_json_flag(args.json);
    let client = build_client()?;
    let resp = match client.calendar_entry_update(args.id, inner) {
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
            println!("updated entry {}.", resp.entry.id);
            print!("{}", render_entry_detail(&resp.entry));
        }
    }
    Ok(())
}

// --- note -------------------------------------------------------------------

fn run_note(args: CalendarNoteArgs) -> Result<()> {
    let mode = OutputMode::from_json_flag(args.json);
    let client = build_client()?;
    let resp = match client.calendar_entry_note(args.id, &args.note) {
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
            println!("note set on entry {}.", resp.entry.id);
        }
    }
    Ok(())
}

// --- cancel -----------------------------------------------------------------

/// Parse a comma-separated id list into `Vec<u64>`. Returns an error if any
/// segment doesn't parse. Trims whitespace around segments.
pub fn parse_ids_csv(s: &str) -> anyhow::Result<Vec<u64>> {
    let mut out: Vec<u64> = Vec::new();
    for raw in s.split(',') {
        let trimmed = raw.trim();
        if trimmed.is_empty() {
            continue;
        }
        let id: u64 = trimmed
            .parse()
            .map_err(|e| anyhow::anyhow!("invalid id `{}`: {}", trimmed, e))?;
        out.push(id);
    }
    Ok(out)
}

fn run_cancel(args: CalendarCancelArgs) -> Result<()> {
    let ids = match parse_ids_csv(&args.ids) {
        Ok(v) if v.is_empty() => {
            eprintln!("cancel: at least one id is required");
            std::process::exit(ExitCode::Validation.as_i32());
        }
        Ok(v) => v,
        Err(e) => {
            eprintln!("cancel: {}", e);
            std::process::exit(ExitCode::Validation.as_i32());
        }
    };
    let confirmed = confirm::is_confirmed(args.confirm);
    let mode = OutputMode::from_json_flag(args.json);

    if !confirmed {
        match mode {
            OutputMode::Json => {
                let payload = serde_json::json!({
                    "preview": true,
                    "ids": ids,
                    "message": "rerun with --confirm yes to soft-cancel.",
                });
                println!("{}", serde_json::to_string(&payload)?);
            }
            OutputMode::Plaintext => {
                println!(
                    "would soft-cancel {} entr{}.",
                    ids.len(),
                    if ids.len() == 1 { "y" } else { "ies" }
                );
                println!("rerun with --confirm yes to apply.");
            }
        }
        return Ok(());
    }

    let client = build_client()?;
    let resp = match client.calendar_entry_soft_cancel(&ids) {
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
            print!("{}", render_soft_cancel(&resp));
        }
    }
    Ok(())
}

pub fn render_soft_cancel(resp: &CalendarEntrySoftCancelResponse) -> String {
    let mut out = String::new();
    out.push_str(&format!("cancelled: {}\n", resp.cancelled.len()));
    for c in &resp.cancelled {
        out.push_str(&format!("  - {} ({})\n", c.id, c.state));
    }
    if !resp.skipped.is_empty() {
        out.push_str(&format!("skipped: {}\n", resp.skipped.len()));
        for s in &resp.skipped {
            out.push_str(&format!("  - {} ({})\n", s.id, s.reason));
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::endpoints::calendar::{SoftCancelSkippedRow, SoftCancelledRow};

    fn sample_entry() -> CalendarEntrySummary {
        CalendarEntrySummary {
            id: 12,
            entry_type: "game_release".to_string(),
            title: "Hades 2 launch".to_string(),
            starts_at: Some("2026-05-13T17:00:00Z".to_string()),
            ends_at: None,
            all_day: false,
            timezone: Some("Europe/Bucharest".to_string()),
            state: "scheduled".to_string(),
            source: Some("derived".to_string()),
            read_only: true,
            game_id: Some(42),
            video_id: None,
            channel_id: None,
            project_id: None,
            milestone_rule_id: None,
        }
    }

    #[test]
    fn render_entries_table_emits_header_and_rows() {
        let out = render_entries_table(&[sample_entry()]);
        let lines: Vec<&str> = out.lines().collect();
        assert_eq!(lines.len(), 3);
        assert!(lines[0].contains("id"));
        assert!(lines[0].contains("entry_type"));
        assert!(lines[0].contains("read_only"));
        assert!(lines[2].contains("Hades 2 launch"));
        // Boundary rule.
        assert!(lines[2].contains("yes"));
    }

    #[test]
    fn render_entries_table_empty_emits_no_records() {
        let out = render_entries_table(&[]);
        assert_eq!(out, "no records.\n");
    }

    #[test]
    fn parse_ids_csv_handles_single_id() {
        let v = parse_ids_csv("42").expect("parse");
        assert_eq!(v, vec![42]);
    }

    #[test]
    fn parse_ids_csv_handles_multiple_ids() {
        let v = parse_ids_csv("12,55,99").expect("parse");
        assert_eq!(v, vec![12, 55, 99]);
    }

    #[test]
    fn parse_ids_csv_trims_whitespace() {
        let v = parse_ids_csv(" 12 , 55 ").expect("parse");
        assert_eq!(v, vec![12, 55]);
    }

    #[test]
    fn parse_ids_csv_rejects_non_numeric() {
        let err = parse_ids_csv("42,evil").expect_err("must reject");
        assert!(format!("{}", err).contains("invalid"));
    }

    #[test]
    fn parse_ids_csv_skips_empty_segments() {
        let v = parse_ids_csv("12,,55").expect("parse");
        assert_eq!(v, vec![12, 55]);
    }

    #[test]
    fn build_create_inner_serializes_all_fields_with_yes_no_strings() {
        let args = CalendarCreateArgs {
            entry_type: "milestone_manual".to_string(),
            title: "ship".to_string(),
            starts_at: "2026-06-01T10:00:00Z".to_string(),
            ends_at: Some("2026-06-01T12:00:00Z".to_string()),
            timezone: Some("Europe/Bucharest".to_string()),
            all_day: Some(YesNo::No),
            description: Some("notes".to_string()),
            parent_entry_id: Some(7),
            json: false,
        };
        let inner = build_create_inner(&args);
        assert_eq!(
            inner["entry_type"],
            Value::String("milestone_manual".into())
        );
        assert_eq!(inner["title"], Value::String("ship".into()));
        assert_eq!(
            inner["starts_at"],
            Value::String("2026-06-01T10:00:00Z".into())
        );
        // Yes/no boundary — string, not bool.
        assert_eq!(inner["all_day"], Value::String("no".into()));
        assert_eq!(inner["parent_entry_id"], Value::Number(7.into()));
    }

    #[test]
    fn build_create_inner_omits_unset_optionals() {
        let args = CalendarCreateArgs {
            entry_type: "milestone_manual".to_string(),
            title: "ship".to_string(),
            starts_at: "2026-06-01T10:00:00Z".to_string(),
            ends_at: None,
            timezone: None,
            all_day: None,
            description: None,
            parent_entry_id: None,
            json: false,
        };
        let inner = build_create_inner(&args);
        let map = inner.as_object().expect("object");
        // Only the three required fields land in the body.
        assert_eq!(map.len(), 3);
        assert!(map.contains_key("entry_type"));
        assert!(map.contains_key("title"));
        assert!(map.contains_key("starts_at"));
    }

    #[test]
    fn build_update_inner_omits_unset_optionals() {
        let args = CalendarUpdateArgs {
            id: 1,
            title: Some("updated".to_string()),
            starts_at: None,
            ends_at: None,
            timezone: None,
            all_day: None,
            description: None,
            json: false,
        };
        let inner = build_update_inner(&args);
        let map = inner.as_object().expect("object");
        // Only `title` was provided.
        assert_eq!(map.len(), 1);
        assert_eq!(map["title"], Value::String("updated".into()));
    }

    #[test]
    fn build_update_inner_uses_yes_no_for_all_day() {
        let args = CalendarUpdateArgs {
            id: 1,
            title: None,
            starts_at: None,
            ends_at: None,
            timezone: None,
            all_day: Some(YesNo::Yes),
            description: None,
            json: false,
        };
        let inner = build_update_inner(&args);
        assert_eq!(inner["all_day"], Value::String("yes".into()));
    }

    #[test]
    fn render_soft_cancel_emits_both_arms() {
        let resp = CalendarEntrySoftCancelResponse {
            cancelled: vec![SoftCancelledRow {
                id: 12,
                state: "cancelled".to_string(),
            }],
            skipped: vec![SoftCancelSkippedRow {
                id: 55,
                reason: "already_cancelled".to_string(),
            }],
        };
        let out = render_soft_cancel(&resp);
        assert!(out.contains("cancelled: 1"));
        assert!(out.contains("12"));
        assert!(out.contains("skipped: 1"));
        assert!(out.contains("already_cancelled"));
    }

    #[test]
    fn render_soft_cancel_omits_skipped_section_when_empty() {
        let resp = CalendarEntrySoftCancelResponse {
            cancelled: vec![SoftCancelledRow {
                id: 12,
                state: "cancelled".to_string(),
            }],
            skipped: vec![],
        };
        let out = render_soft_cancel(&resp);
        assert!(out.contains("cancelled: 1"));
        assert!(!out.contains("skipped"));
    }
}
