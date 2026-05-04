//! TUI overlays for `pito footage import`. Two surfaces:
//!
//! - `confirmation` mirrors `crate::ui::confirmation` but with three sections
//!   (Additions / Changes / Deletions) instead of one.
//! - `progress` mirrors `crate::ui::operation_progress` — 4-frame loader,
//!   per-row indicators (`[done]` / `[fail]` / `[skip]`), top-level gauge,
//!   final summary line.
//!
//! Unlike the persistent TUI client these screens spin up briefly during a
//! `pito footage import` run and tear themselves down when the operation
//! finishes (or the user cancels at the confirmation prompt).

pub mod confirmation;
pub mod progress;
