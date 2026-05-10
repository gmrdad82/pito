//! Integration tests for the Phase 21 `pito games` surfaces.
//!
//! Drives the same `EndpointsClient::games_*` entry points the
//! `commands::games` flows use, end-to-end against a wiremock server.
//! Asserts the on-the-wire shape matches the locked Phase 21 spec
//! (`docs/plans/beta/21-json-endpoints-cli-mcp-parity/specs/01-rails-json-endpoints.md`)
//! and the underlying client decodes it cleanly.

use std::sync::OnceLock;

use pito::api::endpoints::EndpointsClient;
use pito::api::endpoints::games::GamesIndexQuery;
use serde_json::json;
use wiremock::matchers::{method, path, query_param};
use wiremock::{Mock, MockServer, ResponseTemplate};

fn rt() -> &'static tokio::runtime::Runtime {
    static RT: OnceLock<&'static tokio::runtime::Runtime> = OnceLock::new();
    RT.get_or_init(|| {
        let runtime = tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .enable_all()
            .build()
            .expect("tokio runtime");
        Box::leak(Box::new(runtime))
    })
}

fn start_server() -> &'static MockServer {
    let server = rt().block_on(MockServer::start());
    Box::leak(Box::new(server))
}

fn mount(server: &'static MockServer, m: Mock) {
    rt().block_on(async { server.register(m).await });
}

#[test]
fn games_list_decodes_locked_wire_shape() {
    let server = start_server();
    mount(
        server,
        Mock::given(method("GET"))
            .and(path("/games.json"))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!({
                "games": [
                    {
                        "id": 42,
                        "slug": "the-witness",
                        "title": "The Witness",
                        "release_year": 2016,
                        "igdb_rating": 87.4,
                        "platform_owned_id": 3,
                        "played_at": "2024-01-12T00:00:00Z",
                        "cover_image_id": "co1abc",
                        "resyncing": "no",
                        "igdb_synced_at": "2026-05-01T18:21:00Z",
                        "created_at": "2025-12-10T09:14:00Z"
                    }
                ],
                "filter": { "genre_id": null, "platform_owned_id": 3 },
                "sort": { "key": "release_year", "dir": "desc" }
            }))),
    );

    let client = EndpointsClient::new(server.uri(), None);
    let resp = client
        .games_list(&GamesIndexQuery::default())
        .expect("games_list");
    assert_eq!(resp.games.len(), 1);
    assert_eq!(resp.games[0].id, 42);
    assert_eq!(resp.games[0].slug, "the-witness");
    assert!(!resp.games[0].resyncing);
    let sort = resp.sort.expect("sort echo");
    assert_eq!(sort.key.as_deref(), Some("release_year"));
    assert_eq!(sort.dir.as_deref(), Some("desc"));
}

#[test]
fn games_list_forwards_sort_and_pagination_query_params() {
    let server = start_server();
    mount(
        server,
        Mock::given(method("GET"))
            .and(path("/games.json"))
            .and(query_param("sort", "release_year"))
            .and(query_param("dir", "desc"))
            .and(query_param("page", "2"))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!({
                "games": [],
                "filter": null,
                "sort": null
            }))),
    );

    let client = EndpointsClient::new(server.uri(), None);
    let q = GamesIndexQuery {
        sort: Some("release_year".to_string()),
        dir: Some("desc".to_string()),
        page: Some(2),
        ..GamesIndexQuery::default()
    };
    let resp = client.games_list(&q).expect("games_list");
    assert!(resp.games.is_empty());
}

#[test]
fn games_list_returns_empty_games_array() {
    let server = start_server();
    mount(
        server,
        Mock::given(method("GET"))
            .and(path("/games.json"))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!({
                "games": [],
                "filter": null,
                "sort": null
            }))),
    );

    let client = EndpointsClient::new(server.uri(), None);
    let resp = client
        .games_list(&GamesIndexQuery::default())
        .expect("games_list");
    assert!(resp.games.is_empty());
}

#[test]
fn games_list_propagates_500_as_error() {
    let server = start_server();
    mount(
        server,
        Mock::given(method("GET"))
            .and(path("/games.json"))
            .respond_with(ResponseTemplate::new(500)),
    );

    let client = EndpointsClient::new(server.uri(), None);
    let result = client.games_list(&GamesIndexQuery::default());
    assert!(result.is_err());
}

