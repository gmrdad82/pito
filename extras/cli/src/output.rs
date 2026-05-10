//! Shared output / exit-code plumbing for the `pito` CLI subcommand surface.
//!
//! The Phase 18 spec
//! (`docs/plans/beta/18-cli-parity/specs/01-cli-coverage-matrix-and-subcommands.md`)
//! locks the exit-code translation table:
//!
//! | Condition                         | Exit code |
//! | --------------------------------- | --------- |
//! | Success                           | 0         |
//! | Validation error                  | 2         |
//! | Authentication failure            | 3         |
//! | Authorization failure             | 4         |
//! | Not found                         | 5         |
//! | Conflict                          | 6         |
//! | Rate limit                        | 7         |
//! | Server error                      | 10        |
//! | Network error                     | 11        |
//! | Confirmation required (preview)   | 0         |
//! | Bad usage                         | 64        |
//!
//! Output mode is plaintext by default, `--json` switches to a single JSON
//! document on stdout. Errors always go to stderr.

use std::fmt::Write;

/// Exit-code enum mapped to `std::process::exit`. The integer values are
/// stable across releases. The locked exit-code spec defines every variant;
/// some are not yet referenced by any subcommand (only the auth / network /
/// validation / bad-usage paths are wired in this Phase 18 partial pass) —
/// the rest land as more subcommands ship and are kept here as the
/// authoritative table the Phase 18 spec locks.
#[allow(dead_code)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ExitCode {
    Success = 0,
    Validation = 2,
    AuthFailure = 3,
    AuthorizationFailure = 4,
    NotFound = 5,
    Conflict = 6,
    RateLimit = 7,
    ServerError = 10,
    NetworkError = 11,
    BadUsage = 64,
}

impl ExitCode {
    pub fn as_i32(self) -> i32 {
        self as i32
    }
}

/// Output mode for a single subcommand invocation. Selected by the
/// presence-only `--json` flag in clap.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OutputMode {
    Plaintext,
    Json,
}

impl OutputMode {
    pub fn from_json_flag(json: bool) -> Self {
        if json { Self::Json } else { Self::Plaintext }
    }
}

/// Render a fixed-column table to a string. Each row must be the same length
/// as `headers`. Columns are padded to the widest cell in each column. The
/// separator row uses `-` characters.
///
/// Empty `rows` produces a single line: `no records.` (matches the spec's
/// "empty list" edge-case behavior).
pub fn render_table(headers: &[&str], rows: &[Vec<String>]) -> String {
    if rows.is_empty() {
        return "no records.\n".to_string();
    }

    let mut widths: Vec<usize> = headers.iter().map(|h| h.len()).collect();
    for row in rows {
        for (i, cell) in row.iter().enumerate() {
            if i < widths.len() && cell.len() > widths[i] {
                widths[i] = cell.len();
            }
        }
    }

    let mut out = String::new();
    write_row(&mut out, headers, &widths);
    let sep_row: Vec<String> = widths.iter().map(|w| "-".repeat(*w)).collect();
    let sep_refs: Vec<&str> = sep_row.iter().map(|s| s.as_str()).collect();
    write_row(&mut out, &sep_refs, &widths);
    for row in rows {
        let cell_refs: Vec<&str> = row.iter().map(|s| s.as_str()).collect();
        write_row(&mut out, &cell_refs, &widths);
    }
    out
}

fn write_row(out: &mut String, cells: &[&str], widths: &[usize]) {
    let mut first = true;
    for (i, cell) in cells.iter().enumerate() {
        if !first {
            out.push_str("  ");
        }
        first = false;
        let width = widths.get(i).copied().unwrap_or(0);
        let _ = write!(out, "{:<width$}", cell, width = width);
    }
    out.push('\n');
}

