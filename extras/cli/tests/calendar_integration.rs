//! Integration tests for the Phase 21 `pito calendar` surfaces.
//!
//! Drives `EndpointsClient::calendar_*` methods against a wiremock server,
//! covering reads (schedule, month, show), writes (create, update, note),
//! and the soft-cancel deletion endpoint. The wire shapes are pinned per
//! the Phase 21 spec.

use std::sync::OnceLock;

use pito::api::endpoints::EndpointsClient;
use pito::api::endpoints::calendar::{CalendarMonthQuery, CalendarScheduleQuery};
use serde_json::{Value, json};
use wiremock::matchers::{body_json, method, path, query_param};
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

fn entry_summary(id: u64) -> Value {
    json!({
        "id": id,
        "entry_type": "game_release",
        "title": "Hades 2 launch",
        "starts_at": "2026-05-13T17:00:00Z",
        "ends_at": null,
        "all_day": "no",
        "timezone": "Europe/Bucharest",
        "state": "scheduled",
        "source": "derived",
        "read_only": "yes",
        "game_id": 42,
        "video_id": null,
        "channel_id": null,
        "project_id": null,
        "milestone_rule_id": null
    })
}

fn entry_detail(id: u64) -> Value {
    json!({
        "entry": {
            "id": id,
            "entry_type": "milestone_manual",
            "title": "ship phase 21",
            "description": null,
            "starts_at": "2026-06-01T10:00:00Z",
            "ends_at": null,
            "all_day": "no",
            "timezone": "Europe/Bucharest",
            "state": "scheduled",
            "source": "manual",
            "read_only": "no",
            "manual_date_override": "no",
            "release_precision": null,
            "tba_remind_monthly": "no",
            "notify_anyway": "no",
            "metadata": null,
            "parent_entry_id": null,
            "child_entry_ids": [],
            "game_id": null,
            "video_id": null,
            "channel_id": null,
            "project_id": null,
            "milestone_rule_id": null,
            "created_by_user_id": 1,
            "created_at": "2026-05-10T18:00:00Z",
            "updated_at": "2026-05-10T18:00:00Z"
        },
        "dispatch_declarations": []
    })
}

#[test]
fn calendar_schedule_decodes_locked_wire_shape() {
    let server = start_server();
    mount(
        server,
        Mock::given(method("GET"))
            .and(path("/calendar/schedule.json"))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!({
                "page": 1,
                "total_pages": 4,
                "total": 187,
                "per_page": 50,
                "selected_kinds": ["video", "game"],
                "selected_source": null,
                "show_cancelled": "no",
                "install_tz": "Europe/Bucharest",
                "today": "2026-05-10T18:42:00Z",
                "entries": [entry_summary(12)]
            }))),
    );
    let client = EndpointsClient::new(server.uri(), None);
    let resp = client
        .calendar_schedule(&CalendarScheduleQuery::default())
        .expect("schedule");
    assert_eq!(resp.page, 1);
    assert_eq!(resp.total_pages, 4);
    assert_eq!(resp.total, 187);
    assert_eq!(resp.entries.len(), 1);
    assert_eq!(resp.entries[0].id, 12);
    assert!(!resp.show_cancelled);
}

#[test]
fn calendar_schedule_forwards_query_params() {
    let server = start_server();
    mount(
        server,
        Mock::given(method("GET"))
            .and(path("/calendar/schedule.json"))
            .and(query_param("types", "video,game"))
            .and(query_param("page", "2"))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!({
                "page": 2,
                "total_pages": 4,
                "total": 187,
                "per_page": 50,
                "selected_kinds": ["video", "game"],
                "selected_source": null,
                "show_cancelled": "no",
                "install_tz": null,
                "today": null,
                "entries": []
            }))),
    );
    let client = EndpointsClient::new(server.uri(), None);
    let q = CalendarScheduleQuery {
        types: Some("video,game".to_string()),
        page: Some(2),
        ..CalendarScheduleQuery::default()
    };
    let resp = client.calendar_schedule(&q).expect("schedule");
    assert_eq!(resp.page, 2);
    assert!(resp.entries.is_empty());
}

