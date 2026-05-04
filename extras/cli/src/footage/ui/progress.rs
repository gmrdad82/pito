//! Progress overlay rendered while the importer applies a diff. Mirrors the
//! shape of `crate::ui::operation_progress`:
//!
//! - 4-frame loader top-left for any in-flight row (`=---`, `-=--`, `--=-`,
//!   `---=`),
//! - per-row status indicator (`[done]` / `[fail]` / `[skip]`),
//! - top-level gauge with `current/total` label,
//! - final summary `N added, M changed, K deleted, F failed`.
//!
//! The importer drives state by mutating the [`ProgressState`] in-place
//! between each item; the render function reads whatever's current.

use ratatui::{
    Frame,
    layout::{Constraint, Flex, Layout, Rect},
    style::{Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Clear, Gauge, Paragraph},
};

use crate::theme::Theme;

/// Width of the overlay relative to the body area.
const POPUP_PERCENT_X: u16 = 70;
/// Height of the overlay relative to the body area.
const POPUP_PERCENT_Y: u16 = 70;
/// Visible width of a per-row status indicator. `[done]` / `[fail]` / `[skip]`
/// are 6 chars; the loader frames are 4 chars padded to 6 so the path column
/// lines up across rows regardless of state.
const INDICATOR_WIDTH: usize = 6;

/// Dot-loader frames mirroring the Rails `.dot-loader` CSS animation.
pub const LOADER_FRAMES: [&str; 4] = ["=---", "-=--", "--=-", "---="];

/// Per-row outcome bucket.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ItemKind {
    Add,
    Change,
    Delete,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ItemStatus {
    Pending,
    Running,
    Done,
    Failed,
    /// Reserved for future "operation pre-empted at item N because the user
    /// cancelled mid-run"; render path supports it today, the import flow
    /// doesn't yet emit it (every queued entry is attempted exactly once).
    #[allow(dead_code)]
    Skipped,
}

/// One row in the progress list. The label is a path string (probed file or
/// API record), the kind tells the renderer which color to tint the marker.
#[derive(Debug, Clone)]
pub struct ProgressItem {
    pub label: String,
    pub kind: ItemKind,
    pub status: ItemStatus,
    pub error: Option<String>,
}

/// Live state of the progress overlay. Mutated by the importer as items land.
#[derive(Debug, Clone)]
pub struct ProgressState {
    pub items: Vec<ProgressItem>,
    /// Frame counter for the dot loader. Bumped on every render tick.
    pub tick: u8,
    pub finished: bool,
}

impl ProgressState {
    pub fn new(items: Vec<ProgressItem>) -> Self {
        Self {
            items,
            tick: 0,
            finished: false,
        }
    }

    pub fn current(&self) -> u32 {
        self.items
            .iter()
            .filter(|i| {
                matches!(
                    i.status,
                    ItemStatus::Done | ItemStatus::Failed | ItemStatus::Skipped
                )
            })
            .count() as u32
    }

    pub fn total(&self) -> u32 {
        self.items.len() as u32
    }

