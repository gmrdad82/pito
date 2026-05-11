//! Phase 25 — 01c TUI notifications surface.
//!
//! Two submodules:
//!
//! - [`login_pending`] — parses the `login_pending_approval` notification
//!   shape into a TUI-friendly card. The Rails JSON response carries the
//!   notification body as a markdown-ish string (the same body Rails
//!   renders in the in-app banner); this module pulls out the
//!   `login_attempt_id` from the embedded action links plus the geo / IP /
//!   browser / OS / fingerprint lines for display.
//! - [`overlay`] — the in-TUI modal overlay that renders the card and
//!   handles `a` (approve) / `b` (block) / `Esc` (dismiss), with an
//!   in-overlay two-step confirmation gate (`y` to fire, anything else
//!   cancels).
//!
//! Wire-level approve / block goes through
//! [`crate::api::endpoints::login_attempts`] which POSTs `confirm=yes`
//! to the Rails action-screen controllers.

pub mod login_pending;
pub mod overlay;
