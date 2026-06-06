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
      # `#preview <name>` → broadcast-only (no persist); transforms the most-recent
      #   theme_list event in place (kind: theme_diff, phase: preview).
      # `#apply <name>`   → persist + broadcast; transforms the most-recent theme_list
      #   event in place (kind: theme_diff, phase: apply, drops theme_list).
      #
      # If no prior theme_list event is found in the conversation, the handler
      # falls back to the original append behaviour (returns events to append).
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

          # Perform the side-effect (persist for apply, broadcast-only for preview).
          case verb
          when :apply
            Pito::Themes::Switch.apply_only(definition)
          when :preview
            Pito::Themes::Switch.preview_only(definition)
          else
            return Pito::Hashtag::Result::Error.new(
              message_key:  "pito.hashtag.theme.errors.unknown_verb",
              message_args: { verb: verb.to_s }
            )
          end

          # Find the most-recent theme_list event to transform in place.
          list_event = conversation.events
                                   .where("payload->>'theme_list' = 'true'")
                                   .last

          if list_event
            transform_in_place(list_event, definition, verb)
          else
            fallback_append(definition, verb)
          end
        end

        private

        # Extract the first word-token from body_tokens as the theme name.
        def extract_name
          token = message.body_tokens.find { |t| t.type == :word }
          token&.value.to_s.strip.downcase.presence
        end

        # Transform the prior theme_list event into a theme_diff event in place.
        # Updates the event record and broadcasts a Turbo Stream replace.
        # Returns Ok(events: []) — nothing is appended.
        #
        # @param list_event [Event]
        # @param definition [Pito::Themes::Definition]
        # @param verb       [:preview, :apply]
        # @return [Pito::Hashtag::Result::Ok]
        def transform_in_place(list_event, definition, verb)
          granularity = definition.mode == :dark ? "char" : "line"
          from_text   = payload_to_plain_text(list_event.payload)

          new_payload =
            case verb
            when :preview
              build_preview_payload(definition, granularity, from_text)
            when :apply
              build_apply_payload(definition, granularity, from_text)
            end

          list_event.update!(kind: "theme_diff", payload: new_payload)
          Pito::Stream::Broadcaster.new(conversation: conversation).replace_event(list_event)

          Pito::Hashtag::Result::Ok.new(events: [])
        end

        # Fallback: append a new event (today's behaviour when no list exists).
        #
        # @param definition [Pito::Themes::Definition]
        # @param verb       [:preview, :apply]
        # @return [Pito::Hashtag::Result::Ok]
        def fallback_append(definition, verb)
          events =
            case verb
            when :apply
              Pito::Themes::Switch.apply(definition,
                i18n_key: "pito.hashtag.theme.apply.confirmed")
            when :preview
              Pito::Themes::Switch.preview(definition,
                i18n_key: "pito.hashtag.theme.preview.confirmed")
            end

          Pito::Hashtag::Result::Ok.new(events: Array(events))
        end

        # Build the theme_diff payload for preview phase.
        # Keeps theme_list: true so a subsequent #preview/#apply can re-find the event.
        #
        # @param definition  [Pito::Themes::Definition]
        # @param granularity [String] "char" or "line"
        # @param from_text   [String] plain-text snapshot of the prior list
        # @return [Hash]
        def build_preview_payload(definition, granularity, from_text)
          current_slug = AppSetting.theme
          grouped      = Pito::Themes::Registry.grouped

          dark_rows  = build_theme_rows(grouped[:dark]  || [], current_slug)
          light_rows = build_theme_rows(grouped[:light] || [], current_slug)

          {
            theme_diff:     true,
            theme_list:     true,
            phase:          "preview",
            granularity:    granularity,
            previewed_slug: definition.slug,
            from_text:      from_text,
            sections: [
              { title: I18n.t("pito.slash.theme.list.dark_header"),  rows: dark_rows },
              { title: I18n.t("pito.slash.theme.list.light_header"), rows: light_rows }
            ]
          }
        end

        # Build the theme_diff payload for apply phase.
        # Drops theme_list (the list is consumed by the apply action).
        #
        # @param definition  [Pito::Themes::Definition]
        # @param granularity [String] "char" or "line"
        # @param from_text   [String] plain-text snapshot of the prior list
        # @return [Hash]
        def build_apply_payload(definition, granularity, from_text)
          {
            theme_diff:  true,
            phase:       "apply",
            granularity: granularity,
            body:        Pito::Themes::Quips.applied(definition.label),
            from_text:   from_text
          }
        end

        # Build kv rows for a group of theme definitions, marking the current theme.
        # Mirrors the same helper in Pito::Slash::Handlers::Theme.
        #
        # @param definitions  [Array<Pito::Themes::Definition>]
        # @param current_slug [String]
        # @return [Array<Hash>]
        def build_theme_rows(definitions, current_slug)
          definitions.map do |d|
            marker = d.slug == current_slug ? "● " : "  "
            { key: "#{marker}#{d.slug}", value: d.label }
          end
        end

        # Flatten a list payload (body + section titles + rows) into
        # newline-joined plain text. Used as `from_text` in theme_diff payloads
        # so the animation engine can derive the subtraction from the prior state.
        #
        # Accepts either a HashWithIndifferentAccess or plain Hash.
        #
        # @param payload [Hash, HashWithIndifferentAccess]
        # @return [String]
        def payload_to_plain_text(payload)
          p = payload.respond_to?(:with_indifferent_access) ? payload.with_indifferent_access : payload
          lines = []
          lines << p[:body].to_s if p[:body].present?

          Array(p[:sections]).each do |section|
            s = section.respond_to?(:with_indifferent_access) ? section.with_indifferent_access : section
            lines << s[:title].to_s if s[:title].present?
            Array(s[:rows]).each do |row|
              r = row.respond_to?(:with_indifferent_access) ? row.with_indifferent_access : row
              lines << "#{r[:key]} #{r[:value]}"
            end
          end

          lines.join("\n")
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
