use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};

use crate::app::{App, KeyState, Overlay, Screen};
use crate::ui::channels::ChannelFilter;
use crate::ui::confirmation::{self, ConfirmationOutcome};

pub fn handle_key(app: &mut App, key: KeyEvent) {
    // Ctrl+C always quits
    if key.modifiers.contains(KeyModifiers::CONTROL) && key.code == KeyCode::Char('c') {
        app.quit();
        return;
    }

    // Bulk-operation progress overlay: only Esc dismisses (server work
    // continues). Take precedence over other overlays since this overlay is
    // typically launched right after a confirmation closes.
    if app.operation_progress.is_some() {
        if let KeyCode::Esc = key.code {
            app.dismiss_operation_progress();
        }
        return;
    }

    // Help overlay
    if app.overlay == Some(Overlay::Help) {
        match key.code {
            KeyCode::Esc | KeyCode::Char('q') | KeyCode::Char('?') => {
                app.overlay = None;
            }
            _ => {}
        }
        return;
    }

    // Confirmation overlay
    if app.overlay == Some(Overlay::Confirmation) {
        handle_confirmation_input(app, key);
        return;
    }

    // Search overlay
    if app.overlay == Some(Overlay::Search) {
        handle_search_input(app, key);
        return;
    }

    match app.key_state {
        KeyState::Normal => handle_normal(app, key),
        KeyState::GPrefix => handle_g_prefix(app, key),
        KeyState::ColonPrefix => handle_colon_prefix(app, key),
        KeyState::FilterPrefix => handle_filter_prefix(app, key),
    }
}

fn handle_confirmation_input(app: &mut App, key: KeyEvent) {
    let Some(ref state) = app.confirmation_state else {
        app.overlay = None;
        return;
    };
    let outcome = match key.code {
        KeyCode::Esc => Some(ConfirmationOutcome::Cancel),
        KeyCode::Char(c) => confirmation::key_outcome(c, state),
        _ => Some(ConfirmationOutcome::Cancel),
    };
    if let Some(outcome) = outcome {
        app.resolve_confirmation(outcome);
    }
}

fn handle_search_input(app: &mut App, key: KeyEvent) {
    match key.code {
        KeyCode::Esc => {
            app.overlay = None;
        }
        KeyCode::Enter => {
            app.perform_search();
        }
        KeyCode::Backspace
            if app.search_state.cursor_pos > 0 => {
                app.search_state.cursor_pos -= 1;
                app.search_state.query.remove(app.search_state.cursor_pos);
                app.perform_search();
            }
        KeyCode::Down => {
            app.search_state.selected_row += 1;
        }
        KeyCode::Up
            if app.search_state.selected_row > 0 => {
                app.search_state.selected_row -= 1;
            }
        KeyCode::Char(c) => {
            app.search_state.query.insert(app.search_state.cursor_pos, c);
            app.search_state.cursor_pos += 1;
            app.perform_search();
        }
        _ => {}
    }
}