#[test]
fn calendar_month_decodes_buckets_keyed_by_date() {
    let server = start_server();
    mount(
        server,
        Mock::given(method("GET"))
            .and(path("/calendar/month/2026/5.json"))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!({
                "year": 2026,
                "month": 5,
                "install_tz": "Europe/Bucharest",
                "first_day": "2026-04-27",
                "last_day": "2026-06-01",
                "today": "2026-05-10",
                "on_current_month": "yes",
                "selected_kinds": ["video", "game"],
                "show_cancelled": "no",
                "buckets": {
                    "2026-05-13": [entry_summary(12)],
                    "2026-05-21": [entry_summary(13)]
                },
                "nav": {
                    "prev": { "year": 2026, "month": 4 },
                    "next": { "year": 2026, "month": 6 }
                }
            }))),
    );
    let client = EndpointsClient::new(server.uri(), None);
    let resp = client
        .calendar_month(2026, 5, &CalendarMonthQuery::default())
        .expect("month");
    assert_eq!(resp.year, 2026);
    assert_eq!(resp.month, 5);
    assert!(resp.on_current_month);
    assert_eq!(resp.buckets.len(), 2);
    assert!(resp.buckets.contains_key("2026-05-13"));
    assert_eq!(resp.nav.prev.month, 4);
    assert_eq!(resp.nav.next.month, 6);
}

#[test]
fn calendar_month_decodes_empty_buckets_object() {
    let server = start_server();
    mount(
        server,
        Mock::given(method("GET"))
            .and(path("/calendar/month/2027/1.json"))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!({
                "year": 2027,
                "month": 1,
                "install_tz": "Europe/Bucharest",
                "first_day": "2026-12-28",
                "last_day": "2027-01-31",
                "today": "2026-05-10",
                "on_current_month": "no",
                "selected_kinds": null,
                "show_cancelled": "no",
                "buckets": {},
                "nav": {
                    "prev": { "year": 2026, "month": 12 },
                    "next": { "year": 2027, "month": 2 }
                }
            }))),
    );
    let client = EndpointsClient::new(server.uri(), None);
    let resp = client
        .calendar_month(2027, 1, &CalendarMonthQuery::default())
        .expect("month");
    assert!(resp.buckets.is_empty());
    assert!(!resp.on_current_month);
}

#[test]
fn calendar_entry_show_decodes_detail_plus_declarations() {
    let server = start_server();
    mount(
        server,
        Mock::given(method("GET"))
            .and(path("/calendar/entries/12.json"))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!({
                "entry": {
                    "id": 12,
                    "entry_type": "game_release",
                    "title": "Hades 2 launch",
                    "description": null,
                    "starts_at": "2026-05-13T17:00:00Z",
                    "ends_at": null,
                    "all_day": "no",
                    "timezone": "Europe/Bucharest",
                    "state": "scheduled",
                    "source": "derived",
                    "read_only": "yes",
                    "manual_date_override": "no",
                    "release_precision": "exact",
                    "tba_remind_monthly": "no",
                    "notify_anyway": "no",
                    "metadata": { "user_overrides": { "note": "..." } },
                    "parent_entry_id": null,
                    "child_entry_ids": [55, 56],
                    "game_id": 42,
                    "video_id": null,
                    "channel_id": null,
                    "project_id": null,
                    "milestone_rule_id": null,
                    "created_by_user_id": 1,
                    "created_at": "2026-05-10T18:00:00Z",
                    "updated_at": "2026-05-10T18:00:00Z"
                },
                "dispatch_declarations": [
                    {
                        "channel": "in_app",
                        "fires_at": "2026-05-13T17:00:00Z",
                        "kind": "game_release_today",
                        "severity": "info"
                    }
                ]
            }))),
    );
    let client = EndpointsClient::new(server.uri(), None);
    let resp = client.calendar_entry_show(12).expect("show");
    assert_eq!(resp.entry.id, 12);
    assert_eq!(resp.entry.child_entry_ids, vec![55, 56]);
    assert!(resp.entry.read_only);
    assert_eq!(resp.dispatch_declarations.len(), 1);
}