/// Render a key-value table. Used by `show` verbs. Keys are right-padded to
/// the widest key.
///
/// Not yet wired up by any subcommand in this partial Phase 18 pass; the
/// helper lands now so the per-noun `show` dispatches (channels, videos,
/// etc.) can consume it without re-deriving the layout when they ship.
#[allow(dead_code)]
pub fn render_kv(rows: &[(&str, String)]) -> String {
    if rows.is_empty() {
        return String::new();
    }
    let key_width = rows.iter().map(|(k, _)| k.len()).max().unwrap_or(0);
    let mut out = String::new();
    for (k, v) in rows {
        let _ = writeln!(out, "{:<key_width$}  {}", k, v, key_width = key_width);
    }
    out
}

/// Format an error line for stderr. Style: lowercase, terse, no trailing
/// period. e.g. `auth: not authenticated. run \`pito auth login\`.`
///
/// Not yet wired up by any subcommand path in this partial pass — call sites
/// today format inline via `eprintln!`. Kept here as the canonical helper
/// later subcommands route through.
#[allow(dead_code)]
pub fn format_error(category: &str, message: &str) -> String {
    format!("{}: {}", category, message)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn exit_codes_map_to_locked_integers() {
        // Lock the wire shape: any future renumber breaks scripts that
        // grep on these exit codes.
        assert_eq!(ExitCode::Success.as_i32(), 0);
        assert_eq!(ExitCode::Validation.as_i32(), 2);
        assert_eq!(ExitCode::AuthFailure.as_i32(), 3);
        assert_eq!(ExitCode::AuthorizationFailure.as_i32(), 4);
        assert_eq!(ExitCode::NotFound.as_i32(), 5);
        assert_eq!(ExitCode::Conflict.as_i32(), 6);
        assert_eq!(ExitCode::RateLimit.as_i32(), 7);
        assert_eq!(ExitCode::ServerError.as_i32(), 10);
        assert_eq!(ExitCode::NetworkError.as_i32(), 11);
        assert_eq!(ExitCode::BadUsage.as_i32(), 64);
    }

    #[test]
    fn output_mode_from_json_flag() {
        assert_eq!(OutputMode::from_json_flag(true), OutputMode::Json);
        assert_eq!(OutputMode::from_json_flag(false), OutputMode::Plaintext);
    }

    #[test]
    fn render_table_with_rows_aligns_columns() {
        let rows = vec![
            vec!["1".to_string(), "alpha".to_string()],
            vec!["20".to_string(), "beta".to_string()],
        ];
        let out = render_table(&["id", "name"], &rows);
        // Expected: header line + separator + two data lines.
        let lines: Vec<&str> = out.lines().collect();
        assert_eq!(lines.len(), 4);
        // Header: "id  name" (id padded to width 2 since longest cell is "20")
        assert!(lines[0].starts_with("id"));
        assert!(lines[0].contains("name"));
        // Separator row: dashes per column
        assert!(lines[1].contains("--"));
        // Rows align to widest cell.
        assert!(lines[2].starts_with("1 "));
        assert!(lines[3].starts_with("20"));
    }

    #[test]
    fn render_table_with_empty_rows_emits_no_records() {
        let out = render_table(&["id", "name"], &[]);
        assert_eq!(out, "no records.\n");
    }

    #[test]
    fn render_kv_pads_keys_to_widest() {
        let rows = vec![
            ("id", "1".to_string()),
            ("channel_url", "https://x".to_string()),
        ];
        let out = render_kv(&rows);
        let lines: Vec<&str> = out.lines().collect();
        assert_eq!(lines.len(), 2);
        // The shorter key "id" should be right-padded to match "channel_url".
        assert!(lines[0].starts_with("id "));
        assert!(lines[1].starts_with("channel_url"));
    }

    #[test]
    fn render_kv_with_no_rows_returns_empty_string() {
        assert_eq!(render_kv(&[]), "");
    }

    #[test]
    fn format_error_uses_lowercase_terse_no_trailing_period() {
        let s = format_error("auth", "not authenticated");
        assert_eq!(s, "auth: not authenticated");
    }
}
