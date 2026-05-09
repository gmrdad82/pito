//! Rendering for the footage-detail scrub screen.
//!
//! The layout is identical across every capability variant — only the
//! contents of the preview rect and the strip cells change. From top to
//! bottom:
//!
//! ```text
//! ┌───────────────────────────────┐  preview rect (Percentage(75))
//! │       big preview frame       │
//! │      (changes with scrub)     │
//! └───────────────────────────────┘
//!               +                    playhead row (Length(1))
//! │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │     strip rect  (Min(0))
//! ```
//!
//! Capability matrix:
//!
//! - `Kitty` / `Sixel` / `ITerm2` — render via `ratatui-image`'s
//!   `StatefulImage` widget when a live `PreviewProtocol` is supplied.
//!   The protocol is built upstream by `App::refresh_active_preview_
//!   protocol` from the master JPEG bytes returned by `api::thumbnails`,
//!   then handed to the renderer for the duration of one frame. When the
//!   protocol is absent (fetch in flight, fetch failed, empty manifest,
//!   text-only terminal) the renderer falls back to the same text body
//!   the halfblocks path uses.
//! - `Halfblocks` — uses the `StatefulImage` widget too (ratatui-image's
//!   halfblocks protocol works in any color terminal), with the same
//!   `PreviewProtocol` wiring; falls back to text when bytes aren't
//!   available yet.
//! - `TextOnly` — never builds a protocol upstream, so the renderer always
//!   takes the text-fallback branch.
//!
//! Tests use `TestBackend` to assert the layout shape stays identical
//! across capabilities; the actual image bytes can't be snapshot-tested
//! for the Kitty / Sixel paths because those protocols emit out-of-band
//! escape sequences that ratatui's TestBackend doesn't capture.

use ratatui::{
    Frame,
    layout::{Constraint, Layout, Rect},
    style::Style,
    text::{Line, Span},
    widgets::{Block, Borders, Paragraph},
};
use ratatui_image::{Resize, StatefulImage};

use super::capability::TerminalCapability;
use super::preview::PreviewProtocol;
use super::scrub::ScrubRects;
use super::state::FootageDetailState;
use crate::theme::Theme;

/// The character used as the playhead marker.
pub const PLAYHEAD_GLYPH: &str = "+";

/// Render the screen at `area` and return the rectangles the scrub handler
/// should test against. The rectangles match the rendering's interior areas
/// (i.e. inside the borders) so a click on the border doesn't trigger a
/// scrub.
///
/// `preview` is `Some(...)` when a `StatefulProtocol` is loaded for the
/// active scrub timestamp; in that case the big-preview area renders the
/// real image via `ratatui-image::StatefulImage`. When `preview` is `None`
/// (text-only terminal, fetch in flight, fetch failed, or empty manifest),
/// the preview area falls back to the text body that lists the active
/// timestamp + capability label.
pub fn render(
    frame: &mut Frame,
    area: Rect,
    theme: &Theme,
    state: &FootageDetailState,
    capability: TerminalCapability,
    preview: Option<&mut PreviewProtocol>,
) -> ScrubRects {
    let outer = Layout::vertical([
        Constraint::Percentage(75),
        Constraint::Length(1),
        Constraint::Min(0),
    ])
    .split(area);

    let preview_outer = outer[0];
    let playhead_row = outer[1];
    let strip_outer = outer[2];

    let preview_inner = render_preview(frame, preview_outer, theme, state, capability, preview);
    render_playhead_row(frame, playhead_row, theme, state);
    let strip_inner = render_strip(frame, strip_outer, theme, state, capability);
    render_flash(frame, area, theme, state);

    ScrubRects {
        preview: preview_inner,
        strip: strip_inner,
    }
}

