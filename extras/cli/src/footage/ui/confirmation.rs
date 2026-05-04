//! Three-section confirmation overlay for `pito footage import`.
//!
//! Mirrors the shape of `crate::ui::confirmation` (ratatui modal centered over
//! the body) but the body lists three sections — Additions, Changes,
//! Deletions — each with a count and per-row label. Footer reads
//! `[y] confirm   [any other key] cancel`.
//!
//! Pure render + key-handler. The importer drives a small ratatui terminal
//! around it so the same key-input rule (`y` confirms, anything else cancels)
//! holds whether or not we're inside the persistent TUI.

use ratatui::{
    Frame,
    layout::{Constraint, Flex, Layout, Rect},
    style::{Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Clear, Paragraph},
};

use crate::footage::diff::DiffEntry;
use crate::theme::Theme;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConfirmationOutcome {
    Proceed,
    Cancel,
}

/// Sectioned-by-kind view of the diff, ready to render. The importer builds
/// this once after `classify` and hands it to `render`.
#[derive(Debug, Clone)]
pub struct DiffSummary {
    pub adds: Vec<String>,
    pub changes: Vec<String>,
    pub deletes: Vec<String>,
}

impl DiffSummary {
    pub fn from_entries(entries: &[DiffEntry]) -> Self {
        let mut adds = Vec::new();
        let mut changes = Vec::new();
        let mut deletes = Vec::new();
        for e in entries {
            match e {
                DiffEntry::Add(p) => adds.push(p.local_path.clone()),
                DiffEntry::Change(c) => changes.push(c.probed.local_path.clone()),
                DiffEntry::Delete(r) => deletes.push(r.local_path.clone()),
            }
        }
        Self {
            adds,
            changes,
            deletes,
        }
    }

    pub fn total(&self) -> usize {
        self.adds.len() + self.changes.len() + self.deletes.len()
    }

    pub fn has_work(&self) -> bool {
        self.total() > 0
    }
}

/// Map a key character to an outcome. Mirrors the rule used by the channels
/// confirmation: `y` / `Y` confirm; anything else cancels.
pub fn key_outcome(ch: char, summary: &DiffSummary) -> ConfirmationOutcome {
    if !summary.has_work() {
        return ConfirmationOutcome::Cancel;
    }
    match ch {
        'y' | 'Y' => ConfirmationOutcome::Proceed,
        _ => ConfirmationOutcome::Cancel,
    }
}

pub fn render(frame: &mut Frame, area: Rect, theme: &Theme, summary: &DiffSummary) {
    let popup = centered_rect(70, 70, area);
    frame.render_widget(Clear, popup);

    let title = format!(" Footage import — {} change(s) ", summary.total());

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
        Constraint::Min(0),    // body
        Constraint::Length(1), // footer
    ])
    .split(inner);

    render_body(frame, layout[0], theme, summary);
    render_footer(frame, layout[1], theme, summary);
}

fn render_body(frame: &mut Frame, area: Rect, theme: &Theme, summary: &DiffSummary) {
    let visible = area.height as usize;
    let label_budget = area.width.saturating_sub(8) as usize;

    let mut lines: Vec<Line> = Vec::new();
    push_section(
        &mut lines,
        "Additions",
        "[add]",
        theme.success,
        &summary.adds,
        theme,
        label_budget,
    );
    push_section(
        &mut lines,
        "Changes",
        "[chg]",
        theme.accent,
        &summary.changes,
        theme,
        label_budget,
    );
    push_section(
        &mut lines,
        "Deletions",
        "[del]",
        theme.danger,
        &summary.deletes,
        theme,
        label_budget,
    );

    if lines.is_empty() {
        lines.push(Line::from(Span::styled(
            "  Nothing to do — local files match the existing rows.",
            Style::default().fg(theme.muted),
        )));
    }

    if lines.len() > visible {
        lines.truncate(visible.saturating_sub(1));
        let extra = summary.total() - lines.len();
        lines.push(Line::from(Span::styled(
            format!("  ... and {} more", extra),
            Style::default().fg(theme.muted),
        )));
    }

    frame.render_widget(Paragraph::new(lines), area);
}

