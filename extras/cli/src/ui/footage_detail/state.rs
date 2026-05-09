//! State for the footage-detail scrub screen.
//!
//! The screen's primary state is `active_timestamp_seconds`: the position of
//! the playhead expressed in seconds into the source clip. Mouse / keyboard
//! interactions update it; rendering reads it and picks the closest stored
//! frame.
//!
//! `manifest` is the array of timestamps the server reports as on-disk,
//! fetched once when the screen opens. The strip layout walks `manifest` in
//! order, centring the cell whose timestamp is closest to
//! `active_timestamp_seconds` under the fixed `+` playhead.
//!
//! Why we snap to a stored timestamp rather than interpolating: every cell
//! on the strip is a real JPEG, and the big preview only swaps to JPEGs that
//! exist on disk. A purely smooth scrub would force us to fetch+composite
//! frames that aren't in the manifest, which contradicts the spec's "filename
//! IS the timestamp" decision.
//!
//! `set_manifest` is exercised by `App::open_footage_detail` /
//! `App::apply_footage_manifest`. `preview_tier` / `strip_tier` are part
//! of the public state contract but only one (`preview_tier`) is consumed
//! by the live image-fetch path inside `App::refresh_active_preview_
//! protocol`; the strip-tier helper waits for the cell-level image
//! rendering, which is parked behind a future dispatch. Keep
//! `#[allow(dead_code)]` so the binary stays clippy-clean while the API
//! shape we want for the next dispatch stays compiled.
#![allow(dead_code)]

use crate::api::thumbnails::{Manifest, Tier};

/// Footage-detail screen state.
///
/// The fields are public because the scrub interaction handlers and the
/// rendering layer both touch them; we don't bother with getter wrappers
/// since this is a single-process owned-by-`App` struct, not a library API.
#[derive(Debug, Clone)]
pub struct FootageDetailState {
    /// Footage row id. Used to compose URL paths (manifest, frame fetch) and
    /// cache keys.
    pub footage_id: u64,
    /// User-facing identifier for the TextOnly fallback header — usually the
    /// footage filename or the footage's `youtube_video_id` when present.
    /// Falls back to the numeric id if neither is known.
    pub label: String,
    /// Manifest fetched from `/footages/:id/frames.json`. `None` while the
    /// initial fetch is pending; an empty `timestamps` field means "no
    /// frames extracted yet" (the screen renders the placeholder copy in
    /// that case).
    pub manifest: Option<Manifest>,
    /// Most recent flash to show on the screen (e.g. fetch failure).
    pub flash: Option<String>,
    /// Active scrub position, in seconds into the clip. Always corresponds
    /// to a real stored timestamp once the manifest is loaded — `move_to`
    /// snaps to the nearest manifest entry on every transition.
    pub active_timestamp_seconds: u64,
    /// Cached scroll offset for the strip in cells. Persisted across mouse
    /// events so a user's scroll position doesn't reset on every render.
    pub strip_scroll_cells: i64,
}

impl FootageDetailState {
    /// Build a fresh state for a footage. The manifest is unknown at this
    /// point — the scrub screen kicks off the manifest fetch when it opens.
    pub fn new(footage_id: u64, label: impl Into<String>) -> Self {
        Self {
            footage_id,
            label: label.into(),
            manifest: None,
            flash: None,
            active_timestamp_seconds: 0,
            strip_scroll_cells: 0,
        }
    }

    /// Apply a successfully-fetched manifest. Snaps `active_timestamp` to the
    /// median timestamp on first load — matches the spec's
    /// `_footage_pane.html.erb` "frame at 50% duration" rendering, so a fresh
    /// open lands the playhead in the middle of the strip rather than at the
    /// very start.
    pub fn set_manifest(&mut self, manifest: Manifest) {
        if !manifest.timestamps.is_empty() {
            let mid = manifest.timestamps.len() / 2;
            self.active_timestamp_seconds = manifest.timestamps[mid];
        }
        self.manifest = Some(manifest);
    }

