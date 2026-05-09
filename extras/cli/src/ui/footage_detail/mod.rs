//! Footage-detail screen — DaVinci-style scrub UI for an imported footage.
//!
//! Phase 7.5 step 06 (CLI half). The screen splits into:
//!
//! 1. A big preview area on top (75% of vertical real estate).
//! 2. A 1-row playhead band with the fixed `+` glyph at horizontal centre.
//! 3. A scrolling film-strip beneath, one cell per stored frame.
//!
//! Two scrub interactions update the same `active_timestamp_seconds` state:
//! moving the cursor inside the preview rect maps the X position to a 0..1
//! ratio over the clip duration; scroll / drag inside the strip rect walks
//! the active timestamp by one stored cell at a time. Keyboard fallbacks
//! (`←` / `→`, `Home` / `End`, `Space` to recenter) work in every terminal.
//!
//! Rendering picks one of four capability paths:
//!
//! - `Kitty` / `Sixel` / `ITerm2` — `App::refresh_active_preview_protocol`
//!   fetches the active master JPEG via `api::thumbnails`, decodes it via
//!   the `image` crate, hands it to the upstream `Picker::new_resize_
//!   protocol`, and stores the result on `App::footage_detail_preview`. The
//!   renderer draws it via `ratatui-image::StatefulImage`. When the manifest
//!   is empty / the fetch fails / the decode fails, the preview slot stays
//!   empty and the renderer falls back to the text body.
//! - `Halfblocks` — same `StatefulImage` path with the halfblocks protocol;
//!   lower-fidelity colors but works in Alacritty / plain xterm.
//! - `TextOnly` — `App::set_terminal_capability` clears the picker entirely,
//!   so no preview protocol is ever built. The renderer renders the
//!   `[ <label> @ HH:MM:SS ]` placeholder and the bracketed strip cells.
//!
//! The submodules:
//!
//! - [`capability`] — terminal-capability detection and the
//!   `TerminalCapability` enum.
//! - [`preview`] — `PreviewProtocol`, the wrapper that pairs a
//!   `ratatui-image::StatefulProtocol` with the `(footage_id, timestamp)`
//!   it was built for.
//! - [`state`] — `FootageDetailState` plus its scrub-mutation helpers.
//! - [`scrub`] — mouse-event → state mutation handler.
//! - [`render`] — `Frame`-based rendering and snapshot-tested layout shape.

pub mod capability;
pub mod preview;
pub mod render;
pub mod scrub;
pub mod state;

pub use capability::TerminalCapability;
pub use preview::PreviewProtocol;
pub use render::render;
pub use scrub::{ScrubRects, handle_mouse};
pub use state::FootageDetailState;
