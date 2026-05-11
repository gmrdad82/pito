//! Phase 25 — 01c login-pending approve / block client.
//!
//! Hooks the TUI's pending-approval overlay into the Rails-side
//! `Login::ApprovalsController` and `Login::BlocksController`. Both
//! controllers were shipped by the Rails half of 01c (commit `ec66c9b`).
//!
//! Transport
//! ---------
//!
//! Like every other notification surface the CLI already speaks to, this
//! module rides the Rails JSON endpoints rather than MCP. The two Rails
//! controllers (`POST /login/approvals/:id` and `POST /login/blocks/:id`)
//! consume an `application/x-www-form-urlencoded` body — `confirm=yes`
//! per the yes/no boundary rule — and respond with a 302 redirect to the
//! notifications surface on success. The TUI doesn't follow that
//! redirect; a non-error status is enough to declare the action done.
//!
//! The MCP tools `login_attempt_approve` / `login_attempt_block` (Phase
//! 25 sub-spec 01d) cover the same flow over the JSON-RPC transport.
//! They are NOT what we call here — the CLI keeps cookie / bearer
//! parity with `notifications`, `calendar`, `games`, etc.
//!
//! Two-step confirmation
//! ---------------------
//!
//! The overlay calling this client always runs the user through an
//! in-TUI confirmation gate before invoking `approve_pending` /
//! `block_pending`. By the time we hit the wire, the operator has
//! pressed `a` (or `b`), then `y`. The `confirm=yes` payload here is
//! the wire half of that two-step pattern (LD-16 / project-wide hard
//! rule).

use anyhow::{Context, Result};

use super::EndpointsClient;

/// Outcome of a successful approve / block POST. The Rails controllers
/// redirect (302) to the notifications surface; we surface only the
/// fact that the call succeeded plus the redirect target if we can
/// observe it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LoginAttemptActionResponse {
    /// HTTP status the server replied with. 302 / 303 are the normal
    /// success shapes; 200 is also accepted (defensive, in case a
    /// future revision returns JSON).
    pub status: u16,
    /// `Location` header value when present; `None` for non-redirect
    /// responses. Useful for tests and for asserting the redirect
    /// target lands on the notifications path.
    pub location: Option<String>,
}

impl EndpointsClient {
    /// POST `/login/approvals/:id` with `confirm=yes`. Returns the
    /// status + redirect target the controller produced.
    ///
    /// Errors propagate via `anyhow::Result`: transport failures,
    /// non-2xx/3xx statuses (4xx and 5xx both fail `error_for_status`).
    pub fn approve_pending(&self, attempt_id: u64) -> Result<LoginAttemptActionResponse> {
        let url = self.url(&format!("/login/approvals/{}", attempt_id));
        self.post_confirm(&url)
    }

    /// POST `/login/blocks/:id` with `confirm=yes`. Same shape as
    /// `approve_pending` — distinct method so callers don't pass a
    /// stringly-typed "approve" / "block" parameter.
    pub fn block_pending(&self, attempt_id: u64) -> Result<LoginAttemptActionResponse> {
        let url = self.url(&format!("/login/blocks/{}", attempt_id));
        self.post_confirm(&url)
    }

