//! Parser + view-model for the `login_pending_approval` notification.
//!
//! The Rails JSON surface for notifications exposes the formatted body
//! the user already sees in the web banner — a small, well-shaped
//! markdown string emitted by
//! `NotificationFormatter::Templates::LoginPendingApproval`. Sample body:
//!
//! ```text
//! someone with the correct password is trying to sign in from a new location.
//! browser: Chrome on macOS.
//! location: Berlin, Germany (BE).
//! ip: 203.0.113.42.
//! fingerprint: abc123def456.
//!
//! [yeah, it's me](/login/approvals/91) or [block the intruder](/login/blocks/91).
//! ```
//!
//! The TUI doesn't render markdown — it parses the structured fields
//! out so the overlay can lay them out in a fixed grid (one row per
//! attribute). The `login_attempt_id` comes from the embedded action
//! link href; the action keys (`[a]`, `[b]`) post to the same path the
//! link would have followed in a browser.
//!
//! The parser is intentionally forgiving: missing lines default to the
//! template's own "unavailable" / "unknown" placeholders so we render
//! whatever the server emitted rather than crashing.

use crate::api::endpoints::notifications::NotificationSummary;

/// The kind string the Rails-side `Notification#kind` enum stamps on
/// pending-approval rows. Used to filter the notifications index for
/// just the pending rows the overlay cares about.
pub const KIND: &str = "login_pending_approval";

/// Parsed view-model for a single pending-approval notification.
///
/// All string fields are owned so the overlay can hold a snapshot
/// without borrowing the underlying `NotificationSummary` for the
/// lifetime of the overlay. The fields mirror the body lines emitted
/// by `NotificationFormatter::Templates::LoginPendingApproval`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LoginPendingCard {
    /// Notification id. Used to mark the row read once the operator
    /// resolves the pending attempt.
    pub notification_id: u64,
    /// `LoginAttempt` id, pulled from the approve link `(/login/approvals/:id)`.
    /// `None` only on a malformed body — the overlay refuses to fire
    /// approve / block when this is missing.
    pub login_attempt_id: Option<u64>,
    /// `new-location login: <email>` — the notification title verbatim.
    /// Empty string when the server omitted the title (defensive).
    pub title: String,
    /// `browser: <browser> on <os>.` — surfaced as `<browser> on <os>`.
    /// Falls back to "unknown browser on unknown OS" when missing.
    pub browser_os: String,
    /// `location: <city, country (region)>.` — surfaced verbatim;
    /// falls back to "location unknown".
    pub location: String,
    /// `ip: <ip>.` — presentation form, falls back to "(ip unavailable)".
    pub ip: String,
    /// `fingerprint: <short>.` — 12 hex chars, falls back to
    /// "(fingerprint unavailable)".
    pub fingerprint: String,
}

impl LoginPendingCard {
    /// Parse a notification summary into a card. Returns `None` when
    /// the kind doesn't match (`KIND`) — the index endpoint is filtered
    /// to `kind=login_pending_approval` server-side, but the defensive
    /// guard keeps callers honest.
    pub fn from_summary(summary: &NotificationSummary) -> Option<Self> {
        if summary.kind != KIND {
            return None;
        }
        let body = summary.body.as_deref().unwrap_or("");
        Some(Self {
            notification_id: summary.id,
            login_attempt_id: parse_login_attempt_id(body),
            title: summary.title.clone().unwrap_or_default(),
            browser_os: parse_line(body, "browser: ")
                .unwrap_or_else(|| "unknown browser on unknown OS".to_string()),
            location: parse_line(body, "location: ")
                .unwrap_or_else(|| "location unknown".to_string()),
            ip: parse_line(body, "ip: ").unwrap_or_else(|| "(ip unavailable)".to_string()),
            fingerprint: parse_line(body, "fingerprint: ")
                .unwrap_or_else(|| "(fingerprint unavailable)".to_string()),
        })
    }

    /// `true` when the card carries enough state to fire approve / block.
    /// Currently equivalent to "`login_attempt_id` is set" — the
    /// downstream `EndpointsClient::approve_pending` / `block_pending`
    /// calls take only the attempt id.
    pub fn is_actionable(&self) -> bool {
        self.login_attempt_id.is_some()
    }
}

/// Extract the value half of a "<prefix><value>." line out of the
/// notification body. Returns `None` when the prefix isn't found or
/// when the trailing period is missing.
fn parse_line(body: &str, prefix: &str) -> Option<String> {
    for line in body.lines() {
        if let Some(rest) = line.strip_prefix(prefix) {
            let value = rest.trim_end_matches('.').trim();
            return Some(value.to_string());
        }
    }
    None
}

