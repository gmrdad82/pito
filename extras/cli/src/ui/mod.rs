pub mod channel_detail;
pub mod channels;
pub mod confirmation;
pub mod dashboard;
pub mod footage_detail;
pub mod help;
pub mod operation_progress;
pub mod saved_views;
pub mod search;
pub mod settings;
pub mod video_detail;
pub mod videos;

use ratatui::{
    Frame,
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::Style,
    text::{Line, Span},
    widgets::Paragraph,
};

use crate::app::{App, KeyState, Overlay, Screen};

pub fn render(frame: &mut Frame, app: &mut App) {
    let theme = app.theme();

    // Set background
    frame.render_widget(
        ratatui::widgets::Block::default().style(Style::default().bg(theme.bg)),
        frame.area(),
    );

    let layout = Layout::vertical([
        Constraint::Length(1), // header
        Constraint::Min(0),    // body
        Constraint::Length(1), // footer
    ])
    .split(frame.area());

    render_header(frame, layout[0], app);
    render_body(frame, layout[1], app);
    render_footer(frame, layout[2], app);

    // Overlay on top
    match app.overlay {
        Some(Overlay::Help) => help::render(frame, frame.area(), &theme),
        Some(Overlay::Search) => search::render(frame, frame.area(), &theme, &app.search_state),
        Some(Overlay::Confirmation) => {
            if let Some(ref state) = app.confirmation_state {
                confirmation::render(frame, frame.area(), &theme, state);
            }
        }
        None => {}
    }

    // Bulk-operation progress overlay renders on top of everything else (it's
    // launched *after* a confirmation closes, so it normally stands alone, but
    // layering it last guarantees it stays visible if any other overlay races
    // in).
    if let Some(ref progress) = app.operation_progress {
        operation_progress::render(
            frame,
            frame.area(),
            &theme,
            progress,
            &app.channels_state.channels,
        );
    }
}

fn render_header(frame: &mut Frame, area: Rect, app: &mut App) {
    let theme = app.theme();
    let screen_label = match app.screen {
        Screen::Dashboard => "[dashboard]",
        Screen::Channels => "[channels]",
        Screen::ChannelDetail => "[channel]",
        Screen::Videos => "[videos]",
        Screen::VideoDetail => "[video]",
        Screen::SavedViews => "[saved views]",
        Screen::Settings => "[settings]",
        Screen::FootageDetail => "[footage]",
    };

    // Brand + current screen, anchored to the left edge.
    let left = Line::from(vec![
        Span::styled(" pito ", Style::default().fg(theme.accent)),
        Span::styled("| ", Style::default().fg(theme.border)),
        Span::styled(screen_label, Style::default().fg(theme.fg)),
    ]);

    // Theme + help affordances, anchored to the right edge of the bar (web-app
    // top-right convention).
    let right_spans = vec![
        Span::styled("(n)", Style::default().fg(theme.muted)),
        Span::raw(" theme  "),
        Span::styled("(?)", Style::default().fg(theme.muted)),
        Span::raw(" help "),
    ];
    let right_width: usize = right_spans.iter().map(|s| s.content.chars().count()).sum();
    let right_width = right_width.min(area.width as usize) as u16;

    // Split the bar so left can grow and right always reserves exactly the
    // width its spans need.
    let chunks = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Min(0), Constraint::Length(right_width)])
        .split(area);

    let bg = Style::default().bg(theme.bg).fg(theme.fg);
    frame.render_widget(Paragraph::new(left).style(bg), chunks[0]);
    frame.render_widget(
        Paragraph::new(Line::from(right_spans))
            .alignment(Alignment::Right)
            .style(bg),
        chunks[1],
    );
}

fn render_body(frame: &mut Frame, area: Rect, app: &mut App) {
    let theme = app.theme();
    match app.screen {
        Screen::Dashboard => dashboard::render(frame, area, &theme, &app.dashboard_state),
        Screen::Channels => {
            let sync_anim = channels::SyncAnim {
                ids: app.syncing_animated_ids(),
                tick: app.sync_anim_tick(),
            };
            channels::render(frame, area, &theme, &app.channels_state, sync_anim);
        }
        Screen::ChannelDetail => {
            if let Some(ref state) = app.channel_detail_state {
                channel_detail::render(frame, area, &theme, state);
            }
        }
        Screen::Videos => videos::render(frame, area, &theme, &app.videos_state),
        Screen::VideoDetail => {
            if let Some(ref state) = app.video_detail_state {
                video_detail::render(frame, area, &theme, state);
            }
        }
        Screen::SavedViews => saved_views::render(frame, area, &theme, &app.saved_views_state),
        Screen::Settings => settings::render(frame, area, &theme, &app.settings_state),
        Screen::FootageDetail => {
            if let Some(ref state) = app.footage_detail_state {
                let capability = app.terminal_capability;
                // Borrow the live image protocol mutably for the duration of
                // the render. The protocol's internal cache mutates as
                // ratatui-image encodes for the current rect.
                let preview = app.footage_detail_preview.as_mut();
                let rects = footage_detail::render(frame, area, &theme, state, capability, preview);
                app.footage_detail_rects = Some(rects);
            }
        }
    }
}

fn render_footer(frame: &mut Frame, area: Rect, app: &mut App) {
    let theme = app.theme();

    let state_hint = match app.key_state {
        KeyState::Normal => "",
        KeyState::GPrefix => "g...",
        KeyState::ColonPrefix => ":",
        KeyState::FilterPrefix => "f...",
    };

    let line = Line::from(vec![
        Span::styled(" q", Style::default().fg(theme.muted)),
        Span::styled(" back  ", Style::default().fg(theme.fg)),
        Span::styled(":q", Style::default().fg(theme.muted)),
        Span::styled(" quit  ", Style::default().fg(theme.fg)),
        Span::styled("g+key", Style::default().fg(theme.muted)),
        Span::styled(" navigate  ", Style::default().fg(theme.fg)),
        Span::styled("?", Style::default().fg(theme.muted)),
        Span::styled(" help", Style::default().fg(theme.fg)),
        Span::raw("  "),
        Span::styled(state_hint, Style::default().fg(theme.accent)),
    ]);

    let footer = Paragraph::new(line).style(Style::default().bg(theme.bg).fg(theme.fg));
    frame.render_widget(footer, area);
}