fn push_section(
    lines: &mut Vec<Line>,
    title: &str,
    bullet: &str,
    bullet_color: ratatui::style::Color,
    paths: &[String],
    theme: &Theme,
    label_budget: usize,
) {
    if paths.is_empty() {
        return;
    }
    if !lines.is_empty() {
        // Blank separator between sections.
        lines.push(Line::from(""));
    }
    lines.push(Line::from(Span::styled(
        format!("  {} ({})", title, paths.len()),
        Style::default().fg(theme.fg).add_modifier(Modifier::BOLD),
    )));
    for path in paths.iter() {
        let label = truncate(path, label_budget);
        lines.push(Line::from(vec![
            Span::raw("    "),
            Span::styled(format!("{} ", bullet), Style::default().fg(bullet_color)),
            Span::styled(label, Style::default().fg(theme.fg)),
        ]));
    }
}

fn render_footer(frame: &mut Frame, area: Rect, theme: &Theme, summary: &DiffSummary) {
    let line = if summary.has_work() {
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
    use crate::footage::api::models::{FootageRecord, ProbedFile};
    use crate::footage::probe::ffprobe::ProbeReport;

    fn probed(path: &str) -> ProbedFile {
        ProbedFile {
            local_path: path.to_string(),
            filename: std::path::Path::new(path)
                .file_name()
                .map(|s| s.to_string_lossy().into_owned())
                .unwrap_or_default(),
            report: ProbeReport {
                duration_seconds: Some(60),
                resolution: Some("1920x1080".to_string()),
                fps: Some(60.0),
                codec: Some("h264".to_string()),
                bit_depth: 8,
                color_profile: None,
                aspect_ratio: Some("16:9".to_string()),
                orientation: None,
                audio_track_count: 1,
                has_commentary_track: false,
                recorded_at: None,
            },
        }
    }

    fn record(id: u64, path: &str) -> FootageRecord {
        FootageRecord {
            id,
            local_path: path.to_string(),
            filename: std::path::Path::new(path)
                .file_name()
                .map(|s| s.to_string_lossy().into_owned())
                .unwrap_or_default(),
            duration_seconds: Some(60),
            resolution: Some("1920x1080".to_string()),
            fps: Some(60.0),
            codec: Some("h264".to_string()),
            bit_depth: 8,
            color_profile: None,
            aspect_ratio: Some("16:9".to_string()),
            orientation: None,
            audio_track_count: 1,
            has_commentary_track: false,
        }
    }

    #[test]
    fn summary_counts_each_section() {
        let entries = vec![
            DiffEntry::Add(probed("/a.mp4")),
            DiffEntry::Add(probed("/b.mp4")),
            DiffEntry::change(record(1, "/c.mp4"), probed("/c.mp4")),
            DiffEntry::Delete(record(2, "/d.mp4")),
        ];
        let s = DiffSummary::from_entries(&entries);
        assert_eq!(s.adds.len(), 2);
        assert_eq!(s.changes.len(), 1);
        assert_eq!(s.deletes.len(), 1);
        assert_eq!(s.total(), 4);
        assert!(s.has_work());
    }

    #[test]
    fn empty_summary_reports_no_work() {
        let s = DiffSummary::from_entries(&[]);
        assert_eq!(s.total(), 0);
        assert!(!s.has_work());
    }

    #[test]
    fn key_y_proceeds_when_work_present() {
        let s = DiffSummary {
            adds: vec!["/a.mp4".to_string()],
            changes: vec![],
            deletes: vec![],
        };
        assert_eq!(key_outcome('y', &s), ConfirmationOutcome::Proceed);
        assert_eq!(key_outcome('Y', &s), ConfirmationOutcome::Proceed);
    }

    #[test]
    fn any_non_y_key_cancels() {
        let s = DiffSummary {
            adds: vec!["/a.mp4".to_string()],
            changes: vec![],
            deletes: vec![],
        };
        assert_eq!(key_outcome('n', &s), ConfirmationOutcome::Cancel);
        assert_eq!(key_outcome(' ', &s), ConfirmationOutcome::Cancel);
        assert_eq!(key_outcome('q', &s), ConfirmationOutcome::Cancel);
    }

    #[test]
    fn empty_summary_cancels_on_any_key() {
        let s = DiffSummary {
            adds: vec![],
            changes: vec![],
            deletes: vec![],
        };
        assert_eq!(key_outcome('y', &s), ConfirmationOutcome::Cancel);
        assert_eq!(key_outcome('n', &s), ConfirmationOutcome::Cancel);
    }
}