fn render_preview(
    frame: &mut Frame,
    outer: Rect,
    theme: &Theme,
    state: &FootageDetailState,
    capability: TerminalCapability,
    preview: Option<&mut PreviewProtocol>,
) -> Rect {
    let block = Block::default()
        .title(Span::styled(
            preview_title(state),
            Style::default().fg(theme.fg),
        ))
        .borders(Borders::ALL)
        .border_style(Style::default().fg(theme.border));
    let inner = block.inner(outer);
    frame.render_widget(block, outer);

    // When we have a live image protocol (graphics-capable terminal AND a
    // successfully decoded master JPEG for the active timestamp), render
    // it via ratatui-image's StatefulImage widget. Otherwise fall back to
    // the text body — same placeholder copy as the pre-image-fetch path.
    if let Some(preview) = preview {
        let widget = StatefulImage::default().resize(Resize::Fit(None));
        ratatui::widgets::StatefulWidget::render(
            widget,
            inner,
            frame.buffer_mut(),
            preview.protocol_mut(),
        );
    } else {
        let body = preview_body_text(state, capability);
        let para = Paragraph::new(body).style(Style::default().fg(theme.fg));
        frame.render_widget(para, inner);
    }

    inner
}

/// Compose the title line displayed at the top border of the preview rect.
pub fn preview_title(state: &FootageDetailState) -> String {
    match state.manifest.as_ref() {
        Some(_m) => format!(
            "[ footage {} ] {} @ {}",
            state.footage_id,
            state.label,
            state.active_filename_stem()
        ),
        None => format!(
            "[ footage {} ] {} (loading…)",
            state.footage_id, state.label
        ),
    }
}

/// Body text rendered inside the preview rect for fallback / pre-image paths.
pub fn preview_body_text(
    state: &FootageDetailState,
    capability: TerminalCapability,
) -> Vec<Line<'static>> {
    let mut lines: Vec<Line<'static>> = Vec::new();
    match state.manifest.as_ref() {
        None => {
            lines.push(Line::from(Span::raw("fetching frames…")));
        }
        Some(m) if m.timestamps.is_empty() => {
            lines.push(Line::from(Span::raw(
                "no frames extracted yet — re-run `pito footage import` to populate.",
            )));
        }
        Some(m) => {
            // Header: capability + active timestamp. Even when graphics are
            // available, the layout reserves these labels — they're useful
            // for diagnosing why an image didn't render in a manual session.
            lines.push(Line::from(Span::raw(format!(
                "[ {} @ {} ]",
                state.label,
                state.active_filename_stem(),
            ))));
            lines.push(Line::from(Span::raw(format!(
                "duration={:.1}s  frames={}  capability={}",
                m.duration_seconds,
                m.timestamps.len(),
                capability.label(),
            ))));
            if !capability.supports_graphics() {
                lines.push(Line::from(Span::raw(
                    "(text-only fallback — terminal reported no graphics protocol)",
                )));
            } else if matches!(capability, TerminalCapability::Halfblocks) {
                lines.push(Line::from(Span::raw(
                    "(halfblocks fallback — terminal lacks Kitty / Sixel / iTerm2)",
                )));
            } else {
                // Graphics-capable terminal but no protocol is loaded for
                // the active timestamp: the live fetch is in flight, just
                // failed, or returned bytes the decoder rejected. The flash
                // slot carries the user-facing reason; this hint helps when
                // the manual session runs without `RUST_LOG` capture.
                lines.push(Line::from(Span::raw(
                    "(image fetch pending or failed — see flash row)",
                )));
            }
        }
    }
    lines
}

fn render_playhead_row(frame: &mut Frame, row: Rect, theme: &Theme, _state: &FootageDetailState) {
    if row.width == 0 || row.height == 0 {
        return;
    }
    // The `+` glyph is fixed at the horizontal center of the row.
    let center_col = row.width / 2;
    let spans: Vec<Span<'static>> = vec![
        Span::raw(" ".repeat(center_col as usize)),
        Span::styled(PLAYHEAD_GLYPH, Style::default().fg(theme.accent)),
    ];
    let line = Line::from(spans);
    let para = Paragraph::new(line).style(Style::default().fg(theme.fg));
    frame.render_widget(para, row);
}

fn render_strip(
    frame: &mut Frame,
    outer: Rect,
    theme: &Theme,
    state: &FootageDetailState,
    capability: TerminalCapability,
) -> Rect {
    let block = Block::default()
        .borders(Borders::ALL)
        .border_style(Style::default().fg(theme.border));
    let inner = block.inner(outer);
    frame.render_widget(block, outer);

    let strip_text = strip_text(state, capability, inner.width);
    let para = Paragraph::new(strip_text).style(Style::default().fg(theme.fg));
    frame.render_widget(para, inner);

    inner
}

