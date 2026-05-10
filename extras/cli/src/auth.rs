//! Local authentication state for the `pito` CLI.
//!
//! The Phase 18 CLI parity spec
//! (`docs/plans/beta/18-cli-parity/specs/01-cli-coverage-matrix-and-subcommands.md`)
//! locks the on-disk shape:
//!
//! ```toml
//! [server]
//! url = "https://app.pitomd.com"
//!
//! [token]
//! value = "pito_xxxxxxxxxxxxxxxxxxxxxxxx"
//! ```
//!
//! - File path: `~/.config/pito/auth.toml`. `$XDG_CONFIG_HOME`, if set,
//!   overrides `~/.config/`.
//! - File mode: `0600` on creation. We warn (stderr) on read if the existing
//!   mode is wider; we do not hard-fail (per locked Open question 7).
//! - `PITO_API_URL` env var, if set, overrides `[server].url`.
//! - `PITO_API_TOKEN` env var, if set, overrides `[token].value`.
//!
//! This module owns ONLY the file shape and the env-override resolution. The
//! per-command flows (interactive login, logout confirmation, whoami output)
//! live in `commands/auth.rs`.

use std::fs;
use std::io;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result, anyhow};
use serde::{Deserialize, Serialize};

/// Default base URL when neither `[server].url` nor `PITO_API_URL` is set.
/// Mirrors `api::http_client::DEFAULT_BASE_URL` so a fresh `auth.toml` and a
/// fresh env always agree on the production host.
pub const DEFAULT_BASE_URL: &str = "https://app.pitomd.com";

/// Env var that overrides `[server].url` when set.
pub const ENV_API_URL: &str = "PITO_API_URL";

/// Env var that overrides `[token].value` when set. Useful for CI.
pub const ENV_API_TOKEN: &str = "PITO_API_TOKEN";

/// On-disk shape of `auth.toml`. Sections are typed so a malformed file is
/// rejected with a clear error rather than silently producing an empty token.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct AuthFile {
    #[serde(default)]
    pub server: ServerSection,
    #[serde(default)]
    pub token: TokenSection,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Default)]
pub struct ServerSection {
    /// Base URL of the Rails app. Trailing slash is tolerated; the HTTP
    /// client trims it.
    #[serde(default)]
    pub url: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Default)]
pub struct TokenSection {
    /// Bearer token from `/settings/tokens`. Treat as a secret.
    #[serde(default)]
    pub value: String,
}

impl Default for AuthFile {
    fn default() -> Self {
        Self {
            server: ServerSection {
                url: DEFAULT_BASE_URL.to_string(),
            },
            token: TokenSection::default(),
        }
    }
}

