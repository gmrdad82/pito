//! Overlay that visualizes a server-side bulk operation while it progresses.
//!
//! Driven by [`crate::app::OperationProgress`] — the App polls
//! `/bulk_operations/:id/status.json` on a fixed cadence and stores the latest
//! snapshot. This module just renders whatever is current.
//!
//! The overlay mirrors the Rails delete/sync progress UX 1:1: a top-level
//! gauge plus a per-row list, where each row shows either a 4-frame dot-loader
//! animation (`=---`, `-=--`, `--=-`, `---=`) for pending items, or a terminal
//! marker (`[done]`, `[fail]`, `[skip]`) once the row reaches a final state.

use ratatui::{
    Frame,
    layout::{Constraint, Flex, Layout, Rect},
    style::{Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Clear, Gauge, Paragraph},
};

use crate::api::models::{BulkOperationItem, BulkOperationStatus};
use crate::app::OperationProgress;
use crate::theme::Theme;
use crate::ui::channels::ChannelRow;

/// Width of the overlay as a percent of the body area.
const POPUP_PERCENT_X: u16 = 60;
/// Height — generous enough to fit the gauge, the summary line, and a small
/// scrollable item list.
const POPUP_PERCENT_Y: u16 = 60;

/// Visible width of a per-row status indicator. `[done]`/`[fail]`/`[skip]` are
/// 6 chars; the loader frames are 4 chars padded to 6 so the URL column lines
/// up regardless of the row's status.
const INDICATOR_WIDTH: usize = 6;

/// Dot-loader frames mirroring the Rails `.dot-loader` CSS animation. Cycled
/// at ~125ms per tick (set by `App::tick`'s sleep budget).
pub const LOADER_FRAMES: [&str; 4] = ["=---", "-=--", "--=-", "---="];

pub fn render(
    frame: &mut Frame,
    area: Rect,
    theme: &Theme,
    progress: &OperationProgress,
    channels: &[ChannelRow],
) {
    let popup = centered_rect(POPUP_PERCENT_X, POPUP_PERCENT_Y, area);
    frame.render_widget(Clear, popup);

    let kind_label = match progress.kind.as_str() {
        "bulk_delete" => "Deleting channels",
        "bulk_sync" => "Syncing channels",
        other => other,
    };
    let title = format!(" {} ", kind_label);

    let block = Block::default()
        .title(Span::styled(
            title,
            Style::default().fg(theme.fg).add_modifier(Modifier::BOLD),
        ))
        .borders(Borders::ALL)
        .border_style(Style::default().fg(theme.accent))
        .style(Style::default().bg(theme.bg));

    let inner = block.inner(popup);
    frame.render_widget(block, popup);

    // Reserve fixed-height rows for the gauge/summary header and the footer;
    // the item list grows to fill whatever vertical space is left in the
    // middle. If `last_error` is set, we steal one row at the bottom of the
    // list area for the warning.
    let layout = Layout::vertical([
        Constraint::Length(1), // status line
        Constraint::Length(1), // gauge
        Constraint::Length(1), // summary counts
        Constraint::Length(1), // blank spacer
        Constraint::Min(1),    // item list (variable)
        Constraint::Length(1), // footer
    ])
    .split(inner);

    render_status_line(frame, layout[0], theme, progress);
    render_gauge(frame, layout[1], theme, progress);
    render_summary(frame, layout[2], theme, progress);

    // Reserve the bottom-most line of the list area for an error, if any.
    let (list_area, error_area) = match progress.last_error.as_deref() {
        Some(_) if layout[4].height >= 2 => {
            let list = Rect {
                x: layout[4].x,
                y: layout[4].y,
                width: layout[4].width,
                height: layout[4].height.saturating_sub(1),
            };
            let err = Rect {
                x: layout[4].x,
                y: layout[4].y + layout[4].height.saturating_sub(1),
                width: layout[4].width,
                height: 1,
            };
            (list, Some(err))
        }
        _ => (layout[4], None),
    };

    render_item_list(frame, list_area, theme, progress, channels);

    if let (Some(err), Some(rect)) = (progress.last_error.as_deref(), error_area) {
        let line = Line::from(Span::styled(
            format!("  warning: {}", err),
            Style::default().fg(theme.danger),
        ));
        frame.render_widget(Paragraph::new(line), rect);
    }

    render_footer(frame, layout[5], theme);
}

