//! Scrub interaction handlers for the footage-detail screen.
//!
//! Two physical interactions, both updating the same `active_timestamp`
//! state:
//!
//! 1. Hover / cursor on the big preview rect: cursor X relative to the rect
//!    width maps to a 0..1 ratio, ratio × duration gives the target time, and
//!    [`FootageDetailState::move_to_ratio`] snaps to the nearest stored
//!    timestamp.
//! 2. Wheel / drag on the strip rect: each wheel tick walks the active
//!    timestamp by one stored cell. Drag is implemented as cumulative wheel
//!    deltas — crossterm reports drags as `Down` + `Drag` + `Up`, but
//!    crossterm's `Drag` does not include modifier-free `delta_x` so we
//!    translate the column delta from the cursor's current position relative
//!    to the rect.
//!
//! Keyboard equivalents live in `keys.rs`. The `App` dispatches the keys to
//! state-mutator helpers on `FootageDetailState`; this module is mouse-only.

use crossterm::event::{MouseEvent, MouseEventKind};
use ratatui::layout::Rect;

use super::state::FootageDetailState;

/// Layout the screen splits its area into. Hover handler tests pin the
/// expected rectangle so the calculation matches whatever `render` produced.
#[derive(Debug, Clone, Copy)]
pub struct ScrubRects {
    /// Big preview area on top.
    pub preview: Rect,
    /// Strip area beneath the playhead row.
    pub strip: Rect,
}

/// Apply a single mouse event to the scrub state.
///
/// Returns `true` when the event consumed the input (so the rest of the
/// pipeline knows not to treat it as e.g. a click on the navigation bar);
/// `false` when the event was outside both rects or otherwise irrelevant.
pub fn handle_mouse(state: &mut FootageDetailState, rects: ScrubRects, event: MouseEvent) -> bool {
    let MouseEvent {
        kind, column, row, ..
    } = event;

    // Inside the big preview: any movement (Moved or Drag with the left
    // button down) updates the active timestamp by ratio.
    if hits(rects.preview, column, row) {
        match kind {
            MouseEventKind::Moved | MouseEventKind::Drag(_) | MouseEventKind::Down(_) => {
                let ratio = preview_ratio(rects.preview, column);
                state.move_to_ratio(ratio);
                return true;
            }
            _ => {}
        }
    }

    // Inside the strip: scroll moves the active timestamp by one stored cell
    // per wheel tick, drag moves by the column delta.
    if hits(rects.strip, column, row) {
        match kind {
            MouseEventKind::ScrollUp => {
                state.step_strip(1);
                return true;
            }
            MouseEventKind::ScrollDown => {
                state.step_strip(-1);
                return true;
            }
            MouseEventKind::ScrollRight => {
                state.step_strip(1);
                return true;
            }
            MouseEventKind::ScrollLeft => {
                state.step_strip(-1);
                return true;
            }
            MouseEventKind::Down(_) | MouseEventKind::Drag(_) => {
                // Drag-to-scrub: translate the column relative to the strip
                // into a 0..1 ratio (assuming the strip displays the entire
                // manifest). On release crossterm sends `Up`; we don't snap
                // explicitly because every state mutator already snaps.
                let ratio = preview_ratio(rects.strip, column);
                state.move_to_ratio(ratio);
                return true;
            }
            _ => {}
        }
    }
    false
}

/// True when `(column, row)` falls inside `rect` (half-open right/bottom
/// edges, matching crossterm's coordinate convention).
fn hits(rect: Rect, column: u16, row: u16) -> bool {
    column >= rect.x
        && row >= rect.y
        && column < rect.x.saturating_add(rect.width)
        && row < rect.y.saturating_add(rect.height)
}

