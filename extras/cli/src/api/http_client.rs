//! Real HTTP client implementing [`PitoClient`] against the Pito Rails backend.
//!
//! The base URL defaults to `https://app.pitomd.com` and can be overridden via
//! the `PITO_API_URL` env var (typically loaded from a `.env` file). Phase 3
//! authentication is not yet wired up — these endpoints are open for now; once
//! tokens land we'll add an `Authorization` header here.
//!
//! We use `reqwest::blocking` to keep the surface compatible with the existing
//! synchronous TUI loop. Going async would require restructuring `App`, the
//! main loop, and the `tick`/poll plumbing, which is out of scope for this
//! milestone.

use std::time::Duration;

use anyhow::{Context, Result};
use serde_json::json;

use super::client::PitoClient;
use super::models::*;

/// Default base URL when the user hasn't set `PITO_API_URL`.
pub const DEFAULT_BASE_URL: &str = "https://app.pitomd.com";

/// Total request timeout, including connect + read. Generous enough for a
/// cold-cache dashboard fetch but short enough that a hung server doesn't
/// freeze the TUI for minutes.
const REQUEST_TIMEOUT: Duration = Duration::from_secs(15);

/// Real HTTP client targeting the Pito Rails JSON API.
pub struct HttpClient {
    base_url: String,
    client: reqwest::blocking::Client,
}

impl HttpClient {
    /// Build an HTTP client. Reads `PITO_API_URL` from the environment;
    /// callers normally call [`dotenvy::dotenv`] before constructing.
    pub fn new() -> Self {
        let base_url =
            std::env::var("PITO_API_URL").unwrap_or_else(|_| DEFAULT_BASE_URL.to_string());
        Self::with_base_url(base_url)
    }

    /// Build a client pinned to the given base URL. Useful for tests and for
    /// callers that read configuration through their own mechanism.
    pub fn with_base_url(base_url: impl Into<String>) -> Self {
        let client = reqwest::blocking::Client::builder()
            .timeout(REQUEST_TIMEOUT)
            .build()
            .expect("reqwest client build");
        Self {
            base_url: base_url.into(),
            client,
        }
    }

    /// Pure helper: how a GET URL gets composed for a relative path. Tested
    /// directly so we can verify URL shapes without making real HTTP calls.
    pub fn url(&self, path: &str) -> String {
        let trimmed_base = self.base_url.trim_end_matches('/');
        let trimmed_path = path.trim_start_matches('/');
        format!("{}/{}", trimmed_base, trimmed_path)
    }

    fn ids_csv(ids: &[u64]) -> String {
        ids.iter()
            .map(|id| id.to_string())
            .collect::<Vec<_>>()
            .join(",")
    }

    /// Pure helper: build the PATCH body for `update_channel`. Lifted out so
    /// we can assert the exact wire shape (Rails strong-params wrapper, yes/no
    /// strings) without making a live HTTP call.
    pub(crate) fn update_channel_body(star: Option<bool>) -> serde_json::Value {
        let mut inner = serde_json::Map::new();
        if let Some(s) = star {
            inner.insert("star".to_string(), json!(if s { "yes" } else { "no" }));
        }
        json!({ "channel": serde_json::Value::Object(inner) })
    }
}

impl Default for HttpClient {
    fn default() -> Self {
        Self::new()
    }
}

impl PitoClient for HttpClient {
    fn get_dashboard(&self) -> Result<DashboardData> {
        let url = self.url("/dashboard.json");
        let response = self
            .client
            .get(&url)
            .header("Accept", "application/json")
            .send()
            .with_context(|| format!("GET {}", url))?
            .error_for_status()
            .with_context(|| format!("status check {}", url))?;
        let data: DashboardData = response
            .json()
            .with_context(|| format!("decode dashboard {}", url))?;
        Ok(data)
    }

    fn get_channels(&self) -> Result<Vec<Channel>> {
        let url = self.url("/channels.json");
        let response = self
            .client
            .get(&url)
            .header("Accept", "application/json")
            .send()
            .with_context(|| format!("GET {}", url))?
            .error_for_status()?;
        let channels: Vec<Channel> = response.json().context("decode channels")?;
        Ok(channels)
    }

    fn get_channel(&self, id: u64) -> Result<Channel> {
        let url = self.url(&format!("/channels/{}.json", id));
        let response = self
            .client
            .get(&url)
            .header("Accept", "application/json")
            .send()
            .with_context(|| format!("GET {}", url))?
            .error_for_status()?;
        let channel: Channel = response.json().context("decode channel")?;
        Ok(channel)
    }

    fn get_channel_videos(&self, channel_id: u64) -> Result<Vec<Video>> {
        let url = self.url(&format!("/channels/{}/videos.json", channel_id));
        let response = self
            .client
            .get(&url)
            .header("Accept", "application/json")
            .send()
            .with_context(|| format!("GET {}", url))?
            .error_for_status()?;
        let videos: Vec<Video> = response.json().context("decode channel videos")?;
        Ok(videos)
    }

