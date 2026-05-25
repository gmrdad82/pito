use std::io;

use anyhow::Result;
use crossterm::{
    event::{self, DisableMouseCapture, EnableMouseCapture, Event, KeyCode, KeyEventKind, KeyModifiers},
    execute,
    terminal::{EnterAlternateScreen, LeaveAlternateScreen, disable_raw_mode, enable_raw_mode},
};
use ratatui::{Terminal, backend::CrosstermBackend};

use crate::api::client::PitoClient;
use crate::app::App;
// use crate::keys; // simplified — key handling inline
use crate::ui;
use crate::ui::footage_detail::capability;

pub fn run() -> Result<()> {
    dotenvy::dotenv().ok();

    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen, EnableMouseCapture)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    let (cap, picker) = match ratatui_image::picker::Picker::from_query_stdio() {
        Ok(p) => (capability::TerminalCapability::from_protocol(p.protocol_type()), Some(p)),
        Err(_) => (capability::TerminalCapability::Halfblocks, None),
    };

    let use_mock = std::env::var("PITO_USE_MOCK").unwrap_or_default() == "yes";
    let base_url = std::env::var("PITO_API_URL").unwrap_or_else(|_| "https://app.pitomd.com".into());

    if use_mock {
        let client = crate::api::client::MockClient::new();
        let mut app = App::new(client, &base_url);
        if let Some(p) = picker { app.set_terminal_capability_with_picker(cap, p); } else { app.set_terminal_capability(cap); }
        let result = run_loop(&mut terminal, &mut app);
        cleanup(&mut terminal)?;
        return result;
    }

    let client = crate::api::http_client::HttpClient::new();
    let mut app = App::new(client, &base_url);
    if let Some(p) = picker { app.set_terminal_capability_with_picker(cap, p); } else { app.set_terminal_capability(cap); }
    let result = run_loop(&mut terminal, &mut app);
    cleanup(&mut terminal)?;
    result
}

fn cleanup(terminal: &mut Terminal<CrosstermBackend<io::Stdout>>) -> Result<()> {
    execute!(terminal.backend_mut(), DisableMouseCapture, LeaveAlternateScreen)?;
    disable_raw_mode()?;
    terminal.show_cursor()?;
    Ok(())
}

fn run_loop<C: PitoClient>(terminal: &mut Terminal<CrosstermBackend<io::Stdout>>, app: &mut App<C>) -> Result<()> {
    let tick_rate = std::time::Duration::from_millis(50);
    let mut last_tick = std::time::Instant::now();

    // Boot — push welcome lines
    app.push_line("");
    app.push_line("pito  YouTube channel management");
    app.push_line("  type /help for commands");
    app.push_line("  Tab toggles sidebar");
    app.push_line("");

    loop {
        terminal.draw(|frame| ui::render(frame, app))?;

        let timeout = tick_rate.saturating_sub(last_tick.elapsed());
        if event::poll(timeout)? {
            if let Event::Key(key) = event::read()? {
                if key.kind == KeyEventKind::Press {
                    match key.code {
                        KeyCode::Char('q') if key.modifiers.contains(KeyModifiers::CONTROL) => {
                            app.quit();
                        }
                        KeyCode::Esc => {
                            app.quit();
                        }
                        KeyCode::Tab => {
                            app.toggle_sidebar();
                        }
                        KeyCode::Enter => {
                            let cmd = app.input_buffer.clone();
                            app.input_buffer.clear();
                            app.cursor_pos = 0;
                            if !cmd.trim().is_empty() {
                                app.execute_command(&cmd);
                            }
                        }
                        KeyCode::Backspace => {
                            if app.cursor_pos > 0 {
                                app.cursor_pos -= 1;
                                app.input_buffer.remove(app.cursor_pos);
                            }
                        }
                        KeyCode::Char(c) => {
                            app.input_buffer.insert(app.cursor_pos, c);
                            app.cursor_pos += 1;
                        }
                        _ => {}
                    }
                }
            }
        }

        if last_tick.elapsed() >= tick_rate {
            last_tick = std::time::Instant::now();
        }

        if !app.running {
            break;
        }
    }
    Ok(())
}
