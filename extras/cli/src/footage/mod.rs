//! `pito footage` subcommand — Phase 4 footage import flow.
//!
//! Walks a local directory, runs `ffprobe` per file, reconciles the resulting
//! metadata against the Rails footages JSON API, and applies the diff
//! (Add / Change / Delete) one item at a time. The TUI overlays mirror the
//! shapes used elsewhere in the CLI (`ui::confirmation` + `ui::operation_progress`).

pub mod api;
pub mod diff;
pub mod probe;
pub mod ui;
