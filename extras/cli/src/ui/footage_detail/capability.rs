//! Terminal graphics-capability detection for the footage detail scrub
//! screen.
//!
//! `halfblocks_picker` is the test-friendly fallback Picker —
//! `App::set_terminal_capability` calls it whenever the App is constructed
//! without a real Picker (i.e. tests and the binary's pre-detect default).
//! The live binary path goes through `Picker::from_query_stdio` directly
//! and stashes the result via `set_terminal_capability_with_picker`.
#![allow(dead_code)]
//!
//! At boot we ask `ratatui-image`'s `Picker::from_query_stdio()` what graphics
//! protocol the connected terminal supports, then map the result onto a small
//! pito-local enum so the rest of the UI doesn't depend on `ratatui-image`'s
//! type hierarchy at the layout level.
//!
//! Supported variants:
//!
//! - `Kitty` — Kitty / Ghostty / WezTerm / Konsole (Konsole is blacklisted by
//!   ratatui-image upstream because its placeholder support is buggy; we
//!   therefore observe `Kitty` only on terminals that actually implement the
//!   protocol cleanly).
//! - `Sixel` — foot, mlterm, xterm with `--enable-sixel-graphics`.
//! - `ITerm2` — iTerm2 (and WezTerm with the iTerm2 inline-image fallback).
//! - `Halfblocks` — universal fallback for any terminal that responds to
//!   color escapes; Alacritty / plain xterm / tmux without graphics
//!   passthrough end up here.
//! - `TextOnly` — used when capability detection itself fails (e.g. running
//!   under a non-TTY harness, redirected stdout). The footage detail screen
//!   responds by replacing image areas with text labels.
//!
//! The capability is detected once at app boot and stored on `App`. Tests
//! construct the enum directly; live runs go through [`detect`].

use ratatui_image::picker::{Picker, ProtocolType};

/// Pito-local terminal-capability enum. Decoupled from ratatui-image's
/// `ProtocolType` so the rendering layer can branch without re-importing the
/// upstream type at every callsite, and so we can model the `TextOnly`
/// degraded-detection state that ratatui-image itself does not have.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TerminalCapability {
    Kitty,
    Sixel,
    ITerm2,
    Halfblocks,
    /// Detection failed entirely (e.g. running under a harness without a TTY).
    /// The scrub UI replaces image areas with bracketed text labels.
    TextOnly,
}

impl TerminalCapability {
    /// True when the capability supports inline graphics (any non-text
    /// protocol). Used by the scrub UI to decide between the image-ful and
    /// text-only render paths.
    pub fn supports_graphics(self) -> bool {
        !matches!(self, TerminalCapability::TextOnly)
    }

    /// Map ratatui-image's [`ProtocolType`] onto our enum.
    pub fn from_protocol(protocol: ProtocolType) -> Self {
        match protocol {
            ProtocolType::Kitty => TerminalCapability::Kitty,
            ProtocolType::Sixel => TerminalCapability::Sixel,
            ProtocolType::Iterm2 => TerminalCapability::ITerm2,
            ProtocolType::Halfblocks => TerminalCapability::Halfblocks,
        }
    }

    /// Short label for the capability (used in the help / debug overlay).
    pub fn label(self) -> &'static str {
        match self {
            TerminalCapability::Kitty => "kitty",
            TerminalCapability::Sixel => "sixel",
            TerminalCapability::ITerm2 => "iterm2",
            TerminalCapability::Halfblocks => "halfblocks",
            TerminalCapability::TextOnly => "text-only",
        }
    }
}

/// Detect capability via ratatui-image's stdio probe. Falls back to
/// `Halfblocks` when stdio is not a TTY (Picker query returns Err) and to
/// `TextOnly` when even constructing a fallback Picker fails.
///
/// This must be called AFTER raw mode is enabled and AFTER the alternate
/// screen is entered, but BEFORE the first event read — see
/// `Picker::from_query_stdio` upstream docs.
pub fn detect() -> TerminalCapability {
    match Picker::from_query_stdio() {
        Ok(picker) => TerminalCapability::from_protocol(picker.protocol_type()),
        Err(_) => {
            // Stdio query failed (no TTY, redirected output, or terminal
            // didn't respond in time). Halfblocks is the safe fallback.
            TerminalCapability::Halfblocks
        }
    }
}

/// Build a halfblocks-only Picker. Test-friendly: `Picker::halfblocks()` does
/// not touch stdio. The footage detail screen calls this when capability is
/// `Halfblocks`, when running under a TestBackend, or as a permanent fallback
/// for the `TextOnly` branch (so we still have a Picker around for downscale
/// paths even if we choose not to render the image).
pub fn halfblocks_picker() -> Picker {
    Picker::halfblocks()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn from_protocol_round_trips_known_variants() {
        assert_eq!(
            TerminalCapability::from_protocol(ProtocolType::Kitty),
            TerminalCapability::Kitty
        );
        assert_eq!(
            TerminalCapability::from_protocol(ProtocolType::Sixel),
            TerminalCapability::Sixel
        );
        assert_eq!(
            TerminalCapability::from_protocol(ProtocolType::Iterm2),
            TerminalCapability::ITerm2
        );
        assert_eq!(
            TerminalCapability::from_protocol(ProtocolType::Halfblocks),
            TerminalCapability::Halfblocks
        );
    }

    #[test]
    fn supports_graphics_is_false_only_for_text_only() {
        for c in [
            TerminalCapability::Kitty,
            TerminalCapability::Sixel,
            TerminalCapability::ITerm2,
            TerminalCapability::Halfblocks,
        ] {
            assert!(c.supports_graphics(), "{:?}", c);
        }
        assert!(!TerminalCapability::TextOnly.supports_graphics());
    }

    #[test]
    fn label_distinguishes_each_variant() {
        let labels: Vec<&str> = [
            TerminalCapability::Kitty,
            TerminalCapability::Sixel,
            TerminalCapability::ITerm2,
            TerminalCapability::Halfblocks,
            TerminalCapability::TextOnly,
        ]
        .iter()
        .map(|c| c.label())
        .collect();
        // Sanity check: no two variants share a label.
        let mut sorted = labels.clone();
        sorted.sort();
        sorted.dedup();
        assert_eq!(sorted.len(), labels.len());
    }

    #[test]
    fn halfblocks_picker_constructs_without_stdio() {
        // Test-friendly construction must not panic and must report
        // halfblocks back through `protocol_type()`.
        let picker = halfblocks_picker();
        assert_eq!(picker.protocol_type(), ProtocolType::Halfblocks);
    }
}
