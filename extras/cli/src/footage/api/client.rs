//! Thin HTTP client for the footages JSON API. Wraps the per-call URL shape
//! and request body assembly so the importer's main flow stays focused on
//! diffing and progress.
//!
//! Endpoints (per spec §7.5, all served by `Api::FootagesController` with
//! Bearer-token auth and `project:write` scope on writes):
//!
//! - `GET    /api/projects/<id>/footages.json` — list existing rows
//! - `POST   /api/projects/<id>/footages.json` — create a new row from a
//!   `ProbedFile`
//! - `PATCH  /api/footages/<id>.json` — update probed metadata on an existing
//!   row
//! - `DELETE /api/footages/<id>.json` — remove a row whose file disappeared
//!
//! All four endpoints live under the `/api/` namespace; collection and member
//! actions are symmetric. (Earlier revisions of the wire contract had member
//! actions at the top level `/footages/:id.json` — Phase 5.5 moved them under
//! `Api::FootagesController` with the rest of the surface.)
//!
//! Booleans across the wire use `"yes"`/`"no"` strings. We assemble the
//! request bodies as `serde_json::Value` so the strong-params wrapper
//! (`{"footage": { ... }}`) and the yes/no rule can be applied directly,
//! mirroring `HttpClient::update_channel_body` in `src/api/http_client.rs`.
//!
//! Response decoding is forgiving: the apply layer treats an HTTP 2xx with an
//! unparseable body as a success-with-warning rather than a failure, so a
//! schema mismatch on the response side does not cause the CLI to falsely
//! report that records weren't written. See [`ApplyOutcome`].

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
    /// Bearer token attached to every request. `None` is allowed for tests
    /// that exercise pure URL / body assembly; member-action writes (PATCH /
    /// DELETE on `/api/footages/:id.json`) refuse to hit the wire when the
    /// token is missing — see [`require_token`].
    token: Option<String>,
}

/// Outcome of a single apply call (POST / PATCH).
///
/// HTTP non-2xx is reported as `Err(...)` and counted as a genuine failure.
/// HTTP 2xx with a decodable body is `Decoded(record)`. HTTP 2xx with an
/// unparseable body is `Unparseable { warning }` — the server accepted the
/// write, so the CLI must classify it as a success even though the response
/// payload was unusable; the `warning` string is surfaced on stderr at the
/// end of the run.
///
/// The `Decoded` payload is not currently read by the importer — the apply
/// step only cares about success/failure plus the optional warning — but it
/// is exposed so that future callers (e.g. a server-side ID round-trip log)
/// can recover the row without re-fetching. Tests pattern-match on it.
#[derive(Debug, Clone)]
pub enum ApplyOutcome {
    /// HTTP 2xx + JSON parsed cleanly into a `FootageRecord`. Boxed because
    /// the record is ~240B while `Unparseable` is only ~24B; clippy's
    /// `large_enum_variant` lint flags the size skew.
    Decoded(#[allow(dead_code)] Box<FootageRecord>),
    /// HTTP 2xx but the response body could not be decoded. The write landed
    /// on the server; the CLI logs the warning and counts the row as success.
    Unparseable { warning: String },
}

impl ApplyOutcome {
    /// True when the operation reached a 2xx server response. Failures land
    /// on the `Err` arm of the surrounding `Result`, never here. Used by
    /// integration tests as a single-call invariant gate.
    #[allow(dead_code)]
    pub fn is_success(&self) -> bool {
        matches!(
            self,
            ApplyOutcome::Decoded(_) | ApplyOutcome::Unparseable { .. }
        )
    }

