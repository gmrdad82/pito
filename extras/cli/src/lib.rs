//! Library crate for the `pito` CLI. The `pito` binary at `src/main.rs`
//! consumes its own copy of these modules — the library exists so the
//! integration tests under `tests/` can drive the same code without spawning
//! a child process.
//!
//! Keep the public surface minimal: only what the integration tests need
//! today (`footage`, `cli` arg types, `theme` for overlay tests).

pub mod api;
pub mod cli;
pub mod footage;
pub mod theme;
