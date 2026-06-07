# frozen_string_literal: true

module Pito
  module FollowUp
    module Handlers
      # Follow-up handler for theme-list events (reply_target: "theme_list").
      #
      # When `/theme list` stamps a System message with `reply_handle` +
      # `reply_target: "theme_list"`, the user can reply:
      #
      #   #<handle> preview <name>   — live-preview (set-theme broadcast) and
      #                                mutate the list to theme_diff preview state.
      #                                Stays follow-up-able (repeatable; NOT consumed).
      #
      #   #<handle> apply <name>     — persist the theme (AppSetting.theme=) and
      #                                mutate the list to theme_diff apply state
      #                                (witty quip). Consumed — no further replies.
      #
      # == Payload shapes (IDENTICAL to P12a — ThemeDiffComponent unchanged)
      #
      # Preview mutation payload:
      #   kind:           "theme_diff"
      #   phase:          "preview"
      #   granularity:    "char" (dark) | "line" (light)
      #   previewed_slug: "<slug>"
      #   sections:       Array — Dark/Light theme rows (current slug marked with ●)
      #   from_text:      String — plain-text snapshot of the prior content
      #   reply_handle:   String — RETAINED (keeps the message follow-up-able)
      #   reply_target:   "theme_list"
      #   (reply_consumed is NOT set — repeatable)
      #
      # Apply mutation payload:
      #   kind:           "theme_diff"
      #   phase:          "apply"
      #   granularity:    "char" (dark) | "line" (light)
      #   body:           String — witty quip (Pito::Themes::Quips.applied)
      #   from_text:      String — plain-text snapshot of the prior content
      #   reply_handle:   String — RETAINED (handle stays reserved)
      #   reply_target:   "theme_list"
      #   reply_consumed: true  — not routable after apply
      #
      # == Granularity rule
      #   dark theme  → "char"
      #   light theme → "line"
      # (matches P12a; controls pito--diff-reveal animation in P12b)
      #
      # == Error cases
      #   invalid action (not preview/apply) → Result::Error
      #   unknown theme name                 → Result::Error
      class ThemeList < Pito::FollowUp::Handler
        self.target "theme_list"
        self.mode   :mutate
        self.actions "preview", "apply"

        VALID_ACTIONS = %w[preview apply].freeze

        # @param event        [Event]        the source theme-list (or theme-diff) event.
        # @param rest         [String]       text after `#<handle> ` — e.g. "preview dracula".
        # @param conversation [Conversation] the owning conversation.
        # @return [Pito::FollowUp::Result::Mutation | Result::Error]
        def call(event:, rest:, conversation:) # rubocop:disable Lint/UnusedMethodArgument
          action, name = parse_rest(rest)

          unless VALID_ACTIONS.include?(action)
            return Pito::FollowUp::Result::Error.new(
              message_key:  "pito.follow_up.theme_list.errors.invalid_action",
              message_args: { action: action }
            )
          end

          if name.blank?
            return Pito::FollowUp::Result::Error.new(
              message_key:  "pito.follow_up.theme_list.errors.missing_name",
              message_args: { action: action }
            )
          end

          definition = Pito::Themes::Registry.resolve_target(name)
          unless definition
            return Pito::FollowUp::Result::Error.new(
              message_key:  "pito.follow_up.theme_list.errors.unknown_target",
              message_args: { name: name }
            )
          end

          granularity = definition.mode == :dark ? "char" : "line"
          from_text   = payload_to_plain_text(event.payload)

          # Preserve handle + target so the mutation payload carries them forward.
          handle = event.payload["reply_handle"].to_s

          case action
          when "preview"
            Pito::Themes::Switch.preview_only(definition)
            Pito::FollowUp::Result::Mutation.new(
              kind:    "theme_diff",
              payload: build_preview_payload(definition, granularity, from_text, handle)
            )
          when "apply"
            Pito::Themes::Switch.apply_only(definition)
            Pito::FollowUp::Result::Mutation.new(
              kind:    "theme_diff",
              payload: build_apply_payload(definition, granularity, from_text, handle)
            )
          end
        end

        private

        # Build the theme_diff payload for the preview phase.
        # Retains reply_handle + reply_target so the message stays follow-up-able
        # (the user can run #<handle> preview <other> again, or #<handle> apply).
        # reply_consumed is NOT set — the event remains routable.
        #
        # @param definition  [Pito::Themes::Definition]
        # @param granularity [String] "char" or "line"
        # @param from_text   [String] plain-text snapshot of the prior content
        # @param handle      [String] the reply handle to carry forward
        # @return [Hash]
        def build_preview_payload(definition, granularity, from_text, handle)
          current_slug = AppSetting.theme
          grouped      = Pito::Themes::Registry.grouped

          dark_rows  = build_theme_rows(grouped[:dark]  || [], current_slug)
          light_rows = build_theme_rows(grouped[:light] || [], current_slug)

          {
            "phase"          => "preview",
            "granularity"    => granularity,
            "previewed_slug" => definition.slug,
            "from_text"      => from_text,
            "sections"       => [
              { "title" => I18n.t("pito.slash.theme.list.dark_header"),  "rows" => dark_rows },
              { "title" => I18n.t("pito.slash.theme.list.light_header"), "rows" => light_rows }
            ],
            "reply_handle"  => handle,
            "reply_target"  => "theme_list"
            # reply_consumed deliberately omitted — stays routable
          }
        end

        # Build the theme_diff payload for the apply phase.
        # Retains reply_handle + reply_target but sets reply_consumed: true so the
        # handle is reserved but the event is no longer routable.
        #
        # @param definition  [Pito::Themes::Definition]
        # @param granularity [String] "char" or "line"
        # @param from_text   [String] plain-text snapshot of the prior content
        # @param handle      [String] the reply handle to carry forward
        # @return [Hash]
        def build_apply_payload(definition, granularity, from_text, handle)
          {
            "phase"          => "apply",
            "granularity"    => granularity,
            "body"           => Pito::Copy.render("pito.copy.theme.applied", { theme: definition.label }),
            "from_text"      => from_text,
            "reply_handle"   => handle,
            "reply_target"   => "theme_list",
            "reply_consumed" => true
          }
        end

        # Build kv rows for a group of theme definitions, marking the current theme.
        # Mirrors the same helper in Pito::Slash::Handlers::Theme and the old
        # Pito::Hashtag::Handlers::Theme (relocated here as the canonical home).
        #
        # @param definitions  [Array<Pito::Themes::Definition>]
        # @param current_slug [String]
        # @return [Array<Hash>]
        def build_theme_rows(definitions, current_slug)
          definitions.map do |d|
            marker = d.slug == current_slug ? "● " : "  "
            { "key" => "#{marker}#{d.slug}", "value" => d.label }
          end
        end

        # Flatten a payload (body + section titles + rows) into newline-joined
        # plain text.  Used as `from_text` in theme_diff payloads so the
        # pito--diff-reveal engine can derive the subtraction from the prior state.
        #
        # Relocated from Pito::Hashtag::Handlers::Theme (P12a) — this is now the
        # canonical location.  Accepts either string or symbol keys.
        #
        # @param payload [Hash, HashWithIndifferentAccess, ActionController::Parameters]
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
    end
  end
end