#[test]
fn games_show_decodes_detail_shape_with_genres_and_platforms() {
    let server = start_server();
    mount(
        server,
        Mock::given(method("GET"))
            .and(path("/games/the-witness.json"))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!({
                "game": {
                    "id": 42,
                    "slug": "the-witness",
                    "igdb_id": 18811,
                    "title": "The Witness",
                    "summary": "puzzles",
                    "release_date": "2016-01-26",
                    "release_year": 2016,
                    "igdb_rating": 87.4,
                    "igdb_rating_count": 421,
                    "aggregated_rating": null,
                    "total_rating": null,
                    "total_rating_count": null,
                    "ttb_main_seconds": 36000,
                    "ttb_extras_seconds": null,
                    "ttb_completionist_seconds": null,
                    "external_steam_app_id": "210970",
                    "external_gog_id": null,
                    "external_epic_id": null,
                    "cover_image_id": "co1abc",
                    "platform_owned_id": 3,
                    "played_at": null,
                    "notes": null,
                    "hours_of_footage_manual": 12.5,
                    "hours_of_footage_cached": 8.2,
                    "manual_date_override": "no",
                    "resyncing": "no",
                    "igdb_synced_at": "2026-05-01T18:21:00Z",
                    "last_sync_error": null,
                    "genres": [{ "id": 1, "name": "Puzzle" }],
                    "platforms_owning": [{ "id": 3, "name": "Steam" }],
                    "created_at": "2025-12-10T09:14:00Z",
                    "updated_at": "2026-05-01T18:21:00Z"
                }
            }))),
    );

    let client = EndpointsClient::new(server.uri(), None);
    let resp = client.games_show("the-witness").expect("games_show");
    assert_eq!(resp.game.id, 42);
    assert_eq!(resp.game.slug, "the-witness");
    assert_eq!(resp.game.genres.len(), 1);
    assert_eq!(resp.game.genres[0].name, "Puzzle");
    assert_eq!(resp.game.platforms_owning[0].name, "Steam");
    assert!(!resp.game.manual_date_override);
}

#[test]
fn games_show_handles_integer_id_as_path_segment() {
    // The Rails server 301s integer-id → canonical slug; reqwest follows
    // by default. To assert that behavior, we mount BOTH endpoints: the
    // initial 301 from /games/42.json and the canonical 200 from
    // /games/the-witness.json.
    let server = start_server();
    mount(
        server,
        Mock::given(method("GET"))
            .and(path("/games/42.json"))
            .respond_with(
                ResponseTemplate::new(301).insert_header("Location", "/games/the-witness.json"),
            ),
    );
    mount(
        server,
        Mock::given(method("GET"))
            .and(path("/games/the-witness.json"))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!({
                "game": {
                    "id": 42,
                    "slug": "the-witness",
                    "igdb_id": null,
                    "title": "The Witness",
                    "summary": null,
                    "release_date": null,
                    "release_year": null,
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
                    "genres": [],
                    "platforms_owning": [],
                    "created_at": null,
                    "updated_at": null
                }
            }))),
    );
    let client = EndpointsClient::new(server.uri(), None);
    let resp = client
        .games_show("42")
        .expect("games_show through redirect");
    assert_eq!(resp.game.id, 42);
    assert_eq!(resp.game.slug, "the-witness");
}

#[test]
fn games_show_propagates_404() {
    let server = start_server();
    mount(
        server,
        Mock::given(method("GET"))
            .and(path("/games/unknown.json"))
            .respond_with(ResponseTemplate::new(404).set_body_json(json!({
                "error": "Not found"
            }))),
    );
    let client = EndpointsClient::new(server.uri(), None);
    let result = client.games_show("unknown");
    assert!(result.is_err());
}

#[test]
fn games_resync_decodes_202_envelope() {
    let server = start_server();
    mount(
        server,
        Mock::given(method("POST"))
            .and(path("/games/the-witness/resync.json"))
            .respond_with(ResponseTemplate::new(202).set_body_json(json!({
                "game_id": 42,
                "resyncing": "yes",
                "enqueued_jid": "abc123def456",
                "message": "refreshing from igdb",
                "error": null
            }))),
    );
    let client = EndpointsClient::new(server.uri(), None);
    let resp = client.games_resync("the-witness").expect("resync");
    assert_eq!(resp.game_id, 42);
    assert!(resp.resyncing);
    assert_eq!(resp.enqueued_jid.as_deref(), Some("abc123def456"));
    assert!(resp.error.is_none());
}