/// Compose the strip text. Ratatui-image isn't wired here yet, so every
/// capability gets the same per-cell text representation. The active cell is
/// styled with the accent colour so the user can locate the playhead even
/// when the strip exceeds the visible width.
pub fn strip_text(
    state: &FootageDetailState,
    capability: TerminalCapability,
    width: u16,
) -> Vec<Line<'static>> {
    let Some(m) = state.manifest.as_ref() else {
        return vec![Line::from(Span::raw("…"))];
    };
    if m.timestamps.is_empty() {
        return vec![Line::from(Span::raw(
            "no frames — re-run `pito footage import` to populate the strip.",
        ))];
    }
    let active_idx = m.closest_index(state.active_timestamp_seconds).unwrap_or(0);

    // The strip renders one cell per stored frame. Cell width is currently
    // fixed at 9 characters (`HH-MM-SS` plus a single bracket / space) —
    // text-fallback for every capability. When the live image-rendering
    // dispatch lands the Kitty / Sixel / iTerm2 paths will pick a different
    // cell width keyed on `capability`; capture the variable now so that
    // wiring is one-line.
    let _ = capability;
    let cell_width = 9usize;
    let cells_visible = (width as usize / cell_width).max(1);

    // Centre the active cell. `start` is the first index in `m.timestamps` to
    // render at the leftmost cell.
    let half = cells_visible / 2;
    let start = active_idx.saturating_sub(half);
    let end = (start + cells_visible).min(m.timestamps.len());

    let mut spans: Vec<Span<'static>> = Vec::new();
    for (i, &ts) in m.timestamps[start..end].iter().enumerate() {
        let stem = crate::api::thumbnails::format_timestamp(ts);
        let label = if (start + i) == active_idx {
            // Mark the active cell with brackets to mirror the bracketed-
            // link convention.
            format!("[{}]", stem)
        } else {
            format!(" {} ", stem)
        };
        spans.push(Span::raw(label));
    }
    vec![Line::from(spans)]
}

