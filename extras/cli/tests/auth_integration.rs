//! Integration tests for the Phase 18 `auth` plumbing.
//!
//! Drives the same library entry points (`pito::auth::*`) the `pito auth`
//! subcommand consumes, end-to-end against a temporary file. Verifies the
//! locked file shape, the env override precedence, and the round-trip
//! through write → load → resolve.

use std::fs;

use pito::auth::{
    AuthFile, AuthSource, DEFAULT_BASE_URL, ENV_API_TOKEN, ENV_API_URL, Env, ServerSection,
    TokenSection, auth_file_path_in, delete_file, load_file, resolve, write_file,
};
use tempfile::TempDir;

#[test]
fn auth_file_path_resolves_from_xdg_then_home() {
    let env_xdg = Env::from_pairs(&[("XDG_CONFIG_HOME", "/tmp/xdg")]);
    let path_xdg = auth_file_path_in(&env_xdg).expect("xdg path");
    assert!(path_xdg.ends_with("pito/auth.toml"));
    assert!(path_xdg.starts_with("/tmp/xdg"));

    let env_home = Env::from_pairs(&[("HOME", "/home/u")]);
    let path_home = auth_file_path_in(&env_home).expect("home path");
    assert!(path_home.ends_with(".config/pito/auth.toml"));
}

#[test]
fn write_then_load_round_trips_locked_shape() {
    let tmp = TempDir::new().expect("tempdir");
    let path = tmp.path().join("auth.toml");
    let original = AuthFile {
        server: ServerSection {
            url: "https://example.test".to_string(),
        },
        token: TokenSection {
            value: "pito_abcd1234".to_string(),
        },
    };
    write_file(&path, &original).expect("write");
    let raw = fs::read_to_string(&path).expect("read raw");
    // The TOML shape is the locked one — section headers must be present so
    // a hand-edit by the user produces a parseable file.
    assert!(raw.contains("[server]"));
    assert!(raw.contains("url = \"https://example.test\""));
    assert!(raw.contains("[token]"));
    assert!(raw.contains("value = \"pito_abcd1234\""));

    let parsed = load_file(&path).expect("load").expect("present");
    assert_eq!(parsed, original);
}

#[test]
fn env_overrides_file_for_token_and_url() {
    let tmp = TempDir::new().expect("tempdir");
    let path = tmp.path().join("auth.toml");
    let file = AuthFile {
        server: ServerSection {
            url: "https://from-file".to_string(),
        },
        token: TokenSection {
            value: "file_token".to_string(),
        },
    };
    write_file(&path, &file).expect("write");
    let loaded = load_file(&path).expect("load").expect("present");

    let env = Env::from_pairs(&[
        (ENV_API_URL, "https://from-env"),
        (ENV_API_TOKEN, "env_token"),
    ]);
    let resolved = resolve(Some(&loaded), &env);
    assert_eq!(resolved.base_url, "https://from-env");
    assert_eq!(resolved.token.as_deref(), Some("env_token"));
    assert_eq!(resolved.source, AuthSource::Env);
}

#[test]
fn resolve_falls_back_to_default_when_nothing_set() {
    let env = Env::from_pairs(&[]);
    let resolved = resolve(None, &env);
    assert_eq!(resolved.base_url, DEFAULT_BASE_URL);
    assert!(resolved.token.is_none());
    assert_eq!(resolved.source, AuthSource::Default);
}

#[test]
fn delete_removes_existing_file() {
    let tmp = TempDir::new().expect("tempdir");
    let path = tmp.path().join("auth.toml");
    write_file(&path, &AuthFile::default()).expect("write");
    assert!(path.exists());
    let removed = delete_file(&path).expect("delete");
    assert!(removed);
    assert!(!path.exists());
}

#[test]
fn delete_is_idempotent_on_missing_file() {
    let tmp = TempDir::new().expect("tempdir");
    let path = tmp.path().join("auth.toml");
    let removed = delete_file(&path).expect("delete");
    assert!(!removed);
}

#[cfg(unix)]
#[test]
fn write_uses_secret_mode_0600() {
    use std::os::unix::fs::PermissionsExt;
    let tmp = TempDir::new().expect("tempdir");
    let path = tmp.path().join("auth.toml");
    write_file(&path, &AuthFile::default()).expect("write");
    let mode = fs::metadata(&path).expect("meta").permissions().mode() & 0o777;
    assert_eq!(mode, 0o600);
}