#[test]
fn games_resync_decodes_409_envelope_as_ok_with_error_field() {
    // Per spec: a 409 still returns the same envelope shape. Treat as Ok
    // so the caller can distinguish the conflict path via `error`.
    let server = start_server();
    mount(
        server,
        Mock::given(method("POST"))
            .and(path("/games/42/resync.json"))
            .respond_with(ResponseTemplate::new(409).set_body_json(json!({
                "game_id": 42,
                "resyncing": "yes",
                "enqueued_jid": null,
                "message": null,
                "error": "already_resyncing"
            }))),
    );
    let client = EndpointsClient::new(server.uri(), None);
    let resp = client.games_resync("42").expect("resync 409");
    assert!(resp.resyncing);
    assert_eq!(resp.error.as_deref(), Some("already_resyncing"));
    assert!(resp.enqueued_jid.is_none());
}

#[test]
fn games_resync_propagates_500_as_error() {
    let server = start_server();
    mount(
        server,
        Mock::given(method("POST"))
            .and(path("/games/42/resync.json"))
            .respond_with(ResponseTemplate::new(500)),
    );
    let client = EndpointsClient::new(server.uri(), None);
    let result = client.games_resync("42");
    assert!(result.is_err());
}

#[test]
fn games_search_decodes_happy_path() {
    let server = start_server();
    mount(
        server,
        Mock::given(method("GET"))
            .and(path("/games/search.json"))
            .and(query_param("q", "witness"))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!({
                "query": "witness",
                "results": [
                    {
                        "igdb_id": 18811,
                        "title": "The Witness",
                        "release_year": 2016,
                        "cover_image_id": "co1abc",
                        "summary": "..."
                    }
                ],
                "took_ms": 142.0,
                "search_error": null
            }))),
    );
    let client = EndpointsClient::new(server.uri(), None);
    let resp = client.games_search("witness").expect("search");
    assert_eq!(resp.query, "witness");
    assert_eq!(resp.results.len(), 1);
    assert_eq!(resp.results[0].igdb_id, 18811);
    assert!(resp.search_error.is_none());
}

#[test]
fn games_search_decodes_upstream_error_envelope_at_200() {
    // Locked decision #8: HTTP 200 with `search_error` populated, never
    // 502. CLI distinguishes via the envelope field.
    let server = start_server();
    mount(
        server,
        Mock::given(method("GET"))
            .and(path("/games/search.json"))
            .and(query_param("q", "witness"))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!({
                "query": "witness",
                "results": [],
                "took_ms": 0.0,
                "search_error": {
                    "kind": "upstream_unavailable",
                    "message": "IGDB 502"
                }
            }))),
    );
    let client = EndpointsClient::new(server.uri(), None);
    let resp = client.games_search("witness").expect("search");
    assert!(resp.results.is_empty());
    let err = resp.search_error.expect("error envelope");
    assert_eq!(err.kind.as_deref(), Some("upstream_unavailable"));
}

#[test]
fn games_search_url_encodes_spaces() {
    let server = start_server();
    mount(
        server,
        Mock::given(method("GET"))
            .and(path("/games/search.json"))
            .and(query_param("q", "the witness"))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!({
                "query": "the witness",
                "results": [],
                "took_ms": 1.0,
                "search_error": null
            }))),
    );
    let client = EndpointsClient::new(server.uri(), None);
    let resp = client.games_search("the witness").expect("search");
    assert_eq!(resp.query, "the witness");
}

#[test]
fn endpoints_client_attaches_bearer_token_when_present() {
    let server = start_server();
    mount(
        server,
        Mock::given(method("GET"))
            .and(path("/games.json"))
            .and(wiremock::matchers::header(
                "authorization",
                "Bearer pito_secret",
            ))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!({
                "games": [],
                "filter": null,
                "sort": null
            }))),
    );
    let client = EndpointsClient::new(server.uri(), Some("pito_secret".to_string()));
    let resp = client
        .games_list(&GamesIndexQuery::default())
        .expect("games_list with bearer");
    assert!(resp.games.is_empty());
}
