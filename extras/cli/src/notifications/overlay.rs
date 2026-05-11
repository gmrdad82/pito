//! In-TUI overlay for the `login_pending_approval` notification.
//!
//! The overlay renders the parsed `LoginPendingCard` and routes the
//! user through the locked Q-F flow:
//!
//! 1. Card view — single key shortcuts: `a` approve, `b` block, `Esc`
//!    dismiss. None of these fire the underlying action yet — they
//!    transition the overlay into a confirmation stage instead, per
//!    the project-wide two-step pattern for destructive / significant
//!    actions (CLAUDE.md hard rule, LD-16).
//! 2. Confirmation view — shows the chosen verb and asks for `y` to
//!    proceed; any other key (including `n`, `Esc`) cancels back to
//!    the card view.
//!
//! Approve / block flow off the wire is implemented by
//! [`crate::api::endpoints::login_attempts`]. The overlay surfaces a
//! status line beneath the buttons that flips to `approving...` /
//! `blocking...` while the call is in flight (driven by the caller
//! transitioning [`Stage`] before issuing the blocking POST), then to
//! `approved` / `blocked` or `error: ...` once it returns.
//!
//! Status-line "pending approval" prompt on non-notification surfaces
//! lives in [`crate::ui::mod`]'s footer renderer — when the overlay
//! has at least one pending card cached, the footer shows
//! `pending approval — [a]pprove [b]lock [l]ater`. That prompt
//! mirrors the in-overlay actions; the overlay itself is the canonical
//! UX.

use ratatui::{
    Frame,
    layout::{Constraint, Flex, Layout, Rect},
    style::{Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Clear, Paragraph},
};

use crate::notifications::login_pending::LoginPendingCard;
use crate::theme::Theme;

/// Which action the overlay is currently asking the user about. Card
/// is the default view; the two `ConfirmApprove` / `ConfirmBlock`
/// stages are reached after the operator presses `a` / `b`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Stage {
    /// Card view — `a` / `b` / `Esc` are live.
    Card,
    /// Approve confirmation — `y` fires, anything else cancels.
    ConfirmApprove,
    /// Block confirmation — `y` fires, anything else cancels.
    ConfirmBlock,
    /// In-flight wire call. Renders the card with a `working...`
    /// status line; key input is ignored. The caller transitions
    /// back to `Card` / `Done` after the POST returns.
    Working,
    /// Terminal "all done" state — the wire call returned successfully
    /// (or failed). The status string carries the message; the user
    /// dismisses with any key.
    Done,
}

/// One outcome of the overlay's key-input router.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InputOutcome {
    /// Stay open, keep rendering. Nothing else to do.
    Stay,
    /// Close the overlay. Caller resets app state.
    Close,
    /// User confirmed approve. Caller should fire the approve POST
    /// and update the overlay's `Stage` based on the result.
    FireApprove,
    /// User confirmed block. Same shape as `FireApprove`.
    FireBlock,
}

/// Open-state for the pending-approval overlay. Holds the parsed card
/// (one pending attempt — we surface the most recent if there are
/// multiple in flight) and the current stage.
#[derive(Debug, Clone)]
pub struct LoginPendingOverlayState {
    pub card: LoginPendingCard,
    pub stage: Stage,
    /// Status line shown on the card view. Empty until the operator
    /// triggers approve / block; flips to `approving...` / `blocking...`
    /// during the POST, then to a success / error message in `Done`.
    pub status: String,
}

impl LoginPendingOverlayState {
    pub fn new(card: LoginPendingCard) -> Self {
        Self {
            card,
            stage: Stage::Card,
            status: String::new(),
        }
    }

    /// Mark the overlay as in-flight. Drops keypress routing through
    /// to `Stay` (no `Esc` cancellation mid-POST — the wire call's
    /// outcome wins).
    pub fn mark_working(&mut self, verb: &str) {
        self.stage = Stage::Working;
        self.status = format!("{verb}...");
    }

    /// Mark the overlay as terminal. Caller sets `success_message` on
    /// success / `error: ...` on failure; the next keypress closes it.
    pub fn mark_done(&mut self, message: impl Into<String>) {
        self.stage = Stage::Done;
        self.status = message.into();
    }
}

