//! Wire models for the footage importer.
//!
//! Two strands:
//!
//! 1. **`ProbedFile`** — the local-side struct produced by walking the
//!    directory and running `ffprobe`. Not directly serialized; assembled into
//!    request bodies by [`super::client`].
//! 2. **`FootageRecord`** — the API-side struct returned by
//!    `GET /projects/:id/footage.json` and the per-row create/update endpoints.
//!    Booleans cross the wire as `"yes"`/`"no"` per the project rule (the
//!    shared `crate::api::yes_no` helper handles serialization both ways).

use serde::{Deserialize, Serialize};

use crate::footage::probe::ffprobe::ProbeReport;

/// Local file + its probe metadata. The diff stage compares this against
/// `FootageRecord`s already on the server.
#[derive(Debug, Clone, PartialEq)]
pub struct ProbedFile {
    /// Canonical absolute path (or whatever string the caller chose as
    /// identity). The diff stage matches on this exact string.
    pub local_path: String,
    pub filename: String,
    pub report: ProbeReport,
}

/// Mirror of the Rails `footages` row as returned by the JSON API. We only
/// model the fields the importer needs to read; richer fields (project_id,
/// game_id, kind, source, description, recorded_at, nas_path) come and go
/// through the API but the importer doesn't compare them in the diff.
///
/// The shape mirrors §3.4 of the project-workspace spec verbatim: snake_case
/// keys, `"yes"`/`"no"` strings on booleans, nullable optional columns.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct FootageRecord {
    pub id: u64,
    pub local_path: String,
    pub filename: String,
    #[serde(default)]
    pub duration_seconds: Option<u64>,
    #[serde(default)]
    pub resolution: Option<String>,
    #[serde(default)]
    pub fps: Option<f64>,
    #[serde(default)]
    pub codec: Option<String>,
    #[serde(default = "default_bit_depth")]
    pub bit_depth: u32,
    #[serde(default)]
    pub color_profile: Option<String>,
    #[serde(default)]
    pub aspect_ratio: Option<String>,
    /// `landscape` / `portrait` as strings — matches the Rails enum's wire
    /// shape (both sides agree on lowercase variant names).
    #[serde(default)]
    pub orientation: Option<String>,
    #[serde(default)]
    pub audio_track_count: u32,
    #[serde(default, with = "crate::api::yes_no")]
    pub has_commentary_track: bool,
}

fn default_bit_depth() -> u32 {
    8
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn footage_record_decodes_yes_no_for_commentary_flag() {
        // The wire format for booleans is the project-wide "yes"/"no" rule.
        let json = r#"{
            "id": 7,
            "local_path": "/footage/a.mp4",
            "filename": "a.mp4",
            "duration_seconds": 120,
            "resolution": "1920x1080",
            "fps": 60.0,
            "codec": "h264",
            "bit_depth": 8,
            "color_profile": "bt709",
            "aspect_ratio": "16:9",
            "orientation": "landscape",
            "audio_track_count": 2,
            "has_commentary_track": "yes"
        }"#;
        let parsed: FootageRecord = serde_json::from_str(json).expect("decode");
        assert_eq!(parsed.id, 7);
        assert!(parsed.has_commentary_track);
    }

    #[test]
    fn footage_record_serializes_yes_no_string() {
        let r = FootageRecord {
            id: 1,
            local_path: "/x".to_string(),
            filename: "x".to_string(),
            duration_seconds: Some(60),
            resolution: Some("1920x1080".to_string()),
            fps: Some(60.0),
            codec: Some("h264".to_string()),
            bit_depth: 8,
            color_profile: None,
            aspect_ratio: Some("16:9".to_string()),
            orientation: Some("landscape".to_string()),
            audio_track_count: 1,
            has_commentary_track: false,
        };
        let value: serde_json::Value = serde_json::to_value(&r).expect("serialize");
        assert_eq!(value["has_commentary_track"], serde_json::json!("no"));
    }

    #[test]
    fn footage_record_handles_missing_optional_columns() {
        // The API may legitimately omit nullable fields; we should accept and
        // round-trip cleanly to defaults.
        let json = r#"{
            "id": 1,
            "local_path": "/x",
            "filename": "x",
            "audio_track_count": 1,
            "has_commentary_track": "no"
        }"#;
        let parsed: FootageRecord = serde_json::from_str(json).expect("decode");
        assert!(parsed.duration_seconds.is_none());
        assert!(parsed.color_profile.is_none());
        // bit_depth default is 8 to match Rails column default.
        assert_eq!(parsed.bit_depth, 8);
    }

    #[test]
    fn footage_record_rejects_native_bool_for_commentary_flag() {
        let json = r#"{
            "id": 1,
            "local_path": "/x",
            "filename": "x",
            "audio_track_count": 1,
            "has_commentary_track": true
        }"#;
        let result: Result<FootageRecord, _> = serde_json::from_str(json);
        assert!(result.is_err(), "native bool must not be accepted");
    }
}