fn render_status_line(frame: &mut Frame, area: Rect, theme: &Theme, p: &OperationProgress) {
    let (status, current, total) = match p.last_status.as_ref() {
        Some(s) => (s.status.as_str(), s.current, s.total),
        None => ("pending", 0u32, 0u32),
    };
    let status_color = match status {
        "completed" => theme.accent,
        "failed" => theme.danger,
        _ => theme.fg,
    };
    let line = Line::from(vec![
        Span::raw("  "),
        Span::styled("status: ", Style::default().fg(theme.muted)),
        Span::styled(
            status.to_string(),
            Style::default()
                .fg(status_color)
                .add_modifier(Modifier::BOLD),
        ),
        Span::raw("   "),
        Span::styled("progress: ", Style::default().fg(theme.muted)),
        Span::styled(
            format!("{}/{}", current, total),
            Style::default().fg(theme.fg),
        ),
    ]);
    frame.render_widget(Paragraph::new(line), area);
}

fn render_gauge(frame: &mut Frame, area: Rect, theme: &Theme, p: &OperationProgress) {
    let (current, total) = match p.last_status.as_ref() {
        Some(s) => (s.current, s.total),
        None => (0u32, 0u32),
    };
    let ratio = if total == 0 {
        0.0
    } else {
        (current as f64 / total as f64).clamp(0.0, 1.0)
    };
    // Indented gauge — a single column of left padding lines it up with the
    // rest of the overlay copy.
    let gauge_area = Rect {
        x: area.x + 2,
        y: area.y,
        width: area.width.saturating_sub(4),
        height: area.height,
    };
    let gauge = Gauge::default()
        .gauge_style(Style::default().fg(theme.accent).bg(theme.border))
        .ratio(ratio)
        .label(format!("{}/{}", current, total));
    frame.render_widget(gauge, gauge_area);
}

fn render_summary(frame: &mut Frame, area: Rect, theme: &Theme, p: &OperationProgress) {
    let line = match p.last_status.as_ref() {
        None => Line::from(Span::styled(
            "  waiting for first status update...",
            Style::default().fg(theme.muted),
        )),
        Some(status) => {
            let (in_flight, succeeded, failed, skipped) = summarize_items(status);
            // Show counts; once running this is a stable, glanceable summary.
            Line::from(vec![
                Span::raw("  "),
                Span::styled("processing: ", Style::default().fg(theme.muted)),
                Span::styled(format!("{}", in_flight), Style::default().fg(theme.fg)),
                Span::raw("   "),
                Span::styled("ok: ", Style::default().fg(theme.muted)),
                Span::styled(format!("{}", succeeded), Style::default().fg(theme.success)),
                Span::raw("   "),
                Span::styled("failed: ", Style::default().fg(theme.muted)),
                Span::styled(format!("{}", failed), Style::default().fg(theme.danger)),
                Span::raw("   "),
                Span::styled("skipped: ", Style::default().fg(theme.muted)),
                Span::styled(format!("{}", skipped), Style::default().fg(theme.danger)),
            ])
        }
    };
    frame.render_widget(Paragraph::new(line), area);
}

fn render_item_list(
    frame: &mut Frame,
    area: Rect,
    theme: &Theme,
    progress: &OperationProgress,
    channels: &[ChannelRow],
) {
    if area.height == 0 {
        return;
    }
    let Some(status) = progress.last_status.as_ref() else {
        return;
    };
    if status.items.is_empty() {
        return;
    }

    let visible_rows = area.height as usize;
    let items_total = status.items.len();
    // Reserve one line for the "+N more" hint when items overflow.
    let max_rendered = if items_total > visible_rows {
        visible_rows.saturating_sub(1)
    } else {
        items_total
    };

    // Width budget: 2-space indent + indicator (6) + 1-space gap + suffix.
    // Suffix may include " (already syncing)" for skipped items, so reserve a
    // small budget for that and let the URL fill what's left.
    let total_width = area.width as usize;
    let indent = 2;
    let indicator = INDICATOR_WIDTH;
    let gap = 1;
    let url_budget = total_width
        .saturating_sub(indent)
        .saturating_sub(indicator)
        .saturating_sub(gap);

    let mut lines: Vec<Line<'static>> = Vec::with_capacity(max_rendered + 1);
    for item in status.items.iter().take(max_rendered) {
        lines.push(render_item_line(
            item,
            progress.tick,
            channels,
            theme,
            url_budget,
        ));
    }

    if items_total > max_rendered {
        let extra = items_total - max_rendered;
        let hint = format!("  ... +{} more", extra);
        lines.push(Line::from(Span::styled(
            hint,
            Style::default().fg(theme.muted),
        )));
    }

    frame.render_widget(Paragraph::new(lines), area);
}

