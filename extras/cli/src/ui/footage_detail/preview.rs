//! Wrapper around `ratatui-image::StatefulProtocol` that tracks the
//! `(footage_id, timestamp_seconds)` it was built for.
//!
//! The footage detail screen rebuilds the protocol every time the active
//! scrub timestamp changes. Storing the identity alongside the protocol
//! lets `App::refresh_active_preview_protocol` cheap-out when nothing has
//! changed (e.g. the user pressed Space to recenter the strip without
//! moving the playhead). It also gives the renderer enough context to
//! decide between the live `StatefulImage` path and the text fallback —
//! `App` can render text when the protocol is missing or is for a stale
//! identity.

use ratatui_image::protocol::StatefulProtocol;

/// Live image-rendering state for the footage detail preview.
///
/// `StatefulProtocol` is `!Clone` and holds an internal cache of encoded
/// bytes + the resize state for the last-rendered area. We keep it in a
/// dedicated wrapper so the outer `App` can move ownership around without
/// touching the protocol type at the call sites.
pub struct PreviewProtocol {
    footage_id: u64,
    timestamp_seconds: u64,
    protocol: StatefulProtocol,
}

impl PreviewProtocol {
    /// Build a fresh preview protocol for `(footage_id, timestamp_seconds)`.
    /// The protocol is created via `Picker::new_resize_protocol` upstream;
    /// callers pass the result in.
    pub fn new(footage_id: u64, timestamp_seconds: u64, protocol: StatefulProtocol) -> Self {
        Self {
            footage_id,
            timestamp_seconds,
            protocol,
        }
    }

    /// True when this protocol was built for the same `(footage_id,
    /// timestamp_seconds)` pair the caller is asking about. Used to avoid
    /// re-fetching + re-decoding when the active timestamp didn't move.
    pub fn matches(&self, footage_id: u64, timestamp_seconds: u64) -> bool {
        self.footage_id == footage_id && self.timestamp_seconds == timestamp_seconds
    }

    /// Mutable access to the underlying protocol so the renderer can pass it
    /// to `StatefulImage::render`. ratatui-image's `StatefulWidget` impl
    /// requires `&mut StatefulProtocol`.
    pub fn protocol_mut(&mut self) -> &mut StatefulProtocol {
        &mut self.protocol
    }

    /// The footage id this protocol was built for. Used by tests.
    #[cfg(test)]
    pub fn footage_id(&self) -> u64 {
        self.footage_id
    }

    /// The active timestamp this protocol was built for. Used by tests.
    #[cfg(test)]
    pub fn timestamp_seconds(&self) -> u64 {
        self.timestamp_seconds
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ratatui_image::picker::Picker;

    fn fixture_protocol() -> StatefulProtocol {
        // 2x2 black image is enough to exercise the wrapper — we never
        // render it in this test, only round-trip it through `new`. The
        // halfblocks Picker doesn't touch stdio, so this test is safe in
        // every harness.
        let img = image::DynamicImage::new_rgba8(2, 2);
        Picker::halfblocks().new_resize_protocol(img)
    }

    #[test]
    fn matches_returns_true_only_for_same_pair() {
        let preview = PreviewProtocol::new(7, 90, fixture_protocol());
        assert!(preview.matches(7, 90));
        assert!(!preview.matches(7, 91));
        assert!(!preview.matches(8, 90));
    }

    #[test]
    fn accessors_round_trip() {
        let preview = PreviewProtocol::new(42, 180, fixture_protocol());
        assert_eq!(preview.footage_id(), 42);
        assert_eq!(preview.timestamp_seconds(), 180);
    }
}