fn handle_normal(app: &mut App, key: KeyEvent) {
    // Dashboard-specific range keys
    if app.screen == Screen::Dashboard {
        match key.code {
            KeyCode::Char('1') => {
                set_dashboard_range(app, 0);
                return;
            }
            KeyCode::Char('2') => {
                set_dashboard_range(app, 1);
                return;
            }
            KeyCode::Char('3') => {
                set_dashboard_range(app, 2);
                return;
            }
            KeyCode::Char('4') => {
                set_dashboard_range(app, 3);
                return;
            }
            KeyCode::Char('5') => {
                set_dashboard_range(app, 4);
                return;
            }
            KeyCode::Char('h') | KeyCode::Left => {
                if app.dashboard_state.range_index > 0 {
                    set_dashboard_range(app, app.dashboard_state.range_index - 1);
                }
                return;
            }
            KeyCode::Char('l') | KeyCode::Right => {
                if app.dashboard_state.range_index < crate::app::RANGES.len() - 1 {
                    set_dashboard_range(app, app.dashboard_state.range_index + 1);
                }
                return;
            }
            _ => {}
        }
    }

    // Channels-screen specific keys (must run before generic q/etc.)
    if app.screen == Screen::Channels {
        match key.code {
            KeyCode::Char('s') => {
                app.toggle_star_for_selected_channel();
                return;
            }
            // `c` is intentionally NOT bound on this screen: connected reflects
            // the OAuth flow and only the web UI may toggle it. The `connected`
            // column and the `f c` filter chip remain read-only views.
            KeyCode::Char('D') => {
                let ids = app.channels_target_ids();
                app.open_delete_confirmation(ids);
                return;
            }
            KeyCode::Char('Y') => {
                let ids = app.channels_target_ids();
                app.open_sync_confirmation(ids);
                return;
            }
            KeyCode::Char('f') => {
                app.key_state = KeyState::FilterPrefix;
                return;
            }
            _ => {}
        }
    }

    // ChannelDetail screen specific keys
    if app.screen == Screen::ChannelDetail {
        match key.code {
            KeyCode::Char('v') => {
                if let Some(ref state) = app.channel_detail_state {
                    let _ = crate::ui::channel_detail::open_in_browser(&state.channel.channel_url);
                }
                return;
            }
            KeyCode::Char('s') => {
                app.toggle_star_on_detail();
                return;
            }
            // `c` intentionally unbound on the detail screen too — connected
            // is OAuth-managed and read-only here.
            KeyCode::Char('D') => {
                if let Some(ref state) = app.channel_detail_state {
                    let id = state.channel.id;
                    app.open_delete_confirmation(vec![id]);
                }
                return;
            }
            KeyCode::Char('Y') => {
                if let Some(ref state) = app.channel_detail_state {
                    let id = state.channel.id;
                    app.open_sync_confirmation(vec![id]);
                }
                return;
            }
            KeyCode::Char('e') => {
                if let Some(ref mut state) = app.channel_detail_state {
                    state.flash = Some("URL is locked".to_string());
                }
                return;
            }
            _ => {}
        }
    }

    match key.code {
        KeyCode::Char('q') => match app.screen {
            Screen::Dashboard => app.quit(),
            Screen::ChannelDetail => app.screen = Screen::Channels,
            Screen::VideoDetail => app.screen = Screen::Videos,
            _ => app.screen = Screen::Dashboard,
        },
        KeyCode::Char(':') => {
            app.key_state = KeyState::ColonPrefix;
        }
        KeyCode::Char('g') => {
            app.key_state = KeyState::GPrefix;
        }
        KeyCode::Char('?') => {
            app.overlay = Some(Overlay::Help);
        }
        KeyCode::Char('n') => {
            app.toggle_theme();
        }
        KeyCode::Char('/') => {
            app.overlay = Some(Overlay::Search);
        }
        KeyCode::Char('j') | KeyCode::Down => {
            handle_move_down(app);
        }
        KeyCode::Char('k') | KeyCode::Up => {
            handle_move_up(app);
        }
        KeyCode::Enter => {
            handle_enter(app);
        }
        KeyCode::Char(' ') => {
            handle_space(app);
        }
        KeyCode::Char('b') => {
            handle_bulk_toggle(app);
        }
        KeyCode::Esc => {
            handle_esc(app);
        }
        _ => {}
    }
}

fn handle_g_prefix(app: &mut App, key: KeyEvent) {
    app.key_state = KeyState::Normal;
    match key.code {
        KeyCode::Char('d') => app.screen = Screen::Dashboard,
        KeyCode::Char('c') => app.screen = Screen::Channels,
        KeyCode::Char('v') => app.screen = Screen::Videos,
        KeyCode::Char('s') => app.screen = Screen::SavedViews,
        KeyCode::Char('e') => app.screen = Screen::Settings,
        _ => {}
    }
}

fn handle_colon_prefix(app: &mut App, key: KeyEvent) {
    app.key_state = KeyState::Normal;
    if let KeyCode::Char('q') = key.code { app.quit() }
}