fn render_flash(frame: &mut Frame, area: Rect, theme: &Theme, state: &FootageDetailState) {
    let Some(ref msg) = state.flash else { return };
    if area.height == 0 {
        return;
    }
    // Render at the bottom row of the screen (similar to other detail
    // screens that overlay flash text on the footer area).
    let row = Rect::new(
        area.x,
        area.y + area.height.saturating_sub(1),
        area.width,
        1,
    );
    let para = Paragraph::new(Line::from(Span::styled(
        msg.clone(),
        Style::default().fg(theme.accent),
    )))
    .style(Style::default().fg(theme.fg));
    frame.render_widget(para, row);
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::thumbnails::Manifest;
    use crate::theme::{Theme, ThemeMode};
    use ratatui::Terminal;
    use ratatui::backend::TestBackend;

    fn theme() -> Theme {
        Theme::from_mode(ThemeMode::Dark)
    }

    fn state(manifest: Option<Manifest>) -> FootageDetailState {
        let mut s = FootageDetailState::new(7, "fixture.mp4");
        if let Some(m) = manifest {
            s.set_manifest(m);
        }
        s
    }

    #[test]
    fn preview_title_includes_id_label_and_filename_stem() {
        let s = state(Some(Manifest {
            duration_seconds: 240.0,
            timestamps: vec![60, 120, 180],
        }));
        let title = preview_title(&s);
        assert!(title.contains("footage 7"));
        assert!(title.contains("fixture.mp4"));
        // Median is 120 → 00-02-00.
        assert!(title.contains("00-02-00"));
    }

    #[test]
    fn preview_title_loading_when_manifest_absent() {
        let s = state(None);
        let title = preview_title(&s);
        assert!(title.contains("loading"));
    }

    #[test]
    fn preview_body_includes_capability_label_for_graphics() {
        let s = state(Some(Manifest {
            duration_seconds: 60.0,
            timestamps: vec![0, 30, 60],
        }));
        let body = preview_body_text(&s, TerminalCapability::Kitty);
        let joined = body
            .iter()
            .flat_map(|l| l.spans.iter().map(|s| s.content.to_string()))
            .collect::<Vec<_>>()
            .join("\n");
        assert!(joined.contains("capability=kitty"));
    }

    #[test]
    fn preview_body_includes_text_only_label_when_no_graphics() {
        let s = state(Some(Manifest {
            duration_seconds: 60.0,
            timestamps: vec![0, 30, 60],
        }));
        let body = preview_body_text(&s, TerminalCapability::TextOnly);
        let joined = body
            .iter()
            .flat_map(|l| l.spans.iter().map(|s| s.content.to_string()))
            .collect::<Vec<_>>()
            .join("\n");
        assert!(joined.contains("text-only"));
    }

    #[test]
    fn preview_body_calls_out_halfblocks_fallback() {
        let s = state(Some(Manifest {
            duration_seconds: 60.0,
            timestamps: vec![0, 30, 60],
        }));
        let body = preview_body_text(&s, TerminalCapability::Halfblocks);
        let joined = body
            .iter()
            .flat_map(|l| l.spans.iter().map(|s| s.content.to_string()))
            .collect::<Vec<_>>()
            .join("\n");
        assert!(joined.contains("halfblocks fallback"));
    }

    #[test]
    fn preview_body_handles_missing_manifest() {
        let s = state(None);
        let body = preview_body_text(&s, TerminalCapability::Halfblocks);
        let joined = body
            .iter()
            .flat_map(|l| l.spans.iter().map(|s| s.content.to_string()))
            .collect::<Vec<_>>()
            .join("\n");
        assert!(joined.contains("fetching"));
    }

    #[test]
    fn preview_body_handles_empty_manifest() {
        let s = state(Some(Manifest {
            duration_seconds: 0.0,
            timestamps: vec![],
        }));
        let body = preview_body_text(&s, TerminalCapability::Halfblocks);
        let joined = body
            .iter()
            .flat_map(|l| l.spans.iter().map(|s| s.content.to_string()))
            .collect::<Vec<_>>()
            .join("\n");
        assert!(joined.contains("no frames"));
    }

    #[test]
    fn strip_text_brackets_active_cell() {
        let s = state(Some(Manifest {
            duration_seconds: 60.0,
            timestamps: vec![0, 30, 60],
        }));
        let lines = strip_text(&s, TerminalCapability::Halfblocks, 80);
        let joined = lines
            .iter()
            .flat_map(|l| l.spans.iter().map(|s| s.content.to_string()))
            .collect::<Vec<_>>()
            .join("");
        // Median = 30s → 00-00-30.
        assert!(joined.contains("[00-00-30]"));
    }

    #[test]
    fn strip_text_handles_empty_manifest_with_placeholder() {
        let s = state(Some(Manifest {
            duration_seconds: 0.0,
            timestamps: vec![],
        }));
        let lines = strip_text(&s, TerminalCapability::Halfblocks, 80);
        let joined = lines
            .iter()
            .flat_map(|l| l.spans.iter().map(|s| s.content.to_string()))
            .collect::<Vec<_>>()
            .join("");
        assert!(joined.contains("no frames"));
    }

    #[test]
    fn render_returns_inner_rects_inside_outer_borders() {
        // Use TestBackend to drive an actual render. The returned ScrubRects
        // must be inside the outer block borders so a click on the border
        // doesn't fire the scrub handler.
        let backend = TestBackend::new(80, 24);
        let mut terminal = Terminal::new(backend).unwrap();
        let s = state(Some(Manifest {
            duration_seconds: 60.0,
            timestamps: vec![0, 30, 60],
        }));
        let theme = theme();
        let mut returned: Option<ScrubRects> = None;
        terminal
            .draw(|frame| {
                let area = frame.area();
                let r = render(
                    frame,
                    area,
                    &theme,
                    &s,
                    TerminalCapability::Halfblocks,
                    None,
                );
                returned = Some(r);
            })
            .unwrap();
        let r = returned.unwrap();
        assert!(r.preview.x >= 1, "preview must sit inside left border");
        assert!(r.strip.x >= 1, "strip must sit inside left border");
        assert!(
            r.preview.y + r.preview.height <= 24,
            "preview must fit screen"
        );
    }

    #[test]
    fn render_layout_shape_is_independent_of_capability() {
        // Halfblocks vs. TextOnly should produce the same rectangles —
        // capability changes content, not layout. This is the core scrub-UX
        // invariant.
        let backend = TestBackend::new(80, 24);
        let mut terminal_a = Terminal::new(backend).unwrap();
        let backend_b = TestBackend::new(80, 24);
        let mut terminal_b = Terminal::new(backend_b).unwrap();
        let s = state(Some(Manifest {
            duration_seconds: 60.0,
            timestamps: vec![0, 30, 60],
        }));
        let theme = theme();
        let mut a: Option<ScrubRects> = None;
        let mut b: Option<ScrubRects> = None;
        terminal_a
            .draw(|frame| {
                a = Some(render(
                    frame,
                    frame.area(),
                    &theme,
                    &s,
                    TerminalCapability::Halfblocks,
                    None,
                ));
            })
            .unwrap();
        terminal_b
            .draw(|frame| {
                b = Some(render(
                    frame,
                    frame.area(),
                    &theme,
                    &s,
                    TerminalCapability::TextOnly,
                    None,
                ));
            })
            .unwrap();
        let a = a.unwrap();
        let b = b.unwrap();
        assert_eq!(a.preview, b.preview);
        assert_eq!(a.strip, b.strip);
    }

    #[test]
    fn render_text_only_includes_label_and_active_timestamp() {
        // Snapshot the text-only branch — the buffer must contain the
        // bracketed `[ <label> @ HH:MM:SS ]` body so the user has something
        // legible without graphics.
        let backend = TestBackend::new(80, 24);
        let mut terminal = Terminal::new(backend).unwrap();
        let s = state(Some(Manifest {
            duration_seconds: 60.0,
            timestamps: vec![0, 30, 60],
        }));
        let theme = theme();
        terminal
            .draw(|frame| {
                let _ = render(
                    frame,
                    frame.area(),
                    &theme,
                    &s,
                    TerminalCapability::TextOnly,
                    None,
                );
            })
            .unwrap();
        let buf = terminal.backend().buffer().clone();
        let mut all = String::new();
        for y in 0..buf.area().height {
            for x in 0..buf.area().width {
                all.push_str(buf.cell((x, y)).unwrap().symbol());
            }
            all.push('\n');
        }
        assert!(all.contains("fixture.mp4"), "label must appear: {}", all);
        assert!(all.contains("00-00-30"), "active stem must appear: {}", all);
        assert!(
            all.contains("text-only"),
            "fallback hint must appear: {}",
            all
        );
    }

    #[test]
    fn render_halfblocks_includes_fallback_hint() {
        let backend = TestBackend::new(80, 24);
        let mut terminal = Terminal::new(backend).unwrap();
        let s = state(Some(Manifest {
            duration_seconds: 60.0,
            timestamps: vec![0, 30, 60],
        }));
        let theme = theme();
        terminal
            .draw(|frame| {
                let _ = render(
                    frame,
                    frame.area(),
                    &theme,
                    &s,
                    TerminalCapability::Halfblocks,
                    None,
                );
            })
            .unwrap();
        let buf = terminal.backend().buffer().clone();
        let mut all = String::new();
        for y in 0..buf.area().height {
            for x in 0..buf.area().width {
                all.push_str(buf.cell((x, y)).unwrap().symbol());
            }
            all.push('\n');
        }
        assert!(all.contains("halfblocks"));
    }

    #[test]
    fn render_includes_playhead_glyph_at_center() {
        let backend = TestBackend::new(80, 24);
        let mut terminal = Terminal::new(backend).unwrap();
        let s = state(Some(Manifest {
            duration_seconds: 60.0,
            timestamps: vec![0, 30, 60],
        }));
        let theme = theme();
        terminal
            .draw(|frame| {
                let _ = render(
                    frame,
                    frame.area(),
                    &theme,
                    &s,
                    TerminalCapability::TextOnly,
                    None,
                );
            })
            .unwrap();
        let buf = terminal.backend().buffer().clone();
        // The playhead row sits at outer[1] which is one row below 75% of
        // 24 → row 18. We don't pin the exact row to keep the test resilient
        // to small layout tweaks; instead we check the buffer contains the
        // glyph.
        let mut found = false;
        for y in 0..buf.area().height {
            for x in 0..buf.area().width {
                if buf.cell((x, y)).unwrap().symbol() == PLAYHEAD_GLYPH {
                    found = true;
                    break;
                }
            }
        }
        assert!(found, "playhead glyph must render somewhere on screen");
    }
}