/// Resolved auth state — what the rest of the CLI consumes. Always carries a
/// concrete `base_url` (env > file > default) and a possibly-empty `token`
/// (env > file). Empty token means "not authenticated".
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ResolvedAuth {
    pub base_url: String,
    pub token: Option<String>,
    /// Whether the token / URL came from env, file, or default.
    pub source: AuthSource,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AuthSource {
    /// At least one of `PITO_API_TOKEN` / `PITO_API_URL` was set.
    Env,
    /// Both pulled from `auth.toml`.
    File,
    /// No file, no env — the default base URL with no token.
    Default,
}

/// Compute the path to the auth file. Honors `$XDG_CONFIG_HOME`; falls back
/// to `$HOME/.config/pito/auth.toml`. Returns an error only if neither env
/// var resolves (which is a malformed environment).
pub fn auth_file_path() -> Result<PathBuf> {
    auth_file_path_in(&Env::system())
}

/// Test seam: same as [`auth_file_path`] but reads from a stub environment.
pub fn auth_file_path_in(env: &Env) -> Result<PathBuf> {
    if let Some(xdg) = env.get(ENV_XDG_CONFIG_HOME)
        && !xdg.is_empty()
    {
        return Ok(PathBuf::from(xdg).join("pito").join("auth.toml"));
    }
    let home = env.get(ENV_HOME).filter(|s| !s.is_empty()).ok_or_else(|| {
        anyhow!("HOME and XDG_CONFIG_HOME are both unset; cannot locate auth.toml")
    })?;
    Ok(PathBuf::from(home)
        .join(".config")
        .join("pito")
        .join("auth.toml"))
}

const ENV_XDG_CONFIG_HOME: &str = "XDG_CONFIG_HOME";
const ENV_HOME: &str = "HOME";

/// Boxed env-var getter. Owned alias so the `Env` struct doesn't trip
/// `clippy::type_complexity`.
type EnvGetter = Box<dyn Fn(&str) -> Option<String>>;

/// Tiny env abstraction so tests can stub `HOME` / `XDG_CONFIG_HOME` without
/// touching the process environment.
pub struct Env {
    getter: EnvGetter,
}

impl Env {
    pub fn system() -> Self {
        Self {
            getter: Box::new(|k| std::env::var(k).ok()),
        }
    }

    /// Build a stub from a slice of `(key, value)` pairs. Used by tests to
    /// exercise the resolver without touching the process environment; not
    /// referenced from binary code paths.
    #[allow(dead_code)]
    pub fn from_pairs(pairs: &[(&str, &str)]) -> Self {
        let owned: Vec<(String, String)> = pairs
            .iter()
            .map(|(k, v)| (k.to_string(), v.to_string()))
            .collect();
        Self {
            getter: Box::new(move |k| {
                owned
                    .iter()
                    .find(|(key, _)| key == k)
                    .map(|(_, v)| v.clone())
            }),
        }
    }

    pub fn get(&self, key: &str) -> Option<String> {
        (self.getter)(key)
    }
}

/// Load `auth.toml` from disk if it exists. Returns `Ok(None)` when the file
/// is absent (treated as "not yet logged in"). Returns `Err` only on parse
/// failure or unexpected IO error (permission denied, etc.).
pub fn load_file(path: &Path) -> Result<Option<AuthFile>> {
    match fs::read_to_string(path) {
        Ok(contents) => {
            let parsed: AuthFile =
                toml::from_str(&contents).with_context(|| format!("parse {}", path.display()))?;
            Ok(Some(parsed))
        }
        Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(None),
        Err(e) => Err(anyhow!("read {}: {}", path.display(), e)),
    }
}

/// Resolve auth state from the file plus environment overrides.
///
/// Order of precedence (per spec):
/// 1. `PITO_API_TOKEN` env > `[token].value` > none.
/// 2. `PITO_API_URL` env > `[server].url` > [`DEFAULT_BASE_URL`].
pub fn resolve(file: Option<&AuthFile>, env: &Env) -> ResolvedAuth {
    let env_token = env.get(ENV_API_TOKEN).filter(|s| !s.is_empty());
    let env_url = env.get(ENV_API_URL).filter(|s| !s.is_empty());

    let file_token = file
        .map(|f| f.token.value.clone())
        .filter(|s| !s.is_empty());
    let file_url = file.map(|f| f.server.url.clone()).filter(|s| !s.is_empty());

    let token = env_token.clone().or(file_token.clone());
    let base_url = env_url
        .clone()
        .or(file_url.clone())
        .unwrap_or_else(|| DEFAULT_BASE_URL.to_string());

    let source = if env_token.is_some() || env_url.is_some() {
        AuthSource::Env
    } else if file.is_some() {
        AuthSource::File
    } else {
        AuthSource::Default
    };

    ResolvedAuth {
        base_url,
        token,
        source,
    }
}

/// Write `auth.toml` to disk, creating the parent directory if needed.
/// Sets file mode `0600` on Unix; on other platforms the mode-set is a
/// best-effort no-op.
pub fn write_file(path: &Path, file: &AuthFile) -> Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("create_dir_all {}", parent.display()))?;
    }
    let serialized = toml::to_string_pretty(file).context("serialize auth.toml")?;
    fs::write(path, serialized).with_context(|| format!("write {}", path.display()))?;
    set_secret_mode(path)?;
    Ok(())
}

/// Delete `auth.toml`. Returns `Ok(true)` if a file was removed, `Ok(false)`
/// if no file existed (idempotent logout).
pub fn delete_file(path: &Path) -> Result<bool> {
    match fs::remove_file(path) {
        Ok(()) => Ok(true),
        Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(false),
        Err(e) => Err(anyhow!("remove {}: {}", path.display(), e)),
    }
}