/// Translate the cursor X within `rect` into a 0..1 ratio. `rect.width == 0`
/// degenerates to 0.0 to avoid a divide-by-zero.
fn preview_ratio(rect: Rect, column: u16) -> f64 {
    if rect.width == 0 {
        return 0.0;
    }
    let local_x = column.saturating_sub(rect.x) as f64;
    let width = rect.width as f64;
    // Clamp at width-1 so a click on the rightmost cell yields 1.0.
    (local_x / (width - 1.0).max(1.0)).clamp(0.0, 1.0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::thumbnails::Manifest;
    use crossterm::event::{MouseButton, MouseEventKind};

    fn rects() -> ScrubRects {
        ScrubRects {
            preview: Rect::new(0, 0, 80, 20),
            strip: Rect::new(0, 21, 80, 4),
        }
    }

    fn state_with_manifest() -> FootageDetailState {
        let mut s = FootageDetailState::new(7, "x");
        s.set_manifest(Manifest {
            duration_seconds: 100.0,
            timestamps: vec![0, 25, 50, 75, 100],
        });
        s
    }

    fn move_event(column: u16, row: u16) -> MouseEvent {
        MouseEvent {
            kind: MouseEventKind::Moved,
            column,
            row,
            modifiers: crossterm::event::KeyModifiers::NONE,
        }
    }

    #[test]
    fn hover_left_edge_snaps_to_first_timestamp() {
        let mut s = state_with_manifest();
        // Median was 50 — make sure we observe a move.
        assert_eq!(s.active_timestamp_seconds, 50);
        let consumed = handle_mouse(&mut s, rects(), move_event(0, 0));
        assert!(consumed);
        assert_eq!(s.active_timestamp_seconds, 0);
    }

    #[test]
    fn hover_right_edge_snaps_to_last_timestamp() {
        let mut s = state_with_manifest();
        let consumed = handle_mouse(&mut s, rects(), move_event(79, 0));
        assert!(consumed);
        assert_eq!(s.active_timestamp_seconds, 100);
    }

    #[test]
    fn hover_middle_lands_on_median() {
        let mut s = state_with_manifest();
        // Move to the leftmost first so the assertion isn't trivial.
        let _ = handle_mouse(&mut s, rects(), move_event(0, 0));
        assert_eq!(s.active_timestamp_seconds, 0);
        // Cursor at column 39/79 = 0.4937… → 49.37s → snaps to 50.
        let _ = handle_mouse(&mut s, rects(), move_event(39, 0));
        assert_eq!(s.active_timestamp_seconds, 50);
    }

    #[test]
    fn hover_outside_rects_is_noop() {
        let mut s = state_with_manifest();
        let before = s.active_timestamp_seconds;
        let consumed = handle_mouse(&mut s, rects(), move_event(0, 100));
        assert!(!consumed);
        assert_eq!(s.active_timestamp_seconds, before);
    }

    #[test]
    fn scroll_over_strip_walks_manifest_one_cell_per_tick() {
        let mut s = state_with_manifest();
        // Median start = 50 (index 2 in a 5-elem manifest).
        let evt = MouseEvent {
            kind: MouseEventKind::ScrollUp,
            column: 10,
            row: 22,
            modifiers: crossterm::event::KeyModifiers::NONE,
        };
        let consumed = handle_mouse(&mut s, rects(), evt);
        assert!(consumed);
        assert_eq!(s.active_timestamp_seconds, 75);
    }

    #[test]
    fn scroll_down_over_strip_walks_backward() {
        let mut s = state_with_manifest();
        let evt = MouseEvent {
            kind: MouseEventKind::ScrollDown,
            column: 10,
            row: 22,
            modifiers: crossterm::event::KeyModifiers::NONE,
        };
        let _ = handle_mouse(&mut s, rects(), evt);
        assert_eq!(s.active_timestamp_seconds, 25);
    }

    #[test]
    fn drag_on_strip_translates_column_to_ratio() {
        let mut s = state_with_manifest();
        let evt = MouseEvent {
            kind: MouseEventKind::Drag(MouseButton::Left),
            column: 0,
            row: 22,
            modifiers: crossterm::event::KeyModifiers::NONE,
        };
        let consumed = handle_mouse(&mut s, rects(), evt);
        assert!(consumed);
        assert_eq!(s.active_timestamp_seconds, 0);

        let evt = MouseEvent {
            kind: MouseEventKind::Drag(MouseButton::Left),
            column: 79,
            row: 22,
            modifiers: crossterm::event::KeyModifiers::NONE,
        };
        let _ = handle_mouse(&mut s, rects(), evt);
        assert_eq!(s.active_timestamp_seconds, 100);
    }

    #[test]
    fn down_on_preview_starts_drag_scrub() {
        // A down click without any hover prior should still update the
        // playhead — match the web behavior where pointerdown inside the big
        // preview seeds the scrub immediately.
        let mut s = state_with_manifest();
        let evt = MouseEvent {
            kind: MouseEventKind::Down(MouseButton::Left),
            column: 0,
            row: 0,
            modifiers: crossterm::event::KeyModifiers::NONE,
        };
        let _ = handle_mouse(&mut s, rects(), evt);
        assert_eq!(s.active_timestamp_seconds, 0);
    }

    #[test]
    fn preview_ratio_is_zero_for_zero_width_rect() {
        let r = Rect::new(0, 0, 0, 0);
        assert_eq!(preview_ratio(r, 5), 0.0);
    }

    #[test]
    fn hits_uses_half_open_right_bottom_edges() {
        let r = Rect::new(2, 3, 4, 5);
        assert!(hits(r, 2, 3));
        assert!(hits(r, 5, 7));
        assert!(!hits(r, 1, 3));
        assert!(!hits(r, 6, 5));
        assert!(!hits(r, 3, 8));
    }
}
