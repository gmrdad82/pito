//! Phase 21 calendar JSON surfaces.
//!
//! Endpoints:
//!
//! - `GET    /calendar/schedule.json?types=&source=&state=&page=` — paginated
//! - `GET    /calendar/month/:year/:month.json?types=&state=`   — grouped by date
//! - `GET    /calendar/entries/:id.json`
//! - `POST   /calendar/entries.json`
//! - `PATCH  /calendar/entries/:id.json`
//! - `PATCH  /calendar/entries/:id/note.json`
//! - `DELETE /deletions/calendar_entry/:ids.json`               — soft-cancel
//!
//! Per spec, every boolean across the wire is the `"yes"` / `"no"` string;
//! the model fields use the `crate::api::yes_no` adapter (or its option
//! variant) so internal Rust code stays in `bool` land.

use std::collections::BTreeMap;

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use serde_json::Value;

use super::{EndpointsClient, encode_query_value};

// --- Wire shapes ------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct CalendarEntrySummary {
    pub id: u64,
    pub entry_type: String,
    pub title: String,
    pub starts_at: Option<String>,
    pub ends_at: Option<String>,
    #[serde(with = "crate::api::yes_no")]
    pub all_day: bool,
    pub timezone: Option<String>,
    pub state: String,
    pub source: Option<String>,
    #[serde(with = "crate::api::yes_no")]
    pub read_only: bool,
    pub game_id: Option<u64>,
    pub video_id: Option<u64>,
    pub channel_id: Option<u64>,
    pub project_id: Option<u64>,
    pub milestone_rule_id: Option<u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CalendarEntryDetail {
    pub id: u64,
    pub entry_type: String,
    pub title: String,
    pub description: Option<String>,
    pub starts_at: Option<String>,
    pub ends_at: Option<String>,
    #[serde(with = "crate::api::yes_no")]
    pub all_day: bool,
    pub timezone: Option<String>,
    pub state: String,
    pub source: Option<String>,
    #[serde(with = "crate::api::yes_no")]
    pub read_only: bool,
    #[serde(with = "crate::api::yes_no")]
    pub manual_date_override: bool,
    pub release_precision: Option<String>,
    #[serde(with = "crate::api::yes_no")]
    pub tba_remind_monthly: bool,
    #[serde(with = "crate::api::yes_no")]
    pub notify_anyway: bool,
    #[serde(default)]
    pub metadata: Option<Value>,
    pub parent_entry_id: Option<u64>,
    #[serde(default)]
    pub child_entry_ids: Vec<u64>,
    pub game_id: Option<u64>,
    pub video_id: Option<u64>,
    pub channel_id: Option<u64>,
    pub project_id: Option<u64>,
    pub milestone_rule_id: Option<u64>,
    pub created_by_user_id: Option<u64>,
    pub created_at: Option<String>,
    pub updated_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CalendarScheduleResponse {
    pub page: u32,
    pub total_pages: u32,
    pub total: u64,
    pub per_page: u32,
    #[serde(default)]
    pub selected_kinds: Option<Value>,
    #[serde(default)]
    pub selected_source: Option<String>,
    #[serde(with = "crate::api::yes_no")]
    pub show_cancelled: bool,
    pub install_tz: Option<String>,
    pub today: Option<String>,
    pub entries: Vec<CalendarEntrySummary>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CalendarMonthNavRef {
    pub year: i32,
    pub month: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CalendarMonthNav {
    pub prev: CalendarMonthNavRef,
    pub next: CalendarMonthNavRef,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CalendarMonthResponse {
    pub year: i32,
    pub month: u32,
    pub install_tz: Option<String>,
    pub first_day: Option<String>,
    pub last_day: Option<String>,
    pub today: Option<String>,
    #[serde(with = "crate::api::yes_no")]
    pub on_current_month: bool,
    #[serde(default)]
    pub selected_kinds: Option<Value>,
    #[serde(with = "crate::api::yes_no")]
    pub show_cancelled: bool,
    /// `buckets` keys are ISO-8601 dates. Empty days are omitted by Rails.
    /// `BTreeMap` keeps the order stable for plaintext output.
    pub buckets: BTreeMap<String, Vec<CalendarEntrySummary>>,
    pub nav: CalendarMonthNav,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CalendarEntryShowResponse {
    pub entry: CalendarEntryDetail,
    #[serde(default)]
    pub dispatch_declarations: Vec<Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SoftCancelledRow {
    pub id: u64,
    pub state: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SoftCancelSkippedRow {
    pub id: u64,
    pub reason: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CalendarEntrySoftCancelResponse {
    #[serde(default)]
    pub cancelled: Vec<SoftCancelledRow>,
    #[serde(default)]
    pub skipped: Vec<SoftCancelSkippedRow>,
}

// --- Query params -----------------------------------------------------------

#[derive(Debug, Default, Clone)]
pub struct CalendarScheduleQuery {
    pub types: Option<String>,
    pub source: Option<String>,
    pub state: Option<String>,
    pub page: Option<u32>,
}

impl CalendarScheduleQuery {
    pub fn to_query_string(&self) -> String {
        let mut parts: Vec<String> = Vec::new();
        if let Some(t) = &self.types {
            parts.push(format!("types={}", encode_query_value(t)));
        }
        if let Some(s) = &self.source {
            parts.push(format!("source={}", encode_query_value(s)));
        }
        if let Some(s) = &self.state {
            parts.push(format!("state={}", encode_query_value(s)));
        }
        if let Some(p) = self.page {
            parts.push(format!("page={}", p));
        }
        if parts.is_empty() {
            String::new()
        } else {
            format!("?{}", parts.join("&"))
        }
    }
}

#[derive(Debug, Default, Clone)]
pub struct CalendarMonthQuery {
    pub types: Option<String>,
    pub state: Option<String>,
}

impl CalendarMonthQuery {
    pub fn to_query_string(&self) -> String {
        let mut parts: Vec<String> = Vec::new();
        if let Some(t) = &self.types {
            parts.push(format!("types={}", encode_query_value(t)));
        }
        if let Some(s) = &self.state {
            parts.push(format!("state={}", encode_query_value(s)));
        }
        if parts.is_empty() {
            String::new()
        } else {
            format!("?{}", parts.join("&"))
        }
    }
}

// --- Client methods ---------------------------------------------------------

impl EndpointsClient {
    pub fn calendar_schedule(&self, q: &CalendarScheduleQuery) -> Result<CalendarScheduleResponse> {
        let url = self.url(&format!("/calendar/schedule.json{}", q.to_query_string()));
        let resp = self
            .with_headers(self.client().get(&url))
            .send()
            .with_context(|| format!("GET {}", url))?
            .error_for_status()
            .with_context(|| format!("status check GET {}", url))?;
        let body: CalendarScheduleResponse = resp.json().context("decode schedule")?;
        Ok(body)
    }

    pub fn calendar_month(
        &self,
        year: i32,
        month: u32,
        q: &CalendarMonthQuery,
    ) -> Result<CalendarMonthResponse> {
        let url = self.url(&format!(
            "/calendar/month/{}/{}.json{}",
            year,
            month,
            q.to_query_string()
        ));
        let resp = self
            .with_headers(self.client().get(&url))
            .send()
            .with_context(|| format!("GET {}", url))?
            .error_for_status()
            .with_context(|| format!("status check GET {}", url))?;
        let body: CalendarMonthResponse = resp.json().context("decode month")?;
        Ok(body)
    }

    pub fn calendar_entry_show(&self, id: u64) -> Result<CalendarEntryShowResponse> {
        let url = self.url(&format!("/calendar/entries/{}.json", id));
        let resp = self
            .with_headers(self.client().get(&url))
            .send()
            .with_context(|| format!("GET {}", url))?
            .error_for_status()
            .with_context(|| format!("status check GET {}", url))?;
        let body: CalendarEntryShowResponse = resp.json().context("decode entry show")?;
        Ok(body)
    }

    /// `POST /calendar/entries.json` — body is the strong-params-wrapped
    /// payload `{ "calendar_entry": { ... } }`. The caller passes a
    /// pre-assembled inner object; this method wraps it. yes/no boolean
    /// fields MUST already be strings.
    pub fn calendar_entry_create(&self, inner: Value) -> Result<CalendarEntryShowResponse> {
        let url = self.url("/calendar/entries.json");
        let body = serde_json::json!({ "calendar_entry": inner });
        let resp = self
            .with_headers(
                self.client()
                    .post(&url)
                    .header("Content-Type", "application/json"),
            )
            .json(&body)
            .send()
            .with_context(|| format!("POST {}", url))?
            .error_for_status()
            .with_context(|| format!("status check POST {}", url))?;
        let parsed: CalendarEntryShowResponse = resp.json().context("decode entry create")?;
        Ok(parsed)
    }

    pub fn calendar_entry_update(
        &self,
        id: u64,
        inner: Value,
    ) -> Result<CalendarEntryShowResponse> {
        let url = self.url(&format!("/calendar/entries/{}.json", id));
        let body = serde_json::json!({ "calendar_entry": inner });
        let resp = self
            .with_headers(
                self.client()
                    .patch(&url)
                    .header("Content-Type", "application/json"),
            )
            .json(&body)
            .send()
            .with_context(|| format!("PATCH {}", url))?
            .error_for_status()
            .with_context(|| format!("status check PATCH {}", url))?;
        let parsed: CalendarEntryShowResponse = resp.json().context("decode entry update")?;
        Ok(parsed)
    }

    /// `PATCH /calendar/entries/:id/note.json` — body
    /// `{ "calendar_entry": { "note": "..." } }`. Works even on read-only
    /// entries (server-side bypass for the metadata column).
    pub fn calendar_entry_note(&self, id: u64, note: &str) -> Result<CalendarEntryShowResponse> {
        let url = self.url(&format!("/calendar/entries/{}/note.json", id));
        let body = serde_json::json!({ "calendar_entry": { "note": note } });
        let resp = self
            .with_headers(
                self.client()
                    .patch(&url)
                    .header("Content-Type", "application/json"),
            )
            .json(&body)
            .send()
            .with_context(|| format!("PATCH {}", url))?
            .error_for_status()
            .with_context(|| format!("status check PATCH {}", url))?;
        let parsed: CalendarEntryShowResponse = resp.json().context("decode entry note")?;
        Ok(parsed)
    }

    /// `DELETE /deletions/calendar_entry/:ids.json` — soft-cancel, accepts
    /// one or N comma-separated ids per the bulk-as-foundation rule.
    pub fn calendar_entry_soft_cancel(
        &self,
        ids: &[u64],
    ) -> Result<CalendarEntrySoftCancelResponse> {
        let csv = ids_csv(ids);
        let url = self.url(&format!("/deletions/calendar_entry/{}.json", csv));
        let resp = self
            .with_headers(self.client().delete(&url))
            .send()
            .with_context(|| format!("DELETE {}", url))?
            .error_for_status()
            .with_context(|| format!("status check DELETE {}", url))?;
        let parsed: CalendarEntrySoftCancelResponse = resp.json().context("decode soft cancel")?;
        Ok(parsed)
    }
}

/// CSV join for the bulk-as-foundation path segment. Lifted to a free
/// function so the same helper is testable without an instance.
pub fn ids_csv(ids: &[u64]) -> String {
    ids.iter()
        .map(|id| id.to_string())
        .collect::<Vec<_>>()
        .join(",")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ids_csv_joins_with_commas() {
        assert_eq!(ids_csv(&[1, 2, 3]), "1,2,3");
        assert_eq!(ids_csv(&[42]), "42");
        assert_eq!(ids_csv(&[]), "");
    }

    #[test]
    fn schedule_query_empty_for_default() {
        let q = CalendarScheduleQuery::default();
        assert_eq!(q.to_query_string(), "");
    }

    #[test]
    fn schedule_query_includes_all_set_fields() {
        let q = CalendarScheduleQuery {
            types: Some("video,game".to_string()),
            source: Some("derived".to_string()),
            state: Some("scheduled".to_string()),
            page: Some(2),
        };
        let s = q.to_query_string();
        assert!(s.contains("types=video,game"));
        assert!(s.contains("source=derived"));
        assert!(s.contains("state=scheduled"));
        assert!(s.contains("page=2"));
    }

    #[test]
    fn month_query_includes_set_fields() {
        let q = CalendarMonthQuery {
            types: Some("game".to_string()),
            state: None,
        };
        assert_eq!(q.to_query_string(), "?types=game");
    }

    #[test]
    fn calendar_entry_summary_round_trip_uses_yes_no() {
        let entry = CalendarEntrySummary {
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
        };
        let s = serde_json::to_string(&entry).expect("serialize");
        assert!(s.contains("\"all_day\":\"no\""));
        assert!(s.contains("\"read_only\":\"yes\""));
        let parsed: CalendarEntrySummary = serde_json::from_str(&s).expect("deserialize");
        assert_eq!(parsed, entry);
    }

    #[test]
    fn calendar_month_response_decodes_buckets_as_btreemap() {
        let json = r#"{
            "year": 2026,
            "month": 5,
            "install_tz": "Europe/Bucharest",
            "first_day": "2026-04-27",
            "last_day": "2026-06-01",
            "today": "2026-05-10",
            "on_current_month": "yes",
            "selected_kinds": ["video", "game"],
            "show_cancelled": "no",
            "buckets": {
                "2026-05-13": [
                    {
                        "id": 12,
                        "entry_type": "game_release",
                        "title": "Hades 2",
                        "starts_at": "2026-05-13T17:00:00Z",
                        "ends_at": null,
                        "all_day": "no",
                        "timezone": "Europe/Bucharest",
                        "state": "scheduled",
                        "source": "derived",
                        "read_only": "yes",
                        "game_id": 42,
                        "video_id": null,
                        "channel_id": null,
                        "project_id": null,
                        "milestone_rule_id": null
                    }
                ]
            },
            "nav": {
                "prev": { "year": 2026, "month": 4 },
                "next": { "year": 2026, "month": 6 }
            }
        }"#;
        let parsed: CalendarMonthResponse = serde_json::from_str(json).expect("deserialize");
        assert_eq!(parsed.buckets.len(), 1);
        let bucket = parsed
            .buckets
            .get("2026-05-13")
            .expect("bucket for 2026-05-13");
        assert_eq!(bucket.len(), 1);
        assert_eq!(bucket[0].title, "Hades 2");
        assert!(parsed.on_current_month);
        assert!(!parsed.show_cancelled);
    }

    #[test]
    fn soft_cancel_response_decodes_both_arms() {
        let json = r#"{
            "cancelled": [{ "id": 12, "state": "cancelled" }],
            "skipped": [{ "id": 55, "reason": "already_cancelled" }]
        }"#;
        let parsed: CalendarEntrySoftCancelResponse =
            serde_json::from_str(json).expect("deserialize");
        assert_eq!(parsed.cancelled.len(), 1);
        assert_eq!(parsed.cancelled[0].state, "cancelled");
        assert_eq!(parsed.skipped[0].reason, "already_cancelled");
    }

    #[test]
    fn soft_cancel_response_decodes_empty_arms() {
        // Either side may be empty if all targets fell into the other arm.
        let json = r#"{ "cancelled": [], "skipped": [] }"#;
        let parsed: CalendarEntrySoftCancelResponse =
            serde_json::from_str(json).expect("deserialize");
        assert!(parsed.cancelled.is_empty());
        assert!(parsed.skipped.is_empty());
    }
}
