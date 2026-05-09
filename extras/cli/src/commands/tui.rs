use std::io;

use anyhow::Result;
use crossterm::{
    event::{self, DisableMouseCapture, EnableMouseCapture, Event, KeyEventKind, MouseEvent},
    execute,
    terminal::{EnterAlternateScreen, LeaveAlternateScreen, disable_raw_mode, enable_raw_mode},
};
use ratatui::{Terminal, backend::CrosstermBackend};

use crate::api::client::{MockClient, PitoClient};
use crate::api::http_client::HttpClient;
use crate::app::{App, Screen};
use crate::keys;
use crate::ui;
use crate::ui::footage_detail::{self, capability};

pub fn run() -> Result<()> {
    // Load .env (if present) before reading any pito env vars. We
    // intentionally swallow the error: a missing .env is the common
    // "developer hasn't created one yet" case and PITO_API_URL has a sensible
    // default.
    dotenvy::dotenv().ok();

    // Setup terminal. Mouse capture is enabled so the footage detail scrub
    // screen can route hover / drag / scroll events to the active timestamp;
    // it has no effect on screens that don't read mouse events.
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen, EnableMouseCapture)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    // Capability detection MUST run after raw mode + alternate screen are
    // active and before we read any events — that's the contract
    // ratatui-image's Picker::from_query_stdio expects. We also keep the
    // resulting Picker around (when detection succeeded) so the live image
    // path uses the correct font_size / is_tmux flags rather than the
    // halfblocks fallback.
    let (cap, picker) = match ratatui_image::picker::Picker::from_query_stdio() {
        Ok(p) => (
            capability::TerminalCapability::from_protocol(p.protocol_type()),
            Some(p),
        ),
        Err(_) => (capability::TerminalCapability::Halfblocks, None),
    };

    // Choose between the real HTTP client and the offline mock. PITO_USE_MOCK
    // is read as "yes"/"no" to match the rest of the codebase's external
    // boolean convention.
    let use_mock = std::env::var("PITO_USE_MOCK").unwrap_or_default() == "yes";
    let client: Box<dyn PitoClient> = if use_mock {
        Box::new(MockClient::new())
    } else {
        Box::new(HttpClient::new())
    };

    // Run app
    let mut app = App::with_client(client);
    if let Some(p) = picker {
        app.set_terminal_capability_with_picker(cap, p);
    } else {
        app.set_terminal_capability(cap);
    }
    let result = run_loop(&mut terminal, &mut app);

    // Restore terminal — order mirrors setup: drop mouse capture, leave
    // alternate screen, disable raw mode.
    execute!(
        terminal.backend_mut(),
        DisableMouseCapture,
        LeaveAlternateScreen
    )?;
    disable_raw_mode()?;
    terminal.show_cursor()?;

    result
}

fn run_loop(terminal: &mut Terminal<CrosstermBackend<io::Stdout>>, app: &mut App) -> Result<()> {
    while app.running {
        terminal.draw(|frame| ui::render(frame, app))?;

        // tick() drives any periodic background work (e.g. post-sync polling)
        // and decides how long the loop is willing to block waiting for the
        // next key press. When no work is in flight the timeout is generous;
        // during sync polling it drops to ~125ms so the dot animation stays
        // smooth and the next refetch fires on time.
        let timeout = app.tick();

        if event::poll(timeout)? {
            match event::read()? {
                Event::Key(key) if key.kind == KeyEventKind::Press => {
                    keys::handle_key(app, key);
                }
                Event::Mouse(mouse) => {
                    handle_mouse(app, mouse);
                }
                _ => {}
            }
        }
    }
    Ok(())
}

/// Route a crossterm mouse event to the relevant screen. Currently only the
/// footage detail scrub UI consumes mouse input; other screens ignore mouse
/// events entirely (their behaviour is identical with mouse capture on or
/// off).
fn handle_mouse(app: &mut App, mouse: MouseEvent) {
    if app.screen != Screen::FootageDetail {
        return;
    }
    let Some(rects) = app.footage_detail_rects else {
        return;
    };
    let consumed = {
        let Some(ref mut state) = app.footage_detail_state else {
            return;
        };
        footage_detail::handle_mouse(state, rects, mouse)
    };
    if consumed {
        // Hover / scroll / drag may have walked `active_timestamp_seconds`;
        // refresh the cached image protocol so the next render shows the
        // newly-active frame.
        app.refresh_active_preview_protocol();
    }
}
