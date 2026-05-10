//! Integration tests for the `pito views list` subcommand.
//!
//! Drives the same `PitoClient::get_saved_views` entry point the
//! `commands::views::run_list` flow uses, end-to-end against a wiremock
//! server. Asserts the on-the-wire shape matches the locked Phase 18 spec
//! (`{ id, kind, name, url }` per row) and the underlying client decodes
//! it cleanly.
//!
//! Threading note: `reqwest::blocking` spins up its own nested runtime per
//! call, so the wiremock server has to live on a separate, leaked, shared
//! runtime — the same trick the footage integration tests use.

use std::sync::OnceLock;

use pito::api::client::PitoClient;
use pito::api::http_client::HttpClient;
use serde_json::json;
use wiremock::matchers::{method, path};
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
fn get_saved_views_decodes_locked_wire_shape() {
    let server = start_server();
    mount(
        server,
        Mock::given(method("GET"))
            .and(path("/saved_views.json"))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!([
                { "id": 1, "kind": "dashboard", "name": "Weekly", "url": "/dashboard?range=7d" },
                { "id": 2, "kind": "channel", "name": "Rust", "url": "/channels/1" }
            ]))),
    );

    let client = HttpClient::with_base_url(server.uri());
    let views = client.get_saved_views().expect("get_saved_views");

    assert_eq!(views.len(), 2);
    assert_eq!(views[0].id, 1);
    assert_eq!(views[0].kind, "dashboard");
    assert_eq!(views[0].name, "Weekly");
    assert_eq!(views[0].url, "/dashboard?range=7d");
}

#[test]
fn get_saved_views_returns_empty_list_when_server_has_none() {
    let server = start_server();
    mount(
        server,
        Mock::given(method("GET"))
            .and(path("/saved_views.json"))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!([]))),
    );

    let client = HttpClient::with_base_url(server.uri());
    let views = client.get_saved_views().expect("get_saved_views");
    assert!(views.is_empty());
}

#[test]
fn get_saved_views_propagates_5xx_as_error() {
    let server = start_server();
    mount(
        server,
        Mock::given(method("GET"))
            .and(path("/saved_views.json"))
            .respond_with(ResponseTemplate::new(500)),
    );

    let client = HttpClient::with_base_url(server.uri());
    let result = client.get_saved_views();
    assert!(result.is_err());
}
