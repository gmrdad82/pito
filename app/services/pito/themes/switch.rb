# frozen_string_literal: true

module Pito
  module Themes
    # Shared service for theme apply and preview operations.
    #
    # Extracts the persist + broadcast logic from the slash handler so the same
    # paths can be reused by the hashtag handler (P7) and any future caller.
    #
    # Contract
    # --------
    # Switch.apply_only(definition)  — persist AppSetting.theme + broadcast; no events returned
    # Switch.preview_only(definition)— broadcast only (no persist); no events returned
    # Switch.apply(definition)       — apply_only + return event hashes
    # Switch.preview(definition)     — preview_only + return event hashes
    # Switch.reset                   — apply the registry default → events
    #
    # The `_only` variants perform only the side-effect and return nil. They are
    # intended for callers (e.g. the hashtag handler) that handle their own
    # response building (e.g. a Turbo Stream replace rather than a new event).
    #
    # `apply` and `preview` return an Array of event hashes ({ kind:, payload: })
    # ready to be wrapped in a Pito::Slash::Result::Ok or Pito::Hashtag::Result::Ok.
    module Switch
      # Persist a theme change and broadcast the set-theme Turbo Stream.
      # Does NOT return events — callers that need event hashes use `apply`.
      #
      # @param definition [Pito::Themes::Definition]
      # @return [nil]
      def self.apply_only(definition)
        AppSetting.theme = definition.slug
        Pito::Stream::Broadcaster.broadcast_global_theme(definition.slug)
        nil
      end

      # Broadcast a set-theme Turbo Stream WITHOUT persisting.
      # Does NOT return events — callers that need event hashes use `preview`.
      #
      # @param definition [Pito::Themes::Definition]
      # @return [nil]
      def self.preview_only(definition)
        Pito::Stream::Broadcaster.broadcast_global_theme(definition.slug)
        nil
      end

      # Persist + broadcast a theme change. Returns event hashes.
      #
      # @param definition [Pito::Themes::Definition]
      # @param reset [Boolean] use the reset confirmation string instead of apply
      # @param i18n_key [String, nil] override the default i18n key
      # @return [Array<Hash>]
      def self.apply(definition, reset: false, i18n_key: nil)
        apply_only(definition)

        msg_key = i18n_key ||
                  (reset ? "pito.slash.theme.reset.confirmed" : "pito.slash.theme.apply.confirmed")

        [
          {
            kind:    "system",
            payload: {
              text: I18n.t(msg_key, name: definition.label, slug: definition.slug)
            }
          }
        ]
      end

      # Broadcast a theme WITHOUT persisting. Returns event hashes.
      #
      # Preview-vs-apply rule:
      #   - Only the Turbo Stream set-theme action fires (recolors the page).
      #   - AppSetting.theme is NOT written.
      #   - The caller must run `/theme apply <name>` or `/theme reset` to make it permanent.
      #
      # @param definition [Pito::Themes::Definition]
      # @param i18n_key [String] override the i18n key (callers may use their own namespace)
      # @return [Array<Hash>]
      def self.preview(definition, i18n_key: "pito.slash.theme.preview.confirmed")
        preview_only(definition)

        [
          {
            kind:    "system",
            payload: {
              text: I18n.t(
                i18n_key,
                name:  definition.label,
                slug:  definition.slug,
                apply: "/theme apply #{definition.slug}",
                reset: "/theme reset"
              )
            }
          }
        ]
      end

      # Apply the registry default (tokyo-night).
      #
      # @return [Array<Hash>]
      def self.reset
        apply(Pito::Themes::Registry.default, reset: true)
      end
    end
  end
end