fn handle_filter_prefix(app: &mut App, key: KeyEvent) {
    app.key_state = KeyState::Normal;
    if app.screen != Screen::Channels {
        return;
    }
    let next = match key.code {
        KeyCode::Char('s') => Some(ChannelFilter::Starred),
        KeyCode::Char('c') => Some(ChannelFilter::Connected),
        KeyCode::Char('y') => Some(ChannelFilter::Syncing),
        _ => None,
    };
    if let Some(target) = next {
        // Toggle: if same filter is active, clear it.
        if app.channels_state.filter == target {
            app.channels_state.filter = ChannelFilter::None;
        } else {
            app.channels_state.filter = target;
        }
        app.channels_state.selected = 0;
        app.channels_state.scroll_offset = 0;
    }
}

fn handle_move_down(app: &mut App) {
    match app.screen {
        Screen::Channels => {
            let len = crate::ui::channels::visible_channels(&app.channels_state).len();
            if app.channels_state.selected < len.saturating_sub(1) {
                app.channels_state.selected += 1;
            }
        }
        Screen::Videos => {
            let len = app.videos_state.videos.len();
            if app.videos_state.selected < len.saturating_sub(1) {
                app.videos_state.selected += 1;
            }
        }
        Screen::ChannelDetail => {
            if let Some(ref mut state) = app.channel_detail_state {
                let len = state.videos.len();
                if state.video_selected < len.saturating_sub(1) {
                    state.video_selected += 1;
                }
            }
        }
        Screen::VideoDetail => {
            if let Some(ref mut state) = app.video_detail_state {
                let len = state.stats.len();
                if state.stats_selected < len.saturating_sub(1) {
                    state.stats_selected += 1;
                }
            }
        }
        Screen::SavedViews => {
            let len = app.saved_views_state.views.len();
            if app.saved_views_state.selected < len.saturating_sub(1) {
                app.saved_views_state.selected += 1;
            }
        }
        _ => {}
    }
}

fn handle_move_up(app: &mut App) {
    match app.screen {
        Screen::Channels
            if app.channels_state.selected > 0 => {
                app.channels_state.selected -= 1;
            }
        Screen::Videos
            if app.videos_state.selected > 0 => {
                app.videos_state.selected -= 1;
            }
        Screen::ChannelDetail => {
            if let Some(ref mut state) = app.channel_detail_state
                && state.video_selected > 0 {
                    state.video_selected -= 1;
                }
        }
        Screen::VideoDetail => {
            if let Some(ref mut state) = app.video_detail_state
                && state.stats_selected > 0 {
                    state.stats_selected -= 1;
                }
        }
        Screen::SavedViews
            if app.saved_views_state.selected > 0 => {
                app.saved_views_state.selected -= 1;
            }
        _ => {}
    }
}

fn handle_enter(app: &mut App) {
    match app.screen {
        Screen::Channels => {
            let visible = crate::ui::channels::visible_channels(&app.channels_state);
            if let Some(channel) = visible.get(app.channels_state.selected) {
                let id = channel.id;
                app.open_channel_detail(id);
            }
        }
        Screen::Videos => {
            if let Some(video) = app.videos_state.videos.get(app.videos_state.selected) {
                let id = video.id;
                app.open_video_detail(id);
            }
        }
        _ => {}
    }
}

fn handle_space(app: &mut App) {
    match app.screen {
        Screen::Channels => {
            // Space only toggles bulk selection while bulk mode is on — the
            // `[ ]` checkbox column isn't rendered otherwise, so silently
            // ignore the keypress to avoid invisible state changes. Press
            // `b` to enter bulk mode.
            if !app.channels_state.bulk_mode {
                return;
            }
            let visible = crate::ui::channels::visible_channels(&app.channels_state);
            if let Some(channel) = visible.get(app.channels_state.selected) {
                let id = channel.id;
                if app.channels_state.selected_ids.contains(&id) {
                    app.channels_state.selected_ids.retain(|&x| x != id);
                } else {
                    app.channels_state.selected_ids.push(id);
                }
            }
        }
        Screen::Videos => {
            if app.videos_state.bulk_mode
                && let Some(video) = app.videos_state.videos.get(app.videos_state.selected) {
                    let id = video.id;
                    if app.videos_state.selected_ids.contains(&id) {
                        app.videos_state.selected_ids.retain(|&x| x != id);
                    } else {
                        app.videos_state.selected_ids.push(id);
                    }
                }
        }
        _ => {}
    }
}

