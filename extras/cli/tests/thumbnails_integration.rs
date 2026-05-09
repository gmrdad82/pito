//! Integration tests for the footage-thumbnails HTTP layer
//! (`api::thumbnails`). Each test stands up a wiremock server that responds
//! with the spec-defined JSON / JPEG shapes; the test asserts the client
//! decodes them correctly and that the cache layer round-trips through disk.
//!
//! Phase 7.5 step 06 (CLI half). The Rails endpoint contract these tests
//! anchor:
//!
//! - `GET /footages/:id/frames.json` returns
//!   `{"duration_seconds": <float>, "timestamps": [<u64>, ...]}`.
//! - `GET /footages/:id/frames/<m|t>/<HH-MM-SS>.jpg` returns raw JPEG bytes
//!   with `Content-Type: image/jpeg`.
//!
//! When the Rails dispatch ships these tests act as the wire-shape contract
//! it must honor.

use pito::api::thumbnails::{Cache, Manifest, Tier, fetch_frame_bytes, fetch_manifest};
use serde_json::json;
use tempfile::tempdir;
use wiremock::matchers::{method, path};
use wiremock::{Mock, MockServer, ResponseTemplate};

#[tokio::test]
async fn fetch_manifest_decodes_canonical_response() {
    let server = MockServer::start().await;
    Mock::given(method("GET"))
        .and(path("/footages/7/frames.json"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({
            "duration_seconds": 240.0,
            "timestamps": [60, 120, 180]
        })))
        .mount(&server)
        .await;

    let url = server.uri();
    // `fetch_manifest` is blocking; spawn_blocking keeps the wiremock
    // runtime alive while we hit the synchronous client.
    let manifest = tokio::task::spawn_blocking(move || fetch_manifest(&url, 7))
        .await
        .unwrap()
        .expect("manifest decode");
    assert!((manifest.duration_seconds - 240.0).abs() < f64::EPSILON);
    assert_eq!(manifest.timestamps, vec![60u64, 120, 180]);
}

#[tokio::test]
async fn fetch_manifest_propagates_404() {
    let server = MockServer::start().await;
    Mock::given(method("GET"))
        .and(path("/footages/999/frames.json"))
        .respond_with(ResponseTemplate::new(404))
        .mount(&server)
        .await;

    let url = server.uri();
    let res = tokio::task::spawn_blocking(move || fetch_manifest(&url, 999))
        .await
        .unwrap();
    assert!(res.is_err(), "404 must surface as an Err");
}

#[tokio::test]
async fn fetch_frame_bytes_returns_raw_jpeg() {
    let server = MockServer::start().await;
    let body: Vec<u8> = vec![0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]; // JPEG SOI + APP0 marker prefix
    Mock::given(method("GET"))
        .and(path("/footages/7/frames/m/00-01-30.jpg"))
        .respond_with(
            ResponseTemplate::new(200)
                .insert_header("Content-Type", "image/jpeg")
                .set_body_bytes(body.clone()),
        )
        .mount(&server)
        .await;

    let url = server.uri();
    let bytes = tokio::task::spawn_blocking(move || fetch_frame_bytes(&url, 7, Tier::Master, 90))
        .await
        .unwrap()
        .expect("fetch frame");
    assert_eq!(bytes, body);
}

#[tokio::test]
async fn cache_round_trips_through_fetch_or_get() {
    let server = MockServer::start().await;
    let body: Vec<u8> = vec![0xFF, 0xD8, 0xFF, 0xD9]; // minimal JPEG
    Mock::given(method("GET"))
        .and(path("/footages/7/frames/t/00-00-30.jpg"))
        .respond_with(
            ResponseTemplate::new(200)
                .insert_header("Content-Type", "image/jpeg")
                .set_body_bytes(body.clone()),
        )
        .expect(1) // verify only one HTTP hit even after two cache calls
        .mount(&server)
        .await;

    let dir = tempdir().unwrap();
    let cache_root = dir.path().to_path_buf();

    // First call — cache miss, fetch happens.
    let url = server.uri();
    let cache_root1 = cache_root.clone();
    let body1 = body.clone();
    let url1 = url.clone();
    let bytes1 = tokio::task::spawn_blocking(move || {
        let cache = Cache::with_root(cache_root1, 1_000_000);
        cache.fetch_or_get(7, Tier::Thumb, 30, || {
            fetch_frame_bytes(&url1, 7, Tier::Thumb, 30)
        })
    })
    .await
    .unwrap()
    .expect("first fetch");
    assert_eq!(bytes1, body1);

    // Second call — cache hit, no HTTP traffic. wiremock asserts on drop;
    // the `.expect(1)` above will fail the test if a second HTTP call lands.
    let cache_root2 = cache_root.clone();
    let url2 = url.clone();
    let bytes2 = tokio::task::spawn_blocking(move || {
        let cache = Cache::with_root(cache_root2, 1_000_000);
        cache.fetch_or_get(7, Tier::Thumb, 30, || {
            fetch_frame_bytes(&url2, 7, Tier::Thumb, 30)
        })
    })
    .await
    .unwrap()
    .expect("cache hit");
    assert_eq!(bytes2, body);
}

#[tokio::test]
async fn manifest_decodes_empty_timestamps_when_extraction_pending() {
    // Server-side returns an empty `timestamps` array when a footage row
    // exists but no frames have been extracted yet. The CLI must accept
    // this — the scrub UI renders a "no frames" placeholder instead of
    // exploding.
    let server = MockServer::start().await;
    Mock::given(method("GET"))
        .and(path("/footages/7/frames.json"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({
            "duration_seconds": 0.0,
            "timestamps": []
        })))
        .mount(&server)
        .await;

    let url = server.uri();
    let manifest: Manifest = tokio::task::spawn_blocking(move || fetch_manifest(&url, 7))
        .await
        .unwrap()
        .expect("decode");
    assert!(manifest.timestamps.is_empty());
}
