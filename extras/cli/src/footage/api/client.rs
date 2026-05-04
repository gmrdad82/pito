//! Thin HTTP client for the footages JSON API. Wraps the per-call URL shape
//! and request body assembly so the importer's main flow stays focused on
//! diffing and progress.
//!
//! Endpoints (per spec §7.5, with the URL contract correction landed
//! 2026-05-04 to match what Rails actually exposes):
//!
//! - `GET /api/projects/<id>/footages.json` — list existing rows
//! - `POST /api/projects/<id>/footages.json` — create a new row from a
//!   `ProbedFile`
//! - `PATCH /footages/<id>.json` — update probed metadata on an existing row
//! - `DELETE /footages/<id>.json` — remove a row whose file disappeared
//!
//! Asymmetry note: collection actions (POST / GET) live under the `/api/`
//! namespace and use the plural `footages`, while member actions (PATCH /
//! DELETE) hit `/footages/:id.json` at the top level — those are served by
//! `FootagesController` (not `Api::FootagesController`). API-surface symmetry
//! is a separate follow-up; we mirror Rails as it is today.
//!
//! Booleans across the wire use `"yes"`/`"no"` strings. We assemble the
//! request bodies as `serde_json::Value` so the strong-params wrapper
//! (`{"footage": { ... }}`) and the yes/no rule can be applied directly,
//! mirroring `HttpClient::update_channel_body` in `src/api/http_client.rs`.

use std::time::Duration;

use anyhow::{Context, Result, anyhow};
use serde_json::{Value, json};

use crate::cli::FootageImportArgs;
use crate::footage::api::models::{FootageRecord, ProbedFile};

/// Default base URL when the user hasn't set `PITO_API_URL`. Matches the
/// shared default in `src/api/http_client.rs`.
pub const DEFAULT_BASE_URL: &str = "https://app.pitomd.com";

/// Total request timeout (connect + read). Matches the rest of the CLI.
const REQUEST_TIMEOUT: Duration = Duration::from_secs(15);

/// HTTP client targeting the Rails footages JSON API.
pub struct FootageApiClient {
    base_url: String,
    client: reqwest::blocking::Client,
    /// Optional bearer token. Reserved for the auth phase — not sent today.
    #[allow(dead_code)]
    token: Option<String>,
}

impl FootageApiClient {
    /// Build a client from the environment: `PITO_API_URL` (default
    /// `https://app.pitomd.com`) and `PITO_API_TOKEN` (optional).
    pub fn from_env() -> Self {
        let base_url =
            std::env::var("PITO_API_URL").unwrap_or_else(|_| DEFAULT_BASE_URL.to_string());
        let token = std::env::var("PITO_API_TOKEN")
            .ok()
            .filter(|s| !s.is_empty());
        Self::with_base_url(base_url, token)
    }

    /// Build a client pinned to a base URL — the test entry point.
    pub fn with_base_url(base_url: impl Into<String>, token: Option<String>) -> Self {
        let client = reqwest::blocking::Client::builder()
            .timeout(REQUEST_TIMEOUT)
            .build()
            .expect("reqwest client build");
        Self {
            base_url: base_url.into(),
            client,
            token,
        }
    }

    fn url(&self, path: &str) -> String {
        let trimmed_base = self.base_url.trim_end_matches('/');
        let trimmed_path = path.trim_start_matches('/');
        format!("{}/{}", trimmed_base, trimmed_path)
    }

    /// `GET /api/projects/:project_id/footages.json` → existing rows.
    pub fn list_footage(&self, project_id: u64) -> Result<Vec<FootageRecord>> {
        let url = self.url(&format!("/api/projects/{}/footages.json", project_id));
        let mut req = self.client.get(&url).header("Accept", "application/json");
        if let Some(t) = self.token.as_deref() {
            req = req.header("Authorization", format!("Bearer {}", t));
        }
        let resp = req
            .send()
            .with_context(|| format!("GET {}", url))?
            .error_for_status()
            .with_context(|| format!("status check GET {}", url))?;
        let rows: Vec<FootageRecord> = resp.json().context("decode footage list")?;
        Ok(rows)
    }