fn handle_bulk_toggle(app: &mut App) {
    match app.screen {
        Screen::Channels => {
            app.channels_state.bulk_mode = !app.channels_state.bulk_mode;
            if !app.channels_state.bulk_mode {
                app.channels_state.selected_ids.clear();
            }
        }
        Screen::Videos => {
            app.videos_state.bulk_mode = !app.videos_state.bulk_mode;
            if !app.videos_state.bulk_mode {
                app.videos_state.selected_ids.clear();
            }
        }
        _ => {}
    }
}

fn handle_esc(app: &mut App) {
    app.clear_flash();
    match app.screen {
        Screen::Channels => {
            if app.channels_state.bulk_mode || !app.channels_state.selected_ids.is_empty() {
                app.channels_state.bulk_mode = false;
                app.channels_state.selected_ids.clear();
            } else if app.channels_state.filter != ChannelFilter::None {
                app.channels_state.filter = ChannelFilter::None;
            }
        }
        Screen::Videos => {
            if app.videos_state.bulk_mode {
                app.videos_state.bulk_mode = false;
                app.videos_state.selected_ids.clear();
            }
        }
        _ => {
            app.overlay = None;
        }
    }
}

fn set_dashboard_range(app: &mut App, index: usize) {
    if index < crate::app::RANGES.len() {
        app.dashboard_state.range_index = index;
        app.dashboard_state.range = crate::app::RANGES[index].to_string();
        app.reload_dashboard();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};

    fn space_event() -> KeyEvent {
        KeyEvent::new(KeyCode::Char(' '), KeyModifiers::NONE)
    }

    #[test]
    fn space_does_nothing_when_bulk_mode_off_on_channels() {
        // Bulk mode off → space must be a silent no-op so the user doesn't
        // accumulate invisible selection state (the `[ ]` column isn't even
        // drawn in this mode).
        let mut app = App::with_client(Box::new(crate::api::client::MockClient::new()));
        app.screen = Screen::Channels;
        app.channels_state.bulk_mode = false;
        app.channels_state.selected_ids.clear();
        // Sanity-check that there's at least one row to (not) toggle.
        assert!(
            !app.channels_state.channels.is_empty(),
            "MockClient seed must include at least one channel for this test"
        );
        app.channels_state.selected = 0;

        handle_key(&mut app, space_event());

        assert!(
            app.channels_state.selected_ids.is_empty(),
            "space must not toggle selection while bulk mode is off"
        );
        assert!(
            !app.channels_state.bulk_mode,
            "space must not flip bulk_mode on as a side effect"
        );
    }

    #[test]
    fn space_toggles_selection_when_bulk_mode_on_for_channels() {
        // Bulk mode on → space toggles the highlighted row's id in and out
        // of `selected_ids` (the existing behaviour).
        let mut app = App::with_client(Box::new(crate::api::client::MockClient::new()));
        app.screen = Screen::Channels;
        app.channels_state.bulk_mode = true;
        app.channels_state.selected_ids.clear();
        app.channels_state.selected = 0;

        let visible = crate::ui::channels::visible_channels(&app.channels_state);
        let target_id = visible
            .first()
            .expect("at least one visible channel for this test")
            .id;

        handle_key(&mut app, space_event());
        assert_eq!(
            app.channels_state.selected_ids,
            vec![target_id],
            "space must add the highlighted id when bulk_mode is on"
        );

        // A second space on the same row clears the selection — i.e., it's
        // a real toggle, not just an additive op.
        handle_key(&mut app, space_event());
        assert!(
            app.channels_state.selected_ids.is_empty(),
            "second space on the same row must remove the id"
        );
    }
}
