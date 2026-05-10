//! Integration tests for the `pito search <query>` subcommand.
//!
//! Drives the same `PitoClient::search` entry point the `commands::search`
//! flow uses, end-to-end against a wiremock server. Verifies the wire
//! shape matches the Rails `SearchController#search_json_payload` output
//! the Phase 18 spec locks.
//!
//! Threading note: shared leaked tokio runtime to keep the wiremock server
//! out of `reqwest::blocking`'s nested runtime — same trick used by
//! `footage_integration.rs`.

use std::sync::OnceLock;

use pito::api::client::PitoClient;
use pito::api::http_client::HttpClient;
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
fn search_decodes_locked_wire_shape() {
    let server = start_server();
    mount(
        server,
        Mock::given(method("GET"))
            .and(path("/search.json"))
            .and(query_param("q", "rust"))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!({
                "query": "rust",
                "videos": [
                    {
                        "record": {
                            "id": 11,
                            "youtube_video_id": "dQw4w9WgXcQ",
                            "channel_id": 1,
                            "channel_url": "https://youtube.com/@x",
                            "star": "no",
                            "views": 1234,
                            "likes": 56,
                            "comments": 7,
                            "watch_time_minutes": 89.5,
                            "last_synced_at": null,
                            "trend": null
                        },
                        "highlights": null
                    }
                ],
                "video_total": 1,
                "took_ms": 12.3
            }))),
    );

    let client = HttpClient::with_base_url(server.uri());
    let results = client.search("rust").expect("search");
    assert_eq!(results.video_total, 1);
    assert_eq!(results.videos.len(), 1);
    assert_eq!(results.videos[0].record.youtube_video_id, "dQw4w9WgXcQ");
}

#[test]
fn search_handles_empty_results() {
    let server = start_server();
    mount(
        server,
        Mock::given(method("GET"))
            .and(path("/search.json"))
            .and(query_param("q", "nope"))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!({
                "query": "nope",
                "videos": [],
                "video_total": 0,
                "took_ms": 1.0
            }))),
    );

    let client = HttpClient::with_base_url(server.uri());
    let results = client.search("nope").expect("search");
    assert_eq!(results.video_total, 0);
    assert!(results.videos.is_empty());
}

#[test]
fn search_url_encodes_spaces_in_query() {
    // The HttpClient does a naive `' ' -> '+'` replacement; the wiremock
    // matcher checks the decoded query value.
    let server = start_server();
    mount(
        server,
        Mock::given(method("GET"))
            .and(path("/search.json"))
            .and(query_param("q", "rust academy"))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!({
                "query": "rust academy",
                "videos": [],
                "video_total": 0,
                "took_ms": 0.5
            }))),
    );

    let client = HttpClient::with_base_url(server.uri());
    let results = client.search("rust academy").expect("search");
    assert_eq!(results.video_total, 0);
}