    /// `POST /api/projects/:project_id/footages.json` — body assembled from
    /// the probed file plus the per-run defaults (kind, source, description,
    /// optional game/platform/nas_path).
    pub fn create_footage(
        &self,
        project_id: u64,
        probed: &ProbedFile,
        args: &FootageImportArgs,
    ) -> Result<FootageRecord> {
        let url = self.url(&format!("/api/projects/{}/footages.json", project_id));
        let body = build_create_body(probed, args);
        let resp = self
            .post_json(&url, &body)
            .with_context(|| format!("POST {}", url))?;
        let row: FootageRecord = resp.json().context("decode created footage")?;
        Ok(row)
    }

    /// `PATCH /footages/:id.json` — only the probed metadata fields are sent.
    /// User-managed columns (description, kind, source, game_id, platform)
    /// are intentionally excluded so a re-run doesn't stomp UI edits.
    pub fn update_footage(&self, existing_id: u64, probed: &ProbedFile) -> Result<FootageRecord> {
        let url = self.url(&format!("/footages/{}.json", existing_id));
        let body = build_update_body(probed);
        let mut req = self
            .client
            .patch(&url)
            .header("Accept", "application/json")
            .header("Content-Type", "application/json")
            .json(&body);
        if let Some(t) = self.token.as_deref() {
            req = req.header("Authorization", format!("Bearer {}", t));
        }
        let resp = req
            .send()
            .with_context(|| format!("PATCH {}", url))?
            .error_for_status()
            .with_context(|| format!("status check PATCH {}", url))?;
        let row: FootageRecord = resp.json().context("decode updated footage")?;
        Ok(row)
    }

    /// `DELETE /footages/:id.json` — no body, no response payload. Returns
    /// Ok(()) on 2xx; any other status surfaces as an error so the caller
    /// marks the item failed.
    pub fn delete_footage(&self, existing_id: u64) -> Result<()> {
        let url = self.url(&format!("/footages/{}.json", existing_id));
        let mut req = self
            .client
            .delete(&url)
            .header("Accept", "application/json");
        if let Some(t) = self.token.as_deref() {
            req = req.header("Authorization", format!("Bearer {}", t));
        }
        let resp = req.send().with_context(|| format!("DELETE {}", url))?;
        let status = resp.status();
        if !status.is_success() {
            return Err(anyhow!("DELETE {} -> {}", url, status));
        }
        Ok(())
    }

    fn post_json(&self, url: &str, body: &Value) -> Result<reqwest::blocking::Response> {
        let mut req = self
            .client
            .post(url)
            .header("Accept", "application/json")
            .header("Content-Type", "application/json")
            .json(body);
        if let Some(t) = self.token.as_deref() {
            req = req.header("Authorization", format!("Bearer {}", t));
        }
        let resp = req.send()?.error_for_status()?;
        Ok(resp)
    }
}

/// Pure helper: assemble the POST body for `create_footage`. Rails strong
/// params expects the payload wrapped in a `footage:` key. Booleans serialize
/// as `"yes"`/`"no"` strings.
pub fn build_create_body(probed: &ProbedFile, args: &FootageImportArgs) -> Value {
    let mut footage = serde_json::Map::new();
    footage.insert("local_path".to_string(), json!(probed.local_path));
    footage.insert("filename".to_string(), json!(probed.filename));
    footage.insert("kind".to_string(), json!(args.kind.as_wire()));
    footage.insert("source".to_string(), json!(args.source.as_wire()));
    if let Some(game_id) = args.game {
        footage.insert("game_id".to_string(), json!(game_id));
    }
    if let Some(ref platform) = args.platform {
        footage.insert("platform".to_string(), json!(platform));
    }
    if let Some(ref desc) = args.description {
        footage.insert("description".to_string(), json!(desc));
    }
    if let Some(ref nas) = args.nas_path {
        footage.insert("nas_path".to_string(), json!(nas));
    }
    insert_probe_fields(&mut footage, probed);
    json!({ "footage": Value::Object(footage) })
}

