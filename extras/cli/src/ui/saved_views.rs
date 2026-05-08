use ratatui::{
    Frame,
    layout::Rect,
    style::Style,
    text::{Line, Span},
    widgets::{Block, Borders, Paragraph},
};

use crate::theme::Theme;

pub struct SavedViewsState {
    pub views: Vec<SavedViewRow>,
    pub selected: usize,
}

pub struct SavedViewRow {
    /// Reserved for upcoming row-click navigation (Enter opens the view).
    #[allow(dead_code)]
    pub id: u64,
    pub name: String,
    pub kind: String,
    pub url: String,
}

pub fn render(frame: &mut Frame, area: Rect, theme: &Theme, state: &SavedViewsState) {
    let block = Block::default()
        .title(" saved views ")
        .borders(Borders::ALL)
        .border_style(Style::default().fg(theme.border));

    let inner = block.inner(area);
    frame.render_widget(block, area);

    let mut lines: Vec<Line> = Vec::new();

    // Header
    lines.push(Line::from(""));
    lines.push(Line::from(vec![
        Span::styled("  ", Style::default().fg(theme.muted)),
        Span::styled(
            format!("{:<24} {:<11} {}", "name", "kind", "url"),
            Style::default().fg(theme.muted),
        ),
    ]));

    // Separator
    lines.push(Line::from(Span::styled(
        format!("  {}", "─".repeat(50)),
        Style::default().fg(theme.border),
    )));

    // Rows
    for (i, view) in state.views.iter().enumerate() {
        let is_selected = i == state.selected;

        let row_text = format!(
            "{:<24} {:<11} {}",
            truncate_str(&view.name, 24),
            &view.kind,
            &view.url,
        );

        let style = if is_selected {
            Style::default().fg(theme.accent)
        } else {
            Style::default().fg(theme.fg)
        };

        let prefix = if is_selected { "> " } else { "  " };
        lines.push(Line::from(Span::styled(
            format!("{}{}", prefix, row_text),
            style,
        )));
    }

    // Footer actions
    lines.push(Line::from(""));
    lines.push(Line::from(vec![
        Span::raw("  "),
        Span::styled("[restore]", Style::default().fg(theme.accent)),
        Span::raw(" "),
        Span::styled("[delete]", Style::default().fg(theme.danger)),
    ]));

    frame.render_widget(Paragraph::new(lines), inner);
}

fn truncate_str(s: &str, max: usize) -> String {
    if s.len() <= max {
        s.to_string()
    } else {
        format!("{}...", &s[..max.saturating_sub(3)])
    }
}
