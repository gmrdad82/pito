//! `pito auth` subcommand family.
//!
//! Per the Phase 18 CLI parity spec (work unit 2), three verbs:
//!
//! - `pito auth login` — interactive (or non-interactive via flags) wizard
//!   that writes `~/.config/pito/auth.toml`.
//! - `pito auth logout` — deletes the file after `--confirm yes`. Without
//!   the confirm flag, prints the preview and exits 0.
//! - `pito auth whoami` — reads the resolved token + URL and prints them.
//!   The spec describes a future `GET /api/auth/whoami.json` round-trip;
//!   that endpoint does not exist yet, so this command currently surfaces
//!   only the local config view (server URL + token preview + source).

use std::io::{self, BufRead, Write};

use anyhow::{Context, Result};

use crate::auth::{self, AuthFile, AuthSource, ServerSection, TokenSection};
use crate::cli::{AuthArgs, AuthCommand, AuthLoginArgs, AuthLogoutArgs, AuthWhoamiArgs};
use crate::confirm;
use crate::output::{ExitCode, OutputMode};

pub fn run(args: AuthArgs) -> Result<()> {
    match args.command {
        AuthCommand::Login(args) => run_login(args),
        AuthCommand::Logout(args) => run_logout(args),
        AuthCommand::Whoami(args) => run_whoami(args),
    }
}

// --- login ------------------------------------------------------------------

fn run_login(args: AuthLoginArgs) -> Result<()> {
    let path = auth::auth_file_path()?;

    // Non-interactive path: both URL and token provided via flags. Useful
    // for CI, fixture seeding, and the `--json` output mode.
    let (url, token) = match (args.url.clone(), args.token.clone()) {
        (Some(u), Some(t)) => (u, t),
        (Some(_), None) | (None, Some(_)) | (None, None)
            if matches!(OutputMode::from_json_flag(args.json), OutputMode::Json) =>
        {
            // `--json` + interactive prompts → reject per the spec's locked
            // edge case (Test posture, "interactive prompts not supported
            // with --json"). Exit code 64 (bad usage).
            eprintln!(
                "auth: interactive prompts not supported with --json; provide --url and --token"
            );
            std::process::exit(ExitCode::BadUsage.as_i32());
        }
        (maybe_url, maybe_token) => prompt_login(maybe_url, maybe_token)?,
    };

    let file = AuthFile {
        server: ServerSection { url: url.clone() },
        token: TokenSection {
            value: token.clone(),
        },
    };
    auth::write_file(&path, &file).with_context(|| format!("write {}", path.display()))?;

    let mode = OutputMode::from_json_flag(args.json);
    match mode {
        OutputMode::Json => {
            let json = serde_json::json!({
                "path": path.display().to_string(),
                "server": { "url": url },
                "token_preview": token_preview(&token),
            });
            println!("{}", serde_json::to_string(&json)?);
        }
        OutputMode::Plaintext => {
            println!("auth saved at {}", path.display());
            println!("server  {}", url);
            println!("token   {}", token_preview(&token));
            eprintln!(
                "the token is stored in plaintext at {}. keep the file private (mode 0600).",
                path.display()
            );
        }
    }
    Ok(())
}

/// Interactive prompt for the URL + token. If a flag was supplied for one of
/// the two, only the missing one is prompted. Returns `(url, token)`.
fn prompt_login(url_flag: Option<String>, token_flag: Option<String>) -> Result<(String, String)> {
    let stdin = io::stdin();
    let mut stdin_lock = stdin.lock();

    let url = if let Some(u) = url_flag {
        u
    } else {
        prompt_line(
            &mut stdin_lock,
            &format!("server url [{}]: ", auth::DEFAULT_BASE_URL),
        )?
        .trim()
        .to_string()
    };
    let url = if url.is_empty() {
        auth::DEFAULT_BASE_URL.to_string()
    } else {
        url
    };

    let token = if let Some(t) = token_flag {
        t
    } else {
        prompt_line(&mut stdin_lock, "api token: ")?
            .trim()
            .to_string()
    };

    if token.is_empty() {
        eprintln!("auth: token cannot be empty");
        std::process::exit(ExitCode::Validation.as_i32());
    }

    Ok((url, token))
}

fn prompt_line<R: BufRead>(reader: &mut R, prompt: &str) -> Result<String> {
    print!("{}", prompt);
    io::stdout().flush().ok();
    let mut buf = String::new();
    reader.read_line(&mut buf).context("read stdin")?;
    Ok(buf)
}

// --- logout -----------------------------------------------------------------