fn render_item_line(
    item: &BulkOperationItem,
    tick: u8,
    channels: &[ChannelRow],
    theme: &Theme,
    url_budget: usize,
) -> Line<'static> {
    let (indicator_text, indicator_style) = render_item_indicator(item, tick, theme);
    let url = lookup_url(item.target_id, channels);
    let url_display = if url_budget == 0 {
        String::new()
    } else {
        truncate(&url, url_budget)
    };

    // Keep the indicator column a fixed width so URLs line up across rows
    // regardless of which marker the row currently shows.
    let padded_indicator = pad_right(&indicator_text, INDICATOR_WIDTH);

    Line::from(vec![
        Span::raw("  "),
        Span::styled(padded_indicator, indicator_style),
        Span::raw(" "),
        Span::styled(url_display, Style::default().fg(theme.fg)),
    ])
}

/// Look up the user-facing URL for a target id. Falls back to `#<id>` so the
/// list renders something even if the channel was already removed locally.
fn lookup_url(target_id: u64, channels: &[ChannelRow]) -> String {
    channels
        .iter()
        .find(|c| c.id == target_id)
        .map(|c| c.channel_url.clone())
        .unwrap_or_else(|| format!("#{}", target_id))
}

/// Compute the indicator text + style for a single item. Pending items render
/// as the active loader frame; terminal items render as a bracketed marker.
pub fn render_item_indicator(item: &BulkOperationItem, tick: u8, theme: &Theme) -> (String, Style) {
    match item.status.as_str() {
        "succeeded" => ("[done]".to_string(), Style::default().fg(theme.success)),
        "failed" => ("[fail]".to_string(), Style::default().fg(theme.danger)),
        "skipped" => ("[skip]".to_string(), Style::default().fg(theme.danger)),
        // "pending" or any non-terminal value — render the active loader frame.
        // Use the per-item phase-shifted frame so adjacent rows aren't in
        // lockstep (mirrors Rails' randomized CSS animation-delay).
        _ => (
            loader_frame_for_item(item.target_id, tick).to_string(),
            Style::default().fg(theme.muted),
        ),
    }
}

/// Pick a phase-shifted loader frame for a single row. Each row gets a
/// deterministic offset derived from its `target_id`, so adjacent rows are
/// out of phase (no extra state, no RNG, stable across re-renders).
///
/// The hash mixes a few right-shifts of the id before taking it mod 4 — this
/// breaks up the trivial pattern you'd get from `id % 4` for sequential ids
/// and gives a more even spread across the four frames.
pub fn loader_frame_for_item(item_id: u64, tick: u8) -> &'static str {
    let mixed = item_id ^ (item_id >> 3) ^ (item_id >> 7);
    let offset = (mixed % LOADER_FRAMES.len() as u64) as u8;
    LOADER_FRAMES[(tick.wrapping_add(offset) as usize) % LOADER_FRAMES.len()]
}

/// Pad a UTF-8 string on the right with spaces to a target column width. Used
/// to keep the indicator column a fixed width regardless of marker length so
/// URLs line up across rows.
fn pad_right(s: &str, width: usize) -> String {
    let count = s.chars().count();
    if count >= width {
        return s.to_string();
    }
    let mut out = String::with_capacity(s.len() + (width - count));
    out.push_str(s);
    for _ in 0..(width - count) {
        out.push(' ');
    }
    out
}

