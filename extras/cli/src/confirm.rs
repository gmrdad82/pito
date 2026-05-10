//! Shared `--confirm yes` parsing for destructive subcommands.
//!
//! Per CLAUDE.md hard rules: every yes/no flag at an external boundary uses
//! the `"yes"` / `"no"` strings. The Phase 18 spec
//! (`docs/plans/beta/18-cli-parity/specs/01-cli-coverage-matrix-and-subcommands.md`)
//! adds the convention that `--confirm` is always optional and defaults to
//! "no" — without `--confirm yes`, destructive verbs print the action
//! confirmation preview and exit cleanly (exit code 0).

/// Yes/no enum used as a clap value type. The wire shape is `yes` or `no`.
/// Internally rendered as a `bool`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, clap::ValueEnum)]
pub enum YesNo {
    Yes,
    No,
}

impl YesNo {
    pub fn is_yes(self) -> bool {
        matches!(self, Self::Yes)
    }

    pub fn as_wire(self) -> &'static str {
        match self {
            Self::Yes => "yes",
            Self::No => "no",
        }
    }
}

impl std::fmt::Display for YesNo {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.as_wire())
    }
}

/// Resolve a confirmation flag. The optional `Option<YesNo>` shape lets
/// clap treat the flag as fully optional (no value defaults to "no" — i.e.
/// preview mode).
pub fn is_confirmed(flag: Option<YesNo>) -> bool {
    flag.map(|y| y.is_yes()).unwrap_or(false)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn yesno_is_yes_returns_true_only_for_yes() {
        assert!(YesNo::Yes.is_yes());
        assert!(!YesNo::No.is_yes());
    }

    #[test]
    fn yesno_wire_format_is_lowercase() {
        assert_eq!(YesNo::Yes.as_wire(), "yes");
        assert_eq!(YesNo::No.as_wire(), "no");
    }

    #[test]
    fn yesno_display_matches_wire_format() {
        assert_eq!(format!("{}", YesNo::Yes), "yes");
        assert_eq!(format!("{}", YesNo::No), "no");
    }

    #[test]
    fn is_confirmed_only_yes_passes() {
        assert!(is_confirmed(Some(YesNo::Yes)));
        assert!(!is_confirmed(Some(YesNo::No)));
        assert!(!is_confirmed(None));
    }
}
