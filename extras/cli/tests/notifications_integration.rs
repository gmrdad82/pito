//! Integration tests for the Phase 21 `pito notifications` surfaces.
//!
//! Drives `EndpointsClient::notifications_*` and
//! `EndpointsClient::notification_mark_*` methods against a wiremock
//! server. Pins the locked decision #2 wire change (single-record
//! PATCH endpoints return 200 + body, not 204) and the badge envelope
//! per locked decision #6.

use std::sync::OnceLock;

use pito::api::endpoints::EndpointsClient;
use pito::api::endpoints::notifications::NotificationsIndexQuery;
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
fn notifications_list_decodes_locked_wire_shape() {
    let server = start_server();
    mount(
        server,
        Mock::given(method("GET"))
            .and(path("/notifications.json"))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!({
                "page": 1,
                "total_pages": 3,
                "total": 124,
                "per_page": 50,
                "filter": "unread",
                "kind": null,
                "severity": null,
                "unread_count": 17,
                "has_failures": "yes",
                "notifications": [
                    {
                        "id": 91,
                        "kind": "video_published",
                        "severity": "success",
                        "event_type": "video.published",
                        "title": "video published",
                        "body": "...",
                        "url": "/videos/abc",
                        "fires_at": "2026-05-10T17:00:00Z",
                        "in_app_read_at": null,
                        "read": "no",
                        "discord_delivered_at": "2026-05-10T17:00:01Z",
                        "slack_delivered_at": null,
                        "retry_count": 0,
                        "last_error": null,
                        "created_at": "2026-05-10T17:00:00Z"
                    }
                ]
            }))),
    );
    let client = EndpointsClient::new(server.uri(), None);
    let resp = client
        .notifications_list(&NotificationsIndexQuery::default())
        .expect("list");
    assert_eq!(resp.page, 1);
    assert_eq!(resp.total, 124);
    assert_eq!(resp.unread_count, 17);
    assert!(resp.has_failures);
    assert_eq!(resp.notifications.len(), 1);
    assert_eq!(resp.notifications[0].id, 91);
    assert!(!resp.notifications[0].read);
}

#[test]
fn notifications_list_forwards_filter_kind_severity_page() {
    let server = start_server();
    mount(
        server,
        Mock::given(method("GET"))
            .and(path("/notifications.json"))
            .and(query_param("filter", "unread"))
            .and(query_param("kind", "video_published"))
            .and(query_param("severity", "success"))
            .and(query_param("page", "2"))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!({
                "page": 2,
                "total_pages": 3,
                "total": 124,
                "per_page": 50,
                "filter": "unread",
                "kind": "video_published",
                "severity": "success",
                "unread_count": 17,
                "has_failures": "no",
                "notifications": []
            }))),
    );
    let client = EndpointsClient::new(server.uri(), None);
    let q = NotificationsIndexQuery {
        filter: Some("unread".to_string()),
        kind: Some("video_published".to_string()),
        severity: Some("success".to_string()),
        page: Some(2),
    };
    let resp = client.notifications_list(&q).expect("list");
    assert_eq!(resp.page, 2);
    assert!(!resp.has_failures);
}

#[test]
fn notifications_show_decodes_detail_plus_payload() {
    let server = start_server();
    mount(
        server,
        Mock::given(method("GET"))
            .and(path("/notifications/91.json"))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!({
                "notification": {
                    "id": 91,
                    "kind": "video_published",
                    "severity": "success",
                    "event_type": "video.published",
                    "title": "video published",
                    "body": "...",
                    "url": "/videos/abc",
                    "fires_at": "2026-05-10T17:00:00Z",
                    "in_app_read_at": null,
                    "read": "no",
                    "discord_delivered_at": null,
                    "slack_delivered_at": null,
                    "retry_count": 0,
                    "last_error": null,
                    "created_at": "2026-05-10T17:00:00Z"
                },
                "payload": { "video_id": 1, "title": "..." }
            }))),
    );
    let client = EndpointsClient::new(server.uri(), None);
    let resp = client.notifications_show(91).expect("show");
    assert_eq!(resp.notification.id, 91);
    assert!(resp.payload.is_some());
}

#[test]
fn notifications_badge_decodes_locked_envelope() {
    let server = start_server();
    mount(
        server,
        Mock::given(method("GET"))
            .and(path("/notifications/badge.json"))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!({
                "unread_count": 17,
                "has_failures": "yes"
            }))),
    );
    let client = EndpointsClient::new(server.uri(), None);
    let resp = client.notifications_badge().expect("badge");
    assert_eq!(resp.unread_count, 17);
    assert!(resp.has_failures);
}

#[test]
fn notification_mark_read_single_decodes_200_body_per_locked_decision_2() {
    // Locked decision #2: the 204 → 200 + body upgrade. Server now
    // returns the full state-change envelope.
    let server = start_server();
    mount(
        server,
        Mock::given(method("PATCH"))
            .and(path("/notifications/91/read.json"))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!({
                "id": 91,
                "read": "yes",
                "in_app_read_at": "2026-05-10T18:42:00Z",
                "unread_count": 16
            }))),
    );
    let client = EndpointsClient::new(server.uri(), None);
    let resp = client.notification_mark_read_single(91).expect("read");
    assert_eq!(resp.id, 91);
    assert!(resp.read);
    assert_eq!(resp.unread_count, 16);
    assert_eq!(resp.in_app_read_at.as_deref(), Some("2026-05-10T18:42:00Z"));
}

#[test]
fn notification_mark_unread_single_decodes_200_body() {
    let server = start_server();
    mount(
        server,
        Mock::given(method("PATCH"))
            .and(path("/notifications/91/unread.json"))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!({
                "id": 91,
                "read": "no",
                "in_app_read_at": null,
                "unread_count": 17
            }))),
    );
    let client = EndpointsClient::new(server.uri(), None);
    let resp = client.notification_mark_unread_single(91).expect("unread");
    assert_eq!(resp.id, 91);
    assert!(!resp.read);
    assert_eq!(resp.unread_count, 17);
}

#[test]
fn notifications_mark_read_bulk_uses_query_string_ids() {
    let server = start_server();
    mount(
        server,
        Mock::given(method("PATCH"))
            .and(path("/notifications/mark_read.json"))
            .and(query_param("ids", "12,13,14"))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!({
                "marked": 3,
                "unread_count": 14,
                "has_failures": "no"
            }))),
    );
    let client = EndpointsClient::new(server.uri(), None);
    let resp = client
        .notifications_mark_read_bulk(&[12, 13, 14])
        .expect("bulk mark_read");
    assert_eq!(resp.marked, 3);
    assert_eq!(resp.unread_count, 14);
    assert!(!resp.has_failures);
}

#[test]
fn notifications_mark_all_read_returns_marked_count() {
    let server = start_server();
    mount(
        server,
        Mock::given(method("PATCH"))
            .and(path("/notifications/mark_all_read.json"))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!({
                "marked": 17,
                "unread_count": 0,
                "has_failures": "no"
            }))),
    );
    let client = EndpointsClient::new(server.uri(), None);
    let resp = client.notifications_mark_all_read().expect("mark_all");
    assert_eq!(resp.marked, 17);
    assert_eq!(resp.unread_count, 0);
    assert!(!resp.has_failures);
}

#[test]
fn notifications_badge_propagates_500_as_error() {
    let server = start_server();
    mount(
        server,
        Mock::given(method("GET"))
            .and(path("/notifications/badge.json"))
            .respond_with(ResponseTemplate::new(500)),
    );
    let client = EndpointsClient::new(server.uri(), None);
    let result = client.notifications_badge();
    assert!(result.is_err());
}