    /// Snap `active_timestamp_seconds` to the manifest entry closest to
    /// `target_seconds`. No-op when the manifest is empty or absent.
    pub fn move_to(&mut self, target_seconds: u64) {
        if let Some(ref m) = self.manifest
            && let Some(closest) = m.closest(target_seconds)
        {
            self.active_timestamp_seconds = closest;
        }
    }

    /// Step the active timestamp by one cell (one stored frame) in either
    /// direction. Saturates at the manifest endpoints.
    pub fn step(&mut self, delta: i32) {
        let Some(ref m) = self.manifest else {
            return;
        };
        if m.timestamps.is_empty() {
            return;
        }
        let Some(idx) = m.closest_index(self.active_timestamp_seconds) else {
            return;
        };
        let new_idx = (idx as i32 + delta).clamp(0, (m.timestamps.len() as i32) - 1) as usize;
        self.active_timestamp_seconds = m.timestamps[new_idx];
    }

    /// Jump to the first stored timestamp (Home / `g`).
    pub fn jump_to_start(&mut self) {
        if let Some(ref m) = self.manifest
            && let Some(&first) = m.timestamps.first()
        {
            self.active_timestamp_seconds = first;
        }
    }

    /// Jump to the last stored timestamp (End / `G`).
    pub fn jump_to_end(&mut self) {
        if let Some(ref m) = self.manifest
            && let Some(&last) = m.timestamps.last()
        {
            self.active_timestamp_seconds = last;
        }
    }

    /// Translate a 0..1 ratio to a snapped active timestamp. Used by the
    /// big-preview hover handler: cursor X / preview width gives a ratio,
    /// the ratio × duration gives target seconds, the manifest snap finds
    /// the closest stored frame.
    pub fn move_to_ratio(&mut self, ratio: f64) {
        let Some(ref m) = self.manifest else { return };
        if m.timestamps.is_empty() {
            return;
        }
        let r = ratio.clamp(0.0, 1.0);
        let target = (m.duration_seconds * r) as u64;
        self.move_to(target);
    }

    /// Recenter the strip under the playhead. The render layer reads
    /// `strip_scroll_cells` to translate the strip horizontally; this helper
    /// resets it so the active cell sits exactly at the playhead column.
    pub fn recenter_strip(&mut self) {
        self.strip_scroll_cells = 0;
    }

    /// Number of cells the strip should pan when the user scrolls
    /// horizontally by one wheel-tick. One cell = one stored frame.
    pub fn step_strip(&mut self, delta: i64) {
        // Mirror the active-timestamp step so `ScrollUp` over the strip moves
        // forward and `ScrollDown` moves backward — the cell under the
        // playhead always corresponds to `active_timestamp`.
        self.step(delta as i32);
    }

    /// Active timestamp expressed as the JPEG filename stem the server
    /// uses (`HH-MM-SS`). Empty string when the manifest hasn't loaded.
    pub fn active_filename_stem(&self) -> String {
        if self.manifest.is_some() {
            crate::api::thumbnails::format_timestamp(self.active_timestamp_seconds)
        } else {
            String::new()
        }
    }

    /// Tier the big preview pulls from.
    pub fn preview_tier(&self) -> Tier {
        Tier::Master
    }