    /// Optional warning to surface on stderr at the end of the run.
    #[allow(dead_code)]
    pub fn warning(&self) -> Option<&str> {
        match self {
            ApplyOutcome::Decoded(_) => None,
            ApplyOutcome::Unparseable { warning } => Some(warning.as_str()),
        }
    }
}

/// Pre-flight check used by member-action writes. We only require the token
/// at the moment we need it on the wire so tests that exercise pure URL /
/// body builders without an env-configured token continue to work.
fn require_token(token: Option<&str>) -> Result<&str> {
    token.ok_or_else(|| {
        anyhow!(
            "PITO_API_TOKEN env var not set; cannot update/delete footage. \
             Set it from your /settings/tokens page."
        )
    })
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
    ///
    /// Requires `PITO_API_TOKEN` (with the `project:write` scope) — this is a
    /// write against the API surface.
    pub fn create_footage(
        &self,
        project_id: u64,
        probed: &ProbedFile,
        args: &FootageImportArgs,
    ) -> Result<ApplyOutcome> {
        let token = require_token(self.token.as_deref())?;
        let url = self.url(&format!("/api/projects/{}/footages.json", project_id));
        let body = build_create_body(probed, args);
        let resp = self
            .client
            .post(&url)
            .header("Accept", "application/json")
            .header("Content-Type", "application/json")
            .header("Authorization", format!("Bearer {}", token))
            .json(&body)
            .send()
            .with_context(|| format!("POST {}", url))?;
        decode_apply_response(resp, "POST", &url)
    }

    /// `PATCH /api/footages/:id.json` — only the probed metadata fields are
    /// sent. User-managed columns (description, kind, source, game_id,
    /// platform) are intentionally excluded so a re-run doesn't stomp UI
    /// edits. Requires `PITO_API_TOKEN` with `project:write`.
    pub fn update_footage(&self, existing_id: u64, probed: &ProbedFile) -> Result<ApplyOutcome> {
        let token = require_token(self.token.as_deref())?;
        let url = self.url(&format!("/api/footages/{}.json", existing_id));
        let body = build_update_body(probed);
        let resp = self
            .client
            .patch(&url)
            .header("Accept", "application/json")
            .header("Content-Type", "application/json")
            .header("Authorization", format!("Bearer {}", token))
            .json(&body)
            .send()
            .with_context(|| format!("PATCH {}", url))?;
        decode_apply_response(resp, "PATCH", &url)
    }

    /// `DELETE /api/footages/:id.json` — no body, no response payload.
    /// Returns Ok(()) on 2xx; any other status surfaces as an error so the
    /// caller marks the item failed. Requires `PITO_API_TOKEN` with
    /// `project:write`.
    pub fn delete_footage(&self, existing_id: u64) -> Result<()> {
        let token = require_token(self.token.as_deref())?;
        let url = self.url(&format!("/api/footages/{}.json", existing_id));
        let resp = self
            .client
            .delete(&url)
            .header("Accept", "application/json")
            .header("Authorization", format!("Bearer {}", token))
            .send()
            .with_context(|| format!("DELETE {}", url))?;
        let status = resp.status();
        if !status.is_success() {
            return Err(anyhow!("DELETE {} -> {}", url, status));
        }
        Ok(())
    }
}

/// Translate an HTTP response into an [`ApplyOutcome`]. Centralizes the
/// "2xx-but-decode-failed" branch so create / update share the same recovery
/// rule: HTTP non-2xx is a genuine failure, HTTP 2xx + decode failure is a
/// success-with-warning.
fn decode_apply_response(
    resp: reqwest::blocking::Response,
    verb: &str,
    url: &str,
) -> Result<ApplyOutcome> {
    let status = resp.status();
    if !status.is_success() {
        return Err(anyhow!("{} {} -> {}", verb, url, status));
    }
    // Read the body once so we can fall back to a warning if JSON decoding
    // fails. `Response::json` consumes the response, which would prevent us
    // from constructing a useful warning string.
    let body = resp
        .text()
        .with_context(|| format!("read {} {} body", verb, url))?;
    match serde_json::from_str::<FootageRecord>(&body) {
        Ok(row) => Ok(ApplyOutcome::Decoded(Box::new(row))),
        Err(decode_err) => {
            let preview: String = body.chars().take(120).collect();
            let warning = format!(
                "{verb} {url} -> {status} (server accepted the write, but \
                 the response body could not be decoded: {decode_err}; body \
                 preview: {preview:?})"
            );
            Ok(ApplyOutcome::Unparseable { warning })
        }
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
    // `filesize_bytes` is sent unconditionally so the server can clear a stale
    // value: `Some(n)` becomes the integer; `None` becomes JSON `null`,
    // matching how the rest of the symmetric metadata travels.
    footage.insert("filesize_bytes".to_string(), json!(probed.filesize_bytes));
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
            filesize_bytes: Some(2048),
            filename: "a.mp4".to_string(),
            report: baseline_report(),
        }
    }