/// Pure helper: assemble the PATCH body for `update_footage`. Only probed
/// metadata travels — user-managed columns are off-limits to re-runs.
pub fn build_update_body(probed: &ProbedFile) -> Value {
    let mut footage = serde_json::Map::new();
    footage.insert("filename".to_string(), json!(probed.filename));
    insert_probe_fields(&mut footage, probed);
    json!({ "footage": Value::Object(footage) })
}

/// Insert the probed-metadata fields into a `footage:` body. Shared between
/// create and update so the wire shape stays identical for the columns we
/// derive from ffprobe.
fn insert_probe_fields(footage: &mut serde_json::Map<String, Value>, probed: &ProbedFile) {
    let r = &probed.report;
    insert_optional(
        footage,
        "duration_seconds",
        r.duration_seconds.map(json_u64),
    );
    insert_optional(
        footage,
        "resolution",
        r.resolution.as_ref().map(|s| json!(s)),
    );
    insert_optional(footage, "fps", r.fps.map(json_f64));
    insert_optional(footage, "codec", r.codec.as_ref().map(|s| json!(s)));
    footage.insert("bit_depth".to_string(), json!(r.bit_depth));
    insert_optional(
        footage,
        "color_profile",
        r.color_profile.as_ref().map(|s| json!(s)),
    );
    insert_optional(
        footage,
        "aspect_ratio",
        r.aspect_ratio.as_ref().map(|s| json!(s)),
    );
    insert_optional(
        footage,
        "orientation",
        r.orientation.map(|o| json!(o.as_wire())),
    );
    footage.insert("audio_track_count".to_string(), json!(r.audio_track_count));
    footage.insert(
        "has_commentary_track".to_string(),
        json!(if r.has_commentary_track { "yes" } else { "no" }),
    );
    insert_optional(
        footage,
        "recorded_at",
        r.recorded_at.as_ref().map(|s| json!(s)),
    );
}

fn insert_optional(map: &mut serde_json::Map<String, Value>, key: &str, value: Option<Value>) {
    if let Some(v) = value {
        map.insert(key.to_string(), v);
    }
}

fn json_u64(n: u64) -> Value {
    json!(n)
}