    /// Tier the strip cells pull from.
    pub fn strip_tier(&self) -> Tier {
        Tier::Thumb
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn manifest_with(timestamps: Vec<u64>) -> Manifest {
        let last = timestamps.last().copied().unwrap_or(0) as f64;
        Manifest {
            duration_seconds: last,
            timestamps,
        }
    }

    #[test]
    fn new_starts_with_empty_manifest_and_zero_position() {
        let s = FootageDetailState::new(7, "fixture.mp4");
        assert!(s.manifest.is_none());
        assert_eq!(s.active_timestamp_seconds, 0);
        assert_eq!(s.footage_id, 7);
    }

    #[test]
    fn set_manifest_snaps_active_to_median() {
        let mut s = FootageDetailState::new(7, "x");
        s.set_manifest(manifest_with(vec![0, 60, 120, 180, 240]));
        // Median index = len/2 = 2 → ts=120.
        assert_eq!(s.active_timestamp_seconds, 120);
    }

    #[test]
    fn set_manifest_with_empty_timestamps_is_safe() {
        let mut s = FootageDetailState::new(7, "x");
        s.set_manifest(Manifest {
            duration_seconds: 100.0,
            timestamps: vec![],
        });
        assert_eq!(s.active_timestamp_seconds, 0);
        assert!(s.manifest.is_some());
    }

    #[test]
    fn move_to_snaps_to_nearest_manifest_entry() {
        let mut s = FootageDetailState::new(7, "x");
        s.set_manifest(manifest_with(vec![60, 120, 180]));
        s.move_to(0);
        assert_eq!(s.active_timestamp_seconds, 60);
        s.move_to(150);
        assert_eq!(s.active_timestamp_seconds, 120);
        s.move_to(170);
        assert_eq!(s.active_timestamp_seconds, 180);
        s.move_to(99999);
        assert_eq!(s.active_timestamp_seconds, 180);
    }

    #[test]
    fn step_walks_manifest_by_cell_count() {
        let mut s = FootageDetailState::new(7, "x");
        s.set_manifest(manifest_with(vec![0, 60, 120, 180, 240]));
        // Median start = 120.
        s.step(1);
        assert_eq!(s.active_timestamp_seconds, 180);
        s.step(2);
        assert_eq!(s.active_timestamp_seconds, 240);
        // Saturates at the end.
        s.step(5);
        assert_eq!(s.active_timestamp_seconds, 240);
        s.step(-100);
        assert_eq!(s.active_timestamp_seconds, 0);
    }

    #[test]
    fn jump_to_start_and_end_clamp_to_endpoints() {
        let mut s = FootageDetailState::new(7, "x");
        s.set_manifest(manifest_with(vec![10, 20, 30, 40, 50]));
        s.jump_to_start();
        assert_eq!(s.active_timestamp_seconds, 10);
        s.jump_to_end();
        assert_eq!(s.active_timestamp_seconds, 50);
    }

    #[test]
    fn move_to_ratio_maps_normalized_position_to_snapped_timestamp() {
        let mut s = FootageDetailState::new(7, "x");
        s.set_manifest(Manifest {
            duration_seconds: 240.0,
            timestamps: vec![0, 60, 120, 180, 240],
        });
        s.move_to_ratio(0.0);
        assert_eq!(s.active_timestamp_seconds, 0);
        s.move_to_ratio(0.5);
        assert_eq!(s.active_timestamp_seconds, 120);
        s.move_to_ratio(1.0);
        assert_eq!(s.active_timestamp_seconds, 240);
        // Ratios outside [0,1] clamp instead of panicking.
        s.move_to_ratio(-1.0);
        assert_eq!(s.active_timestamp_seconds, 0);
        s.move_to_ratio(1.5);
        assert_eq!(s.active_timestamp_seconds, 240);
    }

    #[test]
    fn move_without_manifest_is_noop() {
        let mut s = FootageDetailState::new(7, "x");
        s.move_to(100);
        s.move_to_ratio(0.5);
        s.step(3);
        s.jump_to_end();
        assert_eq!(s.active_timestamp_seconds, 0);
    }

    #[test]
    fn active_filename_stem_zero_pads_using_thumbnails_helper() {
        let mut s = FootageDetailState::new(7, "x");
        assert_eq!(s.active_filename_stem(), "");
        s.set_manifest(manifest_with(vec![90]));
        assert_eq!(s.active_filename_stem(), "00-01-30");
    }

    #[test]
    fn step_strip_mirrors_step() {
        let mut s = FootageDetailState::new(7, "x");
        s.set_manifest(manifest_with(vec![0, 60, 120]));
        // Median start = 60.
        s.step_strip(1);
        assert_eq!(s.active_timestamp_seconds, 120);
        s.step_strip(-2);
        assert_eq!(s.active_timestamp_seconds, 0);
    }
}
