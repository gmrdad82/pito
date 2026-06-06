# frozen_string_literal: true

module Pito
  module Slash
    module Handlers
      # Handler for `/theme [subcommand] [name]`.
      #
      # Subcommands / dispatch table
      # ─────────────────────────────
      # `/theme apply <name>`  — persist + broadcast; also bare `/theme <name>`.
      # `/theme preview <name>`— broadcast only (no persist); System message with
      #                          apply/revert hints. Preview-vs-apply rule:
      #                          preview does NOT write AppSetting; it only sends
      #                          the set-theme Turbo Stream so the current tab
      #                          recolors immediately. The caller must explicitly
      #                          run `/theme apply <name>` or `/theme reset` to
      #                          make the change permanent.
      # `/theme reset`         — apply the registry default (tokyo-night) + confirm.
      # `/theme list` / `ls`   — placeholder (full System message in P7).
      # `/theme`  (bare)       — placeholder (sidebar in P8).
      # `/theme <unknown>`     — witty error pointing to `/theme list`.
      # `/theme --help`        — per-command usage + grouped theme list.
      #
      # The `name` arg accepts any registered slug OR the special token "default"
      # (→ Registry.default). Resolution is delegated to Registry.resolve_target.
      class Theme < Pito::Slash::Handler
        self.verb        = :theme
        self.description_key = "pito.slash.theme.descriptions.theme"

        # Grammar: first positional arg is either a subcommand keyword or a theme
        # name from the :theme_names vocab. Both slots are optional so bare
        # `/theme` is valid (→ sidebar placeholder).
        grammar do
          enum :subcommand, source: :theme_names, optional: true
          auth :authenticated_only
          description_key "pito.grammar.slash.theme"
        end

        # Subcommand keywords routed before the theme-name lookup.
        SUBCOMMANDS = %w[list ls preview apply reset].freeze

        def call
          return show_help if help?

          first_arg = invocation.args.first.to_s.strip.downcase

          case first_arg
          when ""                     then placeholder_sidebar
          when "list", "ls"           then placeholder_list
          when "preview"              then dispatch_preview
          when "apply"                then dispatch_apply
          when "reset"                then dispatch_reset
          else
            # Bare theme name (shorthand apply) or unknown target.
            definition = Pito::Themes::Registry.resolve_target(first_arg)
            definition ? apply(definition) : unknown_target(first_arg)
          end
        end

        # `/theme --help` — usage + grouped theme list.
        def show_help
          grouped = Pito::Themes::Registry.grouped

          dark_rows  = (grouped[:dark]  || []).map { |d| { key: d.slug, value: d.label } }
          light_rows = (grouped[:light] || []).map { |d| { key: d.slug, value: d.label } }

          Pito::Slash::Result::Ok.new(events: [
            {
              kind:    "system",
              payload: {
                body:       I18n.t("pito.slash.theme.help.usage"),
                table_rows: [
                  { key: "──── Dark ────",  value: "" },
                  *dark_rows,
                  { key: "──── Light ───", value: "" },
                  *light_rows
                ],
                info_lines: [ I18n.t("pito.slash.theme.help.description") ]
              }
            }
          ])
        end

        private

        # ── Dispatch helpers ──────────────────────────────────────────────────

        def dispatch_preview
          name = invocation.args[1].to_s.strip.downcase
          if name.empty?
            return Pito::Slash::Result::Error.new(
              message_key:  "pito.slash.theme.errors.missing_name_for_preview"
            )
          end

          definition = Pito::Themes::Registry.resolve_target(name)
          return unknown_target(name) unless definition

          preview(definition)
        end

        def dispatch_apply
          name = invocation.args[1].to_s.strip.downcase
          if name.empty?
            return Pito::Slash::Result::Error.new(
              message_key:  "pito.slash.theme.errors.missing_name_for_apply"
            )
          end

          definition = Pito::Themes::Registry.resolve_target(name)
          return unknown_target(name) unless definition

          apply(definition)
        end

        def dispatch_reset
          apply(Pito::Themes::Registry.default, reset: true)
        end

        # ── apply ─────────────────────────────────────────────────────────────

        # Persists AppSetting.theme, broadcasts to all clients, returns confirm.
        # @param definition [Pito::Themes::Definition]
        # @param reset [Boolean] use the reset confirmation string instead of apply
        def apply(definition, reset: false)
          AppSetting.theme = definition.slug
          Pito::Stream::Broadcaster.broadcast_global_theme(definition.slug)

          msg_key = reset ? "pito.slash.theme.reset.confirmed" : "pito.slash.theme.apply.confirmed"

          Pito::Slash::Result::Ok.new(events: [
            {
              kind:    "system",
              payload: {
                text: I18n.t(msg_key, name: definition.label, slug: definition.slug)
              }
            }
          ])
        end

        # ── preview ───────────────────────────────────────────────────────────

        # Broadcasts the theme WITHOUT persisting. Documents the rule inline:
        #   - Only the Turbo Stream set-theme action fires (recolors the page).
        #   - AppSetting.theme is NOT written.
        #   - The caller must `/theme apply <name>` to keep it or `/theme reset`
        #     to revert to the persisted theme.
        def preview(definition)
          Pito::Stream::Broadcaster.broadcast_global_theme(definition.slug)

          Pito::Slash::Result::Ok.new(events: [
            {
              kind:    "system",
              payload: {
                text: I18n.t(
                  "pito.slash.theme.preview.confirmed",
                  name:  definition.label,
                  slug:  definition.slug,
                  apply: "/theme apply #{definition.slug}",
                  reset: "/theme reset"
                )
              }
            }
          ])
        end

        # ── placeholder paths (P7 / P8) ───────────────────────────────────────

        def placeholder_list
          Pito::Slash::Result::Ok.new(events: [
            {
              kind:    "system",
              payload: {
                text: I18n.t("pito.slash.theme.list.placeholder")
              }
            }
          ])
        end

        def placeholder_sidebar
          Pito::Slash::Result::Ok.new(events: [
            {
              kind:    "system",
              payload: {
                text: I18n.t("pito.slash.theme.sidebar.placeholder")
              }
            }
          ])
        end

        # ── error ─────────────────────────────────────────────────────────────

        def unknown_target(name)
          Pito::Slash::Result::Error.new(
            message_key:  "pito.slash.theme.errors.unknown_target",
            message_args: { name: name }
          )
        end
      end
    end
  end
end