    fn get_videos(&self) -> Result<Vec<Video>> {
        let url = self.url("/videos.json");
        let response = self
            .client
            .get(&url)
            .header("Accept", "application/json")
            .send()
            .with_context(|| format!("GET {}", url))?
            .error_for_status()?;
        let videos: Vec<Video> = response.json().context("decode videos")?;
        Ok(videos)
    }

    fn get_video(&self, id: u64) -> Result<Video> {
        let url = self.url(&format!("/videos/{}.json", id));
        let response = self
            .client
            .get(&url)
            .header("Accept", "application/json")
            .send()
            .with_context(|| format!("GET {}", url))?
            .error_for_status()?;
        let video: Video = response.json().context("decode video")?;
        Ok(video)
    }

    fn get_video_stats(&self, video_id: u64) -> Result<Vec<VideoStat>> {
        let url = self.url(&format!("/videos/{}/stats.json", video_id));
        let response = self
            .client
            .get(&url)
            .header("Accept", "application/json")
            .send()
            .with_context(|| format!("GET {}", url))?
            .error_for_status()?;
        let stats: Vec<VideoStat> = response.json().context("decode stats")?;
        Ok(stats)
    }

    fn search(&self, query: &str) -> Result<SearchResults> {
        // Light, naive URL-encoding of the query string. We avoid pulling
        // `urlencoding` in for one call site — `+` and `%20` are the only
        // characters most Pito search queries hit.
        let encoded = query.replace(' ', "+");
        let url = self.url(&format!("/search.json?q={}", encoded));
        let response = self
            .client
            .get(&url)
            .header("Accept", "application/json")
            .send()
            .with_context(|| format!("GET {}", url))?
            .error_for_status()?;
        let results: SearchResults = response.json().context("decode search")?;
        Ok(results)
    }

    fn get_saved_views(&self) -> Result<Vec<SavedView>> {
        let url = self.url("/saved_views.json");
        let response = self
            .client
            .get(&url)
            .header("Accept", "application/json")
            .send()
            .with_context(|| format!("GET {}", url))?
            .error_for_status()?;
        let views: Vec<SavedView> = response.json().context("decode saved views")?;
        Ok(views)
    }

    fn get_settings(&self) -> Result<AppSettings> {
        let url = self.url("/settings.json");
        let response = self
            .client
            .get(&url)
            .header("Accept", "application/json")
            .send()
            .with_context(|| format!("GET {}", url))?
            .error_for_status()?;
        let settings: AppSettings = response.json().context("decode settings")?;
        Ok(settings)
    }

    fn bulk_delete_channels(&self, ids: &[u64], confirm: bool) -> Result<BulkOperationResponse> {
        let url = self.url(&format!("/deletions/channel/{}.json", Self::ids_csv(ids)));
        let request = if confirm {
            self.client
                .post(&url)
                .header("Accept", "application/json")
                .header("Content-Type", "application/json")
        } else {
            self.client.get(&url).header("Accept", "application/json")
        };
        let response = request
            .send()
            .with_context(|| format!("{} {}", if confirm { "POST" } else { "GET" }, url))?
            .error_for_status()?;
        let body: BulkOperationResponse = response.json().context("decode delete response")?;
        Ok(body)
    }

    fn bulk_sync_channels(&self, ids: &[u64], confirm: bool) -> Result<BulkOperationResponse> {
        let url = self.url(&format!("/syncs/channel/{}.json", Self::ids_csv(ids)));
        let request = if confirm {
            self.client
                .post(&url)
                .header("Accept", "application/json")
                .header("Content-Type", "application/json")
        } else {
            self.client.get(&url).header("Accept", "application/json")
        };
        let response = request
            .send()
            .with_context(|| format!("{} {}", if confirm { "POST" } else { "GET" }, url))?
            .error_for_status()?;
        let body: BulkOperationResponse = response.json().context("decode sync response")?;
        Ok(body)
    }

    fn create_channel(&self, channel_url: &str) -> Result<Channel> {
        let url = self.url("/channels.json");
        let body = json!({ "channel": { "channel_url": channel_url } });
        let response = self
            .client
            .post(&url)
            .header("Accept", "application/json")
            .header("Content-Type", "application/json")
            .json(&body)
            .send()
            .with_context(|| format!("POST {}", url))?
            .error_for_status()?;
        let channel: Channel = response.json().context("decode created channel")?;
        Ok(channel)
    }

    fn update_channel(&self, id: u64, star: Option<bool>) -> Result<Channel> {
        let url = self.url(&format!("/channels/{}.json", id));
        // Yes/no string boundary handled by `update_channel_body` — Channel's
        // serde adapter is for round-tripping the model, but PATCH bodies are
        // ad-hoc and need the Rails strong-params `channel: { ... }` wrapper.
        let body = Self::update_channel_body(star);
        let response = self
            .client
            .patch(&url)
            .header("Accept", "application/json")
            .header("Content-Type", "application/json")
            .json(&body)
            .send()
            .with_context(|| format!("PATCH {}", url))?
            .error_for_status()
            .with_context(|| format!("status check PATCH {}", url))?;
        let channel: Channel = response.json().context("decode updated channel")?;
        Ok(channel)
    }