/// Route a key character against the overlay's current stage. The
/// caller is responsible for invoking the wire call when the outcome
/// is `FireApprove` / `FireBlock` and for closing the overlay on
/// `Close`.
pub fn key_outcome(ch: char, state: &LoginPendingOverlayState) -> InputOutcome {
    match state.stage {
        Stage::Card => match ch {
            'a' | 'A' if state.card.is_actionable() => InputOutcome::Stay,
            'b' | 'B' if state.card.is_actionable() => InputOutcome::Stay,
            // `l` (later) and Esc both dismiss the overlay without
            // touching the wire — matches the spec's "[l]ater" hint on
            // the non-notification status-line prompt.
            'l' | 'L' => InputOutcome::Close,
            _ => InputOutcome::Stay,
        },
        Stage::ConfirmApprove => match ch {
            'y' | 'Y' => InputOutcome::FireApprove,
            _ => InputOutcome::Stay,
        },
        Stage::ConfirmBlock => match ch {
            'y' | 'Y' => InputOutcome::FireBlock,
            _ => InputOutcome::Stay,
        },
        Stage::Working => InputOutcome::Stay,
        Stage::Done => InputOutcome::Close,
    }
}

/// Transition the overlay from the card view into the appropriate
/// confirmation stage. No-op (returns `false`) when the card isn't
/// actionable or the overlay is already past the card stage. Returns
/// `true` when the transition happened.
pub fn enter_approve_confirm(state: &mut LoginPendingOverlayState) -> bool {
    if state.stage != Stage::Card || !state.card.is_actionable() {
        return false;
    }
    state.stage = Stage::ConfirmApprove;
    true
}

/// Mirror of [`enter_approve_confirm`] for the block path.
pub fn enter_block_confirm(state: &mut LoginPendingOverlayState) -> bool {
    if state.stage != Stage::Card || !state.card.is_actionable() {
        return false;
    }
    state.stage = Stage::ConfirmBlock;
    true
}

/// Cancel a pending confirmation stage and drop back to the card
/// view. No-op when the overlay isn't currently in a confirmation
/// stage.
pub fn cancel_confirm(state: &mut LoginPendingOverlayState) -> bool {
    match state.stage {
        Stage::ConfirmApprove | Stage::ConfirmBlock => {
            state.stage = Stage::Card;
            true
        }
        _ => false,
    }
}

/// Render the overlay. Centered within `area`, ~60 columns wide, sized
/// to fit the card body plus a footer hint.
pub fn render(frame: &mut Frame, area: Rect, theme: &Theme, state: &LoginPendingOverlayState) {
    let popup = centered_rect(70, 70, area);
    frame.render_widget(Clear, popup);

    let title = match state.stage {
        Stage::Card => " new-location login — pending approval ".to_string(),
        Stage::ConfirmApprove => " approve? ".to_string(),
        Stage::ConfirmBlock => " block? ".to_string(),
        Stage::Working => " working... ".to_string(),
        Stage::Done => " done ".to_string(),
    };

    let border_color = match state.stage {
        Stage::ConfirmBlock => theme.danger,
        _ => theme.accent,
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
        Constraint::Min(0),    // body
        Constraint::Length(1), // status
        Constraint::Length(1), // footer / keys
    ])
    .split(inner);

    render_body(frame, layout[0], theme, state);
    render_status(frame, layout[1], theme, state);
    render_footer(frame, layout[2], theme, state);
}

fn render_body(frame: &mut Frame, area: Rect, theme: &Theme, state: &LoginPendingOverlayState) {
    let card = &state.card;
    let mut lines: Vec<Line> = Vec::new();

    // Title line — full-bleed so the email stays visible even when
    // the popup is narrow.
    lines.push(Line::from(Span::styled(
        format!(" {}", card.title),
        Style::default().fg(theme.fg).add_modifier(Modifier::BOLD),
    )));
    lines.push(Line::from(""));

    push_field(&mut lines, theme, " browser:    ", &card.browser_os);
    push_field(&mut lines, theme, " location:   ", &card.location);
    push_field(&mut lines, theme, " ip:         ", &card.ip);
    push_field(&mut lines, theme, " fingerprint: ", &card.fingerprint);

    if !card.is_actionable() {
        lines.push(Line::from(""));
        lines.push(Line::from(Span::styled(
            " (no actionable attempt id — dismiss with Esc / l)",
            Style::default().fg(theme.danger),
        )));
    } else if let Stage::ConfirmApprove = state.stage {
        lines.push(Line::from(""));
        lines.push(Line::from(Span::styled(
            " approving will trust this device for future logins.",
            Style::default().fg(theme.muted),
        )));
    } else if let Stage::ConfirmBlock = state.stage {
        lines.push(Line::from(""));
        lines.push(Line::from(Span::styled(
            " blocking will revoke the pending session and add a blocked-location row.",
            Style::default().fg(theme.danger),
        )));
    }

    frame.render_widget(Paragraph::new(lines), area);
}