    fn post_confirm(&self, url: &str) -> Result<LoginAttemptActionResponse> {
        // Form-encoded body, NOT JSON: the Rails controllers read
        // `params[:confirm]` from a normal HTTP form. `confirm=yes`
        // matches the project-wide yes/no boundary rule (LD-15).
        //
        // `redirect(Policy::none())` keeps the 302 in the response so
        // we can surface the redirect target. The Rails controller
        // doesn't expose a JSON variant, so a 302 here is the
        // canonical success signal.
        let client = reqwest::blocking::Client::builder()
            .timeout(super::REQUEST_TIMEOUT)
            .redirect(reqwest::redirect::Policy::none())
            .build()
            .context("build no-redirect client for login attempt action")?;

        let mut req = client
            .post(url)
            .header("Accept", "application/json")
            .form(&[("confirm", "yes")]);
        if let Some(t) = self.bearer_token() {
            req = req.header("Authorization", format!("Bearer {}", t));
        }
        let resp = req.send().with_context(|| format!("POST {}", url))?;
        let status = resp.status();
        let location = resp
            .headers()
            .get(reqwest::header::LOCATION)
            .and_then(|v| v.to_str().ok())
            .map(|s| s.to_string());

        // 302 / 303 are the controllers' normal success shape; 200 is
        // accepted too in case a future revision flips to JSON.
        // Anything else is an error.
        if !(status.is_success() || status.is_redirection()) {
            anyhow::bail!("POST {} returned status {}", url, status.as_u16());
        }

        Ok(LoginAttemptActionResponse {
            status: status.as_u16(),
            location,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use wiremock::matchers::{body_string, header, method, path};
    use wiremock::{Mock, MockServer, ResponseTemplate};

    #[tokio::test(flavor = "current_thread")]
    async fn approve_pending_posts_confirm_yes_and_handles_302() {
        let server = MockServer::start().await;

        Mock::given(method("POST"))
            .and(path("/login/approvals/42"))
            .and(header("content-type", "application/x-www-form-urlencoded"))
            .and(body_string("confirm=yes"))
            .respond_with(ResponseTemplate::new(302).insert_header("Location", "/notifications"))
            .mount(&server)
            .await;

        // Drive the blocking client off the async test thread so the
        // mock server stays responsive while we synchronously POST.
        let base = server.uri();
        let resp = tokio::task::spawn_blocking(move || {
            let client = EndpointsClient::new(base, Some("test-token".to_string()));
            client.approve_pending(42)
        })
        .await
        .expect("spawn_blocking join")
        .expect("approve_pending succeeds against the mock");

        assert_eq!(resp.status, 302);
        assert_eq!(resp.location.as_deref(), Some("/notifications"));
    }

    #[tokio::test(flavor = "current_thread")]
    async fn block_pending_posts_confirm_yes_and_handles_302() {
        let server = MockServer::start().await;

        Mock::given(method("POST"))
            .and(path("/login/blocks/77"))
            .and(body_string("confirm=yes"))
            .respond_with(ResponseTemplate::new(302).insert_header("Location", "/notifications"))
            .mount(&server)
            .await;

        let base = server.uri();
        let resp = tokio::task::spawn_blocking(move || {
            let client = EndpointsClient::new(base, None);
            client.block_pending(77)
        })
        .await
        .expect("spawn_blocking join")
        .expect("block_pending succeeds against the mock");

        assert_eq!(resp.status, 302);
    }

    #[tokio::test(flavor = "current_thread")]
    async fn approve_pending_attaches_bearer_token_when_set() {
        let server = MockServer::start().await;

        Mock::given(method("POST"))
            .and(path("/login/approvals/1"))
            .and(header("authorization", "Bearer pito_abc"))
            .respond_with(ResponseTemplate::new(302))
            .mount(&server)
            .await;

        let base = server.uri();
        let resp = tokio::task::spawn_blocking(move || {
            let client = EndpointsClient::new(base, Some("pito_abc".to_string()));
            client.approve_pending(1)
        })
        .await
        .expect("spawn_blocking join")
        .expect("bearer header propagates");

        assert_eq!(resp.status, 302);
    }

    #[tokio::test(flavor = "current_thread")]
    async fn approve_pending_returns_err_on_4xx() {
        let server = MockServer::start().await;

        Mock::given(method("POST"))
            .and(path("/login/approvals/9"))
            .respond_with(ResponseTemplate::new(422))
            .mount(&server)
            .await;

        let base = server.uri();
        let err = tokio::task::spawn_blocking(move || {
            let client = EndpointsClient::new(base, None);
            client.approve_pending(9)
        })
        .await
        .expect("spawn_blocking join")
        .expect_err("422 must surface as Err");

        let msg = format!("{}", err);
        assert!(
            msg.contains("422"),
            "error message should mention 422: {msg}"
        );
    }
}
