# frozen_string_literal: true

module Pito
  module Hashtag
    module Handlers
      # Handler for `#preview <name>` and `#apply <name>` hashtag replies.
      #
      # These hashtags are follow-up affordances appended to the `/theme list`
      # System message. They let the user preview or apply a theme without
      # retyping the full slash command.
      #
      # Dispatch
      # --------
      # `#preview <name>` → broadcast-only (no persist); same as `/theme preview <name>`.
      # `#apply <name>`   → persist + broadcast; same as `/theme apply <name>`.
      #
      # The handler is registered for BOTH stems (:preview and :apply). A single
      # class handles both by inspecting `message.handle`.
      #
      # Resolution delegates to `Pito::Themes::Registry.resolve_target` — so
      # "default" is accepted in addition to every registered slug.
      #
      # Unknown name → witty i18n error.
      # Missing name → usage hint error.
      class Theme < Pito::Hashtag::Handler
        # Register for :preview first; :apply uses a sibling constant (see below).
        self.handle = :preview

        def call
          verb = message.handle   # :preview or :apply
          name = extract_name

          if name.nil? || name.empty?
            return Pito::Hashtag::Result::Error.new(
              message_key:  "pito.hashtag.theme.errors.missing_name",
              message_args: { verb: verb.to_s }
            )
          end

          definition = Pito::Themes::Registry.resolve_target(name)

          unless definition
            return Pito::Hashtag::Result::Error.new(
              message_key:  "pito.hashtag.theme.errors.unknown_target",
              message_args: { name: name }
            )
          end

          events =
            case verb
            when :apply
              Pito::Themes::Switch.apply(definition,
                i18n_key: "pito.hashtag.theme.apply.confirmed")
            when :preview
              Pito::Themes::Switch.preview(definition,
                i18n_key: "pito.hashtag.theme.preview.confirmed")
            else
              return Pito::Hashtag::Result::Error.new(
                message_key:  "pito.hashtag.theme.errors.unknown_verb",
                message_args: { verb: verb.to_s }
              )
            end

          Pito::Hashtag::Result::Ok.new(events:)
        end

        private

        # Extract the first word-token from body_tokens as the theme name.
        def extract_name
          token = message.body_tokens.find { |t| t.type == :word }
          token&.value.to_s.strip.downcase.presence
        end
      end

      # Sibling constant so the registry can register both handles via a single
      # handler class. Each constant has its own handle value; both share the
      # same implementation via the parent class.
      #
      # We can't set two handles on one class (the registry stores one per class
      # via `self.handle`), so we subclass and override only the handle.
      class ThemeApply < Theme
        self.handle = :apply
      end
    end
  end
end