    fn get_bulk_operation_status(&self, id: u64) -> Result<BulkOperationStatus> {
        let url = self.url(&format!("/bulk_operations/{}/status.json", id));
        let response = self
            .client
            .get(&url)
            .header("Accept", "application/json")
            .send()
            .with_context(|| format!("GET {}", url))?
            .error_for_status()?;
        let status: BulkOperationStatus = response.json().context("decode bulk status")?;
        Ok(status)
    }

    fn execute_command(&self, command: &str) -> Result<String> {
        let url = self.url("/commands/execute.json");
        let body = json!({ "command": command });
        let response = self
            .client
            .post(&url)
            .header("Accept", "application/json")
            .header("Content-Type", "application/json")
            .json(&body)
            .send()
            .with_context(|| format!("POST {}", url))?;
        // Try to extract a server error message from the JSON body on failure.
        if !response.status().is_success() {
            let status_code = response.status().as_u16();
            let server_msg = response
                .text()
                .unwrap_or_else(|_| "no response body".to_string());
            return Err(anyhow::anyhow!(
                "server returned {}: {}",
                status_code,
                server_msg
            ));
        }
        let text = response.text().context("read command response")?;
        Ok(text)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn url_uses_default_base_when_env_not_set() {
        // We can't safely mutate the process env in a test without races, so
        // construct directly with the default. The runtime path
        // (HttpClient::new) is exercised manually via cargo run.
        let client = HttpClient::with_base_url(DEFAULT_BASE_URL);
        assert_eq!(
            client.url("/channels.json"),
            "https://app.pitomd.com/channels.json"
        );
    }

    #[test]
    fn url_strips_trailing_slash_on_base_and_leading_on_path() {
        let client = HttpClient::with_base_url("https://example.test/");
        assert_eq!(
            client.url("channels.json"),
            "https://example.test/channels.json"
        );
        assert_eq!(
            client.url("/channels.json"),
            "https://example.test/channels.json"
        );
    }

    #[test]
    fn ids_csv_joins_with_commas() {
        assert_eq!(HttpClient::ids_csv(&[1, 2, 3]), "1,2,3");
        assert_eq!(HttpClient::ids_csv(&[42]), "42");
        assert_eq!(HttpClient::ids_csv(&[]), "");
    }

    #[test]
    fn bulk_delete_url_has_csv_ids() {
        let client = HttpClient::with_base_url("https://app.pitomd.com");
        let url = client.url(&format!(
            "/deletions/channel/{}.json",
            HttpClient::ids_csv(&[10, 11])
        ));
        assert_eq!(url, "https://app.pitomd.com/deletions/channel/10,11.json");
    }

    #[test]
    fn bulk_sync_url_has_csv_ids() {
        let client = HttpClient::with_base_url("https://app.pitomd.com");
        let url = client.url(&format!(
            "/syncs/channel/{}.json",
            HttpClient::ids_csv(&[1])
        ));
        assert_eq!(url, "https://app.pitomd.com/syncs/channel/1.json");
    }

    #[test]
    fn bulk_operation_status_url_includes_id_segment() {
        let client = HttpClient::with_base_url("https://app.pitomd.com");
        let url = client.url(&format!("/bulk_operations/{}/status.json", 42));
        assert_eq!(url, "https://app.pitomd.com/bulk_operations/42/status.json");
    }

    #[test]
    fn update_channel_url_uses_id_segment() {
        // Star toggles must PATCH /channels/<id>.json — verify URL composition.
        let client = HttpClient::with_base_url("https://app.pitomd.com");
        let url = client.url(&format!("/channels/{}.json", 7));
        assert_eq!(url, "https://app.pitomd.com/channels/7.json");
    }

    #[test]
    fn update_channel_body_wraps_in_channel_for_strong_params_with_yes_string() {
        // Rails strong-params requires the `channel: {...}` wrapper, and the
        // codebase rule is yes/no strings (never native bools) on the wire.
        let body = HttpClient::update_channel_body(Some(true));
        assert_eq!(body, serde_json::json!({"channel": {"star": "yes"}}));
    }

    #[test]
    fn update_channel_body_wraps_in_channel_for_strong_params_with_no_string() {
        let body = HttpClient::update_channel_body(Some(false));
        assert_eq!(body, serde_json::json!({"channel": {"star": "no"}}));
    }

    #[test]
    fn update_channel_body_omits_star_when_none() {
        // None means "don't touch this field" — the inner channel object stays
        // empty rather than emitting an explicit null.
        let body = HttpClient::update_channel_body(None);
        assert_eq!(body, serde_json::json!({"channel": {}}));
    }
}
