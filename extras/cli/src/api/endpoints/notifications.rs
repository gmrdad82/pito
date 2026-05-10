//! Phase 21 notifications JSON surfaces.
//!
//! Endpoints:
//!
//! - `GET   /notifications.json?filter=&kind=&severity=&page=`
//! - `GET   /notifications/:id.json`
//! - `GET   /notifications/badge.json`            — `{ unread_count, has_failures }`
//! - `PATCH /notifications/:id/read.json`
//! - `PATCH /notifications/:id/unread.json`
//! - `PATCH /notifications/mark_read.json?ids=`
//! - `PATCH /notifications/mark_all_read.json`
//!
//! The 204 → 200 + body upgrade on `read` / `unread` (locked decision #2)
//! means callers always get back `{ id, read, in_app_read_at, unread_count }`.

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use serde_json::Value;

use super::{EndpointsClient, encode_query_value};

// --- Wire shapes ------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct NotificationSummary {
    pub id: u64,
    pub kind: String,
    pub severity: String,
    pub event_type: Option<String>,
    pub title: Option<String>,
    pub body: Option<String>,
    pub url: Option<String>,
    pub fires_at: Option<String>,
    pub in_app_read_at: Option<String>,
    #[serde(with = "crate::api::yes_no")]
    pub read: bool,
    pub discord_delivered_at: Option<String>,
    pub slack_delivered_at: Option<String>,
    pub retry_count: Option<u32>,
    pub last_error: Option<String>,
    pub created_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NotificationsIndexResponse {
    pub page: u32,
    pub total_pages: u32,
    pub total: u64,
    pub per_page: u32,
    pub filter: Option<String>,
    pub kind: Option<String>,
    pub severity: Option<String>,
    pub unread_count: u64,
    #[serde(with = "crate::api::yes_no")]
    pub has_failures: bool,
    pub notifications: Vec<NotificationSummary>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NotificationShowResponse {
    pub notification: NotificationSummary,
    #[serde(default)]
    pub payload: Option<Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NotificationBadge {
    pub unread_count: u64,
    #[serde(with = "crate::api::yes_no")]
    pub has_failures: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NotificationStateChangeResponse {
    pub id: u64,
    #[serde(with = "crate::api::yes_no")]
    pub read: bool,
    pub in_app_read_at: Option<String>,
    pub unread_count: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NotificationBulkResponse {
    pub marked: u64,
    pub unread_count: u64,
    #[serde(default = "default_no_yes_no", with = "crate::api::yes_no")]
    pub has_failures: bool,
}

fn default_no_yes_no() -> bool {
    false
}

// --- Query params -----------------------------------------------------------

#[derive(Debug, Default, Clone)]
pub struct NotificationsIndexQuery {
    /// `unread` or `all`. Server defaults to `unread` when None.
    pub filter: Option<String>,
    pub kind: Option<String>,
    pub severity: Option<String>,
    pub page: Option<u32>,
}

impl NotificationsIndexQuery {
    pub fn to_query_string(&self) -> String {
        let mut parts: Vec<String> = Vec::new();
        if let Some(f) = &self.filter {
            parts.push(format!("filter={}", encode_query_value(f)));
        }
        if let Some(k) = &self.kind {
            parts.push(format!("kind={}", encode_query_value(k)));
        }
        if let Some(s) = &self.severity {
            parts.push(format!("severity={}", encode_query_value(s)));
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

// --- Client methods ---------------------------------------------------------

impl EndpointsClient {
    pub fn notifications_list(
        &self,
        q: &NotificationsIndexQuery,
    ) -> Result<NotificationsIndexResponse> {
        let url = self.url(&format!("/notifications.json{}", q.to_query_string()));
        let resp = self
            .with_headers(self.client().get(&url))
            .send()
            .with_context(|| format!("GET {}", url))?
            .error_for_status()
            .with_context(|| format!("status check GET {}", url))?;
        let body: NotificationsIndexResponse = resp.json().context("decode notifications index")?;
        Ok(body)
    }

    pub fn notifications_show(&self, id: u64) -> Result<NotificationShowResponse> {
        let url = self.url(&format!("/notifications/{}.json", id));
        let resp = self
            .with_headers(self.client().get(&url))
            .send()
            .with_context(|| format!("GET {}", url))?
            .error_for_status()
            .with_context(|| format!("status check GET {}", url))?;
        let body: NotificationShowResponse = resp.json().context("decode notification show")?;
        Ok(body)
    }

    pub fn notifications_badge(&self) -> Result<NotificationBadge> {
        let url = self.url("/notifications/badge.json");
        let resp = self
            .with_headers(self.client().get(&url))
            .send()
            .with_context(|| format!("GET {}", url))?
            .error_for_status()
            .with_context(|| format!("status check GET {}", url))?;
        let body: NotificationBadge = resp.json().context("decode notifications badge")?;
        Ok(body)
    }

    pub fn notification_mark_read_single(
        &self,
        id: u64,
    ) -> Result<NotificationStateChangeResponse> {
        let url = self.url(&format!("/notifications/{}/read.json", id));
        let resp = self
            .with_headers(
                self.client()
                    .patch(&url)
                    .header("Content-Type", "application/json"),
            )
            .send()
            .with_context(|| format!("PATCH {}", url))?
            .error_for_status()
            .with_context(|| format!("status check PATCH {}", url))?;
        let body: NotificationStateChangeResponse = resp.json().context("decode read response")?;
        Ok(body)
    }

    pub fn notification_mark_unread_single(
        &self,
        id: u64,
    ) -> Result<NotificationStateChangeResponse> {
        let url = self.url(&format!("/notifications/{}/unread.json", id));
        let resp = self
            .with_headers(
                self.client()
                    .patch(&url)
                    .header("Content-Type", "application/json"),
            )
            .send()
            .with_context(|| format!("PATCH {}", url))?
            .error_for_status()
            .with_context(|| format!("status check PATCH {}", url))?;
        let body: NotificationStateChangeResponse =
            resp.json().context("decode unread response")?;
        Ok(body)
    }

    pub fn notifications_mark_read_bulk(&self, ids: &[u64]) -> Result<NotificationBulkResponse> {
        let csv = super::calendar::ids_csv(ids);
        let url = self.url(&format!("/notifications/mark_read.json?ids={}", csv));
        let resp = self
            .with_headers(
                self.client()
                    .patch(&url)
                    .header("Content-Type", "application/json"),
            )
            .send()
            .with_context(|| format!("PATCH {}", url))?
            .error_for_status()
            .with_context(|| format!("status check PATCH {}", url))?;
        let body: NotificationBulkResponse = resp.json().context("decode mark_read response")?;
        Ok(body)
    }

    pub fn notifications_mark_all_read(&self) -> Result<NotificationBulkResponse> {
        let url = self.url("/notifications/mark_all_read.json");
        let resp = self
            .with_headers(
                self.client()
                    .patch(&url)
                    .header("Content-Type", "application/json"),
            )
            .send()
            .with_context(|| format!("PATCH {}", url))?
            .error_for_status()
            .with_context(|| format!("status check PATCH {}", url))?;
        let body: NotificationBulkResponse =
            resp.json().context("decode mark_all_read response")?;
        Ok(body)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn index_query_empty_for_default() {
        let q = NotificationsIndexQuery::default();
        assert_eq!(q.to_query_string(), "");
    }

    #[test]
    fn index_query_combines_all_fields() {
        let q = NotificationsIndexQuery {
            filter: Some("unread".to_string()),
            kind: Some("video_published".to_string()),
            severity: Some("success".to_string()),
            page: Some(3),
        };
        let s = q.to_query_string();
        assert!(s.contains("filter=unread"));
        assert!(s.contains("kind=video_published"));
        assert!(s.contains("severity=success"));
        assert!(s.contains("page=3"));
    }

    #[test]
    fn notification_summary_round_trip_uses_yes_no_for_read() {
        let n = NotificationSummary {
            id: 91,
            kind: "video_published".to_string(),
            severity: "success".to_string(),
            event_type: Some("video.published".to_string()),
            title: Some("video published".to_string()),
            body: Some("body text".to_string()),
            url: Some("/videos/abc123".to_string()),
            fires_at: Some("2026-05-10T17:00:00Z".to_string()),
            in_app_read_at: None,
            read: false,
            discord_delivered_at: None,
            slack_delivered_at: None,
            retry_count: Some(0),
            last_error: None,
            created_at: Some("2026-05-10T17:00:00Z".to_string()),
        };
        let s = serde_json::to_string(&n).expect("serialize");
        assert!(s.contains("\"read\":\"no\""));
        let parsed: NotificationSummary = serde_json::from_str(&s).expect("deserialize");
        assert_eq!(parsed, n);
    }

    #[test]
    fn notification_badge_decodes_locked_shape() {
        let json = r#"{ "unread_count": 17, "has_failures": "yes" }"#;
        let parsed: NotificationBadge = serde_json::from_str(json).expect("deserialize");
        assert_eq!(parsed.unread_count, 17);
        assert!(parsed.has_failures);
    }

    #[test]
    fn notification_state_change_decodes_locked_shape() {
        let json = r#"{
            "id": 91,
            "read": "yes",
            "in_app_read_at": "2026-05-10T18:42:00Z",
            "unread_count": 16
        }"#;
        let parsed: NotificationStateChangeResponse =
            serde_json::from_str(json).expect("deserialize");
        assert_eq!(parsed.id, 91);
        assert!(parsed.read);
        assert_eq!(parsed.unread_count, 16);
        assert_eq!(
            parsed.in_app_read_at.as_deref(),
            Some("2026-05-10T18:42:00Z")
        );
    }

    #[test]
    fn notification_bulk_response_decodes_with_has_failures() {
        let json = r#"{ "marked": 17, "unread_count": 0, "has_failures": "no" }"#;
        let parsed: NotificationBulkResponse = serde_json::from_str(json).expect("deserialize");
        assert_eq!(parsed.marked, 17);
        assert_eq!(parsed.unread_count, 0);
        assert!(!parsed.has_failures);
    }
}