#[test]
fn calendar_entry_create_wraps_body_in_strong_params() {
    let server = start_server();
    let expected_body = json!({
        "calendar_entry": {
            "entry_type": "milestone_manual",
            "title": "ship phase 21",
            "starts_at": "2026-06-01T10:00:00Z",
            "all_day": "no",
            "timezone": "Europe/Bucharest"
        }
    });
    mount(
        server,
        Mock::given(method("POST"))
            .and(path("/calendar/entries.json"))
            .and(body_json(&expected_body))
            .respond_with(ResponseTemplate::new(201).set_body_json(entry_detail(99))),
    );
    let client = EndpointsClient::new(server.uri(), None);
    let inner = json!({
        "entry_type": "milestone_manual",
        "title": "ship phase 21",
        "starts_at": "2026-06-01T10:00:00Z",
        "all_day": "no",
        "timezone": "Europe/Bucharest"
    });
    let resp = client.calendar_entry_create(inner).expect("create");
    assert_eq!(resp.entry.id, 99);
}

#[test]
fn calendar_entry_create_returns_422_validation_error_as_err() {
    // A 422 from the server is propagated as an `Err`. The caller can then
    // surface the validation error envelope verbatim; the integration test
    // pins the failure shape (not Ok).
    let server = start_server();
    mount(
        server,
        Mock::given(method("POST"))
            .and(path("/calendar/entries.json"))
            .respond_with(ResponseTemplate::new(422).set_body_json(json!({
                "errors": { "starts_at": ["can't be blank"] }
            }))),
    );
    let client = EndpointsClient::new(server.uri(), None);
    let result = client.calendar_entry_create(json!({}));
    assert!(result.is_err());
}

#[test]
fn calendar_entry_update_wraps_body_and_targets_member_path() {
    let server = start_server();
    let expected_body = json!({
        "calendar_entry": { "title": "updated" }
    });
    mount(
        server,
        Mock::given(method("PATCH"))
            .and(path("/calendar/entries/12.json"))
            .and(body_json(&expected_body))
            .respond_with(ResponseTemplate::new(200).set_body_json(entry_detail(12))),
    );
    let client = EndpointsClient::new(server.uri(), None);
    let resp = client
        .calendar_entry_update(12, json!({ "title": "updated" }))
        .expect("update");
    assert_eq!(resp.entry.id, 12);
}

#[test]
fn calendar_entry_note_targets_dedicated_endpoint() {
    let server = start_server();
    let expected_body = json!({
        "calendar_entry": { "note": "post-mortem" }
    });
    mount(
        server,
        Mock::given(method("PATCH"))
            .and(path("/calendar/entries/12/note.json"))
            .and(body_json(&expected_body))
            .respond_with(ResponseTemplate::new(200).set_body_json(entry_detail(12))),
    );
    let client = EndpointsClient::new(server.uri(), None);
    let resp = client.calendar_entry_note(12, "post-mortem").expect("note");
    assert_eq!(resp.entry.id, 12);
}

#[test]
fn calendar_entry_soft_cancel_single_id_uses_csv_path_segment() {
    let server = start_server();
    mount(
        server,
        Mock::given(method("DELETE"))
            .and(path("/deletions/calendar_entry/12.json"))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!({
                "cancelled": [{ "id": 12, "state": "cancelled" }],
                "skipped": []
            }))),
    );
    let client = EndpointsClient::new(server.uri(), None);
    let resp = client.calendar_entry_soft_cancel(&[12]).expect("cancel");
    assert_eq!(resp.cancelled.len(), 1);
    assert_eq!(resp.cancelled[0].id, 12);
    assert!(resp.skipped.is_empty());
}

#[test]
fn calendar_entry_soft_cancel_bulk_combines_ids_with_commas() {
    let server = start_server();
    mount(
        server,
        Mock::given(method("DELETE"))
            .and(path("/deletions/calendar_entry/12,55,99.json"))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!({
                "cancelled": [
                    { "id": 12, "state": "cancelled" },
                    { "id": 99, "state": "cancelled" }
                ],
                "skipped": [
                    { "id": 55, "reason": "already_cancelled" }
                ]
            }))),
    );
    let client = EndpointsClient::new(server.uri(), None);
    let resp = client
        .calendar_entry_soft_cancel(&[12, 55, 99])
        .expect("bulk cancel");
    assert_eq!(resp.cancelled.len(), 2);
    assert_eq!(resp.skipped.len(), 1);
    assert_eq!(resp.skipped[0].reason, "already_cancelled");
}