fn run_logout(args: AuthLogoutArgs) -> Result<()> {
    let path = auth::auth_file_path()?;
    let confirmed = confirm::is_confirmed(args.confirm);
    let mode = OutputMode::from_json_flag(args.json);

    if !confirmed {
        // Preview — same UX as the web's action confirmation page.
        let exists = path.exists();
        match mode {
            OutputMode::Json => {
                let json = serde_json::json!({
                    "preview": true,
                    "path": path.display().to_string(),
                    "exists": exists,
                });
                println!("{}", serde_json::to_string(&json)?);
            }
            OutputMode::Plaintext => {
                if exists {
                    println!("would delete {}", path.display());
                    println!("rerun with --confirm yes to apply.");
                } else {
                    println!("no auth file at {} (already logged out).", path.display());
                }
            }
        }
        return Ok(());
    }

    let removed = auth::delete_file(&path)?;
    match mode {
        OutputMode::Json => {
            let json = serde_json::json!({
                "removed": removed,
                "path": path.display().to_string(),
            });
            println!("{}", serde_json::to_string(&json)?);
        }
        OutputMode::Plaintext => {
            if removed {
                println!("auth file removed: {}", path.display());
            } else {
                println!("no auth file to remove (already logged out).");
            }
        }
    }
    Ok(())
}

// --- whoami -----------------------------------------------------------------

fn run_whoami(args: AuthWhoamiArgs) -> Result<()> {
    let path = auth::auth_file_path()?;
    let file = auth::load_file(&path)?;
    let env = auth::Env::system();
    let resolved = auth::resolve(file.as_ref(), &env);
    let mode = OutputMode::from_json_flag(args.json);

    // Surface a stderr warning if the on-disk file has wider permissions
    // than 0600 (per spec Open question 7 — warn, do not fail).
    if file.is_some()
        && let Some(true) = auth::world_or_group_readable(&path)
    {
        eprintln!(
            "auth: warning — {} has permissions wider than 0600. fix with: chmod 600 {}",
            path.display(),
            path.display()
        );
    }

    match (resolved.token.clone(), mode) {
        (None, OutputMode::Plaintext) => {
            eprintln!("auth: not authenticated. run `pito auth login`.");
            std::process::exit(ExitCode::AuthFailure.as_i32());
        }
        (None, OutputMode::Json) => {
            let json = serde_json::json!({
                "authenticated": false,
                "server": { "url": resolved.base_url },
                "source": source_label(resolved.source),
            });
            println!("{}", serde_json::to_string(&json)?);
            std::process::exit(ExitCode::AuthFailure.as_i32());
        }
        (Some(token), OutputMode::Json) => {
            let json = serde_json::json!({
                "authenticated": true,
                "server": { "url": resolved.base_url },
                "token_preview": token_preview(&token),
                "source": source_label(resolved.source),
                "path": path.display().to_string(),
            });
            println!("{}", serde_json::to_string(&json)?);
        }
        (Some(token), OutputMode::Plaintext) => {
            println!("server   {}", resolved.base_url);
            println!("token    {}", token_preview(&token));
            println!("source   {}", source_label(resolved.source));
            if matches!(resolved.source, AuthSource::File | AuthSource::Default) {
                println!("path     {}", path.display());
            }
        }
    }
    Ok(())
}

/// Preview the last 4 characters of the token. Mirrors the Rails token UI's
/// `last_token_preview` field. Rejects tokens shorter than 4 chars to avoid
/// printing the whole secret on a malformed file.
pub fn token_preview(token: &str) -> String {
    let len = token.chars().count();
    if len <= 4 {
        return "*".repeat(len.max(1));
    }
    let suffix: String = token
        .chars()
        .rev()
        .take(4)
        .collect::<Vec<char>>()
        .into_iter()
        .rev()
        .collect();
    format!("****{}", suffix)
}

fn source_label(source: AuthSource) -> &'static str {
    match source {
        AuthSource::Env => "env",
        AuthSource::File => "file",
        AuthSource::Default => "default",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn token_preview_redacts_all_but_last_4() {
        assert_eq!(token_preview("pito_abcd1234"), "****1234");
    }

    #[test]
    fn token_preview_short_tokens_get_full_redaction() {
        assert_eq!(token_preview(""), "*");
        assert_eq!(token_preview("ab"), "**");
        assert_eq!(token_preview("abcd"), "****");
    }

    #[test]
    fn source_label_renders_known_variants() {
        assert_eq!(source_label(AuthSource::Env), "env");
        assert_eq!(source_label(AuthSource::File), "file");
        assert_eq!(source_label(AuthSource::Default), "default");
    }
}