/// Pull the `:id` out of the approve link `(/login/approvals/:id)`. The
/// body always carries both the approve and the block link with the
/// same id; we read the approve link arbitrarily.
fn parse_login_attempt_id(body: &str) -> Option<u64> {
    let marker = "/login/approvals/";
    let start = body.find(marker)?;
    let after = &body[start + marker.len()..];
    let digits: String = after.chars().take_while(|c| c.is_ascii_digit()).collect();
    if digits.is_empty() {
        return None;
    }
    digits.parse().ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_summary() -> NotificationSummary {
        NotificationSummary {
            id: 7,
            kind: KIND.to_string(),
            severity: "urgent".to_string(),
            event_type: Some("login_pending_approval".to_string()),
            title: Some("new-location login: alice@example.com".to_string()),
            body: Some(
                "someone with the correct password is trying to sign in from a new location.\n\
                 browser: Chrome on macOS.\n\
                 location: Berlin, Germany (BE).\n\
                 ip: 203.0.113.42.\n\
                 fingerprint: abc123def456.\n\
                 \n\
                 [yeah, it's me](/login/approvals/91) or [block the intruder](/login/blocks/91)."
                    .to_string(),
            ),
            url: Some("/notifications/7".to_string()),
            fires_at: Some("2026-05-11T12:00:00Z".to_string()),
            in_app_read_at: None,
            read: false,
            discord_delivered_at: None,
            slack_delivered_at: None,
            retry_count: Some(0),
            last_error: None,
            created_at: Some("2026-05-11T12:00:00Z".to_string()),
        }
    }

    #[test]
    fn from_summary_parses_every_field() {
        let card = LoginPendingCard::from_summary(&sample_summary()).expect("parsed");
        assert_eq!(card.notification_id, 7);
        assert_eq!(card.login_attempt_id, Some(91));
        assert_eq!(card.title, "new-location login: alice@example.com");
        assert_eq!(card.browser_os, "Chrome on macOS");
        assert_eq!(card.location, "Berlin, Germany (BE)");
        assert_eq!(card.ip, "203.0.113.42");
        assert_eq!(card.fingerprint, "abc123def456");
        assert!(card.is_actionable());
    }

    #[test]
    fn from_summary_returns_none_for_other_kinds() {
        let mut summary = sample_summary();
        summary.kind = "video_published".to_string();
        assert!(LoginPendingCard::from_summary(&summary).is_none());
    }

    #[test]
    fn from_summary_falls_back_for_missing_lines() {
        let mut summary = sample_summary();
        summary.body = Some(
            "someone with the correct password is trying to sign in from a new location.\n\
             [yeah, it's me](/login/approvals/12) or [block the intruder](/login/blocks/12)."
                .to_string(),
        );
        let card = LoginPendingCard::from_summary(&summary).expect("parsed");
        assert_eq!(card.login_attempt_id, Some(12));
        assert_eq!(card.browser_os, "unknown browser on unknown OS");
        assert_eq!(card.location, "location unknown");
        assert_eq!(card.ip, "(ip unavailable)");
        assert_eq!(card.fingerprint, "(fingerprint unavailable)");
        // Title still flows through.
        assert_eq!(card.title, "new-location login: alice@example.com");
        // Still actionable: the attempt id parsed fine.
        assert!(card.is_actionable());
    }

    #[test]
    fn from_summary_is_not_actionable_when_attempt_id_missing() {
        // No approve link in the body → card cannot fire approve / block.
        let mut summary = sample_summary();
        summary.body = Some("some unrelated body without the action links".to_string());
        let card = LoginPendingCard::from_summary(&summary).expect("parsed");
        assert_eq!(card.login_attempt_id, None);
        assert!(!card.is_actionable());
    }

    #[test]
    fn parse_line_handles_missing_prefix() {
        assert_eq!(parse_line("foo: bar.", "browser: "), None);
    }

    #[test]
    fn parse_line_trims_period_and_whitespace() {
        assert_eq!(
            parse_line("browser: Chrome on macOS.\n", "browser: ").as_deref(),
            Some("Chrome on macOS")
        );
    }

    #[test]
    fn parse_login_attempt_id_picks_up_numeric_suffix() {
        assert_eq!(
            parse_login_attempt_id(
                "[yeah, it's me](/login/approvals/55) or [block](/login/blocks/55)."
            ),
            Some(55)
        );
    }

    #[test]
    fn parse_login_attempt_id_returns_none_without_link() {
        assert_eq!(parse_login_attempt_id("no link here"), None);
    }
}