/// Truncate a string with an ellipsis if it exceeds `max` characters. Mirrors
/// the helper used by the channels list so the visual length matches.
fn truncate(s: &str, max: usize) -> String {
    let char_count = s.chars().count();
    if char_count <= max {
        s.to_string()
    } else if max <= 3 {
        s.chars().take(max).collect()
    } else {
        format!("{}...", s.chars().take(max - 3).collect::<String>())
    }
}

fn render_footer(frame: &mut Frame, area: Rect, theme: &Theme) {
    let line = Line::from(vec![
        Span::raw("  "),
        Span::styled("[Esc]", Style::default().fg(theme.muted)),
        Span::styled(
            " dismiss (operation continues server-side)",
            Style::default().fg(theme.fg),
        ),
    ]);
    frame.render_widget(Paragraph::new(line), area);
}

fn summarize_items(status: &BulkOperationStatus) -> (u32, u32, u32, u32) {
    let mut in_flight = 0u32;
    let mut succeeded = 0u32;
    let mut failed = 0u32;
    let mut skipped = 0u32;
    for item in status.items.iter() {
        match item.status.as_str() {
            "succeeded" => succeeded += 1,
            "failed" => failed += 1,
            "skipped" => skipped += 1,
            _ => in_flight += 1,
        }
    }
    (in_flight, succeeded, failed, skipped)
}

