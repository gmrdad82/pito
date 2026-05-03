use std::io;

use anyhow::Result;
use crossterm::{
    event::{self, Event, KeyEventKind},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{backend::CrosstermBackend, Terminal};

use crate::api::client::{MockClient, PitoClient};
use crate::api::http_client::HttpClient;
use crate::app::App;
use crate::keys;
use crate::ui;

pub fn run() -> Result<()> {
    // Load .env (if present) before reading any pito env vars. We
    // intentionally swallow the error: a missing .env is the common
    // "developer hasn't created one yet" case and PITO_API_URL has a sensible
    // default.
    dotenvy::dotenv().ok();

    // Setup terminal
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

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
    let result = run_loop(&mut terminal, &mut app);

    // Restore terminal
    disable_raw_mode()?;
    execute!(terminal.backend_mut(), LeaveAlternateScreen)?;
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

        if event::poll(timeout)?
            && let Event::Key(key) = event::read()?
                && key.kind == KeyEventKind::Press {
                    keys::handle_key(app, key);
                }
    }
    Ok(())
}
