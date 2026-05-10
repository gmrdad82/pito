//! Phase 21 games JSON surfaces.
//!
//! Wire contract reference:
//! `docs/plans/beta/21-json-endpoints-cli-mcp-parity/specs/01-rails-json-endpoints.md`
//!
//! Endpoints:
//!
//! - `GET /games.json` — paginated index
//! - `GET /games/:id.json` — slug or id (server 301s integer-id to canonical
//!   slug; reqwest follows)
//! - `POST /games/:id/resync.json` — enqueue IGDB resync (202) or conflict
//!   (409 `already_resyncing`)
//! - `GET /games/search.json?q=` — IGDB type-ahead

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};

use super::{EndpointsClient, encode_query_value};

// --- Wire shapes ------------------------------------------------------------

/// Summary row used in `GET /games.json` and (subset) `GET /games/search.json`.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct GameSummary {
    pub id: u64,
    pub slug: String,
    pub title: String,
    pub release_year: Option<u32>,
    pub igdb_rating: Option<f64>,
    pub platform_owned_id: Option<u64>,
    pub played_at: Option<String>,
    pub cover_image_id: Option<String>,
    #[serde(with = "crate::api::yes_no")]
    pub resyncing: bool,
    pub igdb_synced_at: Option<String>,
    pub created_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct GenreRef {
    pub id: u64,
    pub name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct PlatformRef {
    pub id: u64,
    pub name: String,
}

/// Detail row used in `GET /games/:id.json`.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct GameDetail {
    pub id: u64,
    pub slug: String,
    pub igdb_id: Option<u64>,
    pub title: String,
    pub summary: Option<String>,
    pub release_date: Option<String>,
    pub release_year: Option<u32>,
    pub igdb_rating: Option<f64>,
    pub igdb_rating_count: Option<u64>,
    pub aggregated_rating: Option<f64>,
    pub total_rating: Option<f64>,
    pub total_rating_count: Option<u64>,
    pub ttb_main_seconds: Option<u64>,
    pub ttb_extras_seconds: Option<u64>,
    pub ttb_completionist_seconds: Option<u64>,
    pub external_steam_app_id: Option<String>,
    pub external_gog_id: Option<String>,
    pub external_epic_id: Option<String>,
    pub cover_image_id: Option<String>,
    pub platform_owned_id: Option<u64>,
    pub played_at: Option<String>,
    pub notes: Option<String>,
    pub hours_of_footage_manual: Option<f64>,
    pub hours_of_footage_cached: Option<f64>,
    #[serde(with = "crate::api::yes_no")]
    pub manual_date_override: bool,
    #[serde(with = "crate::api::yes_no")]
    pub resyncing: bool,
    pub igdb_synced_at: Option<String>,
    pub last_sync_error: Option<String>,
    #[serde(default)]
    pub genres: Vec<GenreRef>,
    #[serde(default)]
    pub platforms_owning: Vec<PlatformRef>,
    pub created_at: Option<String>,
    pub updated_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GameSortEcho {
    pub key: Option<String>,
    pub dir: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GameFilterEcho {
    pub genre_id: Option<u64>,
    pub platform_owned_id: Option<u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GamesIndexResponse {
    pub games: Vec<GameSummary>,
    #[serde(default)]
    pub filter: Option<GameFilterEcho>,
    #[serde(default)]
    pub sort: Option<GameSortEcho>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GameShowResponse {
    pub game: GameDetail,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GameResyncResponse {
    pub game_id: u64,
    #[serde(with = "crate::api::yes_no")]
    pub resyncing: bool,
    pub enqueued_jid: Option<String>,
    pub message: Option<String>,
    /// `409` body carries this; `202` body omits it. Renamed via serde
    /// alias so both shapes round-trip cleanly.
    pub error: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct GameSearchHit {
    pub igdb_id: u64,
    pub title: String,
    pub release_year: Option<u32>,
    pub cover_image_id: Option<String>,
    pub summary: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GameSearchErrorEnvelope {
    pub kind: Option<String>,
    pub message: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GameSearchResponse {
    pub query: String,
    pub results: Vec<GameSearchHit>,
    pub took_ms: f64,
    pub search_error: Option<GameSearchErrorEnvelope>,
}

// --- Query params -----------------------------------------------------------

/// Query params for `GET /games.json`. All optional; the Rails controller
/// echoes only the ones it understood.
#[derive(Debug, Default, Clone)]
pub struct GamesIndexQuery {
    pub sort: Option<String>,
    pub dir: Option<String>,
    pub page: Option<u32>,
    pub genre: Option<String>,
    pub platform_owned: Option<String>,
}

impl GamesIndexQuery {
    /// Serialize into a query string suffix (`?a=1&b=2`). Returns an empty
    /// string when no params are set.
    pub fn to_query_string(&self) -> String {
        let mut parts: Vec<String> = Vec::new();
        if let Some(s) = &self.sort {
            parts.push(format!("sort={}", encode_query_value(s)));
        }
        if let Some(d) = &self.dir {
            parts.push(format!("dir={}", encode_query_value(d)));
        }
        if let Some(p) = self.page {
            parts.push(format!("page={}", p));
        }
        if let Some(g) = &self.genre {
            parts.push(format!("genre={}", encode_query_value(g)));
        }
        if let Some(p) = &self.platform_owned {
            parts.push(format!("platform_owned={}", encode_query_value(p)));
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
    /// `GET /games.json` — paginated index.
    pub fn games_list(&self, q: &GamesIndexQuery) -> Result<GamesIndexResponse> {
        let url = self.url(&format!("/games.json{}", q.to_query_string()));
        let resp = self
            .with_headers(self.client().get(&url))
            .send()
            .with_context(|| format!("GET {}", url))?
            .error_for_status()
            .with_context(|| format!("status check GET {}", url))?;
        let body: GamesIndexResponse = resp.json().context("decode games index")?;
        Ok(body)
    }

    /// `GET /games/:slug_or_id.json` — slug or integer id.
    /// reqwest follows the canonical-slug 301 transparently.
    pub fn games_show(&self, slug_or_id: &str) -> Result<GameShowResponse> {
        let url = self.url(&format!("/games/{}.json", encode_query_value(slug_or_id)));
        let resp = self
            .with_headers(self.client().get(&url))
            .send()
            .with_context(|| format!("GET {}", url))?
            .error_for_status()
            .with_context(|| format!("status check GET {}", url))?;
        let body: GameShowResponse = resp.json().context("decode game show")?;
        Ok(body)
    }

    /// `POST /games/:slug_or_id/resync.json` — enqueue IGDB resync.
    ///
    /// Returns the response body whether the status was 202 (success) or
    /// 409 (already_resyncing). The caller distinguishes via the `error`
    /// field: `Some("already_resyncing")` means the mutex was held. Non-2xx
    /// other than 409 propagates as `Err`.
    pub fn games_resync(&self, slug_or_id: &str) -> Result<GameResyncResponse> {
        let url = self.url(&format!(
            "/games/{}/resync.json",
            encode_query_value(slug_or_id)
        ));
        let resp = self
            .with_headers(
                self.client()
                    .post(&url)
                    .header("Content-Type", "application/json"),
            )
            .send()
            .with_context(|| format!("POST {}", url))?;
        let status = resp.status();
        // 202 Accepted on enqueue, 409 Conflict on already_resyncing — both
        // return the same envelope shape with `error` toggled.
        if status.as_u16() == 202 || status.as_u16() == 409 {
            let body: GameResyncResponse = resp.json().context("decode resync response")?;
            return Ok(body);
        }
        // Anything else (5xx, 401, 422, etc.) → propagate as error.
        Err(anyhow::anyhow!("POST {} -> {}", url, status))
    }

    /// `GET /games/search.json?q=<query>` — IGDB type-ahead. Empty `q` is
    /// the server's responsibility — we pass it through. The HTTP status is
    /// always 200; check `search_error` for upstream failures (per locked
    /// decision #8).
    pub fn games_search(&self, query: &str) -> Result<GameSearchResponse> {
        let url = self.url(&format!(
            "/games/search.json?q={}",
            encode_query_value(query)
        ));
        let resp = self
            .with_headers(self.client().get(&url))
            .send()
            .with_context(|| format!("GET {}", url))?
            .error_for_status()
            .with_context(|| format!("status check GET {}", url))?;
        let body: GameSearchResponse = resp.json().context("decode game search")?;
        Ok(body)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn games_index_query_empty_string_when_no_params() {
        let q = GamesIndexQuery::default();
        assert_eq!(q.to_query_string(), "");
    }

    #[test]
    fn games_index_query_single_param() {
        let q = GamesIndexQuery {
            page: Some(2),
            ..GamesIndexQuery::default()
        };
        assert_eq!(q.to_query_string(), "?page=2");
    }

    #[test]
    fn games_index_query_combined_params_join_with_ampersand() {
        let q = GamesIndexQuery {
            sort: Some("release_year".to_string()),
            dir: Some("desc".to_string()),
            page: Some(1),
            ..GamesIndexQuery::default()
        };
        let s = q.to_query_string();
        assert!(s.starts_with("?"));
        assert!(s.contains("sort=release_year"));
        assert!(s.contains("dir=desc"));
        assert!(s.contains("page=1"));
        // exactly two ampersands separate three params
        assert_eq!(s.matches('&').count(), 2);
    }

    #[test]
    fn games_index_query_url_encodes_spaces() {
        let q = GamesIndexQuery {
            genre: Some("role playing".to_string()),
            ..GamesIndexQuery::default()
        };
        assert_eq!(q.to_query_string(), "?genre=role+playing");
    }

    #[test]
    fn game_summary_round_trip_uses_yes_no_for_resyncing() {
        let summary = GameSummary {
            id: 42,
            slug: "the-witness".to_string(),
            title: "The Witness".to_string(),
            release_year: Some(2016),
            igdb_rating: Some(87.4),
            platform_owned_id: Some(3),
            played_at: Some("2024-01-12T00:00:00Z".to_string()),
            cover_image_id: Some("co1abc".to_string()),
            resyncing: false,
            igdb_synced_at: Some("2026-05-01T18:21:00Z".to_string()),
            created_at: Some("2025-12-10T09:14:00Z".to_string()),
        };
        let s = serde_json::to_string(&summary).expect("serialize");
        assert!(s.contains("\"resyncing\":\"no\""));
        let parsed: GameSummary = serde_json::from_str(&s).expect("deserialize");
        assert_eq!(parsed, summary);
    }

    #[test]
    fn game_detail_decodes_genres_and_platforms_arrays() {
        let json = r#"{
            "id": 42,
            "slug": "the-witness",
            "igdb_id": 18811,
            "title": "The Witness",
            "summary": null,
            "release_date": null,
            "release_year": 2016,
            "igdb_rating": null,
            "igdb_rating_count": null,
            "aggregated_rating": null,
            "total_rating": null,
            "total_rating_count": null,
            "ttb_main_seconds": null,
            "ttb_extras_seconds": null,
            "ttb_completionist_seconds": null,
            "external_steam_app_id": null,
            "external_gog_id": null,
            "external_epic_id": null,
            "cover_image_id": null,
            "platform_owned_id": null,
            "played_at": null,
            "notes": null,
            "hours_of_footage_manual": null,
            "hours_of_footage_cached": null,
            "manual_date_override": "no",
            "resyncing": "no",
            "igdb_synced_at": null,
            "last_sync_error": null,
            "genres": [{ "id": 1, "name": "Puzzle" }],
            "platforms_owning": [{ "id": 3, "name": "Steam" }],
            "created_at": null,
            "updated_at": null
        }"#;
        let parsed: GameDetail = serde_json::from_str(json).expect("deserialize");
        assert_eq!(parsed.id, 42);
        assert_eq!(parsed.genres.len(), 1);
        assert_eq!(parsed.genres[0].name, "Puzzle");
        assert_eq!(parsed.platforms_owning[0].name, "Steam");
        assert!(!parsed.manual_date_override);
        assert!(!parsed.resyncing);
    }

    #[test]
    fn game_resync_response_decodes_202_envelope() {
        let json = r#"{
            "game_id": 42,
            "resyncing": "yes",
            "enqueued_jid": "abc123",
            "message": "refreshing from igdb",
            "error": null
        }"#;
        let parsed: GameResyncResponse = serde_json::from_str(json).expect("deserialize");
        assert_eq!(parsed.game_id, 42);
        assert!(parsed.resyncing);
        assert_eq!(parsed.enqueued_jid.as_deref(), Some("abc123"));
        assert!(parsed.error.is_none());
    }

    #[test]
    fn game_resync_response_decodes_409_envelope() {
        let json = r#"{
            "game_id": 42,
            "resyncing": "yes",
            "enqueued_jid": null,
            "message": null,
            "error": "already_resyncing"
        }"#;
        let parsed: GameResyncResponse = serde_json::from_str(json).expect("deserialize");
        assert!(parsed.resyncing);
        assert_eq!(parsed.error.as_deref(), Some("already_resyncing"));
        assert!(parsed.enqueued_jid.is_none());
    }

    #[test]
    fn game_search_response_decodes_with_error_envelope_and_empty_results() {
        let json = r#"{
            "query": "witness",
            "results": [],
            "took_ms": 0.0,
            "search_error": { "kind": "upstream_unavailable", "message": "IGDB 502" }
        }"#;
        let parsed: GameSearchResponse = serde_json::from_str(json).expect("deserialize");
        assert!(parsed.results.is_empty());
        let err = parsed.search_error.expect("error envelope");
        assert_eq!(err.kind.as_deref(), Some("upstream_unavailable"));
    }

    #[test]
    fn game_search_response_decodes_happy_path() {
        let json = r#"{
            "query": "witness",
            "results": [
                {
                    "igdb_id": 18811,
                    "title": "The Witness",
                    "release_year": 2016,
                    "cover_image_id": "co1abc",
                    "summary": "puzzles"
                }
            ],
            "took_ms": 142.0,
            "search_error": null
        }"#;
        let parsed: GameSearchResponse = serde_json::from_str(json).expect("deserialize");
        assert_eq!(parsed.results.len(), 1);
        assert_eq!(parsed.results[0].igdb_id, 18811);
        assert!(parsed.search_error.is_none());
        assert!((parsed.took_ms - 142.0).abs() < f64::EPSILON);
    }
}