fn push_field<'a>(lines: &mut Vec<Line<'a>>, theme: &Theme, label: &'a str, value: &'a str) {
    lines.push(Line::from(vec![
        Span::styled(label, Style::default().fg(theme.muted)),
        Span::styled(value, Style::default().fg(theme.fg)),
    ]));
}

fn render_status(frame: &mut Frame, area: Rect, theme: &Theme, state: &LoginPendingOverlayState) {
    if state.status.is_empty() {
        return;
    }
    let color = match state.stage {
        Stage::Done if state.status.starts_with("error") => theme.danger,
        Stage::Done => theme.success,
        Stage::Working => theme.cyan,
        _ => theme.muted,
    };
    frame.render_widget(
        Paragraph::new(Line::from(Span::styled(
            format!(" {}", state.status),
            Style::default().fg(color),
        ))),
        area,
    );
}

fn render_footer(frame: &mut Frame, area: Rect, theme: &Theme, state: &LoginPendingOverlayState) {
    let actionable = state.card.is_actionable();
    let line = match state.stage {
        Stage::Card if actionable => Line::from(vec![
            Span::raw(" "),
            Span::styled("[a]", Style::default().fg(theme.accent)),
            Span::styled(" approve   ", Style::default().fg(theme.fg)),
            Span::styled("[b]", Style::default().fg(theme.danger)),
            Span::styled(" block   ", Style::default().fg(theme.fg)),
            Span::styled("[l] / Esc", Style::default().fg(theme.muted)),
            Span::styled(" later", Style::default().fg(theme.fg)),
        ]),
        Stage::Card => Line::from(vec![
            Span::raw(" "),
            Span::styled("[l] / Esc", Style::default().fg(theme.muted)),
            Span::styled(" dismiss", Style::default().fg(theme.fg)),
        ]),
        Stage::ConfirmApprove => Line::from(vec![
            Span::raw(" "),
            Span::styled("[y]", Style::default().fg(theme.accent)),
            Span::styled(" confirm approve   ", Style::default().fg(theme.fg)),
            Span::styled("[any other]", Style::default().fg(theme.muted)),
            Span::styled(" cancel", Style::default().fg(theme.fg)),
        ]),
        Stage::ConfirmBlock => Line::from(vec![
            Span::raw(" "),
            Span::styled("[y]", Style::default().fg(theme.danger)),
            Span::styled(" confirm block   ", Style::default().fg(theme.fg)),
            Span::styled("[any other]", Style::default().fg(theme.muted)),
            Span::styled(" cancel", Style::default().fg(theme.fg)),
        ]),
        Stage::Working => Line::from(Span::styled(
            " working — please wait",
            Style::default().fg(theme.muted),
        )),
        Stage::Done => Line::from(Span::styled(
            " any key to dismiss",
            Style::default().fg(theme.muted),
        )),
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::endpoints::notifications::NotificationSummary;
    use crate::theme::ThemeMode;
    use ratatui::{Terminal, backend::TestBackend};

    fn sample_card() -> LoginPendingCard {
        let summary = NotificationSummary {
            id: 11,
            kind: "login_pending_approval".to_string(),
            severity: "urgent".to_string(),
            event_type: Some("login_pending_approval".to_string()),
            title: Some("new-location login: bob@example.com".to_string()),
            body: Some(
                "someone with the correct password is trying to sign in from a new location.\n\
                 browser: Firefox on Linux.\n\
                 location: Paris, France (FR).\n\
                 ip: 198.51.100.7.\n\
                 fingerprint: deadbeef0102.\n\
                 \n\
                 [yeah, it's me](/login/approvals/42) or [block the intruder](/login/blocks/42)."
                    .to_string(),
            ),
            url: Some("/notifications/11".to_string()),
            fires_at: None,
            in_app_read_at: None,
            read: false,
            discord_delivered_at: None,
            slack_delivered_at: None,
            retry_count: None,
            last_error: None,
            created_at: None,
        };
        LoginPendingCard::from_summary(&summary).expect("parses")
    }

    #[test]
    fn key_a_on_card_stays_then_caller_transitions_to_confirm_approve() {
        let state = LoginPendingOverlayState::new(sample_card());
        // Plain `a` is consumed by the overlay's input router. The caller
        // (`keys.rs`) reads the outcome and calls
        // `enter_approve_confirm` to advance the stage. The router
        // itself returns `Stay` for `a` / `b` so the overlay doesn't
        // close.
        assert_eq!(key_outcome('a', &state), InputOutcome::Stay);
        assert_eq!(key_outcome('A', &state), InputOutcome::Stay);
        assert_eq!(key_outcome('b', &state), InputOutcome::Stay);
        assert_eq!(key_outcome('B', &state), InputOutcome::Stay);
    }

    #[test]
    fn enter_approve_confirm_advances_stage() {
        let mut state = LoginPendingOverlayState::new(sample_card());
        assert!(enter_approve_confirm(&mut state));
        assert_eq!(state.stage, Stage::ConfirmApprove);

        // Pressing `y` on the confirm stage fires approve.
        assert_eq!(key_outcome('y', &state), InputOutcome::FireApprove);
        assert_eq!(key_outcome('Y', &state), InputOutcome::FireApprove);

        // Anything else cancels back via the caller's cancel_confirm.
        assert_eq!(key_outcome('n', &state), InputOutcome::Stay);
        assert_eq!(key_outcome(' ', &state), InputOutcome::Stay);
    }

    #[test]
    fn enter_block_confirm_advances_stage() {
        let mut state = LoginPendingOverlayState::new(sample_card());
        assert!(enter_block_confirm(&mut state));
        assert_eq!(state.stage, Stage::ConfirmBlock);
        assert_eq!(key_outcome('y', &state), InputOutcome::FireBlock);
    }

    #[test]
    fn enter_confirm_no_op_when_card_not_actionable() {
        let mut card = sample_card();
        card.login_attempt_id = None; // simulate malformed body
        let mut state = LoginPendingOverlayState::new(card);
        assert!(!enter_approve_confirm(&mut state));
        assert!(!enter_block_confirm(&mut state));
        assert_eq!(state.stage, Stage::Card);
    }

    #[test]
    fn l_key_on_card_closes() {
        let state = LoginPendingOverlayState::new(sample_card());
        assert_eq!(key_outcome('l', &state), InputOutcome::Close);
        assert_eq!(key_outcome('L', &state), InputOutcome::Close);
    }

    #[test]
    fn cancel_confirm_drops_back_to_card_stage() {
        let mut state = LoginPendingOverlayState::new(sample_card());
        enter_approve_confirm(&mut state);
        assert!(cancel_confirm(&mut state));
        assert_eq!(state.stage, Stage::Card);
        // No-op when already on card.
        assert!(!cancel_confirm(&mut state));
    }

    #[test]
    fn working_stage_ignores_input() {
        let mut state = LoginPendingOverlayState::new(sample_card());
        state.mark_working("approving");
        assert_eq!(state.stage, Stage::Working);
        assert_eq!(state.status, "approving...");
        // Even `y` / `Esc`-emulated input must not close mid-POST.
        assert_eq!(key_outcome('y', &state), InputOutcome::Stay);
        assert_eq!(key_outcome('a', &state), InputOutcome::Stay);
    }

    #[test]
    fn done_stage_closes_on_any_key() {
        let mut state = LoginPendingOverlayState::new(sample_card());
        state.mark_done("approved");
        assert_eq!(state.stage, Stage::Done);
        assert_eq!(key_outcome('y', &state), InputOutcome::Close);
        assert_eq!(key_outcome('x', &state), InputOutcome::Close);
    }

    #[test]
    fn render_does_not_panic_on_card_stage() {
        let theme = Theme::from_mode(ThemeMode::Dark);
        let state = LoginPendingOverlayState::new(sample_card());
        let backend = TestBackend::new(100, 30);
        let mut terminal = Terminal::new(backend).expect("test backend");
        terminal
            .draw(|frame| render(frame, frame.area(), &theme, &state))
            .expect("draw card");
    }

    #[test]
    fn render_does_not_panic_on_confirm_stages() {
        let theme = Theme::from_mode(ThemeMode::Dark);
        let mut state = LoginPendingOverlayState::new(sample_card());
        enter_approve_confirm(&mut state);
        let backend = TestBackend::new(100, 30);
        let mut terminal = Terminal::new(backend).expect("test backend");
        terminal
            .draw(|frame| render(frame, frame.area(), &theme, &state))
            .expect("draw approve");

        let mut state2 = LoginPendingOverlayState::new(sample_card());
        enter_block_confirm(&mut state2);
        terminal
            .draw(|frame| render(frame, frame.area(), &theme, &state2))
            .expect("draw block");
    }
}