    #[test]
    fn url_composition_matches_spec_paths() {
        // All four endpoints live under `/api/` post-Phase-5.5; collection and
        // member actions are symmetric.
        let c = FootageApiClient::with_base_url("https://app.pitomd.com", None);
        assert_eq!(
            c.url("/api/projects/3/footages.json"),
            "https://app.pitomd.com/api/projects/3/footages.json"
        );
        assert_eq!(
            c.url("/api/footages/9.json"),
            "https://app.pitomd.com/api/footages/9.json"
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

    #[test]
    fn create_body_includes_filesize_bytes_when_set() {
        let body = build_create_body(&probed(), &args());
        let inner = body.get("footage").unwrap();
        assert_eq!(inner["filesize_bytes"], json!(2048));
    }

    #[test]
    fn create_body_serializes_filesize_bytes_as_null_when_unset() {
        // Production code always populates filesize_bytes, but the wire
        // contract must round-trip None as JSON `null` so the server can
        // distinguish "unknown" from "zero bytes".
        let mut p = probed();
        p.filesize_bytes = None;
        let body = build_create_body(&p, &args());
        let inner = body.get("footage").unwrap();
        assert_eq!(inner["filesize_bytes"], json!(null));
    }

    #[test]
    fn update_body_includes_filesize_bytes() {
        // PATCH carries filesize_bytes alongside the other probe metadata so
        // re-encodes / truncations get reflected on the server.
        let body = build_update_body(&probed());
        let inner = body.get("footage").unwrap();
        assert_eq!(inner["filesize_bytes"], json!(2048));
    }

    #[test]
    fn update_body_serializes_filesize_bytes_as_null_when_unset() {
        let mut p = probed();
        p.filesize_bytes = None;
        let body = build_update_body(&p);
        let inner = body.get("footage").unwrap();
        assert_eq!(inner["filesize_bytes"], json!(null));
    }

    #[test]
    fn require_token_errors_when_token_is_missing() {
        // Member-action writes (and create) refuse to hit the wire without
        // a token — fail fast with a clear message rather than relying on the
        // server to return 401.
        let err = require_token(None).expect_err("missing token must error");
        let msg = err.to_string();
        assert!(
            msg.contains("PITO_API_TOKEN"),
            "error must mention the env var; got: {msg}"
        );
        assert!(
            msg.contains("/settings/tokens"),
            "error must point the user at the tokens page; got: {msg}"
        );
    }

    #[test]
    fn require_token_returns_token_when_present() {
        let token = require_token(Some("abc123")).expect("token present");
        assert_eq!(token, "abc123");
    }

    #[test]
    fn apply_outcome_decoded_is_success_with_no_warning() {
        let outcome = ApplyOutcome::Decoded(Box::new(FootageRecord {
            id: 1,
            local_path: "/x".to_string(),
            filename: "x".to_string(),
            duration_seconds: None,
            resolution: None,
            fps: None,
            codec: None,
            bit_depth: 8,
            color_profile: None,
            aspect_ratio: None,
            orientation: None,
            audio_track_count: 0,
            has_commentary_track: false,
            filesize_bytes: None,
        }));
        assert!(outcome.is_success());
        assert!(outcome.warning().is_none());
    }

    #[test]
    fn apply_outcome_unparseable_is_success_with_warning() {
        let outcome = ApplyOutcome::Unparseable {
            warning: "POST .../footages.json -> 201 (decode failed: ...)".to_string(),
        };
        assert!(
            outcome.is_success(),
            "2xx with bad body still counts as success"
        );
        assert!(
            outcome.warning().is_some(),
            "warning must be carried for stderr"
        );
    }
}