fn json_f64(f: f64) -> Value {
    json!(f)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::cli::{FootageImportArgs, FootageKindArg, FootageSourceArg};
    use crate::footage::probe::ffprobe::{Orientation, ProbeReport};

    fn args() -> FootageImportArgs {
        FootageImportArgs {
            project: 1,
            path: std::path::PathBuf::from("/tmp"),
            game: None,
            platform: None,
            kind: FootageKindArg::ARoll,
            source: FootageSourceArg::Obs,
            description: None,
            nas_path: None,
            dry_run: false,
        }
    }

    fn baseline_report() -> ProbeReport {
        ProbeReport {
            duration_seconds: Some(120),
            resolution: Some("1920x1080".to_string()),
            fps: Some(60.0),
            codec: Some("h264".to_string()),
            bit_depth: 8,
            color_profile: Some("bt709".to_string()),
            aspect_ratio: Some("16:9".to_string()),
            orientation: Some(Orientation::Landscape),
            audio_track_count: 2,
            has_commentary_track: true,
            recorded_at: Some("2026-04-01T10:00:00Z".to_string()),
        }
    }

    fn probed() -> ProbedFile {
        ProbedFile {
            local_path: "/footage/a.mp4".to_string(),
            filename: "a.mp4".to_string(),
            report: baseline_report(),
        }
    }

    #[test]
    fn url_composition_matches_spec_paths() {
        // Collection actions live under `/api/` with the plural `footages`;
        // member actions (PATCH/DELETE) stay at the top level `/footages/:id`.
        let c = FootageApiClient::with_base_url("https://app.pitomd.com", None);
        assert_eq!(
            c.url("/api/projects/3/footages.json"),
            "https://app.pitomd.com/api/projects/3/footages.json"
        );
        assert_eq!(
            c.url("/footages/9.json"),
            "https://app.pitomd.com/footages/9.json"
        );
    }

    #[test]
    fn url_strips_trailing_and_leading_slashes() {
        let c = FootageApiClient::with_base_url("https://example.test/", None);
        assert_eq!(
            c.url("api/projects/1/footages.json"),
            "https://example.test/api/projects/1/footages.json"
        );
    }

    #[test]
    fn create_body_wraps_in_footage_for_strong_params() {
        let body = build_create_body(&probed(), &args());
        // Outer key is `footage` per Rails strong params.
        assert!(body.get("footage").is_some(), "expected `footage:` wrapper");
    }

    #[test]
    fn create_body_serializes_commentary_flag_as_yes_no_string() {
        let body = build_create_body(&probed(), &args());
        let inner = body.get("footage").unwrap();
        assert_eq!(inner["has_commentary_track"], json!("yes"));
    }

    #[test]
    fn create_body_includes_kind_and_source_as_wire_strings() {
        let mut a = args();
        a.kind = FootageKindArg::BRoll;
        a.source = FootageSourceArg::Camera;
        let body = build_create_body(&probed(), &a);
        let inner = body.get("footage").unwrap();
        assert_eq!(inner["kind"], json!("b_roll"));
        assert_eq!(inner["source"], json!("camera"));
    }

    #[test]
    fn create_body_includes_optional_game_and_platform_when_set() {
        let mut a = args();
        a.game = Some(42);
        a.platform = Some("PS5".to_string());
        let body = build_create_body(&probed(), &a);
        let inner = body.get("footage").unwrap();
        assert_eq!(inner["game_id"], json!(42));
        assert_eq!(inner["platform"], json!("PS5"));
    }

    #[test]
    fn create_body_omits_optional_keys_when_unset() {
        let body = build_create_body(&probed(), &args());
        let inner = body.get("footage").unwrap().as_object().unwrap();
        // Optional columns the user didn't set must not appear at all (so
        // Rails uses model defaults / nullable columns).
        assert!(!inner.contains_key("game_id"));
        assert!(!inner.contains_key("platform"));
        assert!(!inner.contains_key("description"));
        assert!(!inner.contains_key("nas_path"));
    }

    #[test]
    fn create_body_includes_color_profile_when_set() {
        let body = build_create_body(&probed(), &args());
        let inner = body.get("footage").unwrap();
        assert_eq!(inner["color_profile"], json!("bt709"));
    }

    #[test]
    fn create_body_omits_color_profile_when_unknown() {
        let mut p = probed();
        p.report.color_profile = None;
        let body = build_create_body(&p, &args());
        let inner = body.get("footage").unwrap().as_object().unwrap();
        // null color profile: column stays nullable in Rails, omit on the wire.
        assert!(!inner.contains_key("color_profile"));
    }

    #[test]
    fn create_body_includes_orientation_as_lowercase_wire_string() {
        let body = build_create_body(&probed(), &args());
        let inner = body.get("footage").unwrap();
        assert_eq!(inner["orientation"], json!("landscape"));
    }

    #[test]
    fn create_body_includes_recorded_at_when_present() {
        let body = build_create_body(&probed(), &args());
        let inner = body.get("footage").unwrap();
        assert_eq!(inner["recorded_at"], json!("2026-04-01T10:00:00Z"));
    }

    #[test]
    fn update_body_omits_user_managed_columns() {
        // PATCH bodies must NOT carry kind/source/description/game_id/platform —
        // those are user-managed in the web UI and a re-run shouldn't stomp
        // them.
        let body = build_update_body(&probed());
        let inner = body.get("footage").unwrap().as_object().unwrap();
        assert!(!inner.contains_key("kind"));
        assert!(!inner.contains_key("source"));
        assert!(!inner.contains_key("description"));
        assert!(!inner.contains_key("game_id"));
        assert!(!inner.contains_key("platform"));
        assert!(!inner.contains_key("nas_path"));
        assert!(!inner.contains_key("local_path"));
    }

    #[test]
    fn update_body_carries_probe_metadata() {
        let body = build_update_body(&probed());
        let inner = body.get("footage").unwrap();
        assert_eq!(inner["resolution"], json!("1920x1080"));
        assert_eq!(inner["bit_depth"], json!(8));
        assert_eq!(inner["has_commentary_track"], json!("yes"));
        assert_eq!(inner["filename"], json!("a.mp4"));
    }
}
