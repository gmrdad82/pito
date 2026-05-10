//! HTTP client surfaces for the Phase 21 JSON endpoints.
//!
//! Phase 21 (`docs/plans/beta/21-json-endpoints-cli-mcp-parity/`) added a
//! JSON contract to `GamesController`, the `Calendar::*Controller` family,
//! and `NotificationsController`. The `pito` CLI consumes those endpoints
//! from a thin client layer kept separate from the legacy `PitoClient`
//! trait so the new surfaces don't bloat that trait's signature.
//!
//! Conventions inherited from the rest of `extras/cli/`:
//!
//! - Booleans across the wire are `"yes"` / `"no"` strings — handled
//!   automatically via `crate::api::yes_no` adapters on model fields.
//! - Bearer auth: when a token is present we attach
//!   `Authorization: Bearer <token>` so future migration to bearer auth on
//!   these surfaces is transparent. The Phase 21 spec rides cookie auth
//!   for now; the header is ignored server-side but doesn't hurt.
//! - URL composition: `{base_url}/{path}` with both edges trimmed.
//! - All endpoints return `anyhow::Result<T>`.

pub mod calendar;
pub mod games;
pub mod notifications;

use std::time::Duration;

use reqwest::blocking::{Client, RequestBuilder};

/// Total request timeout (connect + read). Matches the rest of the CLI.
pub(crate) const REQUEST_TIMEOUT: Duration = Duration::from_secs(15);

/// Thin handle holding the reqwest client, base URL, and optional bearer
/// token. Used by the per-domain endpoint modules so each call site can
/// stay short.
pub struct EndpointsClient {
    base_url: String,
    client: Client,
    token: Option<String>,
}

impl EndpointsClient {
    /// Build a client pinned to the given base URL with an optional bearer
    /// token. `None` means "send no Authorization header"; suitable for
    /// tests and for cookie-session callers.
    pub fn new(base_url: impl Into<String>, token: Option<String>) -> Self {
        let client = Client::builder()
            .timeout(REQUEST_TIMEOUT)
            .build()
            .expect("reqwest client build");
        Self {
            base_url: base_url.into(),
            client,
            token,
        }
    }

    /// Pure helper: compose a full URL from a path. Trims a trailing slash
    /// on the base and a leading slash on the path.
    pub fn url(&self, path: &str) -> String {
        let trimmed_base = self.base_url.trim_end_matches('/');
        let trimmed_path = path.trim_start_matches('/');
        format!("{}/{}", trimmed_base, trimmed_path)
    }

    /// Attach the standard JSON accept + optional bearer headers to a
    /// reqwest request builder.
    pub(crate) fn with_headers(&self, mut req: RequestBuilder) -> RequestBuilder {
        req = req.header("Accept", "application/json");
        if let Some(t) = self.token.as_deref() {
            req = req.header("Authorization", format!("Bearer {}", t));
        }
        req
    }

    pub(crate) fn client(&self) -> &Client {
        &self.client
    }
}

/// Naive URL-encoding for a single query value. We avoid pulling
/// `urlencoding` in for a handful of call sites — `+` for spaces is the
/// only frequent case in pito query strings. Anything more exotic is the
/// caller's job. Mirrors `HttpClient::search`'s approach.
pub(crate) fn encode_query_value(value: &str) -> String {
    value.replace(' ', "+")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn endpoints_client_url_trims_edges() {
        let client = EndpointsClient::new("https://example.test/", None);
        assert_eq!(client.url("/games.json"), "https://example.test/games.json");
        assert_eq!(client.url("games.json"), "https://example.test/games.json");
    }

    #[test]
    fn encode_query_value_replaces_spaces_with_plus() {
        assert_eq!(encode_query_value("hello world"), "hello+world");
        assert_eq!(encode_query_value("simple"), "simple");
        assert_eq!(encode_query_value(""), "");
    }
}