fn centered_rect(percent_x: u16, percent_y: u16, area: Rect) -> Rect {
    let vertical = Layout::vertical([Constraint::Percentage(percent_y)])
        .flex(Flex::Center)
        .split(area);
    let horizontal = Layout::horizontal([Constraint::Percentage(percent_x)])
        .flex(Flex::Center)
        .split(vertical[0]);
    horizontal[0]
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::models::{BulkOperationItem, BulkOperationStatus};
    use crate::theme::{Theme, ThemeMode};
    use ratatui::{Terminal, backend::TestBackend, buffer::Buffer};

    fn item(target_id: u64, status: &str) -> BulkOperationItem {
        BulkOperationItem {
            id: target_id,
            target_id,
            target_type: "Channel".to_string(),
            status: status.to_string(),
            error_message: None,
        }
    }

    fn theme() -> Theme {
        Theme::from_mode(ThemeMode::Dark)
    }

    fn channel(id: u64, url: &str) -> ChannelRow {
        ChannelRow {
            id,
            channel_url: url.to_string(),
            star: false,
            connected: false,
            last_synced_at: None,
        }
    }

    #[test]
    fn summarize_items_counts_each_status() {
        let status = BulkOperationStatus {
            id: 1,
            kind: "bulk_sync".to_string(),
            status: "running".to_string(),
            current: 1,
            total: 4,
            items: vec![
                item(10, "succeeded"),
                item(11, "failed"),
                item(12, "skipped"),
                item(13, "pending"),
            ],
            completed_at: None,
        };
        let (in_flight, ok, failed, skipped) = summarize_items(&status);
        assert_eq!(in_flight, 1);
        assert_eq!(ok, 1);
        assert_eq!(failed, 1);
        assert_eq!(skipped, 1);
    }

    #[test]
    fn render_item_indicator_returns_done_for_succeeded() {
        let theme = theme();
        let (text, style) = render_item_indicator(&item(1, "succeeded"), 0, &theme);
        assert_eq!(text, "[done]");
        // succeeded must use the success color so it pops against the gauge.
        assert_eq!(style.fg, Some(theme.success));
    }

    #[test]
    fn render_item_indicator_returns_fail_for_failed() {
        let theme = theme();
        let (text, style) = render_item_indicator(&item(1, "failed"), 0, &theme);
        assert_eq!(text, "[fail]");
        assert_eq!(style.fg, Some(theme.danger));
    }

    #[test]
    fn render_item_indicator_returns_skip_for_skipped() {
        let theme = theme();
        let (text, style) = render_item_indicator(&item(1, "skipped"), 0, &theme);
        assert_eq!(text, "[skip]");
        // Rails matches skipped to danger for visibility — same here.
        assert_eq!(style.fg, Some(theme.danger));
    }

    #[test]
    fn render_item_indicator_returns_loader_frame_for_pending() {
        let theme = theme();
        // The pending branch now stamps a per-row phase offset onto the
        // global tick — assert we get one of the four canonical frames so
        // the test stays meaningful regardless of the chosen hash.
        let (text, _) = render_item_indicator(&item(1, "pending"), 2, &theme);
        assert!(
            LOADER_FRAMES.contains(&text.as_str()),
            "pending indicator must be one of the loader frames; got {}",
            text
        );
        // Pin the actual frame for id=1, tick=2 so accidental hash changes
        // are caught. id=1 → offset=1 → tick(2)+1 = 3 → "---=".
        assert_eq!(text, "---=");
    }

    #[test]
    fn render_item_indicator_treats_unknown_status_as_pending() {
        // The server can in theory send any string — the overlay must keep
        // animating rather than blanking out for forward-compat statuses.
        let theme = theme();
        let (text, _) = render_item_indicator(&item(1, "running"), 1, &theme);
        // id=1 → offset=1 → tick(1)+1 = 2 → "--=-".
        assert_eq!(text, "--=-");
    }

    #[test]
    fn loader_frame_for_item_distributes_offsets() {
        // Across a small sweep of ids, the four canonical frames must all be
        // reachable at a single tick — this is what proves rows aren't in
        // lockstep. The exact distribution depends on the hash; we only
        // require that all four frames appear for some id in 1..=8.
        let mut seen = std::collections::HashSet::new();
        for id in 1u64..=8 {
            seen.insert(loader_frame_for_item(id, 0));
        }
        for frame in LOADER_FRAMES.iter() {
            assert!(
                seen.contains(frame),
                "expected frame {} to be reachable across ids 1..=8 at tick=0; saw {:?}",
                frame,
                seen
            );
        }
    }

    #[test]
    fn loader_frame_for_item_is_deterministic() {
        // Same id + same tick must always yield the same frame — otherwise
        // the per-row offset would jitter on every render.
        for id in [0u64, 1, 7, 42, 1_000, u64::MAX] {
            for tick in [0u8, 1, 17, u8::MAX] {
                let a = loader_frame_for_item(id, tick);
                let b = loader_frame_for_item(id, tick);
                assert_eq!(a, b, "id={} tick={} not deterministic", id, tick);
            }
        }
    }

    #[test]
    fn loader_frame_for_item_advances_with_tick() {
        // Holding the id fixed and stepping the tick must visit all four
        // frames within four consecutive ticks — i.e., the per-row offset
        // does not break the cycle, it only phase-shifts it.
        let id = 42u64;
        let mut seen = std::collections::HashSet::new();
        for t in 0u8..4 {
            seen.insert(loader_frame_for_item(id, t));
        }
        assert_eq!(
            seen.len(),
            LOADER_FRAMES.len(),
            "id={} did not cycle through all four frames in 4 ticks; saw {:?}",
            id,
            seen
        );
    }

    fn render_to_buffer(
        progress: &OperationProgress,
        channels: &[ChannelRow],
        width: u16,
        height: u16,
    ) -> Buffer {
        let backend = TestBackend::new(width, height);
        let mut terminal = Terminal::new(backend).expect("test backend");
        terminal
            .draw(|frame| {
                let area = frame.area();
                // Paint the popup over a full-screen body — matches the real
                // render flow which stacks the overlay over the active screen.
                render(frame, area, &theme(), progress, channels);
            })
            .expect("draw");
        terminal.backend().buffer().clone()
    }

    fn buffer_to_string(buf: &Buffer) -> String {
        let mut out = String::new();
        for y in 0..buf.area.height {
            for x in 0..buf.area.width {
                out.push_str(buf[(x, y)].symbol());
            }
            out.push('\n');
        }
        out
    }

    #[test]
    fn renders_mixed_state_overlay_with_all_indicators() {
        // Mixed-state snapshot: the overlay should show one row per status
        // type, with the loader frame visible for the pending row.
        let mut progress = OperationProgress::new(99, "bulk_sync");
        progress.tick = 0;
        progress.last_status = Some(BulkOperationStatus {
            id: 99,
            kind: "bulk_sync".to_string(),
            status: "running".to_string(),
            current: 2,
            total: 5,
            items: vec![
                item(10, "pending"),
                item(11, "succeeded"),
                item(12, "skipped"),
                item(13, "pending"),
                item(14, "failed"),
            ],
            completed_at: None,
        });
        let channels = vec![
            channel(
                10,
                "https://www.youtube.com/channel/UC_AAAAAAAAAAAAAAAAAAAA",
            ),
            channel(
                11,
                "https://www.youtube.com/channel/UC_BBBBBBBBBBBBBBBBBBBB",
            ),
            channel(
                12,
                "https://www.youtube.com/channel/UC_CCCCCCCCCCCCCCCCCCCC",
            ),
            channel(
                13,
                "https://www.youtube.com/channel/UC_DDDDDDDDDDDDDDDDDDDD",
            ),
            channel(
                14,
                "https://www.youtube.com/channel/UC_EEEEEEEEEEEEEEEEEEEE",
            ),
        ];

        let buf = render_to_buffer(&progress, &channels, 100, 30);
        let dump = buffer_to_string(&buf);

        // The loader frame for tick=0 must appear at least once (we have two
        // pending rows) — this proves the per-row animation is wired up.
        assert!(
            dump.contains("=---"),
            "expected the tick=0 loader frame in the rendered overlay:\n{}",
            dump
        );
        // All three terminal markers should appear.
        assert!(dump.contains("[done]"), "missing [done]:\n{}", dump);
        assert!(dump.contains("[fail]"), "missing [fail]:\n{}", dump);
        assert!(dump.contains("[skip]"), "missing [skip]:\n{}", dump);
        // At least one of the YouTube URLs should be present (truncated or
        // otherwise) so we know the URL column is being rendered.
        assert!(
            dump.contains("youtube.com/channel"),
            "expected at least one channel URL in the overlay:\n{}",
            dump
        );
    }

    #[test]
    fn renders_top_level_gauge_progress_label() {
        // The existing top-level gauge must remain — the new item list lives
        // *below* it. This test pins the "current/total" label in the buffer.
        let mut progress = OperationProgress::new(1, "bulk_delete");
        progress.last_status = Some(BulkOperationStatus {
            id: 1,
            kind: "bulk_delete".to_string(),
            status: "running".to_string(),
            current: 2,
            total: 5,
            items: vec![item(10, "succeeded"), item(11, "pending")],
            completed_at: None,
        });
        let channels = vec![channel(10, "https://x"), channel(11, "https://y")];

        let buf = render_to_buffer(&progress, &channels, 80, 24);
        let dump = buffer_to_string(&buf);
        assert!(
            dump.contains("2/5"),
            "expected gauge label '2/5':\n{}",
            dump
        );
    }

    #[test]
    fn renders_overflow_hint_when_more_items_than_rows() {
        // With many items and a tight overlay height, the list should show a
        // "+N more" hint rather than overflowing past the overlay border.
        let mut progress = OperationProgress::new(1, "bulk_delete");
        let items: Vec<BulkOperationItem> = (0..20u64).map(|i| item(100 + i, "pending")).collect();
        progress.last_status = Some(BulkOperationStatus {
            id: 1,
            kind: "bulk_delete".to_string(),
            status: "running".to_string(),
            current: 0,
            total: 20,
            items,
            completed_at: None,
        });
        let channels: Vec<ChannelRow> = (0..20u64)
            .map(|i| channel(100 + i, &format!("https://example.com/{}", i)))
            .collect();

        let buf = render_to_buffer(&progress, &channels, 80, 16);
        let dump = buffer_to_string(&buf);
        assert!(
            dump.contains("more"),
            "expected '+N more' overflow hint:\n{}",
            dump
        );
    }

    #[test]
    fn pad_right_pads_short_strings_to_width() {
        assert_eq!(pad_right("[done]", 6), "[done]");
        assert_eq!(pad_right("=---", 6), "=---  ");
        // Strings already at-or-over the width pass through untouched.
        assert_eq!(pad_right("0123456", 6), "0123456");
    }

    #[test]
    fn truncate_caps_long_url_with_ellipsis() {
        let long = "https://www.youtube.com/channel/UC_long_long_long";
        let out = truncate(long, 20);
        assert_eq!(out.chars().count(), 20);
        assert!(out.ends_with("..."));
    }
}