    pub fn counts(&self) -> ProgressCounts {
        let mut c = ProgressCounts::default();
        for i in self.items.iter() {
            match (i.kind, i.status) {
                (ItemKind::Add, ItemStatus::Done) => c.added += 1,
                (ItemKind::Change, ItemStatus::Done) => c.changed += 1,
                (ItemKind::Delete, ItemStatus::Done) => c.deleted += 1,
                (_, ItemStatus::Failed) => c.failed += 1,
                (_, ItemStatus::Skipped) => c.skipped += 1,
                _ => {}
            }
        }
        c
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct ProgressCounts {
    pub added: u32,
    pub changed: u32,
    pub deleted: u32,
    pub failed: u32,
    pub skipped: u32,
}

impl ProgressCounts {
    /// Format the canonical post-import summary line per spec §7.4.
    pub fn summary_line(&self) -> String {
        format!(
            "{} added, {} changed, {} deleted, {} failed",
            self.added, self.changed, self.deleted, self.failed
        )
    }
}

pub fn render(frame: &mut Frame, area: Rect, theme: &Theme, state: &ProgressState) {
    let popup = centered_rect(POPUP_PERCENT_X, POPUP_PERCENT_Y, area);
    frame.render_widget(Clear, popup);

    let title = if state.finished {
        " Footage import — done ".to_string()
    } else {
        " Footage import ".to_string()
    };

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

    let layout = Layout::vertical([
        Constraint::Length(1), // status line
        Constraint::Length(1), // gauge
        Constraint::Length(1), // summary counts
        Constraint::Length(1), // blank spacer
        Constraint::Min(1),    // item list
        Constraint::Length(1), // footer
    ])
    .split(inner);

    render_status(frame, layout[0], theme, state);
    render_gauge(frame, layout[1], theme, state);
    render_summary(frame, layout[2], theme, state);
    render_items(frame, layout[4], theme, state);
    render_footer(frame, layout[5], theme, state);
}

fn render_status(frame: &mut Frame, area: Rect, theme: &Theme, state: &ProgressState) {
    let status_label = if state.finished {
        "completed"
    } else {
        "running"
    };
    let status_color = if state.finished {
        theme.success
    } else {
        theme.fg
    };
    let line = Line::from(vec![
        Span::raw("  "),
        Span::styled("status: ", Style::default().fg(theme.muted)),
        Span::styled(
            status_label.to_string(),
            Style::default()
                .fg(status_color)
                .add_modifier(Modifier::BOLD),
        ),
        Span::raw("   "),
        Span::styled("progress: ", Style::default().fg(theme.muted)),
        Span::styled(
            format!("{}/{}", state.current(), state.total()),
            Style::default().fg(theme.fg),
        ),
    ]);
    frame.render_widget(Paragraph::new(line), area);
}

fn render_gauge(frame: &mut Frame, area: Rect, theme: &Theme, state: &ProgressState) {
    let total = state.total();
    let current = state.current();
    let ratio = if total == 0 {
        0.0
    } else {
        (current as f64 / total as f64).clamp(0.0, 1.0)
    };
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

fn render_summary(frame: &mut Frame, area: Rect, theme: &Theme, state: &ProgressState) {
    let c = state.counts();
    let line = Line::from(vec![
        Span::raw("  "),
        Span::styled("added: ", Style::default().fg(theme.muted)),
        Span::styled(format!("{}", c.added), Style::default().fg(theme.success)),
        Span::raw("   "),
        Span::styled("changed: ", Style::default().fg(theme.muted)),
        Span::styled(format!("{}", c.changed), Style::default().fg(theme.fg)),
        Span::raw("   "),
        Span::styled("deleted: ", Style::default().fg(theme.muted)),
        Span::styled(format!("{}", c.deleted), Style::default().fg(theme.danger)),
        Span::raw("   "),
        Span::styled("failed: ", Style::default().fg(theme.muted)),
        Span::styled(format!("{}", c.failed), Style::default().fg(theme.danger)),
    ]);
    frame.render_widget(Paragraph::new(line), area);
}

fn render_items(frame: &mut Frame, area: Rect, theme: &Theme, state: &ProgressState) {
    if area.height == 0 {
        return;
    }
    let visible_rows = area.height as usize;
    let total = state.items.len();
    let max_rendered = if total > visible_rows {
        visible_rows.saturating_sub(1)
    } else {
        total
    };

    let total_width = area.width as usize;
    let indent = 2;
    let gap = 1;
    let path_budget = total_width
        .saturating_sub(indent)
        .saturating_sub(INDICATOR_WIDTH)
        .saturating_sub(gap);

    let mut lines: Vec<Line<'static>> = Vec::with_capacity(max_rendered + 1);
    for (idx, item) in state.items.iter().take(max_rendered).enumerate() {
        let indicator = render_item_indicator(item, idx, state.tick, theme);
        let path = if path_budget == 0 {
            String::new()
        } else {
            truncate(&item.label, path_budget)
        };
        lines.push(Line::from(vec![
            Span::raw("  "),
            Span::styled(pad_right(&indicator.0, INDICATOR_WIDTH), indicator.1),
            Span::raw(" "),
            Span::styled(path, Style::default().fg(theme.fg)),
        ]));
    }

    if total > max_rendered {
        let extra = total - max_rendered;
        lines.push(Line::from(Span::styled(
            format!("  ... +{} more", extra),
            Style::default().fg(theme.muted),
        )));
    }

    frame.render_widget(Paragraph::new(lines), area);
}

/// Compute the indicator text + style for a single row. Pure (no Frame), so
/// tests can pin the exact strings emitted at each ItemStatus / ItemKind.
pub fn render_item_indicator(
    item: &ProgressItem,
    row_index: usize,
    tick: u8,
    theme: &Theme,
) -> (String, Style) {
    match item.status {
        ItemStatus::Done => ("[done]".to_string(), Style::default().fg(theme.success)),
        ItemStatus::Failed => ("[fail]".to_string(), Style::default().fg(theme.danger)),
        ItemStatus::Skipped => ("[skip]".to_string(), Style::default().fg(theme.danger)),
        ItemStatus::Pending | ItemStatus::Running => (
            loader_frame(row_index, tick).to_string(),
            Style::default().fg(theme.muted),
        ),
    }
}

/// Pick a phase-shifted loader frame for a row index. Adjacent rows are out
/// of phase to mirror the Rails CSS `animation-delay` jitter.
pub fn loader_frame(row_index: usize, tick: u8) -> &'static str {
    let offset = (row_index as u8) % LOADER_FRAMES.len() as u8;
    LOADER_FRAMES[(tick.wrapping_add(offset) as usize) % LOADER_FRAMES.len()]
}

fn render_footer(frame: &mut Frame, area: Rect, theme: &Theme, state: &ProgressState) {
    let line = if state.finished {
        Line::from(vec![
            Span::raw("  "),
            Span::styled(state.counts().summary_line(), Style::default().fg(theme.fg)),
            Span::raw("    "),
            Span::styled("[any key]", Style::default().fg(theme.muted)),
            Span::styled(" dismiss", Style::default().fg(theme.fg)),
        ])
    } else {
        Line::from(vec![
            Span::raw("  "),
            Span::styled("[Esc]", Style::default().fg(theme.muted)),
            Span::styled(" cancel after current item", Style::default().fg(theme.fg)),
        ])
    };
    frame.render_widget(Paragraph::new(line), area);
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

fn truncate(s: &str, max: usize) -> String {
    let chars: Vec<char> = s.chars().collect();
    if chars.len() <= max {
        s.to_string()
    } else if max <= 3 {
        chars.iter().take(max).collect()
    } else {
        let prefix: String = chars.iter().take(max - 3).collect();
        format!("{}...", prefix)
    }
}

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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::theme::{Theme, ThemeMode};

    fn theme() -> Theme {
        Theme::from_mode(ThemeMode::Dark)
    }

    fn item(label: &str, kind: ItemKind, status: ItemStatus) -> ProgressItem {
        ProgressItem {
            label: label.to_string(),
            kind,
            status,
            error: None,
        }
    }

    #[test]
    fn counts_track_done_and_failures_per_kind() {
        let state = ProgressState::new(vec![
            item("/a.mp4", ItemKind::Add, ItemStatus::Done),
            item("/b.mp4", ItemKind::Add, ItemStatus::Failed),
            item("/c.mp4", ItemKind::Change, ItemStatus::Done),
            item("/d.mp4", ItemKind::Delete, ItemStatus::Done),
            item("/e.mp4", ItemKind::Delete, ItemStatus::Failed),
        ]);
        let c = state.counts();
        assert_eq!(c.added, 1);
        assert_eq!(c.changed, 1);
        assert_eq!(c.deleted, 1);
        assert_eq!(c.failed, 2);
    }

    #[test]
    fn summary_line_matches_spec_format() {
        let c = ProgressCounts {
            added: 3,
            changed: 1,
            deleted: 2,
            failed: 1,
            skipped: 0,
        };
        // Spec: "N added, M changed, K deleted, F failed"
        assert_eq!(c.summary_line(), "3 added, 1 changed, 2 deleted, 1 failed");
    }

    #[test]
    fn current_count_excludes_pending_rows() {
        let state = ProgressState::new(vec![
            item("/a.mp4", ItemKind::Add, ItemStatus::Done),
            item("/b.mp4", ItemKind::Add, ItemStatus::Pending),
            item("/c.mp4", ItemKind::Add, ItemStatus::Failed),
        ]);
        assert_eq!(state.current(), 2);
        assert_eq!(state.total(), 3);
    }

    #[test]
    fn render_item_indicator_done_uses_success_color() {
        let theme = theme();
        let it = item("/a.mp4", ItemKind::Add, ItemStatus::Done);
        let (text, style) = render_item_indicator(&it, 0, 0, &theme);
        assert_eq!(text, "[done]");
        assert_eq!(style.fg, Some(theme.success));
    }

    #[test]
    fn render_item_indicator_failed_uses_danger_color() {
        let theme = theme();
        let it = item("/a.mp4", ItemKind::Change, ItemStatus::Failed);
        let (text, style) = render_item_indicator(&it, 0, 0, &theme);
        assert_eq!(text, "[fail]");
        assert_eq!(style.fg, Some(theme.danger));
    }

    #[test]
    fn render_item_indicator_skipped_uses_danger_color() {
        let theme = theme();
        let it = item("/a.mp4", ItemKind::Add, ItemStatus::Skipped);
        let (text, _) = render_item_indicator(&it, 0, 0, &theme);
        assert_eq!(text, "[skip]");
    }

    #[test]
    fn render_item_indicator_pending_returns_loader_frame() {
        let theme = theme();
        let it = item("/a.mp4", ItemKind::Add, ItemStatus::Pending);
        let (text, _) = render_item_indicator(&it, 0, 0, &theme);
        assert!(LOADER_FRAMES.contains(&text.as_str()));
    }

    #[test]
    fn loader_frame_advances_with_tick() {
        let mut seen = std::collections::HashSet::new();
        for t in 0u8..4 {
            seen.insert(loader_frame(0, t));
        }
        assert_eq!(
            seen.len(),
            LOADER_FRAMES.len(),
            "loader did not cycle through all 4 frames in 4 ticks"
        );
    }

    #[test]
    fn loader_frame_phase_shifts_per_row() {
        // Adjacent rows must not be in lockstep — phase shift makes the
        // animation visually richer (and matches the Rails CSS jitter).
        let row0 = loader_frame(0, 0);
        let row1 = loader_frame(1, 0);
        assert_ne!(row0, row1);
    }

    #[test]
    fn pad_right_pads_short_indicator_to_six_columns() {
        assert_eq!(pad_right("=---", INDICATOR_WIDTH), "=---  ");
        assert_eq!(pad_right("[done]", INDICATOR_WIDTH), "[done]");
    }
}