/// Whether the file's permissions are wider than `0600`. Returns `None` on
/// non-Unix platforms (where the mode concept does not apply); the caller
/// can choose to skip the warning. Returns `Some(true)` if any group / other
/// bit is set or if the user `read` bit is missing alongside writeable bits.
#[cfg(unix)]
pub fn world_or_group_readable(path: &Path) -> Option<bool> {
    use std::os::unix::fs::PermissionsExt;
    let meta = fs::metadata(path).ok()?;
    let mode = meta.permissions().mode() & 0o777;
    Some(mode & 0o077 != 0)
}

#[cfg(not(unix))]
pub fn world_or_group_readable(_path: &Path) -> Option<bool> {
    None
}

#[cfg(unix)]
fn set_secret_mode(path: &Path) -> Result<()> {
    use std::os::unix::fs::PermissionsExt;
    let perms = fs::Permissions::from_mode(0o600);
    fs::set_permissions(path, perms).with_context(|| format!("chmod 0600 {}", path.display()))?;
    Ok(())
}

#[cfg(not(unix))]
fn set_secret_mode(_path: &Path) -> Result<()> {
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn auth_file_path_uses_xdg_config_home_when_set() {
        let env = Env::from_pairs(&[(ENV_XDG_CONFIG_HOME, "/tmp/xdg"), (ENV_HOME, "/home/u")]);
        let path = auth_file_path_in(&env).expect("path");
        assert_eq!(path, PathBuf::from("/tmp/xdg/pito/auth.toml"));
    }

    #[test]
    fn auth_file_path_falls_back_to_home_when_xdg_missing() {
        let env = Env::from_pairs(&[(ENV_HOME, "/home/u")]);
        let path = auth_file_path_in(&env).expect("path");
        assert_eq!(path, PathBuf::from("/home/u/.config/pito/auth.toml"));
    }

    #[test]
    fn auth_file_path_falls_back_to_home_when_xdg_empty() {
        // An empty XDG var is treated as unset; we honor only non-empty
        // values per the spec's "if set" wording.
        let env = Env::from_pairs(&[(ENV_XDG_CONFIG_HOME, ""), (ENV_HOME, "/home/u")]);
        let path = auth_file_path_in(&env).expect("path");
        assert_eq!(path, PathBuf::from("/home/u/.config/pito/auth.toml"));
    }

    #[test]
    fn auth_file_path_errors_when_both_envs_unset() {
        let env = Env::from_pairs(&[]);
        let err = auth_file_path_in(&env).expect_err("missing both");
        assert!(format!("{err}").contains("HOME"));
    }

    #[test]
    fn load_file_returns_none_for_missing_file() {
        let tmp = TempDir::new().expect("tempdir");
        let path = tmp.path().join("auth.toml");
        let result = load_file(&path).expect("load");
        assert!(result.is_none());
    }

    #[test]
    fn load_file_parses_locked_shape() {
        let tmp = TempDir::new().expect("tempdir");
        let path = tmp.path().join("auth.toml");
        fs::write(
            &path,
            "[server]\nurl = \"https://example.test\"\n[token]\nvalue = \"pito_abc\"\n",
        )
        .expect("write");
        let parsed = load_file(&path).expect("load").expect("present");
        assert_eq!(parsed.server.url, "https://example.test");
        assert_eq!(parsed.token.value, "pito_abc");
    }

    #[test]
    fn load_file_errors_on_malformed_toml() {
        let tmp = TempDir::new().expect("tempdir");
        let path = tmp.path().join("auth.toml");
        fs::write(&path, "not a toml file [[[").expect("write");
        let err = load_file(&path).expect_err("malformed");
        let s = format!("{err}");
        assert!(s.contains("parse"));
    }

    #[test]
    fn write_file_creates_parent_directory() {
        let tmp = TempDir::new().expect("tempdir");
        let path = tmp.path().join("nested").join("dir").join("auth.toml");
        let file = AuthFile {
            server: ServerSection {
                url: "https://example.test".to_string(),
            },
            token: TokenSection {
                value: "pito_abc".to_string(),
            },
        };
        write_file(&path, &file).expect("write");
        assert!(path.exists());
        let round_tripped = load_file(&path).expect("load").expect("present");
        assert_eq!(round_tripped, file);
    }

    #[cfg(unix)]
    #[test]
    fn write_file_sets_mode_0600() {
        use std::os::unix::fs::PermissionsExt;
        let tmp = TempDir::new().expect("tempdir");
        let path = tmp.path().join("auth.toml");
        let file = AuthFile::default();
        write_file(&path, &file).expect("write");
        let mode = fs::metadata(&path).expect("meta").permissions().mode() & 0o777;
        assert_eq!(mode, 0o600);
    }

    #[cfg(unix)]
    #[test]
    fn world_or_group_readable_detects_wide_permissions() {
        use std::os::unix::fs::PermissionsExt;
        let tmp = TempDir::new().expect("tempdir");
        let path = tmp.path().join("auth.toml");
        fs::write(&path, "[server]\nurl = \"x\"\n").expect("write");
        fs::set_permissions(&path, fs::Permissions::from_mode(0o644)).expect("chmod 0644");
        assert_eq!(world_or_group_readable(&path), Some(true));
        fs::set_permissions(&path, fs::Permissions::from_mode(0o600)).expect("chmod 0600");
        assert_eq!(world_or_group_readable(&path), Some(false));
    }

    #[test]
    fn delete_file_returns_true_when_file_existed() {
        let tmp = TempDir::new().expect("tempdir");
        let path = tmp.path().join("auth.toml");
        fs::write(&path, "x").expect("write");
        assert!(delete_file(&path).expect("rm"));
        assert!(!path.exists());
    }

    #[test]
    fn delete_file_is_idempotent_when_missing() {
        let tmp = TempDir::new().expect("tempdir");
        let path = tmp.path().join("auth.toml");
        assert!(!delete_file(&path).expect("rm"));
    }

    #[test]
    fn resolve_uses_env_over_file() {
        let file = AuthFile {
            server: ServerSection {
                url: "https://from-file".to_string(),
            },
            token: TokenSection {
                value: "file_token".to_string(),
            },
        };
        let env = Env::from_pairs(&[
            (ENV_API_URL, "https://from-env"),
            (ENV_API_TOKEN, "env_token"),
        ]);
        let resolved = resolve(Some(&file), &env);
        assert_eq!(resolved.base_url, "https://from-env");
        assert_eq!(resolved.token.as_deref(), Some("env_token"));
        assert_eq!(resolved.source, AuthSource::Env);
    }

    #[test]
    fn resolve_uses_file_when_env_absent() {
        let file = AuthFile {
            server: ServerSection {
                url: "https://from-file".to_string(),
            },
            token: TokenSection {
                value: "file_token".to_string(),
            },
        };
        let env = Env::from_pairs(&[]);
        let resolved = resolve(Some(&file), &env);
        assert_eq!(resolved.base_url, "https://from-file");
        assert_eq!(resolved.token.as_deref(), Some("file_token"));
        assert_eq!(resolved.source, AuthSource::File);
    }

    #[test]
    fn resolve_returns_default_when_nothing_set() {
        let env = Env::from_pairs(&[]);
        let resolved = resolve(None, &env);
        assert_eq!(resolved.base_url, DEFAULT_BASE_URL);
        assert!(resolved.token.is_none());
        assert_eq!(resolved.source, AuthSource::Default);
    }

    #[test]
    fn resolve_partial_env_overlay_is_marked_env() {
        // Only the URL is overridden; the token still comes from the file,
        // but the source is Env because at least one channel was overridden.
        let file = AuthFile {
            server: ServerSection {
                url: "https://from-file".to_string(),
            },
            token: TokenSection {
                value: "file_token".to_string(),
            },
        };
        let env = Env::from_pairs(&[(ENV_API_URL, "https://from-env")]);
        let resolved = resolve(Some(&file), &env);
        assert_eq!(resolved.base_url, "https://from-env");
        assert_eq!(resolved.token.as_deref(), Some("file_token"));
        assert_eq!(resolved.source, AuthSource::Env);
    }

    #[test]
    fn resolve_treats_empty_env_strings_as_unset() {
        let file = AuthFile {
            server: ServerSection {
                url: "https://from-file".to_string(),
            },
            token: TokenSection {
                value: "file_token".to_string(),
            },
        };
        let env = Env::from_pairs(&[(ENV_API_URL, ""), (ENV_API_TOKEN, "")]);
        let resolved = resolve(Some(&file), &env);
        assert_eq!(resolved.base_url, "https://from-file");
        assert_eq!(resolved.token.as_deref(), Some("file_token"));
        assert_eq!(resolved.source, AuthSource::File);
    }
}
