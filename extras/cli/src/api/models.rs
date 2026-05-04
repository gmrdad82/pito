use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct Channel {
    pub id: u64,
    pub tenant_id: u64,
    pub channel_url: String,
    #[serde(with = "crate::api::yes_no")]
    pub star: bool,
    #[serde(with = "crate::api::yes_no")]
    pub connected: bool,
    #[serde(with = "crate::api::yes_no")]
    pub syncing: bool,
    /// ISO timestamp string. None if the channel has never been synced.
    pub last_synced_at: Option<String>,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Video {
    pub id: u64,
    pub youtube_video_id: String,
    pub title: String,
    pub channel_id: u64,
    pub channel_url: Option<String>,
    pub privacy_status: String,
    pub views: u64,
    pub likes: u64,
    pub comments: u64,
    pub watch_time_minutes: f64,
    pub duration_seconds: Option<u32>,
    pub published_at: Option<String>,
    pub trend: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VideoStat {
    pub date: String,
    pub views: u64,
    pub likes: u64,
    pub comments: u64,
    pub watch_time_minutes: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DashboardData {
    pub video_count: u64,
    pub channel_count: u64,
    pub daily_views: Vec<(String, u64)>,
    pub views_by_channel: Vec<(String, Vec<(String, u64)>)>,
    pub top_videos: Vec<TopVideo>,
    pub daily_engagement: DailyEngagement,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TopVideo {
    pub title: String,
    pub views: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DailyEngagement {
    pub likes: Vec<(String, u64)>,
    pub comments: Vec<(String, u64)>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SearchResults {
    pub videos: Vec<SearchHit<Video>>,
    pub video_total: u64,
    pub took_ms: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SearchHit<T> {
    pub record: T,
    pub highlights: Option<std::collections::HashMap<String, String>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SavedView {
    pub id: u64,
    pub kind: String,
    pub name: String,
    pub url: String,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum ResponseMode {
    Preview,
    Enqueued,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SkippedItem {
    pub id: u64,
    pub reason: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BulkOperationResponse {
    pub mode: ResponseMode,
    pub total: u32,
    /// Channels eligible for sync. Ignored for delete (delete applies to all `total` ids).
    pub syncable: Vec<u64>,
    pub skipped: Vec<SkippedItem>,
    pub operation_id: Option<u64>,
    pub message: String,
}

/// Snapshot of a server-side bulk operation, returned by
/// `GET /bulk_operations/:id/status.json`. Used by the TUI progress overlay
/// to drive the polling state machine.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BulkOperationStatus {
    pub id: u64,
    /// "bulk_delete" or "bulk_sync".
    pub kind: String,
    /// "pending" | "running" | "completed" | "failed".
    pub status: String,
    pub current: u32,
    pub total: u32,
    pub items: Vec<BulkOperationItem>,
    pub completed_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BulkOperationItem {
    pub id: u64,
    pub target_id: u64,
    pub target_type: String,
    /// "pending" | "succeeded" | "failed" | "skipped".
    pub status: String,
    pub error_message: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppSettings {
    pub max_panes: u32,
    pub pane_title_length: u32,
    pub theme: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn channel_round_trip() {
        let original = Channel {
            id: 7,
            tenant_id: 1,
            channel_url: "https://youtube.com/@example".to_string(),
            star: true,
            connected: false,
            syncing: false,
            last_synced_at: Some("2026-04-30T10:00:00Z".to_string()),
            created_at: "2026-01-01T00:00:00Z".to_string(),
            updated_at: "2026-04-30T10:00:00Z".to_string(),
        };
        let serialized = serde_json::to_string(&original).expect("serialize");
        let parsed: Channel = serde_json::from_str(&serialized).expect("deserialize");
        assert_eq!(original, parsed);
    }

    #[test]
    fn channel_handles_null_last_synced_at() {
        let json = r#"{
            "id": 1,
            "tenant_id": 1,
            "channel_url": "https://youtube.com/@a",
            "star": "no",
            "connected": "no",
            "syncing": "no",
            "last_synced_at": null,
            "created_at": "2026-01-01T00:00:00Z",
            "updated_at": "2026-01-01T00:00:00Z"
        }"#;
        let parsed: Channel = serde_json::from_str(json).expect("deserialize");
        assert!(parsed.last_synced_at.is_none());
    }

    #[test]
    fn response_mode_serializes_lowercase() {
        let preview = serde_json::to_string(&ResponseMode::Preview).unwrap();
        let enqueued = serde_json::to_string(&ResponseMode::Enqueued).unwrap();
        assert_eq!(preview, "\"preview\"");
        assert_eq!(enqueued, "\"enqueued\"");
    }

    #[test]
    fn channel_deserializes_yes_no_strings() {
        let json = r#"{
            "id": 1,
            "tenant_id": 1,
            "channel_url": "https://youtube.com/@a",
            "star": "yes",
            "connected": "no",
            "syncing": "yes",
            "last_synced_at": null,
            "created_at": "2026-01-01T00:00:00Z",
            "updated_at": "2026-01-01T00:00:00Z"
        }"#;
        let parsed: Channel = serde_json::from_str(json).expect("deserialize");
        assert!(parsed.star);
        assert!(!parsed.connected);
        assert!(parsed.syncing);
    }

    #[test]
    fn channel_serializes_yes_no_strings() {
        let original = Channel {
            id: 7,
            tenant_id: 1,
            channel_url: "https://youtube.com/@example".to_string(),
            star: true,
            connected: false,
            syncing: true,
            last_synced_at: None,
            created_at: "2026-01-01T00:00:00Z".to_string(),
            updated_at: "2026-01-01T00:00:00Z".to_string(),
        };
        let value: serde_json::Value = serde_json::to_value(&original).expect("serialize to value");
        assert_eq!(value["star"], serde_json::json!("yes"));
        assert_eq!(value["connected"], serde_json::json!("no"));
        assert_eq!(value["syncing"], serde_json::json!("yes"));
    }

    #[test]
    fn channel_round_trip_preserves_yes_no_booleans() {
        let original = Channel {
            id: 7,
            tenant_id: 1,
            channel_url: "https://youtube.com/@example".to_string(),
            star: true,
            connected: false,
            syncing: false,
            last_synced_at: Some("2026-04-30T10:00:00Z".to_string()),
            created_at: "2026-01-01T00:00:00Z".to_string(),
            updated_at: "2026-04-30T10:00:00Z".to_string(),
        };
        let s = serde_json::to_string(&original).expect("serialize");
        // Verify on-the-wire shape uses strings.
        assert!(s.contains("\"star\":\"yes\""));
        assert!(s.contains("\"connected\":\"no\""));
        assert!(s.contains("\"syncing\":\"no\""));
        let parsed: Channel = serde_json::from_str(&s).expect("deserialize");
        assert_eq!(original, parsed);
    }

    #[test]
    fn channel_rejects_native_bool_for_star() {
        let json = r#"{
            "id": 1,
            "tenant_id": 1,
            "channel_url": "https://youtube.com/@a",
            "star": true,
            "connected": "no",
            "syncing": "no",
            "last_synced_at": null,
            "created_at": "2026-01-01T00:00:00Z",
            "updated_at": "2026-01-01T00:00:00Z"
        }"#;
        let result: Result<Channel, _> = serde_json::from_str(json);
        assert!(
            result.is_err(),
            "native bool true should not be accepted for yes/no field"
        );
    }

    #[test]
    fn bulk_operation_status_round_trip() {
        let json = r#"{
            "id": 42,
            "kind": "bulk_delete",
            "status": "running",
            "current": 2,
            "total": 5,
            "items": [
                {
                    "id": 1,
                    "target_id": 10,
                    "target_type": "Channel",
                    "status": "succeeded",
                    "error_message": null
                },
                {
                    "id": 2,
                    "target_id": 11,
                    "target_type": "Channel",
                    "status": "failed",
                    "error_message": "boom"
                }
            ],
            "completed_at": null
        }"#;
        let parsed: BulkOperationStatus = serde_json::from_str(json).expect("deserialize");
        assert_eq!(parsed.id, 42);
        assert_eq!(parsed.kind, "bulk_delete");
        assert_eq!(parsed.status, "running");
        assert_eq!(parsed.current, 2);
        assert_eq!(parsed.total, 5);
        assert_eq!(parsed.items.len(), 2);
        assert_eq!(parsed.items[0].status, "succeeded");
        assert_eq!(parsed.items[1].error_message.as_deref(), Some("boom"));
        assert!(parsed.completed_at.is_none());

        // Round-trip: serialize and re-parse to ensure shape stability.
        let s = serde_json::to_string(&parsed).expect("serialize");
        let again: BulkOperationStatus = serde_json::from_str(&s).expect("re-deserialize");
        assert_eq!(again.id, parsed.id);
        assert_eq!(again.items.len(), parsed.items.len());
    }

    #[test]
    fn channel_rejects_string_true_for_star() {
        let json = r#"{
            "id": 1,
            "tenant_id": 1,
            "channel_url": "https://youtube.com/@a",
            "star": "true",
            "connected": "no",
            "syncing": "no",
            "last_synced_at": null,
            "created_at": "2026-01-01T00:00:00Z",
            "updated_at": "2026-01-01T00:00:00Z"
        }"#;
        let result: Result<Channel, _> = serde_json::from_str(json);
        assert!(
            result.is_err(),
            "the string \"true\" should not be accepted for yes/no field"
        );
        let err_msg = format!("{}", result.unwrap_err());
        assert!(
            err_msg.contains("yes") && err_msg.contains("no"),
            "error should mention yes/no, got: {err_msg}"
        );
    }
}

#[cfg(test)]
mod yes_no_option_tests {
    use serde::{Deserialize, Serialize};

    #[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
    struct Probe {
        #[serde(with = "crate::api::yes_no::option")]
        flag: Option<bool>,
    }

    #[test]
    fn option_round_trips_none() {
        let original = Probe { flag: None };
        let s = serde_json::to_string(&original).expect("serialize");
        assert!(s.contains("\"flag\":null"));
        let parsed: Probe = serde_json::from_str(&s).expect("deserialize");
        assert_eq!(original, parsed);
    }

    #[test]
    fn option_round_trips_some_true() {
        let original = Probe { flag: Some(true) };
        let s = serde_json::to_string(&original).expect("serialize");
        assert!(s.contains("\"flag\":\"yes\""));
        let parsed: Probe = serde_json::from_str(&s).expect("deserialize");
        assert_eq!(original, parsed);
    }

    #[test]
    fn option_round_trips_some_false() {
        let original = Probe { flag: Some(false) };
        let s = serde_json::to_string(&original).expect("serialize");
        assert!(s.contains("\"flag\":\"no\""));
        let parsed: Probe = serde_json::from_str(&s).expect("deserialize");
        assert_eq!(original, parsed);
    }

    #[test]
    fn option_rejects_native_bool() {
        let json = r#"{ "flag": true }"#;
        let result: Result<Probe, _> = serde_json::from_str(json);
        assert!(result.is_err());
    }

    #[test]
    fn option_rejects_unknown_string() {
        let json = r#"{ "flag": "maybe" }"#;
        let result: Result<Probe, _> = serde_json::from_str(json);
        assert!(result.is_err());
    }
}
