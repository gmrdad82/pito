use ratatui::{
    Frame,
    layout::{Constraint, Flex, Layout, Rect},
    style::{Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Clear, Paragraph},
};

use crate::theme::Theme;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConfirmationKind {
    Delete,
    Sync,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConfirmationOutcome {
    Proceed,
    Cancel,
}

#[derive(Debug, Clone)]
pub struct ConfirmationItem {
    pub id: u64,
    /// Truncated label (typically the channel URL).
    pub label: String,
    /// Sync only: this id was returned by the API as already-syncing.
    pub will_be_skipped: bool,
}

#[derive(Debug, Clone)]
pub struct ConfirmationState {
    pub kind: ConfirmationKind,
    pub items: Vec<ConfirmationItem>,
    /// Reserved for a custom-message line on the overlay; not currently
    /// rendered but populated by the API preview path.
    #[allow(dead_code)]
    pub message: String,
}

impl ConfirmationState {
    pub fn proceed_allowed(&self) -> bool {
        match self.kind {
            ConfirmationKind::Delete => !self.items.is_empty(),
            ConfirmationKind::Sync => self.items.iter().any(|i| !i.will_be_skipped),
        }
    }

    pub fn skip_count(&self) -> usize {
        self.items.iter().filter(|i| i.will_be_skipped).count()
    }

    pub fn syncable_ids(&self) -> Vec<u64> {
        self.items
            .iter()
            .filter(|i| !i.will_be_skipped)
            .map(|i| i.id)
            .collect()
    }

    pub fn all_ids(&self) -> Vec<u64> {
        self.items.iter().map(|i| i.id).collect()
    }
}

/// Map a key character to an outcome. Returns `None` for keys that should be ignored
/// (so the caller can keep the confirmation modal open).
pub fn key_outcome(ch: char, state: &ConfirmationState) -> Option<ConfirmationOutcome> {
    match ch {
        'y' | 'Y' => {
            if state.proceed_allowed() {
                Some(ConfirmationOutcome::Proceed)
            } else {
                Some(ConfirmationOutcome::Cancel)
            }
        }
        _ => Some(ConfirmationOutcome::Cancel),
    }
}

pub fn render(frame: &mut Frame, area: Rect, theme: &Theme, state: &ConfirmationState) {
    let popup = centered_rect(70, 70, area);
    frame.render_widget(Clear, popup);

    let title = match state.kind {
        ConfirmationKind::Delete => format!(" Delete {} channel(s)? ", state.items.len()),
        ConfirmationKind::Sync => format!(" Sync {} channel(s)? ", state.items.len()),
    };

    let border_color = match state.kind {
        ConfirmationKind::Delete => theme.danger,
        ConfirmationKind::Sync => theme.accent,
    };

    let block = Block::default()
        .title(Span::styled(
            title,
            Style::default().fg(theme.fg).add_modifier(Modifier::BOLD),
        ))
        .borders(Borders::ALL)
        .border_style(Style::default().fg(border_color))
        .style(Style::default().bg(theme.bg));

    let inner = block.inner(popup);
    frame.render_widget(block, popup);

    let layout = Layout::vertical([
        Constraint::Min(0),    // body (item list)
        Constraint::Length(1), // separator/spacer
        Constraint::Length(1), // skip note
        Constraint::Length(1), // footer keys
    ])
    .split(inner);

    render_body(frame, layout[0], theme, state);
    render_skip_note(frame, layout[2], theme, state);
    render_footer(frame, layout[3], theme, state);
}

fn render_body(frame: &mut Frame, area: Rect, theme: &Theme, state: &ConfirmationState) {
    let visible = area.height as usize;
    let mut lines: Vec<Line> = Vec::with_capacity(state.items.len().min(visible));
    for (i, item) in state.items.iter().take(visible).enumerate() {
        let _ = i;
        let label = truncate(&item.label, area.width.saturating_sub(16) as usize);
        let mut spans: Vec<Span> = Vec::new();
        spans.push(Span::raw("  "));
        if item.will_be_skipped {
            spans.push(Span::styled(
                "[skip] ",
                Style::default().fg(theme.danger),
            ));
            spans.push(Span::styled(label, Style::default().fg(theme.muted)));
        } else {
            let bullet = match state.kind {
                ConfirmationKind::Delete => "[del] ",
                ConfirmationKind::Sync => "[sync] ",
            };
            spans.push(Span::styled(bullet, Style::default().fg(theme.accent)));
            spans.push(Span::styled(label, Style::default().fg(theme.fg)));
        }
        lines.push(Line::from(spans));
    }
    if state.items.len() > visible {
        let extra = state.items.len() - visible;
        lines.push(Line::from(Span::styled(
            format!("  ... and {} more", extra),
            Style::default().fg(theme.muted),
        )));
    }
    frame.render_widget(Paragraph::new(lines), area);
}

fn render_skip_note(frame: &mut Frame, area: Rect, theme: &Theme, state: &ConfirmationState) {
    if state.kind != ConfirmationKind::Sync {
        return;
    }
    let skips = state.skip_count();
    if skips == 0 {
        return;
    }
    let line = Line::from(Span::styled(
        format!("  {} channel(s) will be skipped (already syncing)", skips),
        Style::default().fg(theme.muted),
    ));
    frame.render_widget(Paragraph::new(line), area);
}

fn render_footer(frame: &mut Frame, area: Rect, theme: &Theme, state: &ConfirmationState) {
    let line = if state.proceed_allowed() {
        Line::from(vec![
            Span::raw("  "),
            Span::styled("[y]", Style::default().fg(theme.accent)),
            Span::styled(" confirm   ", Style::default().fg(theme.fg)),
            Span::styled("[any other key]", Style::default().fg(theme.muted)),
            Span::styled(" cancel", Style::default().fg(theme.fg)),
        ])
    } else {
        Line::from(vec![
            Span::raw("  "),
            Span::styled(
                "Nothing to do — press any key to dismiss",
                Style::default().fg(theme.muted),
            ),
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

#[cfg(test)]
mod tests {
    use super::*;

    fn make_items(skips: &[bool]) -> Vec<ConfirmationItem> {
        skips
            .iter()
            .enumerate()
            .map(|(i, &skip)| ConfirmationItem {
                id: i as u64 + 1,
                label: format!("https://youtube.com/@channel-{}", i + 1),
                will_be_skipped: skip,
            })
            .collect()
    }

    #[test]
    fn delete_proceed_allowed_with_items() {
        let state = ConfirmationState {
            kind: ConfirmationKind::Delete,
            items: make_items(&[false, false]),
            message: String::new(),
        };
        assert!(state.proceed_allowed());
    }

    #[test]
    fn delete_proceed_blocked_when_empty() {
        let state = ConfirmationState {
            kind: ConfirmationKind::Delete,
            items: vec![],
            message: String::new(),
        };
        assert!(!state.proceed_allowed());
    }

    #[test]
    fn sync_proceed_blocked_when_all_skipped() {
        let state = ConfirmationState {
            kind: ConfirmationKind::Sync,
            items: make_items(&[true, true]),
            message: String::new(),
        };
        assert!(!state.proceed_allowed());
        assert_eq!(state.skip_count(), 2);
    }

    #[test]
    fn sync_proceed_allowed_with_partial_skips() {
        let state = ConfirmationState {
            kind: ConfirmationKind::Sync,
            items: make_items(&[true, false, true]),
            message: String::new(),
        };
        assert!(state.proceed_allowed());
        assert_eq!(state.syncable_ids(), vec![2]);
        assert_eq!(state.skip_count(), 2);
    }

    #[test]
    fn key_outcome_y_confirms_when_allowed() {
        let state = ConfirmationState {
            kind: ConfirmationKind::Delete,
            items: make_items(&[false]),
            message: String::new(),
        };
        assert_eq!(key_outcome('y', &state), Some(ConfirmationOutcome::Proceed));
        assert_eq!(key_outcome('Y', &state), Some(ConfirmationOutcome::Proceed));
        assert_eq!(
            key_outcome('n', &state),
            Some(ConfirmationOutcome::Cancel)
        );
        assert_eq!(
            key_outcome(' ', &state),
            Some(ConfirmationOutcome::Cancel)
        );
    }

    #[test]
    fn key_outcome_y_cancels_when_blocked() {
        let state = ConfirmationState {
            kind: ConfirmationKind::Sync,
            items: make_items(&[true, true]),
            message: String::new(),
        };
        assert_eq!(key_outcome('y', &state), Some(ConfirmationOutcome::Cancel));
    }

    #[test]
    fn all_ids_returns_every_item() {
        let state = ConfirmationState {
            kind: ConfirmationKind::Delete,
            items: make_items(&[false, true, false]),
            message: String::new(),
        };
        assert_eq!(state.all_ids(), vec![1, 2, 3]);
    }
}
